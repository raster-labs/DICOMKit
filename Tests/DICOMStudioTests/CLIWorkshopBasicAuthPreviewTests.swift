import Foundation
import Testing
@testable import DICOMStudio

@Suite("Workshop Basic authentication preview", .serialized)
@MainActor
struct CLIWorkshopBasicAuthPreviewTests {
    nonisolated private static let toolIDs = ["dicom-qido", "dicom-wado", "dicom-stow", "dicom-ups"]
    nonisolated private static let commandNames = [
        "dicom-qido": "dicom-wado query",
        "dicom-wado": "dicom-wado retrieve",
        "dicom-stow": "dicom-wado store",
        "dicom-ups": "dicom-wado ups",
    ]
    nonisolated private static let password = "M1-private-password-'$;\\secret"
    nonisolated private static let username = "M1-private-username"
    nonisolated private static let token = "M1-bearer-token"

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    private func configuredViewModel(_ toolID: String) throws -> CLIWorkshopViewModel {
        let vm = CLIWorkshopViewModel()
        vm.selectTool(id: toolID)
        let tool = try #require(vm.selectedTool())
        #expect(tool.id == toolID)
        #expect(tool.name == Self.commandNames[toolID])
        vm.updateParameterValue(parameterID: "url", value: "https://example.invalid/dicomweb")
        vm.updateParameterValue(parameterID: "username", value: Self.username)
        vm.updateParameterValue(parameterID: "password", value: Self.password)
        vm.updateParameterValue(parameterID: "token", value: Self.token)
        return vm
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("All catalog Basic-auth entry points are app-only and omit credentials", arguments: toolIDs)
    func basicAuthIsAppOnly(toolID: String) throws {
        let vm = try configuredViewModel(toolID)
        let command = try #require(Self.commandNames[toolID])
        vm.updateParameterValue(parameterID: "auth", value: "basic")

        #expect(vm.commandPreview.hasPrefix("# in-app only — basic auth is not CLI-representable"))
        #expect(vm.commandPreview.contains("# " + command))
        #expect(vm.commandPreview.components(separatedBy: "\n").allSatisfy { $0.hasPrefix("# ") })
        #expect(!vm.commandPreview.contains(Self.password))
        #expect(!vm.commandPreview.contains(Self.username))
        #expect(!vm.commandPreview.contains(Self.token))
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("None and Bearer retain supported command previews", arguments: toolIDs)
    func supportedAuthModesRemainRunnable(toolID: String) throws {
        let vm = try configuredViewModel(toolID)
        let command = try #require(Self.commandNames[toolID])
        vm.updateParameterValue(parameterID: "auth", value: "none")
        #expect(vm.commandPreview.hasPrefix(command + " "))
        #expect(!vm.commandPreview.hasPrefix("#"))
        #expect(!vm.commandPreview.contains("--token"))
        #expect(!vm.commandPreview.contains(Self.token))
        #expect(!vm.commandPreview.contains(Self.password))
        #expect(!vm.commandPreview.contains(Self.username))

        vm.updateParameterValue(parameterID: "auth", value: "bearer")
        #expect(vm.commandPreview.hasPrefix(command + " "))
        #expect(!vm.commandPreview.hasPrefix("#"))
        #expect(vm.commandPreview.contains("--token " + Self.token))
        #expect(!vm.commandPreview.contains(Self.password))
        #expect(!vm.commandPreview.contains(Self.username))

        // A mode change must also remove a previously emitted Bearer token.
        vm.updateParameterValue(parameterID: "auth", value: "basic")
        #expect(vm.commandPreview.hasPrefix("# in-app only"))
        #expect(!vm.commandPreview.contains(Self.token))
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("Basic-auth detection survives changed labels and command spellings", arguments: toolIDs)
    func stableIdentitySurvivesRenaming(toolID: String) throws {
        let vm = try configuredViewModel(toolID)
        let index = try #require(vm.tools.firstIndex(where: { $0.id == toolID }))
        vm.tools[index].displayName = "Renamed DICOMweb operation"
        vm.tools[index].name = "future-web-command operation"
        vm.updateParameterValue(parameterID: "auth", value: "basic")

        #expect(vm.commandPreview.hasPrefix("# in-app only — basic auth is not CLI-representable"))
        #expect(vm.commandPreview.contains("# " + CommandBuilderHelpers.shellEscape("future-web-command operation")))
        #expect(!vm.commandPreview.contains(Self.password))
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("Every line of a multiline Basic-auth preview remains commented", arguments: toolIDs)
    func multilineAppOnlyPreviewCannotExposeRunnableTail(toolID: String) throws {
        let vm = try configuredViewModel(toolID)
        vm.updateParameterValue(parameterID: "url", value: "https://example.invalid/dicomweb\nM1-SECOND-LINE")
        vm.updateParameterValue(parameterID: "auth", value: "basic")

        let lines = vm.commandPreview.components(separatedBy: "\n")
        #expect(lines.count >= 3)
        #expect(lines.allSatisfy { $0.hasPrefix("# ") })
        #expect(vm.commandPreview.contains("M1-SECOND-LINE"))
        #expect(!vm.commandPreview.contains(Self.password))
    }
}
