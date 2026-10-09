// CodecInspectorView.swift
// DICOMStudio
//
// DICOM Studio — Codec inspector panel view (Phase 8)
//
// NEMA-verified: 2026a, checked 2026-10-05 — UI layout only; the #Preview's .4.90 literal and its name "JPEG 2000 Image Compression (Lossless Only)" match PS3.6 2026a Table A-1

#if canImport(SwiftUI)
import SwiftUI
import DICOMCore

// MARK: - CodecInspectorView

/// A compact inspector panel showing which codec decoded the current DICOM image.
///
/// Display it as a floating overlay or inside a sheet within `ImageViewerView`:
///
/// ```swift
/// CodecInspectorView(viewModel: viewerViewModel.codecInspector)
/// ```
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct CodecInspectorView: View {

    let viewModel: CodecInspectorViewModel

    public init(viewModel: CodecInspectorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GroupBox {
            statusContent
        } label: {
            Label(
                NSLocalizedString(
                    "codec.inspector.title",
                    value: "Codec",
                    comment: "Codec inspector panel title"
                ),
                systemImage: "slider.horizontal.3"
            )
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
        }
        .padding(8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            NSLocalizedString(
                "codec.inspector.panel.accessibility",
                value: "Codec Inspector Panel",
                comment: "Accessibility label for the codec inspector panel"
            )
        )
    }

    // MARK: - Status content

    @ViewBuilder
    private var statusContent: some View {
        switch viewModel.status {
        case .noImage:
            Label(
                NSLocalizedString(
                    "codec.inspector.no_image",
                    value: "No image loaded",
                    comment: "Codec inspector: no image"
                ),
                systemImage: "photo"
            )
            .foregroundStyle(.secondary)

        case .decoding:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(
                    NSLocalizedString(
                        "codec.inspector.decoding",
                        value: "Decoding…",
                        comment: "Codec inspector: decoding in progress"
                    )
                )
                .foregroundStyle(.secondary)
            }

        case .decoded(let entry):
            VStack(alignment: .leading, spacing: 6) {
                codecRow(
                    label: NSLocalizedString("codec.inspector.codec",   value: "Codec",       comment: "Codec label"),
                    value: entry.codecName
                )
                codecRow(
                    label:       NSLocalizedString("codec.inspector.backend",  value: "Backend",     comment: "Backend label"),
                    value:       CodecInspectorHelpers.backendDisplayName(entry.backend),
                    systemImage: CodecInspectorHelpers.backendSFSymbol(entry.backend)
                )
                codecRow(
                    label: NSLocalizedString("codec.inspector.time",    value: "Decode Time", comment: "Decode time label"),
                    value: CodecInspectorHelpers.formatDecodeTime(entry.decodeTimeMs)
                )
                codecRow(
                    label: NSLocalizedString("codec.inspector.frames",  value: "Frames",      comment: "Frame count label"),
                    value: "\(entry.frameCount)"
                )
                Divider()
                Text(entry.transferSyntaxUID)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(
                        NSLocalizedString(
                            "codec.inspector.ts_uid.accessibility",
                            value: "Transfer Syntax UID: \(entry.transferSyntaxUID)",
                            comment: "Accessibility: TS UID"
                        )
                    )
            }

        case .uncompressed(let desc):
            Label(
                String(
                    format: NSLocalizedString(
                        "codec.inspector.uncompressed",
                        value: "Uncompressed (%@)",
                        comment: "Codec inspector: uncompressed transfer syntax"
                    ),
                    desc
                ),
                systemImage: "doc.plaintext"
            )
            .foregroundStyle(.secondary)

        case .unsupportedCodec(let uid):
            Label(
                String(
                    format: NSLocalizedString(
                        "codec.inspector.unsupported",
                        value: "No codec for %@",
                        comment: "Codec inspector: unsupported codec UID"
                    ),
                    uid
                ),
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.red)
        }
    }

    // MARK: - Row helper

    @ViewBuilder
    private func codecRow(label: String, value: String, systemImage: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 80, alignment: .leading)
            if let icon = systemImage {
                Label(value, systemImage: icon)
                    .font(.caption.bold())
            } else {
                Text(value)
                    .font(.caption.bold())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Preview

#if DEBUG
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
#Preview("Decoded") {
    let vm = CodecInspectorViewModel()
    vm.status = .decoded(CodecInspectorEntry(
        transferSyntaxUID: "1.2.840.10008.1.2.4.90",
        transferSyntaxDescription: "JPEG 2000 Image Compression (Lossless Only)",
        codecName: "J2KSwift (JPEG 2000)",
        backend: .accelerate,
        decodeTimeMs: 12.3,
        frameCount: 1
    ))
    return CodecInspectorView(viewModel: vm)
        .frame(width: 260)
        .padding()
}

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
#Preview("No Image") {
    CodecInspectorView(viewModel: CodecInspectorViewModel())
        .frame(width: 260)
        .padding()
}
#endif

#endif // canImport(SwiftUI)
