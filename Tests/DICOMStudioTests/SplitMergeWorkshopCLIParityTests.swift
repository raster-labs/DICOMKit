// SplitMergeWorkshopCLIParityTests.swift
// DICOMStudioTests
//
// App-vs-terminal cross-check for `dicom-split` and `dicom-merge`.
//
// For every option combination below the test drives the Studio CLI Workshop
// exactly as the UI does (select the tool, set parameter values, execute) and
// then runs the REAL `dicom-split` / `dicom-merge` binary with the tokens of the
// Workshop's own command preview. It asserts that
//
//   1. the console text is identical line for line (paths canonicalised),
//   2. the success/failure outcome is identical, and
//   3. the written files are identical — byte-for-byte for images, and as a
//      DICOM fingerprint (every element, recursively, minus the UIDs/dates the
//      engine mints fresh per run) for DICOM output.
//
// The binaries are taken from this checkout's `.build/release`; the suite is
// skipped when they have not been built (`swift build -c release --product
// dicom-split --product dicom-merge`).

import Testing
import Foundation
@testable import DICOMStudio
@testable import DICOMKit
import DICOMCore

#if os(macOS)

private typealias Tag = DICOMCore.Tag

@Suite("dicom-split / dicom-merge: Workshop vs terminal", .serialized)
@MainActor
struct SplitMergeWorkshopCLIParityTests {

    // MARK: - Environment

    nonisolated private static let root: String? = CLIToolBuilder.repoRoot()
    nonisolated private static var binDir: String? {
        guard let root else { return nil }
        let dir = "\(root)/.build/release"
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: "\(dir)/dicom-split") && fm.isExecutableFile(atPath: "\(dir)/dicom-merge") ? dir : nil
    }

    /// One fixture tree per suite run, shared by every case.
    nonisolated private static let fixtures: Fixtures = { try! Fixtures.build() }()

    // MARK: - Fixtures

    struct Fixtures {
        let root: URL
        var enhancedCT: String { root.appendingPathComponent("mf/enh_a.dcm").path }
        var multiframeDir: String { root.appendingPathComponent("mf").path }
        var ctSeriesDir: String { root.appendingPathComponent("ct").path }
        var ctSlices: [String] { (0..<3).map { root.appendingPathComponent("ct/slice_00\($0).dcm").path } }
        var multiStudyDir: String { root.appendingPathComponent("multi").path }
        var scDir: String { root.appendingPathComponent("sc").path }
        var badDir: String { root.appendingPathComponent("bad").path }
        var emptyDir: String { root.appendingPathComponent("empty").path }

        nonisolated static func build() throws -> Fixtures {
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent("SplitMergeParity-\(UUID().uuidString)")
            let fx = Fixtures(root: root)
            let U = MultiframeSOPClassMap.UID.self

            // mf/: two Enhanced CT multi-frames (one nested) — 6 frames in 2 stacks, 3 frames in 1 stack.
            try fm.createDirectory(at: root.appendingPathComponent("mf/sub"), withIntermediateDirectories: true)
            try makeEnhancedCT(frames: 6, stacks: 2, sopInstance: "1.2.3.4.5.1001").write()
                .write(to: root.appendingPathComponent("mf/enh_a.dcm"))
            try makeEnhancedCT(frames: 3, stacks: 1, sopInstance: "1.2.3.4.5.1002").write()
                .write(to: root.appendingPathComponent("mf/sub/enh_b.dcm"))

            // ct/: one classic CT series, 5 slices — 3 axial then 2 coronal (for --make-stacks),
            // with acquisition times (for --sort-by AcquisitionTime / --temporal-position).
            try fm.createDirectory(at: root.appendingPathComponent("ct"), withIntermediateDirectories: true)
            for i in 0..<5 {
                let orientation = i < 3 ? "1\\0\\0\\0\\1\\0" : "1\\0\\0\\0\\0\\-1"
                try makeSlice(sopClass: U.ctImage, modality: "CT", study: "1.2.3.4.5.100", series: "1.2.3.4.5.200",
                              index: i, value: UInt16(500 + i), orientation: orientation).write()
                    .write(to: root.appendingPathComponent("ct/slice_00\(i).dcm"))
            }

            // multi/: series A + B in study 100, series C in study 101 (nested dir).
            try fm.createDirectory(at: root.appendingPathComponent("multi/nested"), withIntermediateDirectories: true)
            for i in 0..<3 {
                try makeSlice(sopClass: U.ctImage, modality: "CT", study: "1.2.3.4.5.100", series: "1.2.3.4.5.301",
                              index: i, value: UInt16(10 + i)).write()
                    .write(to: root.appendingPathComponent("multi/a_\(i).dcm"))
            }
            for i in 0..<2 {
                try makeSlice(sopClass: U.ctImage, modality: "CT", study: "1.2.3.4.5.100", series: "1.2.3.4.5.302",
                              index: i, value: UInt16(20 + i)).write()
                    .write(to: root.appendingPathComponent("multi/b_\(i).dcm"))
            }
            for i in 0..<2 {
                try makeSlice(sopClass: U.ctImage, modality: "CT", study: "1.2.3.4.5.101", series: "1.2.3.4.5.303",
                              index: i, value: UInt16(30 + i)).write()
                    .write(to: root.appendingPathComponent("multi/nested/c_\(i).dcm"))
            }

            // sc/: three 8-bit Secondary Capture slices.
            try fm.createDirectory(at: root.appendingPathComponent("sc"), withIntermediateDirectories: true)
            for i in 0..<3 {
                try makeSlice(sopClass: U.secondaryCapture, modality: "OT", study: "1.2.3.4.5.100", series: "1.2.3.4.5.400",
                              index: i, value: UInt16(40 + i), bits: 8).write()
                    .write(to: root.appendingPathComponent("sc/sc_\(i).dcm"))
            }

            // bad/: two slices with different frame sizes (validation failure).
            try fm.createDirectory(at: root.appendingPathComponent("bad"), withIntermediateDirectories: true)
            try makeSlice(sopClass: U.ctImage, modality: "CT", study: "1.2.3.4.5.100", series: "1.2.3.4.5.500",
                          index: 0, value: 1, rows: 4).write().write(to: root.appendingPathComponent("bad/x_0.dcm"))
            try makeSlice(sopClass: U.ctImage, modality: "CT", study: "1.2.3.4.5.100", series: "1.2.3.4.5.500",
                          index: 1, value: 2, rows: 8).write().write(to: root.appendingPathComponent("bad/x_1.dcm"))

            // empty/: no DICOM at all.
            try fm.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)
            try Data("not dicom".utf8).write(to: root.appendingPathComponent("empty/readme.txt"))
            return fx
        }

        nonisolated private static func seq(_ tag: Tag, _ elements: [DataElement]) -> DataElement {
            DataElement(tag: tag, vr: .SQ, length: 0xFFFF_FFFF, valueData: Data(),
                        sequenceItems: [SequenceItem(elements: elements)])
        }

        nonisolated private static func str(_ tag: Tag, _ vr: VR, _ value: String) -> DataElement {
            DataElement.string(tag: tag, vr: vr, value: value)
        }

        nonisolated private static func at(_ tag: Tag, _ value: Tag) -> DataElement {
            DataElement(tag: tag, vr: .AT, length: 4, valueData: Data([
                UInt8(value.group & 0xFF), UInt8(value.group >> 8),
                UInt8(value.element & 0xFF), UInt8(value.element >> 8)]))
        }

        /// Enhanced CT, 16-bit 4×4, `frames` frames in `stacks` stacks, frame f filled
        /// with 100 + f. Carries Shared + Per-frame functional groups, a Multi-frame
        /// Dimension module and one private functional group (for --private-groups).
        nonisolated static func makeEnhancedCT(frames: Int, stacks: Int, sopInstance: String) -> DICOMFile {
            let U = MultiframeSOPClassMap.UID.self
            var ds = DataSet()
            ds.setString(U.enhancedCT, for: .sopClassUID, vr: .UI)
            ds.setString(sopInstance, for: .sopInstanceUID, vr: .UI)
            ds.setString("1.2.3.4.5.100", for: .studyInstanceUID, vr: .UI)
            ds.setString("1.2.3.4.5.201", for: .seriesInstanceUID, vr: .UI)
            ds.setString("1.2.3.4.5.900", for: Tag(group: 0x0020, element: 0x0052), vr: .UI)
            ds.setString("CT", for: .modality, vr: .CS)
            ds.setString("Parity^Patient", for: .patientName, vr: .PN)
            ds.setString("P001", for: .patientID, vr: .LO)
            ds.setString("7", for: .seriesNumber, vr: .IS)
            ds.setString("1", for: .instanceNumber, vr: .IS)
            ds.setStrings(["ORIGINAL", "PRIMARY", "VOLUME", "NONE"], for: .imageType, vr: .CS)
            ds.setUInt16(4, for: .rows)
            ds.setUInt16(4, for: .columns)
            ds.setUInt16(16, for: .bitsAllocated)
            ds.setUInt16(12, for: .bitsStored)
            ds.setUInt16(11, for: .highBit)
            ds.setUInt16(0, for: .pixelRepresentation)
            ds.setUInt16(1, for: .samplesPerPixel)
            ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
            ds.setString("\(frames)", for: .numberOfFrames, vr: .IS)

            let privateCreator = Tag(group: 0x0029, element: 0x0010)
            let privateGroup = Tag(group: 0x0029, element: 0x1010)
            let privateAttr = Tag(group: 0x0029, element: 0x1011)
            ds.setSequence([SequenceItem(elements: [
                seq(.pixelMeasuresSequence, [str(.pixelSpacing, .DS, "0.5\\0.5"), str(.sliceThickness, .DS, "1")]),
                seq(.planeOrientationSequence, [str(.imageOrientationPatient, .DS, "1\\0\\0\\0\\1\\0")]),
                seq(.frameVOILUTSequence, [str(.windowCenter, .DS, "40"), str(.windowWidth, .DS, "400")]),
                seq(.pixelValueTransformationSequence, [str(.rescaleIntercept, .DS, "-1024"), str(.rescaleSlope, .DS, "1"), str(.rescaleType, .LO, "HU")]),
                seq(.ctImageFrameTypeSequence, [DataElement.strings(tag: .frameType, vr: .CS, values: ["ORIGINAL", "PRIMARY", "AXIAL", "NONE"])]),
                str(privateCreator, .LO, "PARITYTEST"),
                seq(privateGroup, [str(privateAttr, .LO, "vendor")]),
            ])], for: .sharedFunctionalGroupsSequence)

            let perStack = max(1, frames / stacks)
            var perFrame: [SequenceItem] = []
            for f in 0..<frames {
                let stack = min(stacks, f / perStack + 1)
                let inStack = f - (stack - 1) * perStack + 1
                perFrame.append(SequenceItem(elements: [
                    seq(.frameContentSequence, [
                        str(.stackID, .SH, "\(stack)"),
                        DataElement.uint32(tag: .inStackPositionNumber, value: UInt32(inStack)),
                        DataElement.uint32s(tag: .dimensionIndexValues, values: [UInt32(stack), UInt32(inStack)]),
                    ]),
                    seq(.planePositionSequence, [str(.imagePositionPatient, .DS, "0\\0\\\(Double(f) * 1.5)")]),
                ]))
            }
            ds.setSequence(perFrame, for: .perFrameFunctionalGroupsSequence)

            let orgUID = "1.2.3.4.5.777"
            ds.setSequence([SequenceItem(elements: [str(.dimensionOrganizationUID, .UI, orgUID)])], for: .dimensionOrganizationSequence)
            ds.setSequence([
                SequenceItem(elements: [str(.dimensionOrganizationUID, .UI, orgUID),
                                        at(.dimensionIndexPointer, .stackID),
                                        at(.functionalGroupPointer, .frameContentSequence)]),
                SequenceItem(elements: [str(.dimensionOrganizationUID, .UI, orgUID),
                                        at(.dimensionIndexPointer, .inStackPositionNumber),
                                        at(.functionalGroupPointer, .frameContentSequence)]),
            ], for: .dimensionIndexSequence)

            var pixels = Data(count: 16 * frames * 2)
            for f in 0..<frames {
                let v = UInt16(100 + f)
                for i in 0..<16 {
                    pixels[(f * 16 + i) * 2] = UInt8(v & 0xFF)
                    pixels[(f * 16 + i) * 2 + 1] = UInt8(v >> 8)
                }
            }
            ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixels)
            return DICOMFile.create(dataSet: ds, sopClassUID: U.enhancedCT)
        }

        /// Classic single-frame slice (16-bit OW, or 8-bit OB when `bits == 8`).
        nonisolated static func makeSlice(sopClass: String, modality: String, study: String, series: String,
                              index: Int, value: UInt16, orientation: String = "1\\0\\0\\0\\1\\0",
                              rows: UInt16 = 4, bits: UInt16 = 16) -> DICOMFile {
            var ds = DataSet()
            ds.setString(sopClass, for: .sopClassUID, vr: .UI)
            ds.setString("\(series).\(index + 1)", for: .sopInstanceUID, vr: .UI)
            ds.setString(study, for: .studyInstanceUID, vr: .UI)
            ds.setString(series, for: .seriesInstanceUID, vr: .UI)
            ds.setString("1.2.3.4.5.900", for: Tag(group: 0x0020, element: 0x0052), vr: .UI)
            ds.setString(modality, for: .modality, vr: .CS)
            ds.setString("Parity^Patient", for: .patientName, vr: .PN)
            ds.setString("P001", for: .patientID, vr: .LO)
            ds.setString("\(index + 1)", for: .instanceNumber, vr: .IS)
            ds.setString("3", for: .seriesNumber, vr: .IS)
            ds.setString("0.5\\0.5", for: .pixelSpacing, vr: .DS)
            ds.setString("1", for: .sliceThickness, vr: .DS)
            ds.setString(orientation, for: .imageOrientationPatient, vr: .DS)
            ds.setString("0\\0\\\(Double(index) * 1.5)", for: .imagePositionPatient, vr: .DS)
            ds.setString("40", for: .windowCenter, vr: .DS)
            ds.setString("400", for: .windowWidth, vr: .DS)
            ds.setString("-1024", for: .rescaleIntercept, vr: .DS)
            ds.setString("1", for: .rescaleSlope, vr: .DS)
            ds.setString("HU", for: .rescaleType, vr: .LO)
            ds.setString(String(format: "1200%02d.000000", index), for: .acquisitionTime, vr: .TM)
            ds.setString("20260101", for: .acquisitionDate, vr: .DA)
            ds.setString("\(index * 10)", for: .triggerTime, vr: .DS)
            ds.setStrings(["ORIGINAL", "PRIMARY", "AXIAL"], for: .imageType, vr: .CS)
            ds.setUInt16(rows, for: .rows)
            ds.setUInt16(4, for: .columns)
            ds.setUInt16(bits, for: .bitsAllocated)
            ds.setUInt16(bits, for: .bitsStored)
            ds.setUInt16(bits - 1, for: .highBit)
            ds.setUInt16(0, for: .pixelRepresentation)
            ds.setUInt16(1, for: .samplesPerPixel)
            ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
            let count = Int(rows) * 4
            if bits == 8 {
                ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: Data(repeating: UInt8(value & 0xFF), count: count))
            } else {
                var pixels = Data(count: count * 2)
                for i in 0..<count {
                    pixels[i * 2] = UInt8(value & 0xFF)
                    pixels[i * 2 + 1] = UInt8(value >> 8)
                }
                ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixels)
            }
            return DICOMFile.create(dataSet: ds, sopClassUID: sopClass)
        }
    }

    // MARK: - Case model

    struct Case: CustomStringConvertible {
        var name: String
        var tool: String
        var input: String
        var params: [(String, String)]
        /// merge `--level file` writes a single file; everything else a directory.
        var outputIsFile = false
        /// Ignore every UI element (the run mints random UIDs).
        var ignoreAllUIDs = false
        /// Ignore the Series Instance UID (minted per run).
        var ignoreSeriesUID = false
        var description: String { name }
    }

    // MARK: - Running one case on both surfaces

    struct Surface {
        var console: [String]
        var succeeded: Bool
        var files: [String: String]   // relative path -> fingerprint / hex digest
    }

    private func runCase(_ c: Case, verbose: Bool) async throws {
        let binDir = try #require(Self.binDir, "release dicom-split/dicom-merge not built — run swift build -c release --product dicom-split --product dicom-merge")
        let fx = Self.fixtures
        let fm = FileManager.default
        let caseDir = fm.temporaryDirectory.appendingPathComponent("SplitMergeParityCase-\(UUID().uuidString)")
        let appOutDir = caseDir.appendingPathComponent("app")
        let cliOutDir = caseDir.appendingPathComponent("cli")
        try fm.createDirectory(at: appOutDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: cliOutDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: caseDir) }

        let appOutput = c.outputIsFile ? appOutDir.appendingPathComponent("merged.dcm").path : appOutDir.path
        let cliOutput = c.outputIsFile ? cliOutDir.appendingPathComponent("merged.dcm").path : cliOutDir.path

        // --- App (CLI Workshop) ---
        let vm = CLIWorkshopViewModel()
        vm.selectTool(id: c.tool)
        vm.updateParameterValue(parameterID: "inputPath", value: c.input)
        vm.updateParameterValue(parameterID: "output", value: appOutput)
        for (k, v) in c.params { vm.updateParameterValue(parameterID: k, value: v) }
        if verbose { vm.updateParameterValue(parameterID: "verbose", value: "true") }
        await vm.executeCommand()
        let preview = vm.commandPreview
        let appConsole = Self.normalize(vm.consoleOutput, appOutput: appOutput, cliOutput: cliOutput, fixtureRoot: fx.root.path, isApp: true)
        let app = Surface(console: appConsole, succeeded: vm.consoleStatus == .success,
                          files: try Self.digest(dir: appOutDir, c))

        // --- Terminal (real binary, same tokens as the preview) ---
        #expect(preview.hasPrefix(c.tool + " "), "[\(c)] preview must be the pasteable command: \(preview)")
        let cliPreview = preview.replacingOccurrences(of: appOutput, with: cliOutput)
        var args = CLIToolTerminalCompare.shellSplit(cliPreview)
        #expect(args.first == c.tool)
        args.removeFirst()
        let outcome = CLIToolTerminalCompare.run(tool: c.tool, arguments: args, binDir: binDir, timeout: 120)
        #expect(outcome.launchError == nil, "[\(c)] \(outcome.launchError ?? "")")
        let cliConsole = Self.normalize(outcome.combined, appOutput: appOutput, cliOutput: cliOutput, fixtureRoot: fx.root.path, isApp: false)
        let cli = Surface(console: cliConsole, succeeded: outcome.exitCode == 0,
                          files: try Self.digest(dir: cliOutDir, c))

        // --- Compare ---
        let label = "[\(c)\(verbose ? " --verbose" : "")]"
        #expect(app.succeeded == cli.succeeded, "\(label) outcome differs: app=\(app.succeeded) cli(exit \(outcome.exitCode))=\(cli.succeeded)\nAPP:\n\(app.console.joined(separator: "\n"))\nCLI:\n\(cli.console.joined(separator: "\n"))")
        #expect(app.console == cli.console, "\(label) console differs\nAPP:\n\(app.console.joined(separator: "\n"))\nCLI:\n\(cli.console.joined(separator: "\n"))\nPREVIEW: \(preview)")
        #expect(Array(app.files.keys).sorted() == Array(cli.files.keys).sorted(), "\(label) written files differ: app=\(app.files.keys.sorted()) cli=\(cli.files.keys.sorted())")
        for (rel, appFp) in app.files {
            if let cliFp = cli.files[rel] {
                #expect(appFp == cliFp, "\(label) content differs for \(rel)")
            }
        }
    }

    // MARK: - Normalisation and fingerprints

    /// Console lines with the surface-specific noise removed: the app's `$ cmd`
    /// echo, ArgumentParser's usage trailer, and the absolute output/fixture paths.
    nonisolated static func normalize(_ raw: String, appOutput: String, cliOutput: String, fixtureRoot: String, isApp: Bool) -> [String] {
        var lines = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if isApp, lines.first?.hasPrefix("$ ") == true {
            lines.removeFirst()
            if lines.first == "" { lines.removeFirst() }
        }
        if !isApp, let usage = lines.firstIndex(where: { $0.hasPrefix("Usage:") }) {
            lines.removeSubrange(usage...)
        }
        // P-SPLIT-1 / D154 (2026-10-05): both surfaces print SplitConsole.framesDeprecatedLine for the
        // 0-based `--frames`, so it is compared like every other line.
        lines = lines.map {
            $0.replacingOccurrences(of: appOutput, with: "<OUT>")
              .replacingOccurrences(of: cliOutput, with: "<OUT>")
              .replacingOccurrences(of: fixtureRoot, with: "<IN>")
              .trimmingCharacters(in: .whitespaces)
        }
        while lines.last == "" { lines.removeLast() }
        return lines
    }

    /// Relative path -> fingerprint for everything written under `dir`.
    nonisolated static func digest(dir: URL, _ c: Case) throws -> [String: String] {
        var out: [String: String] = [:]
        guard let e = FileManager.default.enumerator(atPath: dir.path) else { return out }
        for case let rel as String in e {
            let url = dir.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let data = try Data(contentsOf: url)
            if let file = try? DICOMFile.read(from: data) {
                out[rel] = fingerprint(file.dataSet, c)
            } else {
                out[rel] = data.map { String(format: "%02x", $0) }.joined()
            }
        }
        return out
    }

    nonisolated private static let volatileTags: Set<Tag> = [
        .sopInstanceUID,              // merge mints a fresh one per run
        .dimensionOrganizationUID,    // merge mints one per run
    ]

    nonisolated static func fingerprint(_ ds: DataSet, _ c: Case) -> String {
        var lines: [String] = []
        for el in ds.allElements.sorted(by: { $0.tag < $1.tag }) {
            append(el, depth: 0, c, into: &lines)
        }
        return lines.joined(separator: "\n")
    }

    nonisolated private static func append(_ el: DataElement, depth: Int, _ c: Case, into lines: inout [String]) {
        if [.DA, .TM, .DT].contains(el.vr) { return }                // content/instance date stamps
        if volatileTags.contains(el.tag) { return }
        if c.ignoreAllUIDs && el.vr == .UI { return }
        if c.ignoreSeriesUID && el.tag == .seriesInstanceUID { return }
        let pad = String(repeating: " ", count: depth * 2)
        if let items = el.sequenceItems {
            lines.append("\(pad)\(el.tag) SQ items=\(items.count)")
            for (i, item) in items.enumerated() {
                lines.append("\(pad) item \(i)")
                for sub in item.elements.values.sorted(by: { $0.tag < $1.tag }) {
                    append(sub, depth: depth + 1, c, into: &lines)
                }
            }
        } else if let frags = el.encapsulatedFragments {
            lines.append("\(pad)\(el.tag) \(el.vr) fragments=\(frags.map { $0.count })")
        } else {
            lines.append("\(pad)\(el.tag) \(el.vr) \(el.valueData.map { String(format: "%02x", $0) }.joined())")
        }
    }

    // MARK: - dicom-split matrix

    nonisolated static var splitCases: [Case] {
        let fx = fixtures
        let mf = fx.enhancedCT
        return [
            Case(name: "split defaults", tool: "dicom-split", input: mf, params: []),
            Case(name: "split --frames 1,3-4", tool: "dicom-split", input: mf, params: [("frames", "1,3-4")]),
            Case(name: "split --frames 2 --pattern", tool: "dicom-split", input: mf, params: [("frames", "2"), ("pattern", "f_{number:04d}_{modality}_{instance}_{stack}_{series}.dcm")]),
            Case(name: "split --format png --apply-window 40/400", tool: "dicom-split", input: mf, params: [("format", "png"), ("apply-window", "true"), ("window-center", "40"), ("window-width", "400")]),
            Case(name: "split --format png (no window)", tool: "dicom-split", input: mf, params: [("format", "png")]),
            Case(name: "split --format jpeg --apply-window", tool: "dicom-split", input: mf, params: [("format", "jpeg"), ("apply-window", "true")]),
            Case(name: "split --format tiff --frames 1", tool: "dicom-split", input: mf, params: [("format", "tiff"), ("frames", "1")]),
            Case(name: "split --target same", tool: "dicom-split", input: mf, params: [("target", "same")]),
            Case(name: "split --target classic", tool: "dicom-split", input: mf, params: [("target", "classic")]),
            Case(name: "split --target same --split-by stack", tool: "dicom-split", input: mf, params: [("target", "same"), ("split-by", "stack")]),
            Case(name: "split --split-by stack", tool: "dicom-split", input: mf, params: [("split-by", "stack")]),
            Case(name: "split --split-by temporal", tool: "dicom-split", input: mf, params: [("split-by", "temporal")]),
            Case(name: "split --instance-number instack", tool: "dicom-split", input: mf, params: [("instance-number", "instack")]),
            Case(name: "split --instance-number original", tool: "dicom-split", input: mf, params: [("instance-number", "original")]),
            Case(name: "split --private-groups keep", tool: "dicom-split", input: mf, params: [("private-groups", "keep")]),
            Case(name: "split --private-groups drop", tool: "dicom-split", input: mf, params: [("private-groups", "drop")]),
            Case(name: "split --new-series", tool: "dicom-split", input: mf, params: [("new-series", "true")]),
            Case(name: "split --frames-per 4", tool: "dicom-split", input: mf, params: [("frames-per", "4")]),
            Case(name: "split --frames-per 4 --frames 1", tool: "dicom-split", input: mf, params: [("frames-per", "4"), ("frames", "1")]),
            // P-SPLIT-1 / D154: Frame numbers from 1 (PS3.3 2026a C.7.6.16.1.2 / Table 10-3).
            Case(name: "split --frame-numbers 2,4-5", tool: "dicom-split", input: mf, params: [("frame-numbers", "2,4-5")]),
            Case(name: "split --frame-numbers 1 --format png", tool: "dicom-split", input: mf, params: [("frame-numbers", "1"), ("format", "png")]),
            Case(name: "split --frames-per 4 --frame-numbers 1-6", tool: "dicom-split", input: mf, params: [("frames-per", "4"), ("frame-numbers", "1-6")]),
            Case(name: "split --random-uids", tool: "dicom-split", input: mf, params: [("random-uids", "true")], ignoreAllUIDs: true),
            Case(name: "split --pixel-handling decode", tool: "dicom-split", input: mf, params: [("pixel-handling", "decode")]),
            Case(name: "split --target same --instance-number instack --new-series --split-by stack", tool: "dicom-split", input: mf,
                 params: [("target", "same"), ("instance-number", "instack"), ("new-series", "true"), ("split-by", "stack")]),
            Case(name: "split dir --recursive", tool: "dicom-split", input: fx.multiframeDir, params: [("recursive", "true")]),
            Case(name: "split dir (non-recursive)", tool: "dicom-split", input: fx.multiframeDir, params: []),
            Case(name: "split dir --recursive --format png --frames 1-2", tool: "dicom-split", input: fx.multiframeDir, params: [("recursive", "true"), ("format", "png"), ("frames", "1-2")]),
            Case(name: "split classic single-frame input (skipped)", tool: "dicom-split", input: fx.ctSlices[0], params: []),
            // Error paths
            Case(name: "split --frames abc", tool: "dicom-split", input: mf, params: [("frames", "abc")]),
            Case(name: "split --frames 5-2", tool: "dicom-split", input: mf, params: [("frames", "5-2")]),
            Case(name: "split --frame-numbers 0", tool: "dicom-split", input: mf, params: [("frame-numbers", "0")]),
            Case(name: "split --frame-numbers 3-1", tool: "dicom-split", input: mf, params: [("frame-numbers", "3-1")]),
            Case(name: "split --frames 1 --frame-numbers 2 (conflict)", tool: "dicom-split", input: mf, params: [("frames", "1"), ("frame-numbers", "2")]),
            Case(name: "split --frames-per 0", tool: "dicom-split", input: mf, params: [("frames-per", "0")]),
            Case(name: "split --frames-per x", tool: "dicom-split", input: mf, params: [("frames-per", "x")]),
            Case(name: "split --window-center abc", tool: "dicom-split", input: mf, params: [("format", "png"), ("apply-window", "true"), ("window-center", "abc")]),
            Case(name: "split missing input", tool: "dicom-split", input: fx.root.appendingPathComponent("nope.dcm").path, params: []),
        ]
    }

    @Test("dicom-split: every option combination matches the terminal", arguments: splitCases, [false, true])
    func split(_ c: Case, verbose: Bool) async throws {
        try await runCase(c, verbose: verbose)
    }

    // MARK: - dicom-merge matrix

    nonisolated static var mergeCases: [Case] {
        let fx = fixtures
        let ct = fx.ctSeriesDir
        func file(_ name: String, _ input: String, _ params: [(String, String)], ignoreSeries: Bool = false) -> Case {
            Case(name: name, tool: "dicom-merge", input: input, params: params, outputIsFile: true, ignoreSeriesUID: ignoreSeries)
        }
        return [
            file("merge standard", ct, []),
            file("merge --format auto", ct, [("format", "auto")]),
            file("merge --format enhanced-ct", ct, [("format", "enhanced-ct")]),
            file("merge --format enhanced-ct --make-stacks", ct, [("format", "enhanced-ct"), ("make-stacks", "true")]),
            file("merge --format enhanced-ct --temporal-position", ct, [("format", "enhanced-ct"), ("temporal-position", "true")]),
            file("merge --format enhanced-ct --make-stacks --temporal-position --validate", ct, [("format", "enhanced-ct"), ("make-stacks", "true"), ("temporal-position", "true"), ("validate", "true")]),
            file("merge --format enhanced-ct --new-series", ct, [("format", "enhanced-ct"), ("new-series", "true")], ignoreSeries: true),
            file("merge --format enhanced-ct --pixel-handling decode", ct, [("format", "enhanced-ct"), ("pixel-handling", "decode")]),
            file("merge --format enhanced-mr (source gate)", ct, [("format", "enhanced-mr")]),
            file("merge --format enhanced-mr --allow-any-source", ct, [("format", "enhanced-mr"), ("allow-any-source", "true")]),
            file("merge --format legacy-converted-ct", ct, [("format", "legacy-converted-ct")]),
            file("merge --format enhanced-pet --allow-any-source", ct, [("format", "enhanced-pet"), ("allow-any-source", "true")]),
            file("merge --format sc-multiframe", fx.scDir, [("format", "sc-multiframe")]),
            file("merge --format auto (SC source)", fx.scDir, [("format", "auto")]),
            file("merge --format us-multiframe (gate on CT)", ct, [("format", "us-multiframe")]),
            file("merge --sort-by ImagePositionPatient --order descending", ct, [("sort-by", "ImagePositionPatient"), ("order", "descending")]),
            file("merge --sort-by AcquisitionTime", ct, [("sort-by", "AcquisitionTime")]),
            file("merge --sort-by none --order descending", ct, [("sort-by", "none"), ("order", "descending")]),
            file("merge --sort-by InstanceNumber --order descending --format enhanced-ct", ct, [("order", "descending"), ("format", "enhanced-ct")]),
            file("merge --validate", ct, [("validate", "true")]),
            file("merge --validate inconsistent sizes", fx.badDir, [("validate", "true")]),
            file("merge multi-root a;b;c", "\(fx.ctSlices[0]);\(fx.ctSlices[1]);\(fx.ctSlices[2])", [("format", "enhanced-ct")]),
            file("merge dir --recursive", fx.multiStudyDir, [("recursive", "true")]),
            file("merge empty dir", fx.emptyDir, []),
            file("merge missing input", fx.root.appendingPathComponent("nope").path, []),
            Case(name: "merge --level series", tool: "dicom-merge", input: fx.multiStudyDir, params: [("level", "series")]),
            Case(name: "merge --level series --recursive --format enhanced-ct", tool: "dicom-merge", input: fx.multiStudyDir, params: [("level", "series"), ("recursive", "true"), ("format", "enhanced-ct")]),
            Case(name: "merge --level study --recursive", tool: "dicom-merge", input: fx.multiStudyDir, params: [("level", "study"), ("recursive", "true")]),
            Case(name: "merge --level study --format legacy-converted-ct --sort-by ImagePositionPatient", tool: "dicom-merge", input: fx.multiStudyDir, params: [("level", "study"), ("format", "legacy-converted-ct"), ("sort-by", "ImagePositionPatient")]),
            Case(name: "merge --level series --validate (bad dir)", tool: "dicom-merge", input: fx.badDir, params: [("level", "series"), ("validate", "true")]),
        ]
    }

    @Test("dicom-merge: every option combination matches the terminal", arguments: mergeCases, [false, true])
    func merge(_ c: Case, verbose: Bool) async throws {
        try await runCase(c, verbose: verbose)
    }
}

#endif
