// NEMA-verified: 2026a, checked 2026-09-29 — writes every Type 1/2 attribute of the Encapsulated Document IOD modules (PS3.3 2026a Tables C.7-1, C.7-3, C.24-1, C.7-8, C.8-24, C.24-2, C.12-1) with the VRs of PS3.6 Table 6-1; Source Instance Sequence 1C and Burned In Annotation per Table C.24-2 (private SOP Class, EXPERIMENTAL); the source Photometric Interpretation (PS3.3 C.7.6.3.1.2) round-trips through the sidecar instead of being forced to MONOCHROME2 (D33)
// NEMA-verified: 2026a, checked 2026-10-01 — decode-volume slices: Image Position (Patient) = origin + i·spacing·(row × column cosine) per PS3.3 2026a C.7.6.2.1.1 Equation C.7.6.2.1-1, Image Orientation (Patient) / Pixel Spacing per Table C.7-10, one Frame of Reference UID per series (C.7.4.1.1.1), Rescale from the source, source SOP Class kept (D204); sidecar origin and spacing from the bridge's sorted order along the slice normal (D205)
import Foundation
import DICOMCore
import J2KCore
import J2K3D

/// Encapsulated SOP adapter for JP3D volumetric data.
///
/// `JP3DVolumeDocument` wraps a complete JP3D codestream inside a DICOM
/// Encapsulated Document IOD, allowing multi-frame volumetric data to be
/// stored as a single DICOM file.
///
/// ## Private SOP Class
///
/// JP3D has no DICOM-standard SOP class. This implementation uses:
/// - **SOP Class UID**: `1.2.826.0.1.3680043.10.511.10`
///   ("DICOMKit JP3D Volumetric Storage — EXPERIMENTAL")
/// - **MIME type**: `application/x-jp3d` (unregistered, DICOMKit internal)
///
/// These UIDs and MIME types are **not interoperable** with other DICOM
/// implementations and are clearly labelled experimental.
///
/// ## Warning
///
/// This SOP class is experimental and may change or be removed in future
/// versions of DICOMKit. Do **not** use it for clinical data storage.
/// See `Documentation/ConformanceStatement.md` for limitations.
///
/// ## Usage
///
/// ```swift
/// // Write: encode a series to a JP3D document
/// let doc = try await JP3DVolumeDocument.encode(
///     series: dicomFiles,
///     compressionMode: .lossless,
///     studyInstanceUID: studyUID,
///     seriesInstanceUID: seriesUID
/// )
/// let data = try doc.write()
/// try data.write(to: outputURL)
///
/// // Read: detect and decode a JP3D document
/// let dicomFile = try DICOMFile.read(from: inputURL)
/// if JP3DVolumeDocument.isJP3DVolumeDocument(dicomFile) {
///     let series = try await JP3DVolumeDocument.decode(from: dicomFile)
///     // series is [DICOMFile], one per slice
/// }
/// ```
public enum JP3DVolumeDocument: Sendable {

    // MARK: - SOP Class Constants

    /// Private SOP Class UID for the DICOMKit JP3D Volumetric Storage.
    ///
    /// **Experimental** — not interoperable with other DICOM implementations.
    /// Documented in `Documentation/ConformanceStatement.md`.
    public static let sopClassUID = "1.2.826.0.1.3680043.10.511.10"

    /// MIME type used for the embedded JP3D codestream.
    public static let mimeType = "application/x-jp3d"

    /// Document title embedded in the DICOM file.
    public static let documentTitle = "JP3D Volumetric Codestream (EXPERIMENTAL)"

    // MARK: - Metadata Keys (stored as JSON sidecar in DocumentTitle-equivalent OB element)

    private static let metadataMIMEType = "application/x-jp3d-meta+json"

    // MARK: - Detection

    /// Returns `true` if the given DICOM file is a JP3D volume document.
    ///
    /// Detection checks both the SOP Class UID and the MIME type of the
    /// encapsulated document to guard against false positives.
    ///
    /// - Parameter file: A `DICOMFile` to inspect.
    /// - Returns: `true` when the file contains a JP3D codestream.
    public static func isJP3DVolumeDocument(_ file: DICOMFile) -> Bool {
        let fmiSOP = file.fileMetaInformation.string(for: .mediaStorageSOPClassUID)
        let dsSOP = file.dataSet.string(for: .sopClassUID)
        let mime = file.dataSet.string(for: .mimeTypeOfEncapsulatedDocument)

        let sopMatch = (fmiSOP == sopClassUID) || (dsSOP == sopClassUID)
        let mimeMatch = mime == mimeType
        return sopMatch && mimeMatch
    }

    // MARK: - Encoding

    /// Encodes a DICOM multi-frame series as a single JP3D Encapsulated Document.
    ///
    /// The series is sorted, validated, converted to a `J2KVolume`, and encoded
    /// with JP3D. The resulting codestream is embedded into a DICOM Encapsulated
    /// Document IOD alongside a JSON sidecar that preserves voxel geometry metadata.
    ///
    /// - Parameters:
    ///   - series: Sorted or unsorted array of DICOM files forming a volume.
    ///   - compressionMode: JP3D compression mode (default: `.lossless`).
    ///   - studyInstanceUID: Study UID for the output file (uses series if nil).
    ///   - seriesInstanceUID: Series UID for the output file (auto-generated if nil).
    ///   - sopInstanceUID: SOP Instance UID (auto-generated if nil).
    /// - Returns: A `DICOMFile` containing the encoded JP3D volume document.
    /// - Throws: `JP3DVolumeBridge.BridgeError` or `DICOMError` on failure.
    public static func encode(
        series: [DICOMFile],
        compressionMode: JP3DCodec.CompressionMode = .lossless,
        studyInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil,
        sopInstanceUID: String? = nil
    ) async throws -> DICOMFile {
        guard !series.isEmpty else {
            throw JP3DVolumeBridge.BridgeError.emptySeries
        }

        // Build volume from series
        let volume = try JP3DVolumeBridge.makeVolume(from: series)

        // One Photometric Interpretation / High Bit / Bits Stored for the whole
        // volume: the sidecar records the first slice's (PS3.3 Table C.7-11c).
        let ref = series[0].dataSet
        _ = try DICOMFile.uniformPixelEncoding(
            of: series,
            rows: Int(ref.uint16(for: .rows) ?? 0),
            columns: Int(ref.uint16(for: .columns) ?? 0))

        // Encode volume to JP3D codestream
        let descriptor = makeDescriptor(from: series[0].dataSet, depth: series.count)
        let codec = JP3DCodec(compressionMode: compressionMode)
        guard let component = volume.components.first else {
            throw JP3DVolumeBridge.BridgeError.unsupportedPixelFormat("Volume has no components")
        }
        let codestream = try await codec.encodeVolume(component.data, descriptor: descriptor)

        // Build JSON metadata sidecar
        let meta = makeMetadata(from: series, volume: volume, compressionMode: compressionMode)
        let metaJSON = try JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys, .prettyPrinted])

        // Assemble Encapsulated Document + meta payload
        // Layout: [4-byte JP3D length LE][jp3d codestream][4-byte JSON length LE][JSON bytes]
        var payload = Data()
        var jp3dLen = UInt32(codestream.count).littleEndian
        payload.append(Data(bytes: &jp3dLen, count: 4))
        payload.append(codestream)
        var jsonLen = UInt32(metaJSON.count).littleEndian
        payload.append(Data(bytes: &jsonLen, count: 4))
        payload.append(metaJSON)

        // Resolve UIDs
        let template = series[0].dataSet
        let studyUID = studyInstanceUID
            ?? template.string(for: .studyInstanceUID)
            ?? UIDGenerator.generateUID().value
        let seriesUID = seriesInstanceUID ?? UIDGenerator.generateUID().value
        let instanceUID = sopInstanceUID ?? UIDGenerator.generateUID().value

        // Build data set. The private SOP Class follows the Encapsulated Document
        // IOD shape (PS3.3 Table A.45.1-1): every Type 1/2 attribute of its Mandatory
        // modules is written, empty where unknown (PS3.5 7.4.3).

        var ds = DataSet()

        // Patient Module, Table C.7-1 (all Type 2).
        ds.setString(template.string(for: .patientName) ?? "", for: .patientName, vr: .PN)
        ds.setString(template.string(for: .patientID) ?? "", for: .patientID, vr: .LO)
        ds.setString(template.string(for: .patientBirthDate) ?? "", for: .patientBirthDate, vr: .DA)
        ds.setString(template.string(for: .patientSex) ?? "", for: .patientSex, vr: .CS)

        // General Study Module, Table C.7-3 (Study Instance UID 1, the rest Type 2).
        ds.setString(studyUID, for: .studyInstanceUID, vr: .UI)
        ds.setString(template.string(for: .studyDate) ?? "", for: .studyDate, vr: .DA)
        ds.setString(template.string(for: .studyTime) ?? "", for: .studyTime, vr: .TM)
        ds.setString(template.string(for: .referringPhysicianName) ?? "", for: .referringPhysicianName, vr: .PN)
        ds.setString(template.string(for: .studyID) ?? "", for: .studyID, vr: .SH)
        ds.setString(template.string(for: .accessionNumber) ?? "", for: .accessionNumber, vr: .SH)

        // Encapsulated Document Series Module, Table C.24-1 (all Type 1).
        ds.setString(seriesUID, for: .seriesInstanceUID, vr: .UI)
        ds.setString(Modality.doc.rawValue, for: .modality, vr: .CS)
        ds.setInt(1, for: .seriesNumber, vr: .IS)

        // SOP Common Module, Table C.12-1.
        ds.setString(sopClassUID, for: .sopClassUID, vr: .UI)
        ds.setString(instanceUID, for: .sopInstanceUID, vr: .UI)

        // General Equipment Module, Table C.7-8 (Manufacturer Type 2) and SC Equipment
        // Module, Table C.8-24 (Conversion Type Type 1; Defined Term WSD = Workstation).
        ds.setString("DICOMKit", for: .manufacturer, vr: .LO)
        ds.setString("JP3DVolumeDocument", for: .manufacturerModelName, vr: .LO)
        ds.setString("DICOMKit \(version)", for: .softwareVersions, vr: .LO)
        ds.setString("WSD", for: .conversionType, vr: .CS)

        // Encapsulated Document Module, Table C.24-2.
        ds.setString("1", for: .instanceNumber, vr: .IS)                                   // Type 1
        ds.setString(mimeType, for: .mimeTypeOfEncapsulatedDocument, vr: .LO)              // Type 1
        ds.setString(documentTitle, for: .documentTitle, vr: .ST)                          // Type 2
        ds.setSequence([], for: .conceptNameCodeSequence)                                  // Type 2
        ds.setString(template.string(for: .acquisitionDateTime) ?? "", for: .acquisitionDateTime, vr: .DT) // Type 2
        ds[.encapsulatedDocument] = DataElement.data(                                      // Type 1
            tag: .encapsulatedDocument,
            vr: .OB,
            data: payload
        )
        // Burned In Annotation (Type 1): Table C.24-2 equates patient identification
        // as text in the document with burned-in annotation, and the JSON sidecar
        // carries Patient's Name / Patient ID when the source series has them.
        let sidecarIdentifies = meta["patientName"] != nil || meta["patientID"] != nil
        ds.setString(sidecarIdentifies ? "YES" : "NO", for: .burnedInAnnotation, vr: .CS)

        // Source Instance Sequence (Type 1C: "Required if derived from one or more
        // DICOM Instances") — one Item per source slice (Table 10-11 SOP Instance
        // Reference Macro: Referenced SOP Class UID 1, Referenced SOP Instance UID 1).
        let sourceItems: [SequenceItem] = series.compactMap { file in
            guard let classUID = file.dataSet.string(for: .sopClassUID),
                  let instance = file.dataSet.string(for: .sopInstanceUID) else { return nil }
            return SequenceItem(elements: [
                DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: classUID),
                DataElement.string(tag: .referencedSOPInstanceUID, vr: .UI, value: instance),
            ])
        }
        if !sourceItems.isEmpty {
            ds.setSequence(sourceItems, for: .sourceInstanceSequence)
        }

        // Content Date/Time (Type 2): the document content creation start.
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let dateStr = String(format: "%04d%02d%02d",
            comps.year ?? 2026, comps.month ?? 1, comps.day ?? 1)
        let timeStr = String(format: "%02d%02d%02d",
            comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0)
        ds.setString(dateStr, for: .contentDate, vr: .DA)
        ds.setString(timeStr, for: .contentTime, vr: .TM)

        // Use Explicit VR Little Endian for the container file
        let tsUID = TransferSyntax.explicitVRLittleEndian.uid
        return DICOMFile.create(
            dataSet: ds,
            sopClassUID: sopClassUID,
            sopInstanceUID: instanceUID,
            transferSyntaxUID: tsUID
        )
    }

    // MARK: - Decoding

    /// Decodes a JP3D Encapsulated Document back to a synthetic multi-frame series.
    ///
    /// Reads the JP3D codestream and JSON sidecar from the encapsulated document,
    /// decodes the volume using `JP3DDecoder`, and reconstructs individual DICOM files
    /// using the template metadata stored in the sidecar.
    ///
    /// - Parameter file: A `DICOMFile` known to be a JP3D volume document.
    /// - Returns: An array of `DICOMFile`, one per decoded slice.
    /// - Throws: `DICOMError` if parsing or decoding fails.
    public static func decode(from file: DICOMFile) async throws -> [DICOMFile] {
        guard let payloadElement = file.dataSet[.encapsulatedDocument] else {
            throw DICOMError.parsingFailed("JP3D document: missing Encapsulated Document element")
        }
        let payload = payloadElement.valueData

        // Parse composite payload: [4-byte JP3D len][jp3d][4-byte JSON len][json]
        guard payload.count >= 8 else {
            throw DICOMError.parsingFailed("JP3D document: payload too short (\(payload.count) bytes)")
        }

        let jp3dLen = Int(payload.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
        guard 4 + jp3dLen + 4 <= payload.count else {
            throw DICOMError.parsingFailed("JP3D document: JP3D codestream length overflows payload")
        }
        let codestream = payload.subdata(in: 4..<(4 + jp3dLen))

        let jsonOffset = 4 + jp3dLen
        let jsonLen = Int(payload.subdata(in: jsonOffset..<(jsonOffset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
        guard jsonOffset + 4 + jsonLen <= payload.count else {
            throw DICOMError.parsingFailed("JP3D document: JSON sidecar length overflows payload")
        }
        let jsonData = payload.subdata(in: (jsonOffset + 4)..<(jsonOffset + 4 + jsonLen))

        // Parse sidecar to get geometry
        guard let meta = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw DICOMError.parsingFailed("JP3D document: failed to parse JSON sidecar")
        }

        let rows = meta["rows"] as? Int ?? 0
        let columns = meta["columns"] as? Int ?? 0
        let frames = meta["frames"] as? Int ?? 0
        let bitsAllocated = meta["bitsAllocated"] as? Int ?? 16
        let bitsStored = meta["bitsStored"] as? Int ?? 12
        let isSigned = meta["signed"] as? Bool ?? false

        guard rows > 0, columns > 0, frames > 0 else {
            throw DICOMError.parsingFailed("JP3D document: invalid geometry in sidecar (rows=\(rows) cols=\(columns) frames=\(frames))")
        }

        // Decode the JP3D codestream
        let descriptor = PixelDataDescriptor(
            rows: rows,
            columns: columns,
            numberOfFrames: frames,
            bitsAllocated: bitsAllocated,
            bitsStored: bitsStored,
            highBit: bitsStored - 1,
            isSigned: isSigned,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        let codec = JP3DCodec()
        let pixelData = try await codec.decodeVolume(codestream, descriptor: descriptor)

        // Build a synthetic template DICOMFile from the sidecar metadata
        let template = buildTemplate(from: meta, fileDataSet: file.dataSet)

        // Use bridge to reconstruct slices from decoded volume
        let sliceSpacing = meta["sliceSpacing"] as? Double
        let origin = meta["origin"] as? [Double] ?? [0, 0, 0]
        // Sidecars written before 2026-10-01 carry no orientation: those volumes were stacked
        // along z, i.e. the axial orientation (1,0,0,0,1,0)
        let orientation = (meta["imageOrientationPatient"] as? [Double]).flatMap { $0.count == 6 ? $0 : nil }
        let pixelSpacing = (meta["pixelSpacing"] as? [Double]).flatMap { $0.count == 2 ? $0 : nil }
            ?? [meta["spacingY"] as? Double ?? 1.0, meta["spacingX"] as? Double ?? 1.0]
        // Sidecars written before the field existed carry no interpretation; the
        // encoder then always wrote MONOCHROME2.
        let photometric = (meta["photometricInterpretation"] as? String)
            .flatMap(PhotometricInterpretation.init(rawValue:))
            .flatMap { $0 == .monochrome1 || $0 == .monochrome2 ? $0 : nil }
            ?? .monochrome2
        return try reconstructSlices(
            pixelData: pixelData,
            descriptor: descriptor,
            photometricInterpretation: photometric,
            template: template,
            sliceSpacing: sliceSpacing ?? 1.0,
            origin: origin,
            orientation: orientation,
            pixelSpacing: pixelSpacing
        )
    }

    /// The Storage SOP Class of the decoded slices when the sidecar does not record the
    /// source's (sidecars written before 2026-10-01): by Modality, CT Image Storage, MR Image
    /// Storage or Positron Emission Tomography Image Storage, else Secondary Capture Image
    /// Storage (PS3.4 2026a Table B.5-1). Until then CT Image Storage was used for any source.
    static func fallbackSOPClassUID(modality: String?) -> String {
        switch modality?.trimmingCharacters(in: .whitespaces).uppercased() {
        case "CT": return "1.2.840.10008.5.1.4.1.1.2"
        case "MR": return "1.2.840.10008.5.1.4.1.1.4"
        case "PT": return "1.2.840.10008.5.1.4.1.1.128"
        default: return "1.2.840.10008.5.1.4.1.1.7"
        }
    }

    /// Image Position (Patient) of slice `index`: the first slice's position moved `index`
    /// slice spacings along the normal of Image Orientation (Patient) (row cosine × column
    /// cosine, PS3.3 2026a C.7.6.2.1.1)
    static func slicePosition(origin: [Double], orientation: [Double], spacing: Double, index: Int) -> [Double] {
        let o = origin.count >= 3 ? Array(origin.prefix(3)) : [0, 0, 0]
        let r = Array(orientation[0..<3]), c = Array(orientation[3..<6])
        var n = [r[1] * c[2] - r[2] * c[1], r[2] * c[0] - r[0] * c[2], r[0] * c[1] - r[1] * c[0]]
        let length = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).squareRoot()
        n = length > 1e-6 ? n.map { $0 / length } : [0, 0, 1]
        return (0..<3).map { o[$0] + Double(index) * spacing * n[$0] }
    }

    /// A DS value: the shortest decimal form, at most 16 characters (PS3.5 Table 6.2-1)
    static func decimalString(_ value: Double) -> String {
        let rounded = (value * 1e6).rounded() / 1e6
        var text = rounded == rounded.rounded() ? String(format: "%.0f", rounded) : String(rounded)
        if text == "-0" { text = "0" }
        return text.count <= 16 ? text : String(format: "%.10g", rounded)
    }

    // MARK: - Private helpers

    private static func makeDescriptor(from ds: DataSet, depth: Int) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: Int(ds.uint16(for: .rows) ?? 0),
            columns: Int(ds.uint16(for: .columns) ?? 0),
            numberOfFrames: depth,
            bitsAllocated: Int(ds.uint16(for: .bitsAllocated) ?? 16),
            bitsStored: Int(ds.uint16(for: .bitsStored) ?? 12),
            highBit: Int((ds.uint16(for: .bitsStored) ?? 12)) - 1,
            isSigned: (ds.uint16(for: .pixelRepresentation) ?? 0) != 0,
            samplesPerPixel: Int(ds.uint16(for: .samplesPerPixel) ?? 1),
            photometricInterpretation: .monochrome2
        )
    }

    private static func makeMetadata(
        from series: [DICOMFile],
        volume: J2KVolume,
        compressionMode: JP3DCodec.CompressionMode
    ) -> [String: Any] {
        let ds = series[0].dataSet
        var meta: [String: Any] = [
            "rows": volume.height,
            "columns": volume.width,
            "frames": volume.depth,
            "bitsAllocated": Int(ds.uint16(for: .bitsAllocated) ?? 16),
            "bitsStored": Int(ds.uint16(for: .bitsStored) ?? 12),
            "signed": (ds.uint16(for: .pixelRepresentation) ?? 0) != 0,
            // The source Photometric Interpretation is kept so that a MONOCHROME1
            // series (minimum displayed as white, PS3.3 C.7.6.3.1.2) is not
            // reconstructed as MONOCHROME2 with the same stored values, which
            // would display it inverted.
            "photometricInterpretation": ds.string(for: .photometricInterpretation)
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? "MONOCHROME2",
            "spacingX": volume.spacingX,
            "spacingY": volume.spacingY,
            "spacingZ": volume.spacingZ,
            "originX": volume.originX,
            "originY": volume.originY,
            "originZ": volume.originZ,
            "generator": "DICOMKit/JP3DVolumeDocument",
            "version": 1
        ]

        // Store compression mode for informational purposes
        switch compressionMode {
        case .lossless: meta["compressionMode"] = "lossless"
        case .losslessHTJ2K: meta["compressionMode"] = "losslessHTJ2K"
        case .lossy(let psnr): meta["compressionMode"] = "lossy"; meta["psnr"] = psnr
        case .lossyHTJ2K(let psnr): meta["compressionMode"] = "lossyHTJ2K"; meta["psnr"] = psnr
        }

        // Geometry in the voxel order JP3DVolumeBridge.makeVolume stacks the slices: sorted
        // along the slice normal of Image Orientation (Patient) (PS3.3 2026a C.7.6.2.1.1).
        // Until 2026-10-01 (D205) the origin came from the unsorted series[0] and the spacing
        // from the z coordinates of the first and last input files.
        let sorted = (try? JP3DVolumeBridge.sortedForVolume(series)) ?? series
        let first = sorted[0].dataSet

        // Slice spacing: distance between adjacent slices along the normal
        if sorted.count > 1,
           let sp = try? JP3DVolumeBridge.uniformSliceSpacing(sorted) {
            meta["sliceSpacing"] = sp
        }

        // Image Position (Patient) of the first slice in that order
        if let parts = JP3DVolumeBridge.decimals(first, .imagePositionPatient), parts.count == 3 {
            meta["origin"] = parts
        }

        // Image Orientation (Patient) (Table C.7-10, Type 1), Pixel Spacing (Type 1), Frame of
        // Reference UID (C.7.4.1.1.1) and the Modality LUT rescale (C.11.1) for decode-volume
        if let iop = JP3DVolumeBridge.decimals(first, .imageOrientationPatient), iop.count == 6 {
            meta["imageOrientationPatient"] = iop
        }
        if let ps = JP3DVolumeBridge.decimals(first, .pixelSpacing), ps.count == 2 {
            meta["pixelSpacing"] = ps
        }
        if let uid = first.string(for: .frameOfReferenceUID) { meta["frameOfReferenceUID"] = uid }
        if let slope = first.string(for: .rescaleSlope) { meta["rescaleSlope"] = slope.trimmingCharacters(in: .whitespaces) }
        if let intercept = first.string(for: .rescaleIntercept) { meta["rescaleIntercept"] = intercept.trimmingCharacters(in: .whitespaces) }
        if let type = first.string(for: .rescaleType) { meta["rescaleType"] = type.trimmingCharacters(in: .whitespaces) }
        if let sopClass = first.string(for: .sopClassUID) { meta["sopClassUID"] = sopClass }

        // Preserve key patient/study tags for round-trip fidelity
        if let uid = ds.string(for: .studyInstanceUID) { meta["studyInstanceUID"] = uid }
        if let uid = ds.string(for: .seriesInstanceUID) { meta["sourceSeriesInstanceUID"] = uid }
        if let name = ds.string(for: .patientName) { meta["patientName"] = name }
        if let pid = ds.string(for: .patientID) { meta["patientID"] = pid }
        if let mod = ds.string(for: .modality) { meta["modality"] = mod }
        if let sn = ds.string(for: .seriesDescription) { meta["seriesDescription"] = sn }
        if let thick = ds.string(for: .sliceThickness) { meta["sliceThickness"] = thick }

        return meta
    }

    private static func buildTemplate(from meta: [String: Any], fileDataSet: DataSet) -> DICOMFile {
        var ds = DataSet()
        if let name = (meta["patientName"] as? String) ?? fileDataSet.string(for: .patientName) {
            ds.setString(name, for: .patientName, vr: .PN)
        }
        if let pid = (meta["patientID"] as? String) ?? fileDataSet.string(for: .patientID) {
            ds.setString(pid, for: .patientID, vr: .LO)
        }
        if let uid = (meta["studyInstanceUID"] as? String) ?? fileDataSet.string(for: .studyInstanceUID) {
            ds.setString(uid, for: .studyInstanceUID, vr: .UI)
        }
        if let uid = meta["sourceSeriesInstanceUID"] as? String {
            ds.setString(uid, for: .seriesInstanceUID, vr: .UI)
        }
        if let mod = meta["modality"] as? String {
            ds.setString(mod, for: .modality, vr: .CS)
        }
        if let sopClass = meta["sopClassUID"] as? String {
            ds.setString(sopClass, for: .sopClassUID, vr: .UI)
        }
        if let uid = meta["frameOfReferenceUID"] as? String {
            ds.setString(uid, for: .frameOfReferenceUID, vr: .UI)
        }
        if let slope = meta["rescaleSlope"] as? String, let intercept = meta["rescaleIntercept"] as? String {
            ds.setString(intercept, for: .rescaleIntercept, vr: .DS)
            ds.setString(slope, for: .rescaleSlope, vr: .DS)
            if let type = meta["rescaleType"] as? String { ds.setString(type, for: .rescaleType, vr: .LO) }
        }
        let fmi = DataSet()
        return DICOMFile(fileMetaInformation: fmi, dataSet: ds)
    }

    private static func reconstructSlices(
        pixelData: Data,
        descriptor: PixelDataDescriptor,
        photometricInterpretation: PhotometricInterpretation,
        template: DICOMFile,
        sliceSpacing: Double,
        origin: [Double],
        orientation: [Double]?,
        pixelSpacing: [Double]
    ) throws -> [DICOMFile] {
        let iop = orientation ?? [1, 0, 0, 0, 1, 0]
        let frameOfReferenceUID = template.dataSet.string(for: .frameOfReferenceUID)
            ?? UIDGenerator.generateUID().value
        let sopClassUID = template.dataSet.string(for: .sopClassUID)
            ?? fallbackSOPClassUID(modality: template.dataSet.string(for: .modality))
        let bytesPerFrame = descriptor.bytesPerFrame
        let seriesUID = template.dataSet.string(for: .seriesInstanceUID) ?? UIDGenerator.generateUID().value
        let studyUID = template.dataSet.string(for: .studyInstanceUID) ?? UIDGenerator.generateUID().value

        var slices: [DICOMFile] = []
        for i in 0..<descriptor.numberOfFrames {
            let start = i * bytesPerFrame
            guard start + bytesPerFrame <= pixelData.count else { break }
            let frameData = pixelData.subdata(in: start..<(start + bytesPerFrame))

            var ds = template.dataSet

            // Geometry
            ds.setUInt16(UInt16(descriptor.rows), for: .rows)
            ds.setUInt16(UInt16(descriptor.columns), for: .columns)
            ds.setUInt16(UInt16(descriptor.bitsAllocated), for: .bitsAllocated)
            ds.setUInt16(UInt16(descriptor.bitsStored), for: .bitsStored)
            ds.setUInt16(UInt16(descriptor.bitsStored - 1), for: .highBit)
            ds.setUInt16(descriptor.isSigned ? 1 : 0, for: .pixelRepresentation)
            ds.setUInt16(1, for: .samplesPerPixel)
            ds.setString(photometricInterpretation.rawValue, for: .photometricInterpretation, vr: .CS)

            // Identity
            ds.setString(sopClassUID, for: .sopClassUID, vr: .UI)
            ds.setString(UIDGenerator.generateUID().value, for: .sopInstanceUID, vr: .UI)
            ds.setString(studyUID, for: .studyInstanceUID, vr: .UI)
            ds.setString(seriesUID, for: .seriesInstanceUID, vr: .UI)
            ds.setInt(i + 1, for: .instanceNumber, vr: .IS)

            // Image Plane Module (PS3.3 2026a Table C.7-10): Image Position (Patient) moved
            // along the slice normal (C.7.6.2.1.1), Image Orientation (Patient) and Pixel
            // Spacing (Type 1); Slice Location (Type 3, "relative to an unspecified
            // implementation specific reference point", C.7.6.2.1.2) is the position along
            // the normal. Frame of Reference UID (Table C.7-6, C.7.4.1.1.1): one per series.
            // Until 2026-10-01 (D204) only z moved and the other attributes were not written.
            let position = slicePosition(origin: origin, orientation: iop, spacing: sliceSpacing, index: i)
            ds.setString(position.map(decimalString).joined(separator: "\\"), for: .imagePositionPatient, vr: .DS)
            ds.setString(iop.map(decimalString).joined(separator: "\\"), for: .imageOrientationPatient, vr: .DS)
            ds.setString(pixelSpacing.map(decimalString).joined(separator: "\\"), for: .pixelSpacing, vr: .DS)
            ds.setString(frameOfReferenceUID, for: .frameOfReferenceUID, vr: .UI)
            let normal = JP3DVolumeBridge.sliceNormal(of: ds) ?? [0, 0, 1]
            let location = position[0] * normal[0] + position[1] * normal[1] + position[2] * normal[2]
            ds.setString(decimalString(location), for: .sliceLocation, vr: .DS)

            // Pixel data (uncompressed)
            ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: frameData)

            let sliceFile = DICOMFile.create(
                dataSet: ds,
                sopClassUID: sopClassUID,
                sopInstanceUID: ds.string(for: .sopInstanceUID) ?? UIDGenerator.generateUID().value,
                transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid
            )
            slices.append(sliceFile)
        }
        return slices
    }
}
