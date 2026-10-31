import Foundation
import DICOMPrintCommandSupport

public struct CLIWorkshopPrintCommandCodecError: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
}

/// A literal-argument codec, not a shell interpreter. Both entry and rebuilt
/// imports must pass the exact shared CLI parser before the form is replaced.
public enum CLIWorkshopPrintCommandCodec {
    private static func failure(_ message: String) -> CLIWorkshopPrintCommandCodecError {
        CLIWorkshopPrintCommandCodecError(message: message)
    }

    public static func listValues(_ raw: String) throws -> [String] {
        if raw.isEmpty { return [] }
        guard let data = raw.data(using: .utf8), let values = try? JSONDecoder().decode([String].self, from: data) else {
            throw failure("Enter a JSON array of strings; each item is one literal argument.")
        }
        guard !values.contains(where: { $0.contains("\0") }) else { throw failure("Arguments cannot contain a null character.") }
        return values
    }

    public static func encodedList(_ values: [String]) -> String {
        // An array of Swift strings has no fallible custom Codable implementation.
        String(decoding: try! JSONEncoder().encode(values), as: UTF8.self)
    }

    private static func selector(_ definitions: [CLIParameterDefinition]) throws -> CLIParameterDefinition {
        let selectors = definitions.filter { $0.parameterType == .subcommand }
        guard selectors.count == 1 else { throw failure("The print command requires one subcommand definition.") }
        return selectors[0]
    }

    private static func values(_ supplied: [CLIParameterValue], definitions: [CLIParameterDefinition]) throws -> [String: String] {
        guard Set(definitions.map(\.id)).count == definitions.count else { throw failure("Duplicate print parameter definitions.") }
        var result = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0.defaultValue) })
        var seen: Set<String> = []
        for value in supplied {
            guard seen.insert(value.parameterID).inserted else { throw failure("Duplicate print parameter: \(value.parameterID).") }
            if result[value.parameterID] != nil { result[value.parameterID] = value.stringValue }
        }
        let command = try selector(definitions)
        if result[command.id]?.isEmpty != false { result[command.id] = command.defaultValue }
        guard command.allowedValues.contains(result[command.id] ?? "") else { throw failure("Choose a supported print subcommand.") }
        return result
    }

    private static func visible(_ definition: CLIParameterDefinition, values: [String: String]) -> Bool {
        let conditions = (definition.visibleWhen.map { [$0] } ?? []) + definition.visibleWhenAll
        return conditions.allSatisfy { $0.values.contains(values[$0.parameterId] ?? "") }
    }

    public static func arguments(toolID: String, parameterValues: [CLIParameterValue],
                                 parameterDefinitions: [CLIParameterDefinition]) throws -> [String] {
        guard ["dicom-print", "dicom-printscp"].contains(toolID) else { throw failure("Unsupported print tool.") }
        let selected = try selector(parameterDefinitions)
        let effective = try values(parameterValues, definitions: parameterDefinitions)
        var flags: [String] = [], positionals: [String] = []
        for definition in parameterDefinitions where definition.id != selected.id && !definition.isInternal {
            guard visible(definition, values: effective) else { continue }
            let raw = effective[definition.id] ?? ""
            guard !raw.contains("\0") else { throw failure("Arguments cannot contain a null character.") }
            switch definition.parameterType {
            case .booleanToggle:
                switch raw {
                case "true": flags.append(definition.flag)
                case "false": if let negative = definition.negatedFlag, !negative.isEmpty { flags.append(negative) }
                case "": break
                default: throw failure("\(definition.displayName) must be enabled or disabled.")
                }
            case .flagPicker:
                guard let token = definition.cliMapping[raw] else { throw failure("Choose a supported value for \(definition.displayName).") }
                if !token.isEmpty { flags.append(token) }
            default:
                let items = definition.isRepeatable ? try listValues(raw) : (raw.isEmpty ? [] : [raw])
                if definition.isRequired && items.isEmpty { throw failure("Provide \(definition.displayName).") }
                for item in items {
                    if definition.flag.isEmpty {
                        positionals.append(item)
                    } else if item.hasPrefix("-") {
                        flags.append(definition.flag + "=" + item)
                    } else {
                        flags.append(contentsOf: [definition.flag, item])
                    }
                }
            }
        }
        // All named options precede the delimiter. A leading-dash filename must
        // remain a filename, including in a variadic positional collection.
        return [toolID, effective[selected.id]!] + flags + (positionals.isEmpty ? [] : ["--"] + positionals)
    }

    public static func importCommand(_ text: String, toolID: String,
                                     parameterDefinitions: [CLIParameterDefinition]) throws -> [CLIParameterValue] {
        let tokens = try tokenize(text)
        guard tokens.first == toolID else { throw failure("Import a command beginning with \(toolID).") }
        try validate(Array(tokens.dropFirst()), toolID: toolID)
        let imported = try decode(Array(tokens.dropFirst()), definitions: parameterDefinitions)
        let rebuilt = try arguments(toolID: toolID, parameterValues: imported, parameterDefinitions: parameterDefinitions)
        try validate(Array(rebuilt.dropFirst()), toolID: toolID)
        let roundTrip = try decode(Array(rebuilt.dropFirst()), definitions: parameterDefinitions)
        let lhs = Dictionary(uniqueKeysWithValues: imported.map { ($0.parameterID, $0.stringValue) })
        let rhs = Dictionary(uniqueKeysWithValues: roundTrip.map { ($0.parameterID, $0.stringValue) })
        guard lhs == rhs else { throw failure("This command cannot be represented without changing its arguments.") }
        return imported
    }

    private static func validate(_ arguments: [String], toolID: String) throws {
        switch toolID {
        case "dicom-print": try PrintSCUCommand.validate(arguments: arguments)
        case "dicom-printscp": try PrintSCPCommand.validate(arguments: arguments)
        default: throw failure("Unsupported print tool.")
        }
    }

    private struct FlagBinding {
        let definition: CLIParameterDefinition
        let flagValue: String? // A boolean/tristate flag's stored value; nil consumes a value.
    }

    private static func decode(_ arguments: [String], definitions: [CLIParameterDefinition]) throws -> [CLIParameterValue] {
        let selected = try selector(definitions)
        var effective = try values([], definitions: definitions)
        var tokens = arguments
        if let first = tokens.first, selected.allowedValues.contains(first) {
            effective[selected.id] = tokens.removeFirst()
        }
        let active = definitions.filter { $0.id != selected.id && !$0.isInternal && visible($0, values: effective) }
        var bindings: [String: FlagBinding] = [:]
        func bind(_ flag: String, _ definition: CLIParameterDefinition, _ value: String?) throws {
            guard !flag.isEmpty, bindings[flag] == nil else { throw failure("Ambiguous print option definition.") }
            bindings[flag] = FlagBinding(definition: definition, flagValue: value)
        }
        for definition in active where !definition.flag.isEmpty {
            if definition.parameterType == .flagPicker {
                for (value, token) in definition.cliMapping where !token.isEmpty { try bind(token, definition, value) }
            } else if definition.parameterType == .booleanToggle {
                try bind(definition.flag, definition, "true")
                if let negative = definition.negatedFlag, !negative.isEmpty { try bind(negative, definition, "false") }
            } else {
                try bind(definition.flag, definition, nil)
            }
        }
        // These are the only short aliases declared in the frozen print CLI inventory.
        for (short, long) in [("-v", "--verbose"), ("-r", "--recursive")] {
            if let binding = bindings[long] { bindings[short] = binding }
        }
        var seen: Set<String> = [], repeated: [String: [String]] = [:], positional: [String] = []
        var options = true, index = 0
        while index < tokens.count {
            let token = tokens[index]
            index += 1
            if options && token == "--" { options = false; continue }
            if options && token.hasPrefix("-") && token != "-" {
                // ArgumentParser accepts clustered short boolean aliases (-vr).
                if !token.hasPrefix("--"), token.count > 2,
                   token.dropFirst().allSatisfy({ bindings["-" + String($0)]?.flagValue != nil }) {
                    tokens.insert(contentsOf: token.dropFirst().map { "-" + String($0) }, at: index)
                    continue
                }
                let pair = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let binding = bindings[String(pair[0])] else { throw failure("Unsupported or hidden print option: \(pair[0]).") }
                let definition = binding.definition
                if !definition.isRepeatable && !seen.insert(definition.id).inserted {
                    throw failure("Specify \(definition.flag) only once; duplicate scalar options are ambiguous.")
                }
                let value: String
                if let flagValue = binding.flagValue {
                    guard pair.count == 1 else { throw failure("\(definition.flag) does not take a value.") }
                    value = flagValue
                } else if pair.count == 2 {
                    value = String(pair[1])
                } else {
                    guard index < tokens.count else { throw failure("Missing value for \(definition.flag).") }
                    value = tokens[index]; index += 1
                }
                if definition.isRepeatable {
                    repeated[definition.id, default: []].append(value)
                } else {
                    // An absent optional field and an explicit empty CLI value are
                    // different states. Refuse rather than silently omit the latter.
                    guard !value.isEmpty else { throw failure("An explicit empty value for \(definition.flag) cannot be represented in this form.") }
                    effective[definition.id] = value
                }
            } else {
                positional.append(token)
            }
        }
        var cursor = 0
        for definition in active where definition.flag.isEmpty {
            if definition.isRepeatable {
                repeated[definition.id] = Array(positional.dropFirst(cursor)); cursor = positional.count
            } else if cursor < positional.count {
                guard !positional[cursor].isEmpty else { throw failure("An explicit empty \(definition.displayName) cannot be represented in this form.") }
                effective[definition.id] = positional[cursor]; cursor += 1
            }
        }
        guard cursor == positional.count else { throw failure("Unexpected extra print positional argument.") }
        for definition in active where definition.isRepeatable {
            effective[definition.id] = encodedList(repeated[definition.id] ?? [])
        }
        return definitions.map { CLIParameterValue(parameterID: $0.id, stringValue: effective[$0.id] ?? $0.defaultValue) }
    }

    /// Bounded POSIX-style quoting: recognizes literal quoting and escapes only.
    /// Expansions, redirects, pipelines and command separators are rejected.
    private static func tokenize(_ input: String) throws -> [String] {
        enum Quote: Equatable { case single, double }
        let chars = Array(input)
        var quote: Quote?, token = "", started = false, tokens: [String] = [], index = 0
        func finish() { if started { tokens.append(token); token = ""; started = false } }
        while index < chars.count {
            let c = chars[index]; index += 1
            guard c != "\0" else { throw failure("Arguments cannot contain a null character.") }
            if quote == .single {
                if c == "'" { quote = nil } else { token.append(c) }
                continue
            }
            if c == "\\" {
                guard index < chars.count else { throw failure("A backslash must escape another character.") }
                let next = chars[index]
                if quote == .double && !"$`\"\\\n".contains(next) {
                    token.append(c); continue
                }
                index += 1
                if next != "\n" { token.append(next); started = true }
                continue
            }
            if quote == .double {
                if c == "\"" { quote = nil }
                else if c == "$" || c == "`" { throw failure("Shell expansion is not supported. Quote literal values with single quotes.") }
                else { token.append(c) }
                continue
            }
            if c == "'" { quote = .single; started = true; continue }
            if c == "\"" { quote = .double; started = true; continue }
            if c == " " || c == "\t" { finish(); continue }
            if "\n\r;|&<>`(){}$*?[]~!#".contains(c) || (c == "=" && !started) {
                throw failure("Shell operators or expansion are not supported; quote literal argument values.")
            }
            token.append(c); started = true
        }
        guard quote == nil else { throw failure("Close the quoted argument before importing.") }
        finish()
        guard !tokens.isEmpty else { throw failure("Paste a print command to import.") }
        return tokens
    }
}
