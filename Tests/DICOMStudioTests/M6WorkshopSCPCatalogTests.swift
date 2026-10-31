import Foundation
import XCTest
import DICOMPrintCommandSupport
@testable import DICOMStudio

final class M6WorkshopSCPCatalogTests: XCTestCase {
    func testAllSCPDeclarationsAreRepresentedOnceAndScopedToActualCommands() {
        let definitions = CLIWorkshopPrintSCPCatalog.parameters
        XCTAssertEqual(definitions.count, 73)
        XCTAssertEqual(Set(definitions.map(\.id)).count, definitions.count)
        for (command, count) in [("serve", 43), ("simulate", 41), ("status", 40), ("queues", 1)] {
            let values = [CLIParameterValue(parameterID: "subcommand", stringValue: command)]
            let visible = definitions.filter { $0.id != "subcommand" && CommandBuilderHelpers.isVisible($0, parameterValues: values, parameterDefinitions: definitions) }
            XCTAssertEqual(visible.count, count, command)
            XCTAssertEqual(Set(visible.map(\.flag)).count, count, "Duplicate visible flags in \(command)")
        }
    }

    func testSCPOptionalFlagsExposeInheritAndBothActualParserSpellings() throws {
        let definitions = CLIWorkshopPrintSCPCatalog.parameters
        let triState = definitions.filter { $0.parameterType == .flagPicker }
        XCTAssertEqual(triState.count, 5)
        for definition in triState {
            XCTAssertEqual(definition.defaultValue, "inherit")
            XCTAssertEqual(definition.allowedValues, ["inherit", "enabled", "disabled"])
            XCTAssertEqual(definition.cliMapping["inherit"], "")
            for mode in ["enabled", "disabled"] {
                let flag = try XCTUnwrap(definition.cliMapping[mode])
                XCTAssertNoThrow(try PrintSCPCommand.validate(arguments: ["status", flag]))
            }
        }
        XCTAssertFalse(definitions.contains { $0.flag == "--no-raw" })
    }

    func testAllSCPRepeatablesUseLosslessArrayFields() {
        let definitions = CLIWorkshopPrintSCPCatalog.parameters
        let repeatables = definitions.filter(\.isRepeatable)
        XCTAssertEqual(repeatables.count, 7)
        XCTAssertTrue(repeatables.allSatisfy { $0.parameterType == .arrayField })
        XCTAssertTrue(repeatables.contains { $0.id == "scp.SimulateCommand.paths" && $0.flag.isEmpty })
        XCTAssertTrue(repeatables.contains { $0.flag == "--annotate" })
    }
}
