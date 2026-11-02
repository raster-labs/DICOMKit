// Synthetic print input shared by CLI, Studio and independent-peer tests.
// No patient files or embedded DICOM payloads are used.
import Foundation
import DICOMCore
import DICOMKit

public enum SyntheticPrintFixture {
    public static func data() throws -> Data {
        var dataset = DataSet()
        dataset.setString("CT", for: .modality, vr: .CS)
        dataset.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        dataset.setString("SYNTHETIC^PRINT", for: .patientName, vr: .PN)
        dataset.setString("SYNTHETIC", for: .patientID, vr: .LO)
        dataset.setString("", for: .patientBirthDate, vr: .DA)
        dataset.setString("", for: .patientSex, vr: .CS)
        dataset.setString("20200101", for: .studyDate, vr: .DA)
        dataset.setString("120000", for: .studyTime, vr: .TM)
        dataset.setString("2.25.233.1", for: .studyInstanceUID, vr: .UI)
        dataset.setString("2.25.233.1.1", for: .seriesInstanceUID, vr: .UI)
        dataset.setString("1", for: .seriesNumber, vr: .IS)
        dataset.setString("1", for: .instanceNumber, vr: .IS)
        dataset.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        dataset.setUInt16(8, for: .rows)
        dataset.setUInt16(8, for: .columns)
        dataset.setUInt16(1, for: .samplesPerPixel)
        dataset.setUInt16(16, for: .bitsAllocated)
        dataset.setUInt16(12, for: .bitsStored)
        dataset.setUInt16(11, for: .highBit)
        dataset.setUInt16(0, for: .pixelRepresentation)
        dataset.setStrings(["1", "1"], for: .pixelSpacing, vr: .DS)
        dataset.setString("NO", for: .burnedInAnnotation, vr: .CS)
        // Asymmetric ramp makes rotation and crop assertions meaningful.
        let pixels = (0..<64).flatMap { index -> [UInt8] in
            let value = UInt16(index * 61)
            return [UInt8(truncatingIfNeeded: value), UInt8(value >> 8)]
        }
        dataset[.pixelData] = DataElement(tag: .pixelData, vr: .OW,
            length: UInt32(pixels.count), valueData: Data(pixels))
        return try DICOMFile.create(dataSet: dataset).write()
    }
}
