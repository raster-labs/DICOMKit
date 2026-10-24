#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers

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
