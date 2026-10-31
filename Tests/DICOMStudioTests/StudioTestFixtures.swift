// StudioTestFixtures.swift
// DICOMStudioTests
//
// Generate synthetic print inputs at runtime, outside the checkout. No DICOM
// binaries (including synthetic fixtures) belong in the repository.

import Foundation
import DICOMCore
import DICOMKit

@MainActor
enum StudioTestFixtures {
    private static let syntheticCT: Result<URL, Error> = Result {
        var dataset = DataSet()
        dataset.setString("CT", for: .modality, vr: .CS)
        dataset.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
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
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DICOMStudio-synthetic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("syn-ct.dcm")
        try DICOMFile.create(dataSet: dataset).write().write(to: url, options: .atomic)
        return url
    }

    static func url(named name: String) throws -> URL? {
        guard name == "syn-ct.dcm" else { return nil }
        return try syntheticCT.get()
    }
}
