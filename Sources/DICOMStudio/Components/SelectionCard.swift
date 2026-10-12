// SelectionCard.swift
// DICOMStudio
//
// DICOM Studio — Shared "selected card" look for tab and sidebar rows

#if canImport(SwiftUI)
import SwiftUI

/// The accent-tinted card that marks a selected tab or sidebar row: a soft
/// accent fill with a thin accent border (the CLI Workshop category style).
///
/// `.strong` is the full card — fill plus border — for a top-level pick such
/// as a sidebar category or a tool tab. `.light` is the same fill at a lower
/// tint with no border, for a child row sitting under an already-highlighted
/// parent so the two levels read as one selection rather than two.
@available(macOS 14.0, iOS 17.0, *)
struct SelectionCard: ViewModifier {
    enum Emphasis { case strong, light }

    let isSelected: Bool
    var emphasis: Emphasis = .strong
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(fillColor))
            .overlay(shape.stroke(strokeColor, lineWidth: 1))
            .contentShape(shape)
    }

    private var fillColor: Color {
        guard isSelected else { return .clear }
        return Color.accentColor.opacity(emphasis == .strong ? 0.15 : 0.09)
    }

    private var strokeColor: Color {
        guard isSelected, emphasis == .strong else { return .clear }
        return Color.accentColor.opacity(0.55)
    }
}

@available(macOS 14.0, iOS 17.0, *)
extension View {
    /// Draws the shared accent selection card behind this view when
    /// `isSelected`, otherwise leaves it untouched.
    func selectionCard(_ isSelected: Bool,
                       emphasis: SelectionCard.Emphasis = .strong,
                       cornerRadius: CGFloat = 8) -> some View {
        modifier(SelectionCard(isSelected: isSelected,
                               emphasis: emphasis,
                               cornerRadius: cornerRadius))
    }
}
#endif
