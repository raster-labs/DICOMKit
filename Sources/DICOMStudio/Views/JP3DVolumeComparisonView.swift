// JP3DVolumeComparisonView.swift
// DICOMStudio
//
// Full-blown 3D MPR comparison viewer.
// Layout: 3 plane rows × 2 columns (RAW | J2KSwift Compressed)
// Unified slice + W/L controls at bottom. Dark medical imaging theme.

#if canImport(SwiftUI) && canImport(CoreGraphics)
import SwiftUI
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - JP3DVolumeComparisonView

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct JP3DVolumeComparisonView: View {

    @Bindable var vm: JP3DVolumeComparisonViewModel
    @State private var isDropTargeted = false

    public init(viewModel: JP3DVolumeComparisonViewModel) {
        self.vm = viewModel
    }

    public var body: some View {
        ZStack {
            studioBackground
            if vm.hasVolume {
                studioLayout
            } else if vm.isLoadingVolume {
                loadingOverlay
            } else {
                dropZone
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers); return true
        }
        .overlay(dropTargetRing)
    }

    // MARK: - Backgrounds

    private var studioBackground: some View {
        Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 24) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 72, weight: .ultraLight))
                .foregroundStyle(.quaternary)

            VStack(spacing: 8) {
                Text("3D Volume Comparison Viewer")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Drop a DICOM series folder or JP3D file to open")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Supports multi-frame CT / MR series and JP3D encapsulated documents")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            openVolumeButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.4)
            Text("Loading volume…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var dropTargetRing: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, lineWidth: 3)
                .background(Color.accentColor.opacity(0.06).ignoresSafeArea())
                .allowsHitTesting(false)
        }
    }

    // MARK: - Main Studio Layout

    private var studioLayout: some View {
        VStack(spacing: 0) {
            headerBar
            columnHeaders
            planeGrid
            controlPanel
            metricsBar
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 10) {
            openVolumeButton

            if !vm.volumeInfo.isEmpty {
                Divider().frame(height: 16).foregroundStyle(.tertiary)
                Text(vm.volumeInfo)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Picker("", selection: $vm.selectedID) {
                ForEach(vm.codecOptions) { opt in
                    Text(opt.name).tag(opt.id)
                }
            }
            .labelsHidden()
            #if os(macOS)
            .frame(maxWidth: 170)
            #endif

            compressButtonBar
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(white: 0.10))
    }

    @ViewBuilder
    private var compressButtonBar: some View {
        switch vm.compressionState {
        case .idle:
            Button { vm.runCompression() } label: {
                Label("Compress", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)

        case .compressing(let done, let total):
            HStack(spacing: 8) {
                ProgressView(value: Double(done), total: Double(max(1, total)))
                    .frame(width: 80)
                Text("\(done)/\(total) frames")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

        case .complete:
            Button { vm.runCompression() } label: {
                Label("Re-compress", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)

        case .failed:
            Button { vm.runCompression() } label: {
                Label("Retry", systemImage: "exclamationmark.arrow.circlepath")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    // MARK: - Column Headers

    private var columnHeaders: some View {
        HStack(spacing: 1) {
            columnHeaderCell(
                title: "RAW VOLUME",
                subtitle: "Uncompressed original",
                color: Color(red: 0.20, green: 0.55, blue: 0.90),
                icon: "waveform.path"
            )
            columnHeaderCell(
                title: "SwiftJ2K COMPRESSED",
                subtitle: compressedSubtitle,
                color: compressedHeaderColor,
                icon: "waveform.path.ecg"
            )
        }
        .frame(height: 38)
    }

    private func columnHeaderCell(title: String, subtitle: String, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .tracking(0.8)
                Text(subtitle)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(color.opacity(0.65))
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.10))
        .overlay(alignment: .bottom) {
            color.opacity(0.4).frame(height: 1)
        }
    }

    private var compressedSubtitle: String {
        switch vm.compressionState {
        case .idle:
            return vm.hasVolume ? "Tap Compress to run SwiftJ2K encode → decode" : ""
        case .compressing(let done, let total):
            return "Encoding frame \(done) of \(total)…"
        case .complete(_, _, let ratio, _, let enc):
            return "\(vm.compressedCodecName) · \(String(format: "%.2f×", ratio)) · \(formatBytes(enc))"
        case .failed(let msg):
            return "Error: \(msg)"
        }
    }

    private var compressedHeaderColor: Color {
        switch vm.compressionState {
        case .idle:          return Color(white: 0.45)
        case .compressing:   return Color(red: 0.90, green: 0.70, blue: 0.20)
        case .complete:      return Color(red: 0.25, green: 0.80, blue: 0.50)
        case .failed:        return Color(red: 0.90, green: 0.30, blue: 0.30)
        }
    }

    // MARK: - 3-Row × 2-Column Plane Grid

    private var planeGrid: some View {
        VStack(spacing: 1) {
            ForEach([MPRPlane.axial, .sagittal, .coronal], id: \.self) { plane in
                HStack(spacing: 1) {
                    mprCell(plane: plane, childVM: vm.rawVM, isCompressed: false)
                    mprCell(plane: plane, childVM: vm.compressedVM, isCompressed: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
    }

    // MARK: - Single MPR Cell

    private func mprCell(plane: MPRPlane, childVM: JP3DMPRViewModel, isCompressed: Bool) -> some View {
        GeometryReader { geo in
            ZStack {
                Color(white: 0.07)

                // Medical image
                if let img = cgImage(plane: plane, from: childVM) {
                    Image(decorative: img, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    emptyPanelPlaceholder(plane: plane)
                }

                // Reference lines
                if childVM.volume != nil {
                    referenceLinesCanvas(plane: plane, size: geo.size)
                }

                // Plane label badge (top-left)
                planeBadge(plane, isCompressed: isCompressed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(6)

                // Slice counter (bottom-left)
                sliceCounter(plane: plane)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(6)
            }
            .contentShape(Rectangle())
            .onTapGesture { loc in
                vm.handleClick(x: loc.x, y: loc.y, in: plane, viewSize: geo.size)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        vm.handleClick(x: v.location.x, y: v.location.y, in: plane, viewSize: geo.size)
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func emptyPanelPlaceholder(plane: MPRPlane) -> some View {
        VStack(spacing: 6) {
            Image(systemName: planeSFSymbol(plane))
                .font(.system(size: 22))
                .foregroundStyle(Color(white: 0.22))
            Text(planeName(plane))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color(white: 0.25))
        }
    }

    // MARK: - Reference Lines Canvas

    private func referenceLinesCanvas(plane: MPRPlane, size: CGSize) -> some View {
        Canvas { context, _ in
            for refPlane in MPRPlane.allCases where refPlane != plane {
                guard let t = refLineT(refPlane: refPlane, displayPlane: plane) else { continue }
                let color = JP3DMPRRenderHelpers.referenceLineColour(for: refPlane)
                let axis  = JP3DMPRRenderHelpers.referenceLineAxis(referencePlane: refPlane, displayPlane: plane)
                let path = Path { p in
                    switch axis {
                    case .horizontal:
                        let y = size.height * CGFloat(t)
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                    case .vertical:
                        let x = size.width * CGFloat(t)
                        p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                    }
                }
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Plane Badge + Slice Counter

    private func planeBadge(_ plane: MPRPlane, isCompressed: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(planeDotColor(plane))
                .frame(width: 6, height: 6)
            Text(planeName(plane))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(planeDotColor(plane))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.55))
        .clipShape(Capsule())
    }

    private func sliceCounter(plane: MPRPlane) -> some View {
        let (cur, maxIdx) = sliceInfo(plane: plane)
        return Text("\(cur + 1) / \(maxIdx + 1)")
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(Color(white: 0.55))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.50))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Control Panel (shared sliders)

    private var controlPanel: some View {
        HStack(alignment: .top, spacing: 20) {
            // Plane slice sliders
            VStack(spacing: 6) {
                planeSlider(.axial,    index: vm.axialIndex,    max: vm.maxAxialIndex)    { vm.setAxialIndex($0) }
                planeSlider(.sagittal, index: vm.sagittalIndex, max: vm.maxSagittalIndex) { vm.setSagittalIndex($0) }
                planeSlider(.coronal,  index: vm.coronalIndex,  max: vm.maxCoronalIndex)  { vm.setCoronalIndex($0) }
            }

            Divider().frame(height: 60)

            // Window / Level
            VStack(spacing: 6) {
                wlSlider("W/C", value: vm.windowCenter, range: -1024...3072) { v in
                    vm.setWindowLevel(center: v, width: vm.windowWidth)
                }
                wlSlider("W/W", value: vm.windowWidth, range: 1...4096) { v in
                    vm.setWindowLevel(center: vm.windowCenter, width: v)
                }
            }
            .frame(minWidth: 220)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(white: 0.10))
    }

    private func planeSlider(
        _ plane: MPRPlane,
        index: Int,
        max maxIdx: Int,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(planeDotColor(plane))
                .frame(width: 7, height: 7)
            Text(planeShortName(plane))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(planeDotColor(plane))
                .frame(width: 28, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(index) },
                    set: { onChange(Int($0.rounded())) }
                ),
                in: 0...Double(max(1, maxIdx)), step: 1
            )
            Text("\(index + 1)/\(maxIdx + 1)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.45))
                .frame(width: 58, alignment: .trailing)
        }
    }

    private func wlSlider(
        _ label: String,
        value: Double,
        range: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.50))
                .frame(width: 28, alignment: .leading)
            Slider(
                value: Binding(get: { value }, set: { onChange($0) }),
                in: range, step: 1
            )
            Text(String(format: "%.0f", value))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.45))
                .frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: - Metrics Bar

    @ViewBuilder
    private var metricsBar: some View {
        HStack(spacing: 14) {
            switch vm.compressionState {
            case .idle:
                Text(vm.hasVolume ? "Select a codec and tap Compress to compare." : "")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

            case .compressing(let done, let total):
                Text("Compressing \(done)/\(total) frames…")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(red: 0.90, green: 0.70, blue: 0.20))

            case .complete(let encMs, let decMs, let ratio, let rawB, let encB):
                metricPill("Ratio", value: String(format: "%.2f×", ratio),
                           accent: ratio >= 2 ? .green : .yellow)
                metricPill("Raw",  value: formatBytes(rawB))
                metricPill("Enc'd", value: formatBytes(encB))
                metricPill("Encode", value: formatMs(encMs))
                metricPill("Decode", value: formatMs(decMs))
                metricPill("Total",  value: formatMs(encMs + decMs), accent: .primary)
                Spacer()
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    .font(.system(size: 11))
                Text("Complete")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)

            case .failed(let msg):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(white: 0.09))
    }

    private func metricPill(_ label: String, value: String, accent: Color = .secondary) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.40))
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(accent)
        }
    }

    // MARK: - Open Volume Button

    private var openVolumeButton: some View {
        Button {
            openVolumePicker()
        } label: {
            Label("Open Volume", systemImage: "folder.badge.plus")
                .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Rendering Helpers

    private func cgImage(plane: MPRPlane, from childVM: JP3DMPRViewModel) -> CGImage? {
        guard let dims = childVM.dimensions else { return nil }
        let buf: Data?
        switch plane {
        case .axial:    buf = childVM.axialBuffer
        case .sagittal: buf = childVM.sagittalBuffer
        case .coronal:  buf = childVM.coronalBuffer
        }
        guard let data = buf else { return nil }
        let (w, h) = MPRHelpers.sliceDimensions(plane: plane, dimensions: dims)
        return JP3DMPRRenderHelpers.cgImage(from: data, width: w, height: h)
    }

    private func refLineT(refPlane: MPRPlane, displayPlane: MPRPlane) -> Double? {
        guard let dims = vm.rawVM.dimensions else { return nil }
        let idx: Int
        switch refPlane {
        case .axial:    idx = vm.axialIndex
        case .sagittal: idx = vm.sagittalIndex
        case .coronal:  idx = vm.coronalIndex
        }
        return MPRHelpers.referenceLinePosition(
            referencePlane: refPlane,
            referenceSlice: idx,
            displayPlane: displayPlane,
            dimensions: dims
        )
    }

    private func sliceInfo(plane: MPRPlane) -> (current: Int, max: Int) {
        switch plane {
        case .axial:    return (vm.axialIndex,    vm.maxAxialIndex)
        case .sagittal: return (vm.sagittalIndex, vm.maxSagittalIndex)
        case .coronal:  return (vm.coronalIndex,  vm.maxCoronalIndex)
        }
    }

    // MARK: - Plane Style Helpers

    private func planeDotColor(_ plane: MPRPlane) -> Color {
        switch plane {
        case .axial:    return Color(red: 0.0,  green: 0.9,  blue: 0.9)   // cyan
        case .sagittal: return Color(red: 1.0,  green: 0.85, blue: 0.0)   // yellow
        case .coronal:  return Color(red: 0.25, green: 0.85, blue: 0.35)  // green
        }
    }

    private func planeName(_ plane: MPRPlane) -> String {
        switch plane {
        case .axial:    return "AXIAL"
        case .sagittal: return "SAGITTAL"
        case .coronal:  return "CORONAL"
        }
    }

    private func planeShortName(_ plane: MPRPlane) -> String {
        switch plane {
        case .axial:    return "AX"
        case .sagittal: return "SAG"
        case .coronal:  return "COR"
        }
    }

    private func planeSFSymbol(_ plane: MPRPlane) -> String {
        switch plane {
        case .axial:    return "square.split.1x2"
        case .sagittal: return "square.split.2x1"
        case .coronal:  return "square.grid.2x2"
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                try? await self.vm.loadVolume(from: url)
            }
        }
    }

    // MARK: - File Picker

    private func openVolumePicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a DICOM series folder or JP3D file"
        if panel.runModal() == .OK, let url = panel.url {
            Task { try? await vm.loadVolume(from: url) }
        }
        #endif
    }

    // MARK: - Formatters

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024       { return "\(bytes) B" }
        if bytes < 1_048_576  { return String(format: "%.1f KB", Double(bytes) / 1_024) }
        return                         String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    private func formatMs(_ ms: Double) -> String {
        ms < 1_000 ? String(format: "%.0f ms", ms) : String(format: "%.2f s", ms / 1_000)
    }
}

// MARK: - Preview

#if DEBUG
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
#Preview("Empty Drop Zone") {
    JP3DVolumeComparisonView(viewModel: JP3DVolumeComparisonViewModel())
        .frame(width: 1100, height: 780)
}
#endif

#endif // canImport(SwiftUI) && canImport(CoreGraphics)
