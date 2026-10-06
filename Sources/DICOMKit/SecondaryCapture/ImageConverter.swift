// NEMA-verified: 2026a, checked 2026-10-06 — SC Image IOD (Table A.8-1) Type 1/2 attributes written: Patient C.7-1, General Study C.7-3, General Series C.7-5a, General Image C.7-9, Image Pixel C.7-11a, SC Equipment C.8-24 (Conversion Type; converter identity in Secondary Capture Device Manufacturer / Model Name / Software Versions (0018,1016/1018/1019) per the C.8.6.1 scenario table, General Equipment (U) not written), SC Image C.8-25 (Nominal Scanned Pixel Spacing); Specific Character Set ISO_IR 192 for non-ASCII text (Table C.12-1 1C, C.12-5); EXIF text in Study Description cut to LO (64 chars, no backslash or control characters, PS3.5 Table 6.2-1); Study Date / Time (0008,0020/0030) Type 2 "Date / Time the Study started" (Table C.7-3) from Metadata, empty when nil (PS3.5 7.4.3), the conversion moment as Instance Creation Date / Time (0008,0012/0013, Table C.12-1) and Date / Time of Secondary Capture (0018,1012/1014, Table C.8-25), DA on the Gregorian calendar (PS3.5 Table 6.2-1); VRs per PS3.6 Table 6-1
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

/// Errors raised while converting a standard image to DICOM Secondary Capture.
public enum ImageConversionError: Error, LocalizedError {
    case imageLoadFailed
    case pixelDataExtractionFailed
    case contextCreationFailed
    case noPages
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .imageLoadFailed: return "Failed to load image file"
        case .pixelDataExtractionFailed: return "Failed to extract pixel data from image"
        case .contextCreationFailed: return "Failed to create graphics context"
        case .noPages: return "TIFF file contains no pages"
        case .unsupportedPlatform: return "Image conversion not supported on this platform"
        }
    }
}

/// Converts standard images (JPEG/PNG/TIFF/…) to DICOM Secondary Capture.
///
/// Lives in the DICOMKit library so the `dicom-image` CLI and DICOMStudio run the
/// exact same conversion (pixel extraction, color-space handling, EXIF mapping,
/// Secondary Capture data-set assembly). Each adapter keeps its own orchestration
/// (file enumeration, output paths, sandbox writes, summaries); the per-image core
/// is shared here. UIDs are minted with `DICOMCore.UIDGenerator` for conformance.
public enum ImageConverter {

    /// Per-image Secondary Capture metadata.
    public struct Metadata: Sendable {
        public var patientName: String
        public var patientID: String
        public var studyUID: String
        public var seriesUID: String
        public var instanceNumber: Int
        public var studyDescription: String?
        public var seriesDescription: String?
        public var modality: String
        public var seriesNumber: Int?
        /// Conversion Type (0008,0064), Type 1 in the SC Equipment Module (PS3.3
        /// Table C.8-24). WSD (Workstation) by default; use `.scannedImage` /
        /// `.scannedDocument` for scans, `.drawing` for drawings.
        public var conversionType: ConversionType
        /// Patient's Birth Date (0010,0030), Type 2; written empty when nil.
        public var patientBirthDate: DICOMDate?
        /// Patient's Sex (0010,0040), Type 2 (M, F or O); written empty when nil.
        public var patientSex: String?
        /// Referring Physician's Name (0008,0090), Type 2; written empty when nil.
        public var referringPhysicianName: String?
        /// Study ID (0020,0010), Type 2; written empty when nil.
        public var studyID: String?
        /// Accession Number (0008,0050), Type 2; written empty when nil.
        public var accessionNumber: String?
        /// Study Date (0008,0020), Type 2: "Date the Study started" (PS3.3 2026a Table C.7-3);
        /// written empty when nil. ``OutputRules/studyDateTime(studyDate:studyTime:studyUID:runDate:)``
        /// gives the value both adapters use.
        public var studyDate: DICOMDate?
        /// Study Time (0008,0030), Type 2: "Time the Study started"; written empty when nil.
        public var studyTime: DICOMTime?
        /// The moment this instance is converted, written as Date / Time of Secondary Capture
        /// (0018,1012 / 0018,1014; SC Image Module, Table C.8-25) and Instance Creation Date /
        /// Time (0008,0012 / 0008,0013; SOP Common Module, Table C.12-1), in local time.
        public var conversionDate: Date

        public init(
            patientName: String, patientID: String,
            studyUID: String, seriesUID: String, instanceNumber: Int,
            studyDescription: String? = nil, seriesDescription: String? = nil,
            modality: String = "OT", seriesNumber: Int? = nil,
            conversionType: ConversionType = .workstation,
            patientBirthDate: DICOMDate? = nil, patientSex: String? = nil,
            referringPhysicianName: String? = nil, studyID: String? = nil,
            accessionNumber: String? = nil,
            studyDate: DICOMDate? = nil, studyTime: DICOMTime? = nil,
            conversionDate: Date = Date()
        ) {
            self.patientName = patientName
            self.patientID = patientID
            self.studyUID = studyUID
            self.seriesUID = seriesUID
            self.instanceNumber = instanceNumber
            self.studyDescription = studyDescription
            self.seriesDescription = seriesDescription
            self.modality = modality
            self.seriesNumber = seriesNumber
            self.conversionType = conversionType
            self.patientBirthDate = patientBirthDate
            self.patientSex = patientSex
            self.referringPhysicianName = referringPhysicianName
            self.studyID = studyID
            self.accessionNumber = accessionNumber
            self.studyDate = studyDate
            self.studyTime = studyTime
            self.conversionDate = conversionDate
        }
    }

    /// A fresh DICOM UID (delegates to the shared `UIDGenerator`).
    public static func generateUID() -> String {
        UIDGenerator.generateUID().value
    }

    /// Whether the URL looks like a supported image by extension.
    public static func isImageFile(_ url: URL) -> Bool {
        let supportedExtensions = ["jpg", "jpeg", "png", "tif", "tiff", "bmp", "gif"]
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    #if canImport(CoreGraphics)
    /// Number of pages/frames in an image (1 for most formats; >1 for multi-page TIFF).
    public static func pageCount(of imageURL: URL) throws -> Int {
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else {
            throw ImageConversionError.imageLoadFailed
        }
        return CGImageSourceGetCount(imageSource)
    }

    /// Loads one page of an image and returns a DICOM Secondary Capture file as
    /// bytes. `useExif` pulls acquisition date/time, pixel spacing, and a study
    /// description from the image's metadata.
    public static func secondaryCaptureData(
        imageURL: URL,
        pageIndex: Int = 0,
        metadata: Metadata,
        useExif: Bool
    ) throws -> Data {
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, pageIndex, nil) else {
            throw ImageConversionError.imageLoadFailed
        }

        var exifMetadata: [String: Any]?
        if useExif {
            if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, pageIndex, nil) as? [String: Any] {
                exifMetadata = properties
            }
        }

        let dataSet = try makeSecondaryCaptureDataSet(image: cgImage, metadata: metadata, exifMetadata: exifMetadata)
        let dicomFile = DICOMFile.create(dataSet: dataSet, transferSyntaxUID: "1.2.840.10008.1.2.1")
        return try dicomFile.write()
    }

    // MARK: - Secondary Capture DataSet Creation

    private static func makeSecondaryCaptureDataSet(
        image: CGImage,
        metadata: Metadata,
        exifMetadata: [String: Any]?
    ) throws -> DataSet {
        var dataSet = DataSet()

        // SOP Common Module
        dataSet.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI) // Secondary Capture Image Storage
        dataSet.setString(generateUID(), for: .sopInstanceUID, vr: .UI)
        let conversionDate = OutputRules.localDate(metadata.conversionDate)
        let conversionTime = OutputRules.localTime(metadata.conversionDate)
        dataSet.setString(conversionDate.dicomString, for: .instanceCreationDate, vr: .DA)
        dataSet.setString(conversionTime.dicomString, for: .instanceCreationTime, vr: .TM)

        // Patient Module (Table C.7-1): all four Type 2
        dataSet.setString(metadata.patientName, for: .patientName, vr: .PN)
        dataSet.setString(metadata.patientID, for: .patientID, vr: .LO)
        dataSet.setString(metadata.patientBirthDate?.dicomString ?? "", for: .patientBirthDate, vr: .DA)
        dataSet.setString(metadata.patientSex ?? "", for: .patientSex, vr: .CS)

        // General Study Module (Table C.7-3)
        dataSet.setString(metadata.studyUID, for: .studyInstanceUID, vr: .UI)
        if let studyDesc = metadata.studyDescription {
            dataSet.setString(studyDesc, for: .studyDescription, vr: .LO)
        } else if let exifDesc = extractEXIFDescription(from: exifMetadata).flatMap(longStringValue) {
            dataSet.setString(exifDesc, for: .studyDescription, vr: .LO)
        }
        dataSet.setString(metadata.studyDate?.dicomString ?? "", for: .studyDate, vr: .DA)
        dataSet.setString(metadata.studyTime?.dicomString ?? "", for: .studyTime, vr: .TM)
        dataSet.setString(metadata.referringPhysicianName ?? "", for: .referringPhysicianName, vr: .PN)
        dataSet.setString(metadata.studyID ?? "", for: .studyID, vr: .SH)
        dataSet.setString(metadata.accessionNumber ?? "", for: .accessionNumber, vr: .SH)

        // General Series Module (Table C.7-5a)
        dataSet.setString(metadata.seriesUID, for: .seriesInstanceUID, vr: .UI)
        dataSet.setString(metadata.modality, for: .modality, vr: .CS)
        if let seriesDesc = metadata.seriesDescription {
            dataSet.setString(seriesDesc, for: .seriesDescription, vr: .LO)
        }
        dataSet.setString(metadata.seriesNumber.map(String.init) ?? "", for: .seriesNumber, vr: .IS)

        // SC Equipment Module (Table C.8-24): Conversion Type Type 1. The converter is
        // the Secondary Capture Device (0018,1016/1018/1019, Type 3); the General
        // Equipment Module (U in Table A.8-1) describes the equipment that created the
        // original image (C.8.6.1 scenario table), which is unknown here, so it is
        // not written.
        dataSet.setString(metadata.conversionType.standardTerm, for: .conversionType, vr: .CS)
        dataSet.setString(secondaryCaptureDeviceManufacturer,
                          for: Self.secondaryCaptureDeviceManufacturerTag, vr: .LO)
        dataSet.setString(secondaryCaptureDeviceModelName,
                          for: Self.secondaryCaptureDeviceManufacturerModelNameTag, vr: .LO)
        dataSet.setString(DICOMFile.implementationVersionName,
                          for: Self.secondaryCaptureDeviceSoftwareVersionsTag, vr: .LO)
        // SC Image Module (Table C.8-25): "The date / time the Secondary Capture Image was captured".
        dataSet.setString(conversionDate.dicomString, for: .dateOfSecondaryCapture, vr: .DA)
        dataSet.setString(conversionTime.dicomString, for: .timeOfSecondaryCapture, vr: .TM)

        // General Image Module (Table C.7-9): Instance Number Type 2, Patient
        // Orientation Type 2C (required: the SC IOD carries no Image Orientation
        // (Patient)); the orientation of an imported picture is unknown, so empty.
        dataSet.setInt(metadata.instanceNumber, for: .instanceNumber, vr: .IS)
        dataSet.setString("", for: .patientOrientation, vr: .CS)

        // Image Pixel Module
        let width = image.width
        let height = image.height
        let samplesPerPixel = getSamplesPerPixel(image: image)
        let photometricInterpretation = getPhotometricInterpretation(image: image)

        dataSet.setInt(samplesPerPixel, for: .samplesPerPixel, vr: .US)
        dataSet.setString(photometricInterpretation, for: .photometricInterpretation, vr: .CS)
        dataSet.setInt(height, for: .rows, vr: .US)
        dataSet.setInt(width, for: .columns, vr: .US)
        dataSet.setInt(8, for: .bitsAllocated, vr: .US)
        dataSet.setInt(8, for: .bitsStored, vr: .US)
        dataSet.setInt(7, for: .highBit, vr: .US)
        dataSet.setInt(0, for: .pixelRepresentation, vr: .US)

        if samplesPerPixel == 3 {
            dataSet.setInt(0, for: .planarConfiguration, vr: .US)
        }

        // Extract and convert pixel data
        let pixelData = try extractPixelData(from: image, samplesPerPixel: samplesPerPixel)
        dataSet[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: pixelData)

        // Add EXIF metadata if available
        if let exif = exifMetadata {
            addEXIFMetadataToDICOM(exif: exif, dataSet: &dataSet)
        }

        // Text is written as UTF-8: Specific Character Set (0008,0005) is Type 1C,
        // required when a value is not ASCII (Table C.12-1; ISO_IR 192, Table C.12-5).
        dataSet.setUTF8SpecificCharacterSetIfNeeded()

        return dataSet
    }
    #endif

    // MARK: - SC Equipment identity (PS3.3 2026a Table C.8-24)

    /// Secondary Capture Device Manufacturer (0018,1016), LO (PS3.6 Table 6-1).
    static let secondaryCaptureDeviceManufacturerTag = Tag(group: 0x0018, element: 0x1016)
    /// Secondary Capture Device Manufacturer's Model Name (0018,1018), LO.
    static let secondaryCaptureDeviceManufacturerModelNameTag = Tag(group: 0x0018, element: 0x1018)
    /// Secondary Capture Device Software Versions (0018,1019), LO, VM 1-n.
    static let secondaryCaptureDeviceSoftwareVersionsTag = Tag(group: 0x0018, element: 0x1019)

    /// The device that converts the image: this library (the same value whether the
    /// dicom-image CLI or DICOMStudio runs the conversion).
    static let secondaryCaptureDeviceManufacturer = "DICOMKit"
    static let secondaryCaptureDeviceModelName = "DICOMKit ImageConverter"

    /// A Long String (LO) value made from free text such as an EXIF description:
    /// control characters become spaces, the backslash (the value delimiter) becomes
    /// "/", and the result is trimmed and cut to 64 characters (PS3.5 2026a Table
    /// 6.2-1, LO). Nil when nothing printable is left.
    static func longStringValue(_ text: String) -> String? {
        let cleaned = String(text.unicodeScalars.map { scalar -> Character in
            if scalar == "\\" { return "/" }
            if scalar.properties.generalCategory == .control { return " " }
            return Character(scalar)
        })
        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return String(String(trimmed.prefix(64)).trimmingCharacters(in: .whitespaces))
    }

    #if canImport(CoreGraphics)

    // MARK: - Pixel / format helpers

    private static func extractPixelData(from image: CGImage, samplesPerPixel: Int) throws -> Data {
        let width = image.width
        let height = image.height

        if samplesPerPixel == 3 {
            // Core Graphics has no packed 24-bit RGB layout for 8-bit components; the
            // only supported RGB layouts are 32 bits per pixel. Render into RGBX,
            // compositing any alpha onto white, then strip the padding byte.
            let bytesPerRow = width * 4
            var rgbx = Data(count: bytesPerRow * height)
            try rgbx.withUnsafeMutableBytes { buffer in
                guard let baseAddress = buffer.baseAddress else {
                    throw ImageConversionError.pixelDataExtractionFailed
                }
                guard let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                ) else {
                    throw ImageConversionError.contextCreationFailed
                }
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }

            var rgb = Data(count: width * height * 3)
            rgb.withUnsafeMutableBytes { dst in
                rgbx.withUnsafeBytes { src in
                    let s = src.bindMemory(to: UInt8.self)
                    let d = dst.bindMemory(to: UInt8.self)
                    var di = 0
                    for si in stride(from: 0, to: s.count, by: 4) {
                        d[di] = s[si]
                        d[di + 1] = s[si + 1]
                        d[di + 2] = s[si + 2]
                        di += 3
                    }
                }
            }
            return rgb
        }

        let bytesPerRow = width
        var pixelData = Data(count: bytesPerRow * height)
        try pixelData.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw ImageConversionError.pixelDataExtractionFailed
            }
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                throw ImageConversionError.contextCreationFailed
            }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixelData
    }

    private static func getSamplesPerPixel(image: CGImage) -> Int {
        switch image.colorSpace?.model {
        case .monochrome: return 1
        case .rgb: return 3
        default: return 3
        }
    }

    private static func getPhotometricInterpretation(image: CGImage) -> String {
        getSamplesPerPixel(image: image) == 1 ? "MONOCHROME2" : "RGB"
    }

    private static func extractEXIFDescription(from exif: [String: Any]?) -> String? {
        guard let exif = exif else { return nil }

        if let exifDict = exif[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            if let userComment = exifDict[kCGImagePropertyExifUserComment as String] as? String {
                return userComment
            }
            if let imageDescription = exifDict["ImageDescription"] as? String {
                return imageDescription
            }
        }

        if let tiffDict = exif[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            if let imageDescription = tiffDict[kCGImagePropertyTIFFImageDescription as String] as? String {
                return imageDescription
            }
        }

        return nil
    }

    private static func addEXIFMetadataToDICOM(exif: [String: Any], dataSet: inout DataSet) {
        if let exifDict = exif[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            if let dateTimeOriginal = exifDict[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                // EXIF date format: "YYYY:MM:DD HH:MM:SS"
                let components = dateTimeOriginal.components(separatedBy: " ")
                if components.count == 2 {
                    let datePart = components[0].replacingOccurrences(of: ":", with: "")
                    let timePart = components[1].replacingOccurrences(of: ":", with: "")
                    dataSet.setString(datePart, for: .acquisitionDate, vr: .DA)
                    dataSet.setString(timePart, for: .acquisitionTime, vr: .TM)
                }
            }
        }

        // The file's DPI is the spacing on the scanned/rendered medium, which is
        // Nominal Scanned Pixel Spacing (0018,2010) of the SC Image Module (Table
        // C.8-25: "Physical distance on the media being digitized or scanned"),
        // not Pixel Spacing (0028,0030) of the Image Plane Module, whose Type 1
        // Image Position/Orientation (Patient) the converter cannot supply.
        if let dpiWidth = exif[kCGImagePropertyDPIWidth as String] as? Double,
           let dpiHeight = exif[kCGImagePropertyDPIHeight as String] as? Double,
           dpiWidth > 0, dpiHeight > 0 {
            let mmPerInch = 25.4
            let pixelSpacingX = mmPerInch / dpiWidth
            let pixelSpacingY = mmPerInch / dpiHeight
            let pixelSpacing = String(format: "%.6f\\%.6f", pixelSpacingY, pixelSpacingX)
            dataSet.setString(pixelSpacing, for: .nominalScannedPixelSpacing, vr: .DS)
        }
    }
    #endif
}
