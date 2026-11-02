import Foundation

/// Narrow compatibility checks for retired Toolbox settings. Never infer a new
/// retention policy from a legacy profile name or an arbitrary tag allow-list.
public enum ToolboxCommandContract {
    public static let anonymizationProfiles = ["ps315", "basic"]
    public static let scriptTemplates = ["workflow", "pipeline", "query", "archive", "anonymize"]

    public static func issues(toolID: String, values: [String: String], subcommand: String?) -> [String] {
        var result: [String] = []
        if toolID == "dicom-anon" {
            if let profile = values["profile"], !profile.isEmpty, !anonymizationProfiles.contains(profile) {
                result.append("The saved profile '\(profile)' is unsupported. Select PS3.15 or Basic (alias), then review the retention options; legacy profiles are not equivalent.")
            }
            if let value = values["regenerate-uids"], !value.isEmpty {
                result.append("The saved Regenerate UIDs setting uses a removed option. Discard that setting, then choose Retain UIDs explicitly: off regenerates UIDs; on retains them.")
            }
            if let value = values["keep"], !value.isEmpty {
                result.append("The saved Tags to Keep setting uses the removed --keep option. Discard it and review the standard retention options in dicom-anon; arbitrary tag retention is unavailable in this form.")
            }
        }
        if toolID == "dicom-script", subcommand == "template" {
            if let output = values["output"], !output.isEmpty {
                result.append("Script Template no longer accepts --output. Discard the saved output setting, choose a template name, then copy the generated script from the console.")
            }
            if let name = values["template-name"], !name.isEmpty, !scriptTemplates.contains(name) {
                result.append("Unknown template '\(name)'. Choose workflow, pipeline, query, archive, or anonymize.")
            }
        }
        return result
    }

    /// Validate persisted literal argv too: old history may disagree with its
    /// parameter dictionary. Refuse before replay or exporting executable text.
    public static func replayIssue(_ invocation: CommandInvocation) -> String? {
        let args = invocation.arguments
        func has(_ flag: String) -> Bool { args.contains { $0 == flag || $0.hasPrefix(flag + "=") } }
        func option(_ flag: String) -> String? {
            for (index, value) in args.enumerated() {
                if value.hasPrefix(flag + "=") { return String(value.dropFirst(flag.count + 1)) }
                if value == flag { return index + 1 < args.count ? args[index + 1] : "" }
            }
            return nil
        }
        if invocation.executable == "dicom-anon" {
            if has("--keep") || has("--regenerate-uids") {
                return "This saved anonymization command uses removed --keep or --regenerate-uids options. Rebuild it in Toolbox and review Retain UIDs before running."
            }
            if let profile = option("--profile"), !anonymizationProfiles.contains(profile) {
                return "This saved anonymization profile is unsupported. Rebuild using PS3.15 or Basic (alias) and explicit retention settings."
            }
        }
        if invocation.executable == "dicom-script", args.first == "template" {
            if has("--output") || args.count != 2 || !scriptTemplates.contains(args[1]) {
                return "Rebuild this saved template command with one template name (workflow, pipeline, query, archive, anonymize). Output is printed to the console; --output is unsupported."
            }
        }
        return nil
    }
}

public struct ToolboxCommandValidationError: LocalizedError, Sendable {
    public let messages: [String]
    public var errorDescription: String? { messages.joined(separator: "\n") }
}
