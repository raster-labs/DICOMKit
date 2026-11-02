// AnonWorkshopCLIParityTests.swift
// DICOMStudioTests
//
// App-vs-terminal cross-check for `dicom-anon`.
//
// For every option combination below the test drives the Studio CLI Workshop
// exactly as the UI does (select the tool, set parameter values, execute) and
// then runs the REAL `dicom-anon` binary with the tokens of the Workshop's own
// command preview. It asserts that
//
//   1. the console text is identical line for line (paths canonicalised),
//   2. the success/failure outcome is identical, and
//   3. the written files are identical as a DICOM fingerprint (every element,
//      recursively, minus the UIDs and date/time stamps the engines mint per run).
//
// Both surfaces run the shared `AnonymizationWorkflow`; this suite is what proves
// the Workshop's parameter form and executor feed it the same request the CLI
// parses from argv — the PS3.15 retention options, the Clean Pixel Data default
// and its Burned In Annotation policy, and the whole pixel pipeline (explicit
// regions, OCR modes, styles, re-encoding, refusal).
//
// Use this checkout's debug product, built with the tests, so parity never exercises
// an older release binary from a different branch.

import Testing
import Foundation
@testable import DICOMStudio
@testable import DICOMKit
import DICOMCore

#if os(macOS)
import CoreGraphics
import CoreText

private typealias Tag = DICOMCore.Tag

@Suite("dicom-anon: Workshop vs terminal", .serialized)
@MainActor
struct AnonWorkshopCLIParityTests {

    // MARK: - Environment

    nonisolated private static let root: String? = CLIToolBuilder.repoRoot()
    nonisolated private static var binDir: String? {
        let dir: String
        if let explicit = ProcessInfo.processInfo.environment["DICOMKIT_TEST_BIN_DIR"], !explicit.isEmpty {
            dir = explicit
        } else {
            guard let root else { return nil }
            dir = "\(root)/.build/debug"
        }
        return FileManager.default.isExecutableFile(atPath: "\(dir)/dicom-anon") ? dir : nil
    }

    nonisolated private static let fixtures: Fixtures = { try! Fixtures.build() }()

    // MARK: - Fixtures

    struct Fixtures {
        let root: URL
        /// PHI in the header, flat pixels.
        var phi: String { root.appendingPathComponent("phi.dcm").path }
        /// PHI in the header and Burned In Annotation = YES.
        var burnedIn: String { root.appendingPathComponent("bia.dcm").path }
        /// PHI in the header and Burned In Annotation = NO (trusted by policy).
        var declaredClean: String { root.appendingPathComponent("bia-no.dcm").path }
        /// 512×256 frame with "SMITH JOHN 0012345" rendered at the top; header names the same patient.
        var banner: String { root.appendingPathComponent("banner.dcm").path }
        /// Two PHI files, one nested, plus a non-DICOM file.
        var dir: String { root.appendingPathComponent("dir").path }

        nonisolated static func build() throws -> Fixtures {
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent("AnonParity-\(UUID().uuidString)")
            try fm.createDirectory(at: root.appendingPathComponent("dir/nested"), withIntermediateDirectories: true)
            let fx = Fixtures(root: root)
            try phiFile().write(to: URL(fileURLWithPath: fx.phi))
            try phiFile(burnedIn: "YES").write(to: URL(fileURLWithPath: fx.burnedIn))
            try phiFile(burnedIn: "NO").write(to: URL(fileURLWithPath: fx.declaredClean))
            try bannerFile(text: "SMITH JOHN 0012345").write(to: URL(fileURLWithPath: fx.banner))
            try phiFile(sopInstance: "1.2.3.4.5.6.7.8.10").write(to: root.appendingPathComponent("dir/a.dcm"))
            try phiFile(sopInstance: "1.2.3.4.5.6.7.8.11").write(to: root.appendingPathComponent("dir/nested/b.dcm"))
            try Data("not dicom".utf8).write(to: root.appendingPathComponent("dir/readme.txt"))
            return fx
        }

        nonisolated static func dataSet(rows: Int, columns: Int, pixels: Data, burnedIn: String?, sopInstance: String) -> DataSet {
            var ds = DataSet()
            ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
            ds.setString(sopInstance, for: .sopInstanceUID, vr: .UI)
            ds.setString("1.2.3.4.5.100", for: .studyInstanceUID, vr: .UI)
            ds.setString("1.2.3.4.5.200", for: .seriesInstanceUID, vr: .UI)
            ds.setString("OT", for: .modality, vr: .CS)
            ds.setString("SMITH^JOHN", for: .patientName, vr: .PN)
            ds.setString("0012345", for: .patientID, vr: .LO)
            ds.setString("19800101", for: .patientBirthDate, vr: .DA)
            ds.setString("M", for: .patientSex, vr: .CS)
            ds.setString("20200101", for: .studyDate, vr: .DA)
            ds.setString("101500", for: .studyTime, vr: .TM)
            ds.setString("General Hospital", for: .institutionName, vr: .LO)
            ds.setString("ACME", for: .manufacturer, vr: .LO)
            ds.setString("Chest study", for: .studyDescription, vr: .LO)
            if let burnedIn { ds.setString(burnedIn, for: .burnedInAnnotation, vr: .CS) }
            ds.setUInt16(UInt16(rows), for: .rows)
            ds.setUInt16(UInt16(columns), for: .columns)
            ds.setUInt16(8, for: .bitsAllocated)
            ds.setUInt16(8, for: .bitsStored)
            ds.setUInt16(7, for: .highBit)
            ds.setUInt16(0, for: .pixelRepresentation)
            ds.setUInt16(1, for: .samplesPerPixel)
            ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
            ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: pixels)
            return ds
        }

        nonisolated static func file(_ ds: DataSet) throws -> Data {
            var meta = DataSet()
            meta.setString("1.2.840.10008.1.2.1", for: Tag(group: 0x0002, element: 0x0010), vr: .UI)
            return try DICOMFile(fileMetaInformation: meta, dataSet: ds).write()
        }

        nonisolated static func phiFile(burnedIn: String? = nil, sopInstance: String = "1.2.3.4.5.6.7.8.9") throws -> Data {
            try file(dataSet(rows: 8, columns: 16, pixels: Data(repeating: 200, count: 16 * 8),
                             burnedIn: burnedIn, sopInstance: sopInstance))
        }

        nonisolated static func bannerFile(text: String, columns: Int = 512, rows: Int = 256) throws -> Data {
            let space = CGColorSpaceCreateDeviceGray()
            let ctx = try #require(CGContext(
                data: nil, width: columns, height: rows, bitsPerComponent: 8,
                bytesPerRow: columns, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue))
            ctx.setFillColor(gray: 0.2, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: columns, height: rows))
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 28, nil)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(gray: 1, alpha: 1)]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
            ctx.textPosition = CGPoint(x: 24, y: CGFloat(rows) - 50)
            CTLineDraw(line, ctx)
            let raw = try #require(ctx.data)
            let pixels = Data(bytes: raw, count: columns * rows)
            return try file(dataSet(rows: rows, columns: columns, pixels: pixels, burnedIn: "YES",
                                    sopInstance: "1.2.3.4.5.6.7.8.20"))
        }
    }

    // MARK: - Cases

    struct Case: CustomStringConvertible {
        var name: String
        var input: String
        var params: [(String, String)]
        /// Leave `--output` unset (inspection / error paths).
        var noOutput = false
        /// Directory output (`--recursive`) instead of a single file.
        var outputIsDir = false
        /// Also pass `--audit-log` (written OUTSIDE the digested output dir).
        var auditLog = false
        var description: String { name }
    }

    struct Surface {
        var console: [String]
        var succeeded: Bool
        var files: [String: String]
    }

    private func runCase(_ c: Case, verbose: Bool) async throws {
        let binDir = try #require(Self.binDir, "debug dicom-anon not built — run swift build --product dicom-anon")
        let fx = Self.fixtures
        let fm = FileManager.default
        let caseDir = fm.temporaryDirectory.appendingPathComponent("AnonParityCase-\(UUID().uuidString)")
        let appOutDir = caseDir.appendingPathComponent("app")
        let cliOutDir = caseDir.appendingPathComponent("cli")
        try fm.createDirectory(at: appOutDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: cliOutDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: caseDir) }

        let appOutput = c.outputIsDir ? appOutDir.path : appOutDir.appendingPathComponent("anon.dcm").path
        let cliOutput = c.outputIsDir ? cliOutDir.path : cliOutDir.appendingPathComponent("anon.dcm").path
        let appAudit = caseDir.appendingPathComponent("app-audit.log").path
        let cliAudit = caseDir.appendingPathComponent("cli-audit.log").path

        // --- App (CLI Workshop) ---
        let vm = CLIWorkshopViewModel()
        vm.selectTool(id: "dicom-anon")
        vm.updateParameterValue(parameterID: "inputPath", value: c.input)
        if !c.noOutput { vm.updateParameterValue(parameterID: "output", value: appOutput) }
        if c.auditLog { vm.updateParameterValue(parameterID: "audit-log", value: appAudit) }
        for (k, v) in c.params { vm.updateParameterValue(parameterID: k, value: v) }
        if verbose { vm.updateParameterValue(parameterID: "verbose", value: "true") }
        await vm.executeCommand()
        let preview = vm.commandPreview
        let appConsole = Self.normalize(vm.consoleOutput, replacing: [appOutput, cliOutput, appAudit, cliAudit],
                                        fixtureRoot: fx.root.path, isApp: true)
        let app = Surface(console: appConsole, succeeded: vm.consoleStatus == .success,
                          files: try Self.digest(dir: appOutDir))

        // --- Terminal (real binary, same tokens as the preview) ---
        #expect(preview.hasPrefix("dicom-anon "), "[\(c)] preview must be the pasteable command: \(preview)")
        let cliPreview = preview
            .replacingOccurrences(of: appOutput, with: cliOutput)
            .replacingOccurrences(of: appAudit, with: cliAudit)
        var args = CLIToolTerminalCompare.shellSplit(cliPreview)
        #expect(args.first == "dicom-anon")
        args.removeFirst()
        let outcome = CLIToolTerminalCompare.run(tool: "dicom-anon", arguments: args, binDir: binDir, timeout: 180)
        #expect(outcome.launchError == nil, "[\(c)] \(outcome.launchError ?? "")")
        let cliConsole = Self.normalize(outcome.combined, replacing: [appOutput, cliOutput, appAudit, cliAudit],
                                        fixtureRoot: fx.root.path, isApp: false)
        let cli = Surface(console: cliConsole, succeeded: outcome.exitCode == 0,
                          files: try Self.digest(dir: cliOutDir))

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
        if c.auditLog {
            #expect(fm.fileExists(atPath: appAudit) == fm.fileExists(atPath: cliAudit), "\(label) audit log presence differs")
        }
    }

    // MARK: - Normalisation and fingerprints

    nonisolated static func normalize(_ raw: String, replacing paths: [String], fixtureRoot: String, isApp: Bool) -> [String] {
        var lines = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if isApp, lines.first?.hasPrefix("$ ") == true {
            lines.removeFirst()
            if lines.first == "" { lines.removeFirst() }
        }
        if !isApp, let usage = lines.firstIndex(where: { $0.hasPrefix("Usage:") }) {
            lines.removeSubrange(usage...)
        }
        lines = lines.map { line in
            var l = line
            for p in paths { l = l.replacingOccurrences(of: p, with: "<OUT>") }
            return l.replacingOccurrences(of: fixtureRoot, with: "<IN>").trimmingCharacters(in: .whitespaces)
        }
        while lines.last == "" { lines.removeLast() }
        return lines
    }

    nonisolated static func digest(dir: URL) throws -> [String: String] {
        var out: [String: String] = [:]
        guard let e = FileManager.default.enumerator(atPath: dir.path) else { return out }
        for case let rel as String in e {
            let url = dir.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let data = try Data(contentsOf: url)
            if let file = try? DICOMFile.read(from: data) {
                var lines: [String] = []
                for el in file.dataSet.allElements.sorted(by: { $0.tag < $1.tag }) {
                    append(el, depth: 0, into: &lines)
                }
                out[rel] = lines.joined(separator: "\n")
            } else {
                out[rel] = data.map { String(format: "%02x", $0) }.joined()
            }
        }
        return out
    }

    nonisolated private static func append(_ el: DataElement, depth: Int, into lines: inout [String]) {
        if [.DA, .TM, .DT, .UI].contains(el.vr) { return }   // minted per run (UIDs, de-identification stamps)
        let pad = String(repeating: " ", count: depth * 2)
        if let items = el.sequenceItems {
            lines.append("\(pad)\(el.tag) SQ items=\(items.count)")
            for (i, item) in items.enumerated() {
                lines.append("\(pad) item \(i)")
                for sub in item.elements.values.sorted(by: { $0.tag < $1.tag }) {
                    append(sub, depth: depth + 1, into: &lines)
                }
            }
        } else if let frags = el.encapsulatedFragments {
            lines.append("\(pad)\(el.tag) \(el.vr) fragments=\(frags.map { $0.count })")
        } else {
            lines.append("\(pad)\(el.tag) \(el.vr) \(el.valueData.map { String(format: "%02x", $0) }.joined())")
        }
    }

    // MARK: - Matrix

    nonisolated static var cases: [Case] {
        let fx = fixtures
        return [
            // The one profile and its options
            Case(name: "defaults (Basic Profile, pixel cleaning on)", input: fx.phi, params: []),
            Case(name: "all retention options", input: fx.phi, params: [
                ("retain-dates", "true"), ("retain-characteristics", "true"), ("retain-device", "true"),
                ("retain-institution", "true"), ("retain-uids", "true"), ("clean-descriptors", "true")]),
            Case(name: "shift-dates (Modified Dates)", input: fx.phi, params: [("shift-dates", "100")]),
            Case(name: "retain-dates + shift-dates conflict", input: fx.phi, params: [("retain-dates", "true"), ("shift-dates", "7")]),
            Case(name: "header only (--no-clean-pixel-data)", input: fx.phi, params: [("clean-pixel-data", "false")]),
            Case(name: "dry-run", input: fx.phi, params: [("dry-run", "true")], noOutput: true),
            Case(name: "backup", input: fx.phi, params: [("backup", "true")]),
            Case(name: "audit-log", input: fx.phi, params: [("dry-run", "true")], noOutput: true, auditLog: true),
            Case(name: "directory --recursive", input: fx.dir, params: [("recursive", "true")], outputIsDir: true),
            // Error paths (shared messages)
            Case(name: "directory without --recursive", input: fx.dir, params: [], outputIsDir: true),
            Case(name: "single file without --output", input: fx.phi, params: [], noOutput: true),
            Case(name: "missing input", input: fx.root.appendingPathComponent("nope.dcm").path, params: []),
            Case(name: "invalid --ocr-mode", input: fx.phi, params: [("ocr-mode", "fuzzy")]),
            Case(name: "invalid --redact-region", input: fx.phi, params: [("redact-region", "1,2,3")]),
            Case(name: "--recompress without cleaning", input: fx.phi, params: [("clean-pixel-data", "false"), ("recompress", "rle")]),
            Case(name: "removed ocr-mode all", input: fx.phi, params: [("ocr-mode", "all")]),
            Case(name: "text-only without cleaning", input: fx.phi, params: [("clean-pixel-data", "false"), ("text-only", "true")]),
            // Burned In Annotation policy
            Case(name: "BIA=NO trusted", input: fx.declaredClean, params: []),
            Case(name: "BIA=NO + redact-region overrides trust", input: fx.declaredClean, params: [("redact-region", "0,0,16,2")]),
            Case(name: "BIA=YES cleaning unresolved (no region source)", input: fx.burnedIn, params: []),
            Case(name: "BIA=YES header-only refuses", input: fx.burnedIn, params: [("clean-pixel-data", "false")]),
            Case(name: "BIA=YES header-only --allow-burned-in-phi", input: fx.burnedIn, params: [("clean-pixel-data", "false"), ("allow-burned-in-phi", "true")]),
            Case(name: "BIA=YES header-only dry-run reports residual", input: fx.burnedIn, params: [("clean-pixel-data", "false"), ("dry-run", "true")], noOutput: true),
            // Pixel pipeline: explicit regions
            Case(name: "redact-region", input: fx.burnedIn, params: [("redact-region", "0,0,16,2")]),
            Case(name: "two regions + fill", input: fx.phi, params: [("redact-region", "0,0,16,2; 0,6,4,2"), ("redact-fill", "9")]),
            Case(name: "region + label style", input: fx.banner, params: [("redact-region", "0,0,512,64"), ("redact-style", "label"), ("redact-label", "CLEANED")]),
            Case(name: "region + recompress rle", input: fx.phi, params: [("redact-region", "0,0,16,2"), ("recompress", "rle")]),
            Case(name: "region + recompress source", input: fx.phi, params: [("redact-region", "0,0,16,2"), ("recompress", "source")]),
            Case(name: "region dry-run plan", input: fx.phi, params: [("redact-region", "0,0,16,2"), ("dry-run", "true")], noOutput: true),
            Case(name: "redact-region + white fill", input: fx.burnedIn, params: [("redact-region", "0,0,16,2"), ("redact-fill", "white")]),
            Case(name: "redact-region + black fill (default, not echoed)", input: fx.burnedIn, params: [("redact-region", "0,0,16,2"), ("redact-fill", "black")]),
            // Pixel pipeline: OCR (default classify)
            Case(name: "banner cleaned by default", input: fx.banner, params: []),
            Case(name: "banner dry-run", input: fx.banner, params: [("dry-run", "true")], noOutput: true),
            Case(name: "ocr-mode classify dry-run", input: fx.banner, params: [("ocr-mode", "classify"), ("dry-run", "true")], noOutput: true),
            Case(name: "replace style", input: fx.banner, params: [("redact-style", "replace")]),
            Case(name: "ocr-all-frames + label", input: fx.banner, params: [("ocr-all-frames", "true"), ("redact-style", "label")]),
            Case(name: "OCR mode hidden when cleaning off is not applied", input: fx.phi, params: [("ocr-mode", "classify"), ("clean-pixel-data", "false")]),
            // header mode (fail-open, no keep-region bands) and the white fill
            Case(name: "ocr-mode header dry-run", input: fx.banner, params: [("ocr-mode", "header"), ("dry-run", "true")], noOutput: true),
            Case(name: "ocr-mode header", input: fx.banner, params: [("ocr-mode", "header")]),
            Case(name: "ocr-mode header + replace style", input: fx.banner, params: [("ocr-mode", "header"), ("redact-style", "replace")]),
            // text-only: flagged text at its exact position, no banner band
            Case(name: "header + text-only dry-run", input: fx.banner, params: [("ocr-mode", "header"), ("text-only", "true"), ("dry-run", "true")], noOutput: true),
            Case(name: "header + text-only + white fill", input: fx.banner, params: [("ocr-mode", "header"), ("text-only", "true"), ("redact-fill", "white")]),
            Case(name: "text-only hidden when cleaning off is not applied", input: fx.phi, params: [("text-only", "true"), ("clean-pixel-data", "false")]),
        ]
    }

    @Test("dicom-anon: every option combination matches the terminal", arguments: cases, [false, true])
    func anon(_ c: Case, verbose: Bool) async throws {
        try await runCase(c, verbose: verbose)
    }
}

#endif
