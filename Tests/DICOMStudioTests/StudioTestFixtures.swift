// StudioTestFixtures.swift
// DICOMStudioTests
//
// Generate synthetic print inputs at runtime, outside the checkout. No DICOM
// binaries (including synthetic fixtures) belong in the repository.

import Foundation
import DICOMPrintTestSupport

@MainActor
enum StudioTestFixtures {
    private static let syntheticCT: Result<URL, Error> = Result {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DICOMStudio-synthetic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("syn-ct.dcm")
        try SyntheticPrintFixture.data().write(to: url, options: .atomic)
        return url
    }

    static func url(named name: String) throws -> URL? {
        guard name == "syn-ct.dcm" else { return nil }
        return try syntheticCT.get()
    }
}
