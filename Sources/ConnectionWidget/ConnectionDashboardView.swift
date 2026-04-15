import AppKit
import Charts
import SwiftUI

struct ConnectionDashboardView: View {
    @EnvironmentObject private var monitor: ConnectivityMonitor
    @State private var hostDraft = ""
    @State private var intervalDraft: Double = 5
    @State private var showingCopyDiagnosticsConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerCard
                controlCard
                latencyChartCard
                metricsCard
                settingsCard
                utilityActionsCard
                speedTestLink
            }
            .padding(16)
        }
        .frame(width: 420, height: 620)
        .onAppear {
            hostDraft = monitor.targetHost
            intervalDraft = monitor.probeIntervalSeconds
        }
        .confirmationDialog(
            "Copy redacted diagnostics?",
            isPresented: $showingCopyDiagnosticsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Copy Redacted Diagnostics") {
                copyRedactedDiagnosticsToClipboard()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clipboard contents may be readable by other apps.")
        }
    }

    private var headerCard: some View {
        card {
            HStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection Widget")
                        .font(.headline)
                    Text("Live internet health and bandwidth snapshot")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                statusBadge
            }
        }
    }

    private var statusBadge: some View {
        Text(monitor.status.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.18), in: Capsule())
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch monitor.status {
        case .online: .green
        case .degraded: .orange
        case .offline: .red
        }
    }

    private var controlCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Monitor")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(monitor.pathSnapshot.interfaceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    monitor.isMonitoring ? monitor.stopMonitoring() : monitor.startMonitoring()
                } label: {
                    Text(monitor.isMonitoring ? "Stop" : "Check Connection")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(monitor.isMonitoring ? .red : .blue)
            }
        }
    }

    private var latencyChartCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Latency (recent)")
                    .font(.subheadline.weight(.semibold))

                if monitor.probes.isEmpty {
                    Text("No probes yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Chart {
                        ForEach(monitor.probes.suffix(30)) { probe in
                            if let latency = probe.latencyMs {
                                LineMark(
                                    x: .value("Time", probe.timestamp),
                                    y: .value("Latency (ms)", latency)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(.blue.gradient)
                            }
                        }

                        ForEach(monitor.recentFailureTimes.suffix(30), id: \.self) { failedAt in
                            RuleMark(x: .value("Failure", failedAt))
                                .foregroundStyle(.red.opacity(0.25))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4))
                    }
                    .frame(height: 140)
                }
            }
        }
    }

    private var metricsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Metrics")
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 6) {
                    metricRow("Success rate", "\(formatPercent(monitor.metrics.successRate))%")
                    metricRow("Packet loss", "\(formatPercent(monitor.metrics.packetLossPercent))%")
                    metricRow("Latest latency", formatLatency(monitor.metrics.latestLatencyMs))
                    metricRow("Avg / max latency", "\(formatLatency(monitor.metrics.avgLatencyMs)) / \(formatLatency(monitor.metrics.maxLatencyMs))")
                    metricRow("Jitter", formatLatency(monitor.metrics.jitterMs))
                    metricRow("Rx / Tx", "\(formatBytesPerSecond(monitor.rxBytesPerSecond)) / \(formatBytesPerSecond(monitor.txBytesPerSecond))")
                    metricRow("Link state", monitor.pathSnapshot.isSatisfied ? "Path available" : "Path unavailable")
                    metricRow("Low data mode", monitor.pathSnapshot.isConstrained ? "On" : "Off")
                    metricRow("Expensive", monitor.pathSnapshot.isExpensive ? "Yes" : "No")

                    if let duration = monitor.monitoringDuration {
                        metricRow("Monitoring for", formatDuration(duration))
                    }

                    if let offlineDuration = monitor.currentOfflineDuration {
                        metricRow("Offline for", formatDuration(offlineDuration))
                    }
                }
                .font(.footnote.monospacedDigit())
            }
        }
    }

    private var settingsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Settings")
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ping host")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("google.com", text: $hostDraft)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                applyHostSetting()
                            }

                        Button("Apply") {
                            applyHostSetting()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let hostValidationMessage = monitor.hostValidationMessage {
                    Text(hostValidationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Toggle(
                    "Public internet hosts only",
                    isOn: Binding(
                        get: { monitor.publicInternetHostsOnly },
                        set: { monitor.setPublicInternetHostsOnly($0) }
                    )
                )
                .font(.caption)

                Text("Blocks private/internal address ranges (RFC1918, loopback, link-local, and IPv6 ULA).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Probe interval")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Stepper(value: $intervalDraft, in: 1...60, step: 1) {
                            Text("\(String(format: "%.0f", intervalDraft)) sec")
                        }
                        .onChange(of: intervalDraft) { newValue in
                            monitor.setProbeIntervalSeconds(newValue)
                        }
                    }
                }
            }
        }
    }

    private var utilityActionsCard: some View {
        card {
            HStack {
                Button("Clear History") {
                    monitor.clearHistory()
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Copy Diagnostics") {
                    showingCopyDiagnosticsConfirmation = true
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)
        }
    }

    private var speedTestLink: some View {
        Link("Open Google Speed Test", destination: URL(string: "https://www.google.com/search?q=internet+speed+test")!)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 4)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.14))
            )
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.primary)
        }
    }

    private func applyHostSetting() {
        monitor.setTargetHost(hostDraft)
        hostDraft = monitor.targetHost
    }

    private func copyRedactedDiagnosticsToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(monitor.redactedDiagnosticsReport(), forType: .string)
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func formatLatency(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f ms", value)
    }

    private func formatBytesPerSecond(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary) + "/s"
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, remainingSeconds)
        }
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, remainingSeconds)
        }
        return "\(remainingSeconds)s"
    }
}
