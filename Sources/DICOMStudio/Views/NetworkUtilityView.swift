// NetworkUtilityView.swift
// DICOMStudio
//
// DICOM Studio — Network Utility view: a set of general (non-DICOM) network
// diagnostic tools (interfaces, ping, port scan, traceroute, DNS, netstat)
// behind a tab picker. Results are shown both as readable structured cards
// and as a dark, system-terminal-style output panel that fills the pane.

#if canImport(SwiftUI)
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct NetworkUtilityView: View {
    @Bindable var viewModel: NetworkUtilityViewModel

    public init(viewModel: NetworkUtilityViewModel) {
        self.viewModel = viewModel
    }

    // Terminal palette
    private static let termBackground = Color(red: 0.07, green: 0.08, blue: 0.10)
    private static let termText       = Color(red: 0.80, green: 0.92, blue: 0.82)

    /// Width cap for single-line text inputs (host / IP address fields) so they
    /// read as a precise field rather than stretching the full pane width.
    private static let inputWidth: CGFloat = 420

    /// Tools that render their output live (streamed line-by-line) and so
    /// suppress the centre "Working…" overlay, which would otherwise hide the
    /// very output the user wants to watch.
    private static let streamingTools: Set<NetworkUtilityTool> =
        [.ping, .portScan, .traceroute, .dnsLookup, .netstat]

    public var body: some View {
        VStack(spacing: 0) {
            toolPicker
            Divider()
            toolContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay {
            // Ping and Port Scanner fill their output live, so a blocking spinner
            // would only hide the very thing the user wants to watch.
            if viewModel.isRunning && !Self.streamingTools.contains(viewModel.activeTool) {
                ProgressView("Working…")
                    .font(.title3)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Network Utility", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let msg = viewModel.errorMessage { Text(msg) }
        }
        .onDisappear { viewModel.cancel() }
    }

    // MARK: - Tab picker

    private var toolPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NetworkUtilityTool.allCases) { tool in
                    let selected = viewModel.activeTool == tool
                    Button { viewModel.activeTool = tool } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tool.sfSymbol)
                                .font(.title3)
                                .foregroundStyle(selected ? Color.accentColor : .secondary)
                            Text(tool.displayName)
                                .font(.body.weight(selected ? .semibold : .regular))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .selectionCard(selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tool.displayName)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var toolContent: some View {
        switch viewModel.activeTool {
        case .interfaces:  interfacesContent
        case .ping:        pingContent
        case .portScan:    portContent
        case .traceroute:  traceContent
        case .dnsLookup:   dnsContent
        case .netstat:     netstatContent
        }
    }

    /// Outer scaffold for a tool pane: fixed content at the top, growing to
    /// fill the available height so a trailing terminal panel reaches the
    /// bottom of the window.
    private func toolScaffold<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) { content() }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Shared building blocks

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inputCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.callout.weight(.medium)).foregroundStyle(.secondary)
    }

    private func runButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: action) {
                Label(title, systemImage: systemImage).font(.body.weight(.semibold)).padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isRunning)
            if viewModel.isRunning {
                Button("Cancel", role: .cancel) { viewModel.cancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private func statusBanner(_ status: NetRunStatus) -> some View {
        if status != .success {
            HStack(spacing: 10) {
                Image(systemName: status == .cancelled ? "stop.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title3)
                Text(status.message).font(.body)
            }
            .foregroundStyle(status == .cancelled ? Color.secondary : Color(.systemOrange))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Dark terminal-style output panel: no header bar, text pinned to the
    /// top-left, copy button floating in the top-right corner. Fills the
    /// remaining vertical space of its container.
    ///
    /// `.fixedSize(horizontal: true)` stops the text frame from becoming
    /// ambiguous inside a bidirectional ScrollView (which proposes unconstrained
    /// width), which would otherwise centre the text.
    private func terminalPanel(_ text: String) -> some View {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScrollView([.vertical, .horizontal]) {
            Text(body.isEmpty ? "— no output —" : body)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Self.termText)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .padding(14)
        }
        .defaultScrollAnchor(.topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Self.termBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.35)))
        .overlay(alignment: .topTrailing) {
            #if canImport(AppKit)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(body, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc").font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.45))
            .padding(10)
            .help("Copy output")
            #endif
        }
    }

    private func familyPicker(_ selection: Binding<IPFamily>) -> some View {
        HStack(spacing: 10) {
            fieldLabel("IP Version")
            Picker("IP Version", selection: selection) {
                ForEach(IPFamily.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
        }
    }

    private func hostField(_ binding: Binding<String>, prompt: String, onSubmit: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            fieldLabel("Host")
            TextField(prompt, text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .frame(maxWidth: Self.inputWidth)
                .onSubmit(onSubmit)
            Spacer()
        }
    }

    // MARK: - 1. Interfaces

    private var interfacesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    header("Interfaces", "Local network interfaces, addresses and traffic counters.")
                    Spacer()
                    Button { viewModel.loadInterfaces() } label: {
                        Label("Refresh", systemImage: "arrow.clockwise").font(.body)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(viewModel.isRunning)
                }

                if !viewModel.interfaces.isEmpty {
                    interfacePicker
                }

                if let iface = viewModel.selectedInterface {
                    interfaceInfoCard(iface)
                    transferStatsCard(iface)
                } else if !viewModel.isRunning {
                    Text("No network interfaces found.")
                        .font(.body).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { if viewModel.interfaces.isEmpty { viewModel.loadInterfaces() } }
    }

    private var interfacePicker: some View {
        HStack(spacing: 14) {
            fieldLabel("Network Interface")
            Spacer()
            Picker("Network Interface", selection: Binding(
                get: { viewModel.selectedInterface?.name ?? "" },
                set: { viewModel.selectedInterfaceName = $0 }
            )) {
                ForEach(viewModel.interfaces) { iface in
                    Text(iface.menuTitle).tag(iface.name)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 280)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func interfaceInfoCard(_ iface: NetworkInterface) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Interface Information")
            VStack(alignment: .leading, spacing: 10) {
                infoRow("Interface", iface.displayName ?? iface.name)
                infoRow("Name", iface.name, mono: true)
                infoRow("Hardware Address", iface.macAddress ?? "—", mono: true)
                infoRow("IPv4 Address", iface.ipv4Address ?? "—", mono: true)
                infoRow("IPv6 Address", iface.ipv6Address ?? "—", mono: true)
                HStack(alignment: .top, spacing: 16) {
                    Text("Status").font(.body).foregroundStyle(.secondary)
                        .frame(width: 170, alignment: .leading)
                    Text(iface.isActive ? "Active" : "Inactive")
                        .font(.body.weight(.medium))
                        .foregroundStyle(iface.isActive ? Color.green : Color.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func infoRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label).font(.body).foregroundStyle(.secondary)
                .frame(width: 170, alignment: .leading)
            Text(value)
                .font(mono ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func transferStatsCard(_ iface: NetworkInterface) -> some View {
        let s = iface.statistics
        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Transfer Statistics")
            Grid(alignment: .trailing, horizontalSpacing: 48, verticalSpacing: 12) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    Text("Sent").font(.headline)
                    Text("Received").font(.headline)
                }
                statRow("Packets", sent: s?.packetsOut, received: s?.packetsIn)
                statRow("Bytes", sent: s?.bytesOut, received: s?.bytesIn)
                statRow("Errors", sent: s?.errorsOut, received: s?.errorsIn)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statRow(_ label: String, sent: UInt64?, received: UInt64?) -> some View {
        GridRow {
            Text(label).font(.body).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            Text(sent.map(formatCount) ?? "—").font(.body.monospacedDigit())
                .frame(minWidth: 120, alignment: .trailing)
            Text(received.map(formatCount) ?? "—").font(.body.monospacedDigit())
                .frame(minWidth: 120, alignment: .trailing)
        }
    }

    private func formatCount(_ v: UInt64) -> String { v.formatted(.number) }

    // MARK: - 2. Ping

    private var pingContent: some View {
        toolScaffold {
            header("Ping", "Measure round-trip time and packet loss to a host (ICMP).")
            inputCard {
                hostField($viewModel.sharedHost, prompt: "example.com or 1.2.3.4") { viewModel.runPing() }
                HStack(alignment: .center, spacing: 16) {
                    fieldLabel("Packets")
                    Stepper("\(viewModel.pingCount)", value: $viewModel.pingCount, in: 1...20)
                        .font(.body).frame(width: 140)
                    Divider().frame(height: 20)
                    familyPicker($viewModel.pingFamily)
                    Spacer()
                }
                runButton("Ping", systemImage: "dot.radiowaves.left.and.right") { viewModel.runPing() }
            }

            if let r = viewModel.pingResult {
                statusBanner(r.status)
                if r.packetsReceived > 0 || r.rttAvgMs != nil {
                    summaryGrid([
                        ("Transmitted", "\(r.packetsTransmitted)"),
                        ("Received", "\(r.packetsReceived)"),
                        ("Loss", String(format: "%.1f%%", r.packetLossPercent)),
                        ("Avg RTT", r.rttAvgMs.map { String(format: "%.2f ms", $0) } ?? "—"),
                        ("Min RTT", r.rttMinMs.map { String(format: "%.2f ms", $0) } ?? "—"),
                        ("Max RTT", r.rttMaxMs.map { String(format: "%.2f ms", $0) } ?? "—"),
                    ])
                }
                sectionTitle("Output")
                terminalPanel(r.rawOutput)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    /// A wrapping grid of labelled metric chips.
    private func summaryGrid(_ items: [(String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0).font(.caption).foregroundStyle(.secondary)
                    Text(item.1).font(.title3.weight(.medium).monospacedDigit())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - 3. Port Scanner

    private var portContent: some View {
        toolScaffold {
            header("Port Scanner", "Check which TCP ports are open on a host.")
            inputCard {
                hostField($viewModel.sharedHost, prompt: "example.com or 1.2.3.4") { viewModel.runPortScan() }
                HStack(alignment: .center, spacing: 12) {
                    fieldLabel("Ports")
                    TextField("22,80,443,8000-8100", text: $viewModel.portSpec)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: Self.inputWidth)
                    Spacer()
                }
                HStack(alignment: .center, spacing: 12) {
                    fieldLabel("Timeout: \(String(format: "%.2f s", viewModel.portTimeout))")
                    Slider(value: $viewModel.portTimeout, in: 0.25...5, step: 0.25).frame(maxWidth: 260)
                    Spacer()
                }
                runButton("Scan", systemImage: "lock.open.rotation") { viewModel.runPortScan() }
            }

            if viewModel.isRunning || !viewModel.portResults.isEmpty {
                // Render while scanning too (not just once results exist) so the
                // header appears immediately — an all-filtered host otherwise
                // shows nothing until the first per-port timeout elapses.
                let open = viewModel.portResults.filter { $0.status == .open }.count
                sectionTitle("\(viewModel.portResults.count) scanned · \(open) open")
                terminalPanel(portScanText)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    /// Left-pads/truncates to a fixed column width for terminal alignment.
    private func pad(_ s: String, _ w: Int) -> String {
        s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
    }

    /// Port results in arrival order (not re-sorted) so each line appends to the
    /// bottom of the panel as the probe completes — a stable, live scan log
    /// rather than a table that reshuffles on every result.
    private var portScanText: String {
        var lines = [pad("PORT", 12) + pad("STATE", 12) + pad("SERVICE", 14) + "LATENCY"]
        for p in viewModel.portResults {
            let port = "\(p.port)/tcp"
            let svc = p.serviceName ?? ""
            let lat = p.latencyMs.map { String(format: "%.0f ms", $0) } ?? ""
            lines.append(pad(port, 12) + pad(p.status.rawValue, 12) + pad(svc, 14) + lat)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 4. Traceroute

    private var traceContent: some View {
        toolScaffold {
            header("Traceroute", "Trace the network hops to a destination.")
            inputCard {
                hostField($viewModel.sharedHost, prompt: "example.com or 1.2.3.4") { viewModel.runTraceroute() }
                HStack(alignment: .center, spacing: 16) {
                    fieldLabel("Max hops")
                    Stepper("\(viewModel.traceMaxHops)", value: $viewModel.traceMaxHops, in: 1...30)
                        .font(.body).frame(width: 140)
                    Divider().frame(height: 20)
                    familyPicker($viewModel.traceFamily)
                    Spacer()
                }
                runButton("Trace", systemImage: "point.topleft.down.curvedto.point.bottomright.up") { viewModel.runTraceroute() }
            }

            if let r = viewModel.traceResult {
                statusBanner(r.status)
                sectionTitle(r.reachedDestination ? "Reached \(r.host) in \(r.hops.count) hops" : "Hops to \(r.host)")
                terminalPanel(r.rawOutput)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 5. DNS Lookup

    private var dnsContent: some View {
        toolScaffold {
            header("DNS Lookup", "Resolve a domain and inspect its DNS records.")
            inputCard {
                hostField($viewModel.dnsHost, prompt: "example.com") { viewModel.runDNSLookup() }
                HStack(alignment: .center, spacing: 12) {
                    fieldLabel("Record types")
                    HStack(spacing: 8) {
                        ForEach(DNSRecordType.allCases) { type in
                            let on = viewModel.dnsTypes.contains(type)
                            Button(type.displayName) { viewModel.toggleDNSType(type) }
                                .buttonStyle(.plain)
                                .font(.callout.monospaced().weight(on ? .bold : .regular))
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .background(on ? Color.accentColor.opacity(0.22) : Color.gray.opacity(0.14),
                                            in: RoundedRectangle(cornerRadius: 7))
                                .accessibilityLabel("\(type.displayName) record\(on ? ", selected" : "")")
                        }
                    }
                    Spacer()
                }
                runButton("Lookup", systemImage: "magnifyingglass") { viewModel.runDNSLookup() }
            }

            if let r = viewModel.dnsResult {
                statusBanner(r.status)
                if !r.records.isEmpty {
                    sectionTitle("\(r.records.count) record\(r.records.count == 1 ? "" : "s")")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(DNSRecordType.allCases) { type in
                                let recs = r.records.filter { $0.type == type }
                                if !recs.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(type.displayName).font(.headline.monospaced())
                                        ForEach(recs) { rec in
                                            HStack(alignment: .top, spacing: 14) {
                                                if let ttl = rec.ttlSeconds {
                                                    Text("ttl \(ttl)").foregroundStyle(.secondary)
                                                        .frame(width: 100, alignment: .leading)
                                                }
                                                Text(rec.value).textSelection(.enabled)
                                            }
                                            .font(.system(.body, design: .monospaced))
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
                sectionTitle("Output")
                terminalPanel(r.rawOutput)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 6. Netstat

    private var netstatContent: some View {
        toolScaffold {
            header("Netstat", "Active sockets, listeners and the routing table.")
            inputCard {
                HStack(alignment: .center, spacing: 12) {
                    fieldLabel("Mode")
                    Picker("Mode", selection: $viewModel.netstatMode) {
                        ForEach(NetstatMode.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                    Spacer()
                }
                runButton("Run", systemImage: "list.bullet.rectangle") { viewModel.runNetstat() }
            }

            if let r = viewModel.netstatResult {
                statusBanner(r.status)
                // The parsed counts are only meaningful once the run completes;
                // while streaming, the raw output below tells the live story.
                if !viewModel.isRunning {
                    if viewModel.netstatMode == .connections {
                        sectionTitle("\(r.listeners.count) listening · \(r.connections.count) connections")
                    } else {
                        sectionTitle("\(r.routes.count) routes")
                    }
                }
                terminalPanel(r.rawOutput)
            } else {
                Spacer(minLength: 0)
            }
        }
    }
}
#endif
