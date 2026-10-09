// NEMA-verified: 2026a, checked 2026-10-01 — derived MPR output against PS3.3 2026a C.7.6.1.1.2 (Image Type DERIVED\SECONDARY, new SOP Instance UID), C.8.3.1.1.1 (MR Value 3 MPR) and C.8.2.1.1.1 (CT Value 3 AXIAL covers coronal/sagittal), C.12.4 Table C.12-10 (Derivation Description, Derivation Code Sequence, Source Image Sequence), PS3.16 2026a CID 7203 (DCM 113072 "Multiplanar reformatting", 1 of 34 rows used) and CID 7202 (DCM 121322), Table C.7-10 / C.7.6.2.1.1 (Image Position/Orientation (Patient), Pixel Spacing row\column), C.11.1.1.2 (stored value = (output - intercept) / slope), PS3.5 Table 6.2-1 (DS 16 bytes, ST 1024 chars); oblique slices carry their own Image Position / Orientation (Patient)
import Foundation
import DICOMCore
import DICOMKit

/// Writes reformatted planes as a derived image series (`dicom-3d mpr --format dcm`).
///
/// Each output instance is a copy of the first source instance with:
/// - a new SOP Instance UID and, per plane, a new Series Instance UID (C.7.6.1.1.2);
/// - Image Type (0008,0008) `DERIVED\SECONDARY` plus Value 3 (MR: `MPR`, C.8.3.1.1.1;
///   other modalities keep the source's Value 3, e.g. CT `AXIAL` = any cross-sectional
///   image, C.8.2.1.1.1);
/// - Derivation Code Sequence (0008,9215) DCM 113072 "Multiplanar reformatting"
///   (PS3.16 CID 7203) and Derivation Description (0008,2111);
/// - Source Image Sequence (0008,2112) listing every source instance, Purpose of
///   Reference DCM 121322 (CID 7202);
/// - the plane's Image Position (Patient), Image Orientation (Patient), Pixel Spacing,
///   Slice Thickness, Rows and Columns;
/// - Pixel Data re-encoded through the source Rescale Slope/Intercept and clamped to
///   the stored range of Bits Stored / Pixel Representation.
enum DerivedSeries {

    /// PS3.16 2026a CID 7203 "Image Derivation".
    static let multiplanarReformatting = (value: "113072", scheme: "DCM", meaning: "Multiplanar reformatting")
    /// PS3.16 2026a CID 7202 "Source Image Purpose of Reference".
    static let sourcePurpose = (value: "121322", scheme: "DCM",
                                meaning: "Source image for image processing operation")

    enum DerivedError: Error, CustomStringConvertible {
        case noTemplate
        case enhancedSource
        case unsupportedBitsAllocated(Int)
        case missingGeometry

        var description: String {
            switch self {
            case .noTemplate:
                return "--format dcm needs DICOM source instances"
            case .enhancedSource:
                return "--format dcm is not supported for Enhanced multi-frame sources (functional groups); use --format png"
            case .unsupportedBitsAllocated(let bits):
                return "--format dcm supports Bits Allocated 8 or 16, not \(bits)"
            case .missingGeometry:
                return "reformatted slice has no plane geometry"
            }
        }
    }

    /// Image Type for the derived instances.
    static func imageType(source: [String]?, modality: String?) -> [String] {
        var values = ["DERIVED", "SECONDARY"]
        if modality?.trimmingCharacters(in: .whitespaces).uppercased() == "MR" {
            values.append("MPR")
        } else if let source, source.count > 2 {
            values.append(contentsOf: source[2...])
        }
        return values
    }

    /// Builds one derived instance per slice of a plane.
    static func makeInstances(slices: [SliceImage], plane: PatientPlane, volume: VolumeData,
                              seriesInstanceUID: String = UIDGenerator.generateUID().value) throws -> [DICOMFile] {
        try makeInstances(slices: slices, planeName: plane.rawValue, volume: volume,
                          seriesInstanceUID: seriesInstanceUID)
    }

    /// Builds one derived instance per slice; `planeName` is axial, sagittal, coronal or
    /// oblique (an oblique slice carries its own Image Orientation / Position (Patient)).
    static func makeInstances(slices: [SliceImage], planeName: String, volume: VolumeData,
                              seriesInstanceUID: String = UIDGenerator.generateUID().value) throws -> [DICOMFile] {
        let template = volume.template
        guard let sopClassUID = template.string(for: .sopClassUID) else { throw DerivedError.noTemplate }
        guard template[.perFrameFunctionalGroupsSequence] == nil,
              template[.sharedFunctionalGroupsSequence] == nil else { throw DerivedError.enhancedSource }
        guard volume.bitsAllocated == 8 || volume.bitsAllocated == 16 else {
            throw DerivedError.unsupportedBitsAllocated(volume.bitsAllocated)
        }

        let signed = volume.pixelRepresentation == 1
        let bits = max(1, min(volume.bitsStored, volume.bitsAllocated))
        let storedMin = signed ? -(1 << (bits - 1)) : 0
        let storedMax = signed ? (1 << (bits - 1)) - 1 : (1 << bits) - 1
        let slope = volume.rescaleSlope == 0 ? 1 : volume.rescaleSlope
        let intercept = volume.rescaleIntercept

        var base = template
        for tag in [Tag.pixelData, .sopInstanceUID, .instanceNumber, .imagePositionPatient,
                    .imageOrientationPatient, .pixelSpacing, .sliceLocation, .sliceThickness,
                    .spacingBetweenSlices, .smallestImagePixelValue, .largestImagePixelValue,
                    .smallestPixelValueInSeries, .largestPixelValueInSeries,
                    .derivationCodeSequence, .derivationDescription, .sourceImageSequence,
                    Tag(group: 0x0088, element: 0x0200)] {   // Icon Image Sequence
            base.remove(tag: tag)
        }
        // Overlay planes (60xx) were drawn on the source geometry.
        for element in base.allElements where element.tag.group >= 0x6000 && element.tag.group <= 0x601E
            && element.tag.group % 2 == 0 {
            base.remove(tag: element.tag)
        }

        base.setStrings(imageType(source: template.strings(for: .imageType),
                                  modality: template.string(for: .modality)),
                        for: .imageType, vr: .CS)
        base.setString(seriesInstanceUID, for: .seriesInstanceUID, vr: .UI)
        let sourceDescription = template.string(for: .seriesDescription)?.trimmingCharacters(in: .whitespaces) ?? ""
        let description = (sourceDescription.isEmpty ? "" : sourceDescription + " ") + "MPR " + planeName
        base.setString(String(description.prefix(64)), for: .seriesDescription, vr: .LO)

        let derivationCode = SequenceItem(elements: [
            DataElement.string(tag: .codeValue, vr: .SH, value: multiplanarReformatting.value),
            DataElement.string(tag: .codingSchemeDesignator, vr: .SH, value: multiplanarReformatting.scheme),
            DataElement.string(tag: .codeMeaning, vr: .LO, value: multiplanarReformatting.meaning),
        ])
        base.setSequence([derivationCode], for: .derivationCodeSequence)
        base.setString("Multiplanar reformatting, \(planeName) plane, by dicom-3d",
                       for: .derivationDescription, vr: .ST)

        let purpose = SequenceItem(elements: [
            DataElement.string(tag: .codeValue, vr: .SH, value: sourcePurpose.value),
            DataElement.string(tag: .codingSchemeDesignator, vr: .SH, value: sourcePurpose.scheme),
            DataElement.string(tag: .codeMeaning, vr: .LO, value: sourcePurpose.meaning),
        ])
        var purposeHolder = DataSet()
        purposeHolder.setSequence([purpose], for: .purposeOfReferenceCodeSequence)
        let sourceItems = volume.sourceReferences.map { ref in
            SequenceItem(elements: [
                DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: ref.classUID),
                DataElement.string(tag: .referencedSOPInstanceUID, vr: .UI, value: ref.instanceUID),
            ] + (purposeHolder[.purposeOfReferenceCodeSequence].map { [$0] } ?? []))
        }
        if !sourceItems.isEmpty {
            base.setSequence(sourceItems, for: .sourceImageSequence)
        }

        var files: [DICOMFile] = []
        for (index, slice) in slices.enumerated() {
            guard let g = slice.geometry else { throw DerivedError.missingGeometry }
            var ds = base
            let uid = UIDGenerator.generateUID().value
            ds.setString(uid, for: .sopInstanceUID, vr: .UI)
            ds.setInt(index + 1, for: .instanceNumber, vr: .IS)
            ds.setStrings([g.imagePosition.x, g.imagePosition.y, g.imagePosition.z].map(formatted),
                          for: .imagePositionPatient, vr: .DS)
            ds.setStrings([g.rowCosines.x, g.rowCosines.y, g.rowCosines.z,
                           g.columnCosines.x, g.columnCosines.y, g.columnCosines.z].map(formatted),
                          for: .imageOrientationPatient, vr: .DS)
            ds.setStrings([formatted(g.rowSpacing), formatted(g.columnSpacing)], for: .pixelSpacing, vr: .DS)
            ds.setString(formatted(g.sliceThickness), for: .sliceThickness, vr: .DS)
            ds.setUInt16(UInt16(slice.height), for: .rows)
            ds.setUInt16(UInt16(slice.width), for: .columns)

            var data = Data(capacity: slice.pixels.count * volume.bitsAllocated / 8)
            for value in slice.pixels {
                let stored = Int(((value - intercept) / slope).rounded())
                let clamped = min(max(stored, storedMin), storedMax)
                if volume.bitsAllocated == 8 {
                    data.append(UInt8(truncatingIfNeeded: clamped))
                } else {
                    let word = UInt16(truncatingIfNeeded: clamped)
                    data.append(UInt8(word & 0xFF))
                    data.append(UInt8(word >> 8))
                }
            }
            if data.count % 2 == 1 { data.append(0) }
            ds[.pixelData] = DataElement.data(tag: .pixelData, vr: volume.bitsAllocated == 8 ? .OB : .OW, data: data)

            files.append(DICOMFile.create(dataSet: ds, sopClassUID: sopClassUID, sopInstanceUID: uid,
                                          transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid))
        }
        return files
    }

    /// DS text (PS3.5 2026a Table 6.2-1: at most 16 bytes).
    static func formatted(_ value: Double) -> String {
        let v = abs(value) < 1e-12 ? 0 : value
        if v == v.rounded(), abs(v) < 1e15 { return String(Int(v)) }
        var s = String(format: "%.10g", v)
        if s.count > 16 { s = String(format: "%.8g", v) }
        if s.count > 16 { s = String(s.prefix(16)) }
        return s
    }
}
