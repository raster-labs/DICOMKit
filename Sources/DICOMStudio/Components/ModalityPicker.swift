// ModalityPicker.swift
// DICOMStudio
//
// DICOM Studio — a sectioned picker over the DICOM modality defined terms.
//
// NEMA-verified: 2026a, checked 2026-10-05 — offers DICOMCore Modality.groupedByCategory: 79 current codes == the PS3.3 2026a C.7.3.1.1.1 Defined Terms (0 wrong, 0 missing); retired and private codes stay selectable when already bound

#if canImport(SwiftUI)
import SwiftUI
import DICOMCore

/// A picker over every current DICOM modality, grouped by category.
///
/// The list comes from ``DICOMCore/Modality/allCases`` — all 79 PS3.3
/// C.7.3.1.1.1 defined terms — so the app offers what the standard defines
/// rather than a hand-maintained subset. Retired codes and the conventional
/// non-standard codes (`SC`, `VL`) are excluded: they are recognized on parse
/// but never offered for new objects.
///
/// A flat 79-item menu is unusable, so entries are sectioned by
/// ``DICOMCore/Modality/Category``.
@available(macOS 14.0, iOS 17.0, *)
public struct ModalityPicker: View {
    private let title: String
    private let includeAnyOption: Bool
    private let anyOptionLabel: String
    @Binding private var selection: String

    /// Creates a modality picker.
    ///
    /// - Parameters:
    ///   - title: The picker's label.
    ///   - selection: The bound modality code. When `includeAnyOption` is true,
    ///     the empty string means "no filter".
    ///   - includeAnyOption: Adds a leading empty entry, for filter fields where
    ///     no modality means "match any".
    ///   - anyOptionLabel: The label for that leading entry.
    public init(
        _ title: String,
        selection: Binding<String>,
        includeAnyOption: Bool = false,
        anyOptionLabel: String = "Any"
    ) {
        self.title = title
        self._selection = selection
        self.includeAnyOption = includeAnyOption
        self.anyOptionLabel = anyOptionLabel
    }

    public var body: some View {
        Picker(title, selection: $selection) {
            if includeAnyOption {
                Text(anyOptionLabel).tag("")
            }
            // A value already in the data but not offered — a retired code, a
            // private one, or SC — still has to be selectable, or binding to it
            // would silently reset the field to the first entry.
            if !selection.isEmpty, Modality(rawValue: selection)?.isCurrent != true {
                Text(currentSelectionLabel).tag(selection)
            }
            ForEach(Modality.groupedByCategory, id: \.category) { group in
                Section(group.category.name) {
                    ForEach(group.modalities, id: \.rawValue) { modality in
                        Text("\(modality.rawValue) — \(modality.name)")
                            .tag(modality.rawValue)
                    }
                }
            }
        }
        .accessibilityLabel("\(title) selection")
    }

    /// Label for a bound value that is not among the offered codes.
    private var currentSelectionLabel: String {
        guard let modality = Modality(rawValue: selection) else {
            return "\(selection) — private code"
        }
        if modality.isRetired { return "\(modality.rawValue) — \(modality.name) (retired)" }
        return "\(modality.rawValue) — \(modality.name)"
    }
}
#endif
