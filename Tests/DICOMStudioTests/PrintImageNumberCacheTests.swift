// PrintImageNumberCacheTests.swift
// DICOMStudioTests
//
// Reading the image numbers the print range matches against.
//
// The property under test: the number comes out of the *file*. Marking a whole
// series records paths and nothing else — deliberately, so the viewer is not
// stalled reading two hundred headers for a tray nobody has opened — so a range
// that trusted the mark alone was filtering by tray position, and "3 to 9"
// printed whichever seven marks happened to sit in those slots.

import Testing
@testable import DICOMStudio
import DICOMCore
import DICOMKit
import Foundation

@MainActor
@Suite("Print Image Number Cache Tests")
struct PrintImageNumberCacheTests {

    /// A minimal explicit-VR little-endian Part 10 file carrying one instance
    /// number — enough for the header read this cache performs.
    private func writeFile(
        instanceNumber: Int?,
        seriesDescription: String? = nil,
        to url: URL
    ) throws {
        var data = Data(repeating: 0, count: 128)
        data.append(contentsOf: Array("DICM".utf8))

        func element(group: UInt16, element: UInt16, vr: String, value: String) -> Data {
            var padded = value
            if padded.utf8.count % 2 == 1 { padded += vr == "UI" ? "\0" : " " }
            var out = Data()
            out.append(contentsOf: withUnsafeBytes(of: group.littleEndian) { Array($0) })
            out.append(contentsOf: withUnsafeBytes(of: element.littleEndian) { Array($0) })
            out.append(contentsOf: Array(vr.utf8))
            out.append(contentsOf: withUnsafeBytes(of: UInt16(padded.utf8.count).littleEndian) {
                Array($0)
            })
            out.append(contentsOf: Array(padded.utf8))
            return out
        }

        let sopClass = "1.2.840.10008.5.1.4.1.1.7"
        let sopInstance = "1.2.826.0.1.3680043.10.543.20261024.7.\(instanceNumber ?? 0)"
        // Legal Part 10 identity and UI padding. This remains a deliberately
        // small metadata fixture, not a complete Secondary Capture IOD.
        var meta = Data([0x02, 0x00, 0x01, 0x00, 0x4f, 0x42, 0x00, 0x00,
                         0x02, 0x00, 0x00, 0x00, 0x00, 0x01]) // File Meta Information Version
        meta.append(element(group: 0x0002, element: 0x0002, vr: "UI", value: sopClass))
        meta.append(element(group: 0x0002, element: 0x0003, vr: "UI", value: sopInstance))
        meta.append(element(group: 0x0002, element: 0x0010, vr: "UI", value: "1.2.840.10008.1.2.1"))
        meta.append(element(group: 0x0002, element: 0x0012, vr: "UI", value: "1.2.826.0.1.3680043.10.543.7"))

        // Group length is a UL — four bytes of little-endian length, rather than
        // the string payload the helper above writes.
        var withGroupLength = data
        var groupLengthElement = Data()
        groupLengthElement.append(contentsOf: withUnsafeBytes(of: UInt16(0x0002).littleEndian) { Array($0) })
        groupLengthElement.append(contentsOf: withUnsafeBytes(of: UInt16(0x0000).littleEndian) { Array($0) })
        groupLengthElement.append(contentsOf: Array("UL".utf8))
        groupLengthElement.append(contentsOf: withUnsafeBytes(of: UInt16(4).littleEndian) { Array($0) })
        groupLengthElement.append(contentsOf: withUnsafeBytes(of: UInt32(meta.count).littleEndian) { Array($0) })
        withGroupLength.append(groupLengthElement)
        withGroupLength.append(meta)

        // Data set: SOP class/instance and the number under test.
        withGroupLength.append(element(group: 0x0008, element: 0x0016, vr: "UI", value: sopClass))
        withGroupLength.append(element(group: 0x0008, element: 0x0018, vr: "UI", value: sopInstance))
        withGroupLength.append(element(group: 0x0008, element: 0x0060, vr: "CS", value: "CT"))
        if let seriesDescription {
            withGroupLength.append(element(group: 0x0008, element: 0x103E, vr: "LO",
                                           value: seriesDescription))
        }
        if let instanceNumber {
            withGroupLength.append(element(group: 0x0020, element: 0x0013, vr: "IS",
                                           value: String(instanceNumber)))
        }
        try withGroupLength.write(to: url)
        // Fail at fixture construction if the same metadata reader cannot
        // parse it; cache error handling must not disguise an invalid fixture.
        let parsed = try DICOMFile.read(from: withGroupLength, force: true,
            options: ParsingOptions(mode: .metadataOnly, stopAfterTag: .instanceNumber))
        #expect(parsed.dataSet.string(for: .sopClassUID) == sopClass)
        #expect(parsed.dataSet.string(for: .sopInstanceUID) == sopInstance)
        #expect(parsed.dataSet.string(for: .instanceNumber) == instanceNumber.map(String.init))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("print-numbers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("The number is read out of the file, not guessed from the tray")
    func testReadsInstanceNumberFromFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Files named so that their position in the tray is nothing like their
        // image number: alphabetical order is a.dcm, b.dcm, c.dcm — positions
        // 1, 2, 3 — while the images are 101, 102, 103.
        let paths = try ["a": 101, "b": 102, "c": 103].map { name, number -> String in
            let url = directory.appendingPathComponent("\(name).dcm")
            try writeFile(instanceNumber: number, to: url)
            return url.path
        }

        let cache = PrintImageNumberCache()
        await cache.load(paths: paths)

        let read = paths.compactMap { cache.number(forPath: $0) }.sorted()
        #expect(read == [101, 102, 103], "read \(read) from \(paths.count) files")
        #expect(cache.hasNumbers(for: paths))
        #expect(!cache.isLoading)
    }

    @Test("A file with no image number is remembered as having none")
    func testUnnumberedFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("plain.dcm")
        try writeFile(instanceNumber: nil, to: url)

        let cache = PrintImageNumberCache()
        await cache.load(paths: [url.path])

        #expect(cache.number(forPath: url.path) == nil)
        // Known to have none, so the range falls back for this one rather than
        // reading it again on every look.
        #expect(cache.hasNumbers(for: [url.path]))
    }

    @Test("A file that cannot be read is not retried forever")
    func testMissingFile() async {
        let cache = PrintImageNumberCache()
        await cache.load(paths: ["/nowhere/missing.dcm"])

        #expect(cache.number(forPath: "/nowhere/missing.dcm") == nil)
        #expect(!cache.isLoading)
    }

    @Test("The range uses the numbers the cache read for marks that carry none")
    func testRangeUsesTheCache() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Marked whole-series style: paths only, no numbers on the marks.
        var paths: [String] = []
        for number in 20...29 {
            let url = directory.appendingPathComponent("slice\(number).dcm")
            try writeFile(instanceNumber: number, to: url)
            paths.append(url.path)
        }

        let selection = PrintSelectionModel()
        selection.add(contentsOf: paths.map {
            PrintSelectionItem(filePath: $0, seriesInstanceUID: "1.2.3")
        })
        let viewModel = PrintViewModel(selection: selection)

        // Before the read the marks say nothing, so the bounds are positions.
        #expect(viewModel.markedImageNumberBounds == 1...10)

        await viewModel.loadImageNumbers()

        #expect(viewModel.hasImageNumbers)
        #expect(viewModel.markedImageNumberBounds == 20...29,
                "the control now offers the numbers the series actually has")

        viewModel.setImageRange(from: 22, to: 24)
        #expect(viewModel.printedItems.count == 3)
        #expect(viewModel.printedItems.map { $0.filePath.hasSuffix("slice22.dcm")
            || $0.filePath.hasSuffix("slice23.dcm")
            || $0.filePath.hasSuffix("slice24.dcm") }.allSatisfy { $0 })
    }

    @Test("The series description rides along with the number read")
    func testReadsSeriesDescription() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("slice.dcm")
        try writeFile(instanceNumber: 7, seriesDescription: "CHEST AXIAL", to: url)

        let cache = PrintImageNumberCache()
        await cache.load(paths: [url.path])

        #expect(cache.number(forPath: url.path) == 7)
        #expect(cache.seriesDescription(forPath: url.path) == "CHEST AXIAL")
    }

    @Test("The modality rides along too — it names which presets the cell gets")
    func testReadsModality() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("slice.dcm")
        try writeFile(instanceNumber: 7, to: url)

        let cache = PrintImageNumberCache()
        #expect(cache.modality(forPath: url.path) == nil, "nothing before the read")
        await cache.load(paths: [url.path])

        // The fixture writes Modality (0008,0060) as "CT".
        #expect(cache.modality(forPath: url.path) == "CT")
    }

    @Test("The range row is named by the file's description, not the UID folder")
    func testRowLabelPrefersHeaderDescriptionOverFolder() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Marked whole-series style from an export: the folder is the Series
        // Instance UID, and the marks carry no description of their own.
        let seriesFolder = directory.appendingPathComponent("1.2.840.113619.2.55.3")
        try FileManager.default.createDirectory(at: seriesFolder, withIntermediateDirectories: true)
        var paths: [String] = []
        for number in 1...3 {
            let url = seriesFolder.appendingPathComponent("\(number).dcm")
            try writeFile(instanceNumber: number, seriesDescription: "T2 SAGITTAL", to: url)
            paths.append(url.path)
        }

        let selection = PrintSelectionModel()
        selection.add(contentsOf: paths.map {
            PrintSelectionItem(filePath: $0, seriesInstanceUID: "1.2.840.113619.2.55.3")
        })
        let viewModel = PrintViewModel(selection: selection)

        #expect(viewModel.markedSeriesRanges.first?.label == "1.2.840.113619.2.55.3",
                "before the read, the folder is all there is")

        await viewModel.loadImageNumbers()

        #expect(viewModel.markedSeriesRanges.first?.label == "T2 SAGITTAL",
                "after it, the row says what the series is")
    }
}
