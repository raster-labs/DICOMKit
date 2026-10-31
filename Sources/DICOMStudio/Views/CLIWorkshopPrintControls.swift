#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

/// Print flags use one semantic checkbox, with longer instructions outside its
/// label. The composed SwiftUI checkbox label can lose its name in macOS AX.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct CLIWorkshopPrintOptionCheckbox: View {
    let parameter: CLIParameterDefinition
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            #if canImport(AppKit)
            CLIWorkshopPrintCheckboxBridge(parameter: parameter, isOn: $isOn)
                .fixedSize(horizontal: false, vertical: true)
            #else
            Toggle(parameter.displayName, isOn: $isOn)
                .accessibilityIdentifier("print-option-\(parameter.id)")
                .accessibilityHint(parameter.helpText)
            #endif
            if !parameter.helpText.isEmpty {
                Text(parameter.helpText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if canImport(AppKit)
@available(macOS 14.0, *)
private struct CLIWorkshopPrintCheckboxBridge: NSViewRepresentable {
    let parameter: CLIParameterDefinition
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> CLIWorkshopPrintNativeCheckbox {
        CLIWorkshopPrintNativeCheckbox(parameter: parameter, isOn: $isOn, isEnabled: isEnabled)
    }

    func updateNSView(_ checkbox: CLIWorkshopPrintNativeCheckbox, context: Context) {
        checkbox.update(parameter: parameter, isOn: $isOn, isEnabled: isEnabled)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CLIWorkshopPrintNativeCheckbox, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        // NSButton's unconstrained title width must not become the minimum
        // width of the entire vertical form. Let AppKit wrap within the actual
        // proposal, including SwiftUI's zero-width minimum-size probe.
        let intrinsicHeight = max(0, nsView.intrinsicContentSize.height)
        guard width > 0 else { return CGSize(width: 0, height: intrinsicHeight) }
        let bounds = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude)
        let height = max(intrinsicHeight, nsView.cell?.cellSize(forBounds: bounds).height ?? intrinsicHeight)
        return CGSize(width: width, height: height)
    }
}

/// Native switch semantics expose name, state and press action together. Keep
/// the binding current when SwiftUI reuses a row after changing subcommands.
@available(macOS 14.0, *)
@MainActor
final class CLIWorkshopPrintNativeCheckbox: NSButton {
    private var value: Binding<Bool>

    init(parameter: CLIParameterDefinition, isOn: Binding<Bool>, isEnabled: Bool = true) {
        value = isOn
        super.init(frame: .zero)
        setButtonType(.switch)
        cell?.wraps = true
        cell?.usesSingleLineMode = false
        lineBreakMode = .byWordWrapping
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        target = self
        action = #selector(valueChanged)
        update(parameter: parameter, isOn: isOn, isEnabled: isEnabled)
    }

    required init?(coder: NSCoder) { return nil }

    func update(parameter: CLIParameterDefinition, isOn: Binding<Bool>, isEnabled: Bool = true) {
        value = isOn
        self.isEnabled = isEnabled
        title = parameter.flag.isEmpty ? parameter.displayName : "\(parameter.flag)  \(parameter.displayName)"
        state = isOn.wrappedValue ? .on : .off
        setAccessibilityLabel(parameter.displayName)
        setAccessibilityHelp(parameter.helpText)
        setAccessibilityIdentifier("print-option-\(parameter.id)")
        toolTip = parameter.helpText
    }

    @objc private func valueChanged() {
        guard isEnabled else { return }
        value.wrappedValue = state == .on
    }
}
#endif

/// One literal argument per row: spaces, semicolons and empty strings are data.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct CLIWorkshopPrintListField: View {
    @Binding var rawValue: String
    let label: String
    let isFileList: Bool
    let selectedFiles: ([URL]) -> Void
    @State private var choosingFiles = false

    private var values: [String] {
        (try? CLIWorkshopPrintCommandCodec.listValues(rawValue)) ?? []
    }
    private func set(_ values: [String]) {
        rawValue = CLIWorkshopPrintCommandCodec.encodedList(values)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(values.indices), id: \.self) { index in
                HStack {
                    TextField("Value", text: Binding(
                        get: { values.indices.contains(index) ? values[index] : "" },
                        set: { value in
                            var copy = values
                            guard copy.indices.contains(index) else { return }
                            copy[index] = value
                            set(copy)
                        }))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("\(label) entry \(index + 1)")
                    Button {
                        var copy = values
                        guard copy.indices.contains(index) else { return }
                        copy.remove(at: index)
                        set(copy)
                    } label: { Image(systemName: "minus.circle") }
                        .accessibilityLabel("Remove \(label) entry \(index + 1)")
                }
            }
            HStack {
                Button("Add Entry") { set(values + [""]) }
                    .accessibilityLabel("Add \(label) entry")
                if isFileList {
                    Button("Browse") { choosingFiles = true }
                        .accessibilityLabel("Browse for \(label)")
                }
            }
        }
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.data, .folder],
            allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { selectedFiles(urls) }
            }
    }
}
#endif
