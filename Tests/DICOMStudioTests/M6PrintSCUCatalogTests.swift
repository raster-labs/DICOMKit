import Foundation
import XCTest
import DICOMPrintCommandSupport
@testable import DICOMStudio

@MainActor
final class M6PrintSCUCatalogTests: XCTestCase {
    func testEveryFrozenSCUDeclarationHasAnApplicableControl() throws {
        let all = CLIWorkshopPrintCatalog.parameters
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        let operation = try XCTUnwrap(all.first { $0.id == "operation" })
        XCTAssertEqual(operation.defaultValue, "send")
        XCTAssertEqual(operation.allowedValues, ["status", "send", "job", "list-printers", "add-printer", "remove-printer"])
        let expected: [String: Set<String>] = [
            "status": ["url", "--aet", "--called-aet", "--timeout", "--verbose", "--format"],
            "send": ["url", "paths", "--aet", "--called-aet", "--copies", "--film-size", "--orientation",
                     "--priority", "--layout", "--template", "--medium", "--magnification", "--film-destination",
                     "--check-status", "--verify", "--format", "--color", "--frame", "--all-frames", "--raw",
                     "--window-center", "--window-width", "--bit-depth", "--presentation-lut", "--palette",
                     "--annotate", "--annotation-format", "--recursive", "--dry-run", "--verbose", "--timeout", "--retries"],
            "job": ["url", "--aet", "--called-aet", "--job-id", "--timeout", "--verbose", "--format"],
            "list-printers": ["--format", "--verbose"],
            "add-printer": ["--name", "--host", "--port", "--called-ae", "--calling-ae", "--color", "--default"],
            "remove-printer": ["--name"]
        ]
        var declarationCount = 0
        for command in operation.allowedValues {
            let active = all.filter { $0.id != "operation" && ($0.visibleWhen?.values.contains(command) ?? false) }
            let flags = active.map { $0.flag.isEmpty ? $0.id : $0.flag }
            XCTAssertEqual(Set(flags), expected[command], command)
            XCTAssertEqual(flags.count, Set(flags).count, "A flag binds once for \(command)")
            declarationCount += active.count
        }
        XCTAssertEqual(declarationCount, 55, "Frozen SCU declaration count")
    }

    func testRepeatableAndAliasFieldsDoNotLoseImportedMeaning() throws {
        let fields = Dictionary(uniqueKeysWithValues: CLIWorkshopPrintCatalog.parameters.map { ($0.id, $0) })
        for id in ["paths", "annotate"] {
            XCTAssertEqual(fields[id]?.parameterType, .arrayField)
            XCTAssertTrue(fields[id]?.isRepeatable == true)
        }
        for id in ["filmSize", "orientation", "priority", "medium", "magnification", "filmDestination", "layout", "presentationLut", "palette"] {
            XCTAssertEqual(fields[id]?.parameterType, .textField, "\(id) accepts editable CLI aliases")
        }
        XCTAssertEqual(fields["sendTimeout"]?.defaultValue, "60")
        XCTAssertEqual(fields["queryTimeout"]?.defaultValue, "30")
        XCTAssertEqual(fields["raw"]?.defaultValue, "false")
        XCTAssertNil(fields["raw"]?.negatedFlag)
        XCTAssertEqual(fields["name"]?.visibleWhen?.values, ["add-printer", "remove-printer"])
    }

    func testWorkshopAdapterUsesSameParserRefusals() {
        for arguments in [["send", "pacs://localhost", "x.dcm", "--aet", "APP", "--no-raw"],
                          ["send", "pacs://localhost", "x.dcm", "--aet", "APP", "--window-center=-600"],
                          ["status"], ["job", "pacs://localhost", "--aet", "APP"],
                          ["add-printer", "--name", "missing-fields"], ["remove-printer"]] {
            XCTAssertThrowsError(try CLIWorkshopPrintExecutor.validate(arguments: arguments))
            XCTAssertThrowsError(try PrintSCUCommand.validate(arguments: arguments))
        }
        XCTAssertNoThrow(try CLIWorkshopPrintExecutor.validate(arguments: ["send", "pacs://localhost", "x.dcm", "--aet", "APP",
            "--layout", "ROW\\1,3", "--window-center=-600", "--window-width", "1200",
            "--annotate", "literal; one", "--annotate", "two \\ slash", "--annotation-format", "FMT"]))
    }

    func testWorkshopAdapterMutatesOnlyExplicitRegistryLocation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("m6-workshop-registry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = root.appendingPathComponent("isolated/printers.json")
        let context = PrintCommandContext(printersURL: registry, defaultSCPConfigURL: root.appendingPathComponent("unused.json"),
            output: { _ in }, diagnostic: { _ in })
        try await CLIWorkshopPrintExecutor.execute(arguments: ["add-printer", "--name", "Synthetic; 雪", "--host", "localhost",
            "--called-ae", "PRINTER", "--default"], context: context)
        let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: registry)) as? [[String: Any]])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0]["name"] as? String, "Synthetic; 雪")
        XCTAssertEqual(entries[0]["isDefault"] as? Bool, true)
        try await CLIWorkshopPrintExecutor.execute(arguments: ["remove-printer", "--name", "Synthetic; 雪"], context: context)
        let empty = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: registry)) as? [Any])
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.defaultSCPConfigURL.path))
    }
}
