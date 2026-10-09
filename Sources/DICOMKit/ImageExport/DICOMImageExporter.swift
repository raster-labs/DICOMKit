// NEMA-verified: 2026a, checked 2026-10-06 — determineModalityWindow returns the window in the units the Modality LUT puts out, the units PS3.3 2026a C.11.2.1.2.1 applies it in ("after any Modality LUT or Rescale Slope and Intercept specified in the IOD have been applied"), i.e. what GrayscaleDisplayPipeline and DICOMFile.renderFrame(_:window:) apply (PS3.4 2026a N.2); the full-range fallback is C.11.2.1.2.1's x1…x2 window as GrayscaleDisplayPipeline.fullRangeWindow writes it; determineWindowSettings (stored units, exact only for slope 1 and no Modality LUT Sequence) is deprecated (A6 / D65)
// NEMA-verified: 2026a, checked 2026-09-30 — monochrome export applies the PS3.4 2026a N.2 chain (GrayscaleDisplayPipeline): Modality LUT Sequence or this frame's rescale, then the window in modality units (PS3.3 C.11.2.1.2.1) or the VOI LUT Sequence (C.11.2.1.1), then INVERSE for MONOCHROME1 (C.7.6.3.1.2) (D65); full-range and identity fallbacks per C.11.2.1.2.1 (D66)
// NEMA-verified: 2026a, checked 2026-09-29 — window and rescale per PS3.3 2026a C.11.2.1.2 and C.11.1.1.2
// NEMA-verified: 2026a, checked 2026-10-01 — EXIF export: Study Date read as DA and Study Time as TM per PS3.5 2026a Table 6.2-1 and converted to Exif DateTimeOriginal (non-DA values not written); Patient ID / Modality / Series Description into Exif UserComment as PS3.6 keyword=value (D126)
import Foundation
import DICOMCore
import DICOMDictionary

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// Shared image-export engine for the `dicom-export` CLI and DICOMStudio. Builds on
// the already-shared rendering primitives (PixelData / PixelDataRenderer /
// WindowSettings / DICOMFile.tryRenderFrame). This collects the pure, deterministic
// pieces both adapters used to duplicate — EXIF mapping, contact-sheet geometry,
// path organization, window resolution, and image encoding. Each adapter keeps its
// own render/compose orchestration (the CLI writes files directly; DICOMStudio
// writes through its sandbox-aware OutputAccess) but shares this logic.

/// Output image formats for export.
public enum ExportImageFormat: String, CaseIterable, Sendable {
    case png
    case jpeg
    case tiff

    public var fileExtension: String { rawValue }

    #if canImport(UniformTypeIdentifiers)
    public var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        }
    }
    #endif
}

/// Directory organization scheme for bulk export.
public enum OrganizationScheme: String, CaseIterable, Sendable {
    case flat
    case patient
    case study
    case series
}

/// Errors raised during image export.
public enum ExportError: LocalizedError {
    case noPixelData
    case renderFailed
    case exportFailed
    case unsupportedPlatform
    case invalidFrame(Int, Int)
    case noFrames
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .noPixelData: return "No pixel data found in DICOM file"
        case .renderFailed: return "Failed to render pixel data to image"
        case .exportFailed: return "Failed to export image to file"
        case .unsupportedPlatform: return "Image export requires macOS or iOS (CoreGraphics)"
        case .invalidFrame(let requested, let total):
            return "Invalid frame \(requested). File has \(total) frames (0-\(total - 1))"
        case .noFrames: return "No frames available in DICOM file"
        case .invalidInput(let message): return message
        }
    }
}

/// Shared, deterministic helpers behind the DICOM image-export workflow.
public enum DICOMImageExporter {

    /// Version stamp embedded in EXIF Software tags (matches the CLI tool version).
    public static let toolVersion = "1.2.2"

    // MARK: - EXIF metadata

    /// The PS3.6 keywords `--exif-fields` accepts (case-insensitive), in help order.
    public static let supportedEXIFFields: [String] = [
        "PatientName", "PatientID", "StudyDate", "Modality", "StudyDescription", "SeriesDescription",
        "InstitutionName", "Manufacturer", "ManufacturerModelName", "StationName",
    ]

    /// The requested keywords that `buildEXIFMetadata` cannot embed (not in ``supportedEXIFFields``).
    public static func unsupportedEXIFFields(_ fields: [String]) -> [String] {
        let known = Set(supportedEXIFFields.map { $0.lowercased() })
        return fields.filter { !known.contains($0.trimmingCharacters(in: .whitespaces).lowercased()) }
    }

    /// Maps DICOM field names to EXIF/TIFF dictionary keys.
    ///
    /// Patient ID (0010,0020), Modality (0008,0060) and Series Description (0008,103E) have no
    /// EXIF/TIFF tag of their own: they share Exif UserComment as `<PS3.6 keyword>=<value>`
    /// entries (D126; Modality used to go to an Exif "Software" key, which is a TIFF tag that
    /// the exporter overwrites, and Patient ID was read but dropped).
    public static func mapDICOMFieldToEXIF(_ field: String) -> (dictionary: String, key: String)? {
        switch field.trimmingCharacters(in: .whitespaces).lowercased() {
        case "patientname": return ("tiff", "ImageDescription")
        case "studydate": return ("exif", "DateTimeOriginal")
        case "modality", "patientid", "seriesdescription": return ("exif", "UserComment")
        case "studydescription": return ("tiff", "DocumentName")
        case "institutionname": return ("tiff", "Artist")
        case "manufacturer": return ("tiff", "Make")
        case "manufacturermodelname": return ("tiff", "Model")
        case "stationname": return ("tiff", "HostComputer")
        default: return nil
        }
    }

    /// Retrieves a DICOM field value from a DICOMFile by field name.
    public static func getDICOMFieldValue(_ file: DICOMFile, field: String) -> String? {
        switch field.trimmingCharacters(in: .whitespaces).lowercased() {
        case "patientname": return file.dataSet.string(for: .patientName)
        case "patientid": return file.dataSet.string(for: .patientID)
        case "studydate": return file.dataSet.string(for: .studyDate)
        case "studydescription": return file.dataSet.string(for: .studyDescription)
        case "seriesdescription": return file.dataSet.string(for: .seriesDescription)
        case "modality": return file.dataSet.string(for: .modality)
        case "institutionname": return file.dataSet.string(for: .institutionName)
        case "manufacturer": return file.dataSet.string(for: .manufacturer)
        case "manufacturermodelname": return file.dataSet.string(for: .manufacturerModelName)
        case "stationname": return file.dataSet.string(for: .stationName)
        default: return nil
        }
    }

    /// Exif DateTimeOriginal text "YYYY:MM:DD HH:MM:SS" from a DICOM DA value (YYYYMMDD,
    /// PS3.5 2026a Table 6.2-1) and an optional TM value (HHMMSS.FFFFFF, unspecified MM / SS
    /// taken as 00, fraction dropped). Returns nil when `da` is not 8 digits or names no
    /// Gregorian date. Without a usable TM the time is written as blanks ("  :  :  "), Exif's
    /// spelling of an unknown value, rather than an invented midnight.
    public static func exifDateTime(fromDA da: String, tm: String? = nil) -> String? {
        let date = da.trimmingCharacters(in: .whitespaces)
        guard date.count == 8, date.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let digits = Array(date)
        let year = String(digits[0..<4]), month = String(digits[4..<6]), day = String(digits[6..<8])
        var components = DateComponents()
        components.year = Int(year); components.month = Int(month); components.day = Int(day)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let m = components.month, let d = components.day, (1...12).contains(m), d >= 1,
              let probe = calendar.date(from: components),
              calendar.component(.day, from: probe) == d, calendar.component(.month, from: probe) == m else {
            return nil
        }
        var timeText = "  :  :  "
        if let tm {
            let whole = tm.trimmingCharacters(in: .whitespaces).split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
            if [2, 4, 6].contains(whole.count), whole.allSatisfy({ $0.isASCII && $0.isNumber }) {
                let t = Array(whole)
                let hh = String(t[0..<2])
                let mm = t.count >= 4 ? String(t[2..<4]) : "00"
                let ss = t.count >= 6 ? String(t[4..<6]) : "00"
                if let h = Int(hh), let mi = Int(mm), let se = Int(ss), h <= 23, mi <= 59, se <= 60 {
                    timeText = "\(hh):\(mm):\(ss)"
                }
            }
        }
        return "\(year):\(month):\(day) \(timeText)"
    }

    #if canImport(CoreGraphics)
    /// Builds EXIF/TIFF metadata dictionaries from a DICOM file.
    ///
    /// Study Date (0008,0020) is converted from DA to Exif DateTimeOriginal with Study Time
    /// (0008,0030) (``exifDateTime(fromDA:tm:)``); a value that is not a DA is not written.
    public static func buildEXIFMetadata(from file: DICOMFile, fields: [String]?) -> CFDictionary {
        var tiffDict: [String: Any] = [:]
        var exifDict: [String: Any] = [:]
        var userComment: [String] = []

        let fieldsToEmbed = fields ?? ["PatientName", "StudyDate", "Modality", "StudyDescription", "Manufacturer"]

        for field in fieldsToEmbed {
            guard let value = getDICOMFieldValue(file, field: field),
                  let mapping = mapDICOMFieldToEXIF(field) else {
                continue
            }
            let keyword = supportedEXIFFields.first { $0.lowercased() == field.trimmingCharacters(in: .whitespaces).lowercased() } ?? field
            switch (mapping.dictionary, mapping.key) {
            case ("exif", "DateTimeOriginal"):
                if let text = exifDateTime(fromDA: value, tm: file.dataSet.string(for: .studyTime)) {
                    exifDict[mapping.key] = text
                }
            case ("exif", "UserComment"):
                userComment.append("\(keyword)=\(value)")
            case ("tiff", _):
                tiffDict[mapping.key] = value
            default:
                exifDict[mapping.key] = value
            }
        }
        if !userComment.isEmpty {
            exifDict["UserComment"] = userComment.joined(separator: "; ")
        }

        tiffDict["Software"] = "DICOMKit dicom-export v\(toolVersion)"

        var properties: [String: Any] = [:]
        if !tiffDict.isEmpty {
            properties[kCGImagePropertyTIFFDictionary as String] = tiffDict
        }
        if !exifDict.isEmpty {
            properties[kCGImagePropertyExifDictionary as String] = exifDict
        }

        return properties as CFDictionary
    }
    #endif

    // MARK: - Contact sheet geometry

    /// Computes contact sheet grid dimensions.
    public static func contactSheetLayout(
        imageCount: Int, columns: Int, thumbnailSize: Int, spacing: Int, includeLabels: Bool
    ) -> (rows: Int, totalWidth: Int, totalHeight: Int) {
        let rows = max(1, (imageCount + columns - 1) / columns)
        let labelHeight = includeLabels ? 20 : 0
        let totalWidth = columns * thumbnailSize + (columns + 1) * spacing
        let totalHeight = rows * (thumbnailSize + labelHeight) + (rows + 1) * spacing
        return (rows, totalWidth, totalHeight)
    }

    /// Returns the position for a thumbnail at a given index in the grid.
    public static func thumbnailPosition(
        index: Int, columns: Int, thumbnailSize: Int, spacing: Int, includeLabels: Bool
    ) -> (x: Int, y: Int) {
        let col = index % columns
        let row = index / columns
        let labelHeight = includeLabels ? 20 : 0
        let x = spacing + col * (thumbnailSize + spacing)
        let y = spacing + row * (thumbnailSize + labelHeight + spacing)
        return (x, y)
    }

    // MARK: - Animation

    /// Computes the GIF frame delay from FPS.
    public static func gifFrameDelay(fps: Double) -> Double {
        guard fps > 0 else { return 0.1 }
        return 1.0 / fps
    }

    /// Validates and clamps a frame range.
    public static func validatedFrameRange(start: Int, end: Int?, totalFrames: Int) -> (start: Int, end: Int)? {
        guard totalFrames > 0 else { return nil }
        let clampedStart = max(0, min(start, totalFrames - 1))
        let clampedEnd: Int
        if let end = end {
            clampedEnd = max(clampedStart, min(end, totalFrames - 1))
        } else {
            clampedEnd = totalFrames - 1
        }
        return (clampedStart, clampedEnd)
    }

    // MARK: - Bulk export paths

    /// Sanitizes a string for use as a path component.
    public static func sanitizePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        var result = ""
        for char in value.unicodeScalars {
            result.append(allowed.contains(char) ? Character(char) : "_")
        }
        return result.isEmpty ? "UNKNOWN" : result
    }

    /// The bulk-export patient folder name (P-EXPORT-2, approved 2026-10-01): Patient ID
    /// (0010,0020, PS3.3 2026a Table C.7-1; the Patient level unique key of PS3.4 Table C.6-1),
    /// followed by `@` and Issuer of Patient ID (0010,0021, Table 10-18) when that is present.
    /// Each part is sanitized; an absent or empty Patient ID gives "UNKNOWN". `@` never comes
    /// out of ``sanitizePathComponent(_:)``, so the two parts cannot be confused.
    public static func patientFolderName(patientID: String?, issuerOfPatientID: String?) -> String {
        let id = patientID?.trimmingCharacters(in: .whitespaces) ?? ""
        let folder = sanitizePathComponent(id)
        let issuer = issuerOfPatientID?.trimmingCharacters(in: .whitespaces) ?? ""
        return issuer.isEmpty ? folder : folder + "@" + sanitizePathComponent(issuer)
    }

    /// Builds the output path for a bulk export file based on the organization scheme. The
    /// patient folder is ``patientFolderName(patientID:issuerOfPatientID:)``; study and series
    /// add Study Instance UID (0020,000D) and Series Instance UID (0020,000E) folders.
    public static func buildOrganizedPath(
        baseOutput: String, scheme: OrganizationScheme,
        patientID: String?, issuerOfPatientID: String?,
        studyUID: String?, seriesUID: String?, filename: String
    ) -> String {
        let patient = patientFolderName(patientID: patientID, issuerOfPatientID: issuerOfPatientID)
        switch scheme {
        case .flat:
            return (baseOutput as NSString).appendingPathComponent(filename)
        case .patient:
            return (baseOutput as NSString).appendingPathComponent(patient).appending("/\(filename)")
        case .study:
            let study = sanitizePathComponent(studyUID ?? "UNKNOWN")
            return (baseOutput as NSString).appendingPathComponent(patient).appending("/\(study)/\(filename)")
        case .series:
            let study = sanitizePathComponent(studyUID ?? "UNKNOWN")
            let series = sanitizePathComponent(seriesUID ?? "UNKNOWN")
            return (baseOutput as NSString).appendingPathComponent(patient).appending("/\(study)/\(series)/\(filename)")
        }
    }

    /// Builds the output path with the patient folder named from Patient's Name (0010,0010),
    /// the layout `dicom-export bulk` used before 2026-10-01.
    @available(*, deprecated, message: "P-EXPORT-2: the patient folder is keyed on Patient ID (0010,0020) and Issuer of Patient ID (0010,0021) (PS3.3 Table C.7-1); use buildOrganizedPath(baseOutput:scheme:patientID:issuerOfPatientID:studyUID:seriesUID:filename:)")
    public static func buildOrganizedPath(
        baseOutput: String, scheme: OrganizationScheme,
        patientName: String?, studyUID: String?, seriesUID: String?, filename: String
    ) -> String {
        switch scheme {
        case .flat:
            return (baseOutput as NSString).appendingPathComponent(filename)
        case .patient:
            let patient = sanitizePathComponent(patientName ?? "UNKNOWN")
            return (baseOutput as NSString).appendingPathComponent(patient).appending("/\(filename)")
        case .study:
            let patient = sanitizePathComponent(patientName ?? "UNKNOWN")
            let study = sanitizePathComponent(studyUID ?? "UNKNOWN")
            return (baseOutput as NSString).appendingPathComponent(patient).appending("/\(study)/\(filename)")
        case .series:
            let patient = sanitizePathComponent(patientName ?? "UNKNOWN")
            let study = sanitizePathComponent(studyUID ?? "UNKNOWN")
            let series = sanitizePathComponent(seriesUID ?? "UNKNOWN")
            return (baseOutput as NSString).appendingPathComponent(patient).appending("/\(study)/\(series)/\(filename)")
        }
    }

    // MARK: - Window settings

    /// Resolves window settings for a frame: explicit values, the file's own
    /// window, the frame's pixel range, or a 16-bit fallback.
    ///
    /// Window Center / Width (whether supplied explicitly or read from the file's
    /// (0028,1050)/(0028,1051)) are expressed in **output (rescaled) units**, but
    /// `PixelDataRenderer` applies the window to the **stored** pixel values it reads
    /// from the frame. We therefore convert HU→stored using Rescale Slope/Intercept
    /// — exactly as the on-screen viewer does (`(center - intercept) / slope`) — so
    /// the exported raster matches what the viewer shows. Without this, a CT with a
    /// non-zero Rescale Intercept (e.g. −1024 / −8192) renders with a window centred
    /// far from the data, producing a washed-out or near-blank image. The pixel-range
    /// and 16-bit fallbacks are already computed in stored space, so they are used
    /// as-is. Reference: DICOM PS3.3 C.11.2 (VOI LUT) + C.11.1 (Modality LUT).
    ///
    /// `frameIndex` is honoured at every rung: on an Enhanced multi-frame object
    /// the rescale pair and the VOI come from *that frame's* Pixel Value
    /// Transformation / Frame VOI LUT functional groups (else the shared ones),
    /// so a multi-echo MR or a per-frame-windowed PET pages through the viewer
    /// and exports with each frame's own window rather than frame 0's.
    ///
    /// **Stored-value units — deprecated.** The conversion `(c − b) / m`, `w / |m|`
    /// reproduces PS3.3 C.11.2.1.2.1 (the window applied after the rescale) only for a
    /// slope of 1, and a negative slope inverts the ramp; a Modality LUT Sequence is not
    /// applied at all. Nothing in DICOMKit renders with a stored-unit window any more:
    /// ``DICOMFile/renderFrame(_:window:)`` and ``PixelDataRenderer/renderMonochromeFrame(_:pipeline:pseudoColor:)``
    /// take the window in modality units (D243). Use
    /// ``determineModalityWindow(from:pixelData:frameIndex:windowCenter:windowWidth:)``,
    /// which is exact, or ``determineDisplayPipeline(from:pixelData:frameIndex:windowCenter:windowWidth:)``
    /// for the whole chain (D65, A6).
    @available(*, deprecated, renamed: "determineModalityWindow(from:pixelData:frameIndex:windowCenter:windowWidth:)",
               message: "returns a stored-unit window that is exact only for Rescale Slope 1 and no Modality LUT Sequence; the renderers apply the window in modality units")
    public static func determineWindowSettings(
        from file: DICOMFile, pixelData: PixelData, frameIndex: Int,
        windowCenter: Double?, windowWidth: Double?
    ) -> WindowSettings {
        let slope = file.rescaleSlope(frameIndex: frameIndex)
        let intercept = file.rescaleIntercept(frameIndex: frameIndex)
        func toStored(center: Double, width: Double) -> WindowSettings {
            guard slope != 0 else { return WindowSettings(center: center, width: width) }
            return WindowSettings(center: (center - intercept) / slope, width: width / abs(slope))
        }

        if let center = windowCenter, let width = windowWidth {
            return toStored(center: center, width: width)
        }
        // A file may declare several VOI pairs — CT routinely carries a lung and a
        // soft-tissue window in one multi-valued element (`-600\50` / `1200\350`).
        // The first pair is the default presentation, so read the multi-valued
        // form first: ``DICOMFile/windowSettings()`` parses a *single* DS and
        // returns nil for those files, which would drop a perfectly good VOI on
        // the floor and auto-stretch the full pixel range instead.
        if let windowFromFile = file.allWindowSettings(frameIndex: frameIndex).first
            ?? file.windowSettings(frameIndex: frameIndex) {
            return toStored(center: windowFromFile.center, width: windowFromFile.width)
        }
        // The frame's full input range x1…x2 (PS3.3 C.11.2.1.2.1: centre
        // (x1+x2+1)/2, width x2-x1+1), else the mathematical identity for 16-bit
        // unsigned values (centre 2^15, width 2^16) (D66).
        if let range = pixelData.pixelRange(forFrame: frameIndex) {
            return WindowSettings(center: Double(range.min + range.max + 1) / 2.0,
                                  width: Double(range.max - range.min + 1))
        }
        let assumedBitDepth = 16
        return WindowSettings(center: Double(1 << (assumedBitDepth - 1)),
                              width: Double(1 << assumedBitDepth))
    }

    /// The window a frame is rendered with when none is supplied, in the units the
    /// renderers apply it (A6 / D65): modality units, the output of the Modality LUT
    /// Sequence or of this frame's Rescale Slope / Intercept, which PS3.3 C.11.2.1.2.1
    /// applies the window to ("after any Modality LUT or Rescale Slope and Intercept
    /// specified in the IOD have been applied"). ``DICOMFile/renderFrame(_:window:)``,
    /// ``GrayscaleDisplayPipeline`` and ``determineDisplayPipeline(from:pixelData:frameIndex:windowCenter:windowWidth:)``
    /// all take the window in these units, so the result renders exactly, for any slope
    /// and for a table-form Modality LUT, where the stored-unit conversion of the
    /// deprecated ``determineWindowSettings(from:pixelData:frameIndex:windowCenter:windowWidth:)``
    /// was exact only for a slope of 1.
    ///
    /// Resolution, each rung honouring `frameIndex` on an Enhanced object:
    /// - explicit `windowCenter` / `windowWidth` (LINEAR);
    /// - else the file's first Window Center (0028,1050) / Window Width (0028,1051) pair
    ///   for this frame, with its VOI LUT Function (0028,1056) and explanation;
    /// - else the window over the frame's own modality range — PS3.3 C.11.2.1.2.1's
    ///   full-range window x1…x2, as ``GrayscaleDisplayPipeline/fullRangeWindow(modalityLUT:storedRange:)``
    ///   writes it (LINEAR_EXACT, centre (x1+x2)/2, width x2−x1, identical for
    ///   integral values);
    /// - else that window over the 16-bit stored range 0…65 535 (the identity window
    ///   centre 2^15, width 2^16 of C.11.2.1.2.1, through the Modality LUT).
    ///
    /// A VOI LUT Sequence (0028,3010) table cannot be expressed as a window; a file
    /// whose default presentation is a table gets the full-range window here, and the
    /// table through ``determineDisplayPipeline(from:pixelData:frameIndex:windowCenter:windowWidth:)``.
    /// A caller that keeps its window state in stored units converts with
    /// `(center − intercept) / slope`, `width / |slope|` itself (only exact for a
    /// rescale pair, never for a table).
    public static func determineModalityWindow(
        from file: DICOMFile, pixelData: PixelData, frameIndex: Int,
        windowCenter: Double?, windowWidth: Double?
    ) -> WindowSettings {
        if let center = windowCenter, let width = windowWidth {
            return WindowSettings(center: center, width: width)
        }
        if let window = file.allWindowSettings(frameIndex: frameIndex).first
            ?? file.windowSettings(frameIndex: frameIndex) {
            return window
        }
        let modality = file.modalityLUT(frameIndex: frameIndex)
        let storedRange = pixelData.pixelRange(forFrame: frameIndex) ?? (min: 0, max: (1 << 16) - 1)
        guard case .window(let center, let width, let explanation, let function) =
                GrayscaleDisplayPipeline.fullRangeWindow(modalityLUT: modality, storedRange: storedRange) else {
            // fullRangeWindow only ever returns a window; the identity of C.11.2.1.2.1.
            return WindowSettings(center: Double(1 << 15), width: Double(1 << 16))
        }
        return WindowSettings(center: center, width: width, explanation: explanation, function: function)
    }

    /// Resolves the PS3.4 N.2 grayscale chain for a frame, the way the standard
    /// orders it (D65, P-PIPELINE):
    ///
    /// - **Modality LUT** (C.11.1): the Modality LUT Sequence when present, else this
    ///   frame's Rescale Slope / Intercept (identity when 1 / 0).
    /// - **VOI** (C.11.2), in modality units: explicit centre/width (LINEAR); else the
    ///   file's first window for this frame (with its VOI LUT Function); else the
    ///   file's first VOI LUT Sequence table; else a window over the frame's own
    ///   modality range (``GrayscaleDisplayPipeline/fullRangeWindow(modalityLUT:storedRange:)``).
    /// - **Presentation LUT**: INVERSE for MONOCHROME1 (C.7.6.3.1.2), else IDENTITY.
    ///
    /// For a slope of 1 and integral windows this renders the same bytes the stored-unit
    /// window of ``determineWindowSettings(from:pixelData:frameIndex:windowCenter:windowWidth:)``
    /// does; for any other slope, a Modality LUT Sequence or a VOI LUT Sequence, it is the
    /// standard's picture and that one is not.
    public static func determineDisplayPipeline(
        from file: DICOMFile, pixelData: PixelData, frameIndex: Int,
        windowCenter: Double?, windowWidth: Double?
    ) -> GrayscaleDisplayPipeline {
        let dataSet = file.dataSet
        let modality = file.modalityLUT(frameIndex: frameIndex)

        let voi: VOILUT
        if let center = windowCenter, let width = windowWidth {
            voi = .window(center: center, width: width, explanation: nil, function: .linear)
        } else if let window = file.allWindowSettings(frameIndex: frameIndex).first
                    ?? file.windowSettings(frameIndex: frameIndex) {
            voi = VOILUT(window)
        } else if let table = dataSet.voiLUT() {
            voi = .lut(LUTData(table))
        } else if let range = pixelData.pixelRange(forFrame: frameIndex) {
            voi = GrayscaleDisplayPipeline.fullRangeWindow(modalityLUT: modality, storedRange: range)
        } else {
            voi = .window(center: Double(1 << 15), width: Double(1 << 16), explanation: nil, function: .linear)
        }
        return .standard(for: pixelData.descriptor.photometricInterpretation,
                         modalityLUT: modality, voiLUT: voi)
    }

    // MARK: - Frame rendering

    #if canImport(CoreGraphics)
    /// Renders a single frame for image export, applying the shared window-resolution
    /// policy. This is the ONE render decision used by both the `dicom-convert` CLI and
    /// DICOMStudio's CLI Workshop, so their exported raster is byte-for-byte identical
    /// (CLI ↔ app parity) instead of each adapter picking its own windowing fallback.
    ///
    /// - When `applyWindow` is false the frame is rendered with the renderer's default
    ///   (no explicit window).
    /// - When `applyWindow` is true the chain is resolved via ``determineDisplayPipeline(from:pixelData:frameIndex:windowCenter:windowWidth:)``
    ///   (explicit center/width → the file's window → its VOI LUT table → the frame's
    ///   modality range → a 16-bit fallback) and the frame is rendered with it.
    ///
    /// The caller owns frame-bounds validation, file/console I/O, and encoding (via
    /// ``exportCGImage(_:to:format:quality:metadata:)``).
    public static func renderFrameForExport(
        file: DICOMFile, pixelData: PixelData, frameIndex: Int,
        applyWindow: Bool, windowCenter: Double?, windowWidth: Double?
    ) throws -> CGImage {
        // Always resolve a clinically-appropriate window through the shared policy
        // (explicit center/width → the file's VOI window, rescale-adjusted → the
        // frame's pixel range → a 16-bit fallback). Honouring the file's stored
        // Window Center/Width by DEFAULT — rather than auto-stretching the full
        // pixel range when `--apply-window` is absent — makes the exported raster
        // match the on-screen viewer (and Horos), which always apply the file's VOI
        // window. For images without a stored window the policy degrades to the same
        // pixel-range auto-window the renderer used before, so windowless sources are
        // unaffected. `applyWindow` only gates whether explicit center/width override.
        // Monochrome frames go through the Modality → VOI → Presentation chain with
        // the window in modality units (PS3.3 C.11.2.1.2.1, D65).
        if pixelData.descriptor.photometricInterpretation.isMonochrome {
            let pipeline = determineDisplayPipeline(
                from: file, pixelData: pixelData, frameIndex: frameIndex,
                windowCenter: applyWindow ? windowCenter : nil,
                windowWidth: applyWindow ? windowWidth : nil)
            guard let image = PixelDataRenderer(pixelData: pixelData)
                .renderMonochromeFrame(frameIndex, pipeline: pipeline) else {
                throw ExportError.renderFailed
            }
            return image
        }
        // Colour and palette frames take no window (D243: the window-taking render
        // ignores it for them; the plain render is the same raster).
        guard let image = try file.tryRenderFrame(frameIndex) else {
            throw ExportError.renderFailed
        }
        return image
    }
    #endif

    // MARK: - Image encoding

    #if canImport(CoreGraphics) && canImport(ImageIO)
    /// Writes a CGImage to a file URL in the given format, with optional EXIF metadata.
    public static func exportCGImage(
        _ image: CGImage, to url: URL, format: ExportImageFormat, quality: Int, metadata: CFDictionary?
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, format.utType.identifier as CFString, 1, nil
        ) else {
            throw ExportError.exportFailed
        }

        var options: [CFString: Any] = [:]
        if format == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = Double(quality) / 100.0
        }

        if let metadata = metadata, let metaDict = metadata as? [String: Any] {
            for (key, value) in metaDict {
                options[key as CFString] = value
            }
        }

        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.exportFailed
        }
    }
    #endif
}

// MARK: - Shared console output (dicom-export CLI ⇄ Workshop executor)

/// Builds every console line `dicom-export` prints. The CLI text is canonical and
/// the Workshop executor renders identical strings, so the two surfaces cannot drift.
public enum ExportConsole {
    /// Single-image success line.
    public static func exportedLine(path: String) -> String {
        "Exported: \(path)"
    }

    /// Contact-sheet success line.
    public static func contactSheetLine(path: String, imageCount: Int, columns: Int, rows: Int) -> String {
        "Contact sheet exported: \(path) (\(imageCount) images, \(columns)x\(rows) grid)"
    }

    /// Animated-GIF success line.
    public static func animatedGIFLine(path: String, frameCount: Int, fps: Double) -> String {
        "Animated GIF exported: \(path) (\(frameCount) frames, \(fps) fps)"
    }

    /// Verbose bulk line for a file with no pixel data.
    public static func bulkSkipLine(fileName: String) -> String {
        "⚠ Skipping (no pixel data): \(fileName)"
    }

    /// Verbose bulk per-file success line (full output path).
    public static func bulkSuccessLine(path: String) -> String {
        "✓ \(path)"
    }

    /// Verbose bulk per-file failure line.
    public static func bulkFailureLine(fileName: String, message: String) -> String {
        "✗ \(fileName): \(message)"
    }

    /// The unconditional end-of-bulk summary line.
    public static func bulkSummaryLine(success: Int, total: Int, failed: Int) -> String {
        "Bulk export complete: \(success)/\(total) succeeded, \(failed) failed"
    }
}
