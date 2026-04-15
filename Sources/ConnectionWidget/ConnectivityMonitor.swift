import Foundation
import Network
import Combine

@MainActor
final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var isMonitoring = false
    @Published private(set) var status: ConnectionStatus = .offline
    @Published private(set) var pathSnapshot = PathSnapshot(
        isSatisfied: false,
        isExpensive: false,
        isConstrained: false,
        interfaceName: "Unknown"
    )
    @Published private(set) var probes: [ProbeSample] = []
    @Published private(set) var metrics: ProbeMetrics = .empty
    @Published private(set) var rxBytesPerSecond: Double = 0
    @Published private(set) var txBytesPerSecond: Double = 0
    @Published private(set) var monitoringStartedAt: Date?
    @Published private(set) var lastSuccessAt: Date?
    @Published private(set) var lastFailureAt: Date?
    @Published private(set) var targetHost: String
    @Published private(set) var probeIntervalSeconds: Double
    @Published private(set) var hostValidationMessage: String?
    @Published private(set) var publicInternetHostsOnly: Bool

    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "ConnectionWidget.PathMonitor")
    private let trafficSampler = NetworkTrafficSampler()
    private let perProbeWaitMs: Int
    private let maxProbeHistory: Int

    private var monitorTask: Task<Void, Never>?
    private var consecutiveFailures = 0

    init(
        host: String = "google.com",
        probeIntervalSeconds: Double = 5,
        perProbeWaitMs: Int = 1_000,
        maxProbeHistory: Int = 120,
        publicInternetHostsOnly: Bool = true
    ) {
        switch PingTargetValidator.validate(host) {
        case .valid(let validatedHost):
            self.targetHost = validatedHost
            self.hostValidationMessage = nil
        case .invalid(let reason):
            self.targetHost = "google.com"
            self.hostValidationMessage = "Invalid initial host (\(reason)); using google.com."
        }
        self.probeIntervalSeconds = Self.clampedProbeInterval(probeIntervalSeconds)
        self.perProbeWaitMs = perProbeWaitMs
        self.maxProbeHistory = maxProbeHistory
        self.publicInternetHostsOnly = publicInternetHostsOnly

        configurePathMonitor()
    }
    var probeIntervalDisplayText: String {
        String(format: "%.1f s", probeIntervalSeconds)
    }


    var menuBarSymbolName: String {
        status.symbolName
    }

    var recentFailureTimes: [Date] {
        probes.filter { !$0.success }.map(\.timestamp)
    }

    var monitoringDuration: TimeInterval? {
        guard let monitoringStartedAt else { return nil }
        return Date().timeIntervalSince(monitoringStartedAt)
    }

    var currentOfflineDuration: TimeInterval? {
        guard status != .online,
              let lastSuccessAt
        else {
            return nil
        }
        return Date().timeIntervalSince(lastSuccessAt)
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        status = .degraded
        monitoringStartedAt = Date()
        probes.removeAll(keepingCapacity: true)
        metrics = .empty
        consecutiveFailures = 0
        lastSuccessAt = nil
        lastFailureAt = nil
        rxBytesPerSecond = 0
        txBytesPerSecond = 0

        monitorTask = Task { [weak self] in
            await self?.runProbeLoop()
        }
    }

    func setTargetHost(_ host: String) {
        switch PingTargetValidator.validate(host) {
        case .valid(let validatedHost):
            targetHost = validatedHost
            hostValidationMessage = nil
        case .invalid(let reason):
            hostValidationMessage = reason
        }
    }

    func setProbeIntervalSeconds(_ seconds: Double) {
        probeIntervalSeconds = Self.clampedProbeInterval(seconds)
    }

    func setPublicInternetHostsOnly(_ enabled: Bool) {
        publicInternetHostsOnly = enabled
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        monitorTask?.cancel()
        monitorTask = nil
        status = pathSnapshot.isSatisfied ? .degraded : .offline
    }

    func clearHistory() {
        probes.removeAll(keepingCapacity: true)
        metrics = .empty
        consecutiveFailures = 0
        if isMonitoring {
            status = .degraded
        } else {
            status = pathSnapshot.isSatisfied ? .degraded : .offline
        }
    }

    func diagnosticsReport() -> String {
        diagnosticsReport(redacted: false)
    }

    func redactedDiagnosticsReport() -> String {
        diagnosticsReport(redacted: true)
    }

    private func diagnosticsReport(redacted: Bool) -> String {
        let dateFormatter = ISO8601DateFormatter()
        let recent = probes.suffix(12).map { probe in
            let when = dateFormatter.string(from: probe.timestamp)
            let latency = probe.latencyMs.map { String(format: "%.1fms", $0) } ?? "n/a"
            let detail = redacted ? "<redacted>" : probe.detail
            return "[\(when)] success=\(probe.success) latency=\(latency) exit=\(probe.exitCode) detail=\(detail)"
        }

        return """
        Connection Widget Diagnostics
        status=\(status.title)
        targetHost=\(redacted ? "<redacted>" : targetHost)
        publicInternetHostsOnly=\(publicInternetHostsOnly)
        probeIntervalSeconds=\(probeIntervalSeconds)
        pathSatisfied=\(pathSnapshot.isSatisfied)
        interface=\(pathSnapshot.interfaceName)
        expensive=\(pathSnapshot.isExpensive)
        constrained=\(pathSnapshot.isConstrained)
        successRate=\(String(format: "%.1f", metrics.successRate))%
        packetLoss=\(String(format: "%.1f", metrics.packetLossPercent))%
        latestLatencyMs=\(metrics.latestLatencyMs.map { String(format: "%.1f", $0) } ?? "n/a")
        rxBps=\(Int(rxBytesPerSecond))
        txBps=\(Int(txBytesPerSecond))
        recentProbes:
        \(recent.joined(separator: "\n"))
        """
    }

    private func configurePathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let snapshot = PathSnapshot(
                isSatisfied: path.status == .satisfied,
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained,
                interfaceName: Self.describeInterface(for: path)
            )

            Task { @MainActor in
                self?.pathSnapshot = snapshot
                self?.recomputeStatus()
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    nonisolated private static func describeInterface(for path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) { return "Wi‑Fi" }
        if path.usesInterfaceType(.wiredEthernet) { return "Ethernet" }
        if path.usesInterfaceType(.cellular) { return "Cellular" }
        if path.usesInterfaceType(.loopback) { return "Loopback" }
        if path.usesInterfaceType(.other) { return "Other" }
        return "Unknown"
    }

    private func runProbeLoop() async {
        await runProbeCycle()

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: currentProbeIntervalDuration())
            } catch {
                break
            }
            await runProbeCycle()
        }
    }

    private func runProbeCycle() async {
        guard isMonitoring else { return }
        let hostAccessPolicy: HostAccessPolicy = publicInternetHostsOnly ? .publicInternetOnly : .allowAny
        let probe = await PingProber.probe(host: targetHost, waitTimeMs: perProbeWaitMs, policy: hostAccessPolicy)
        let traffic = await trafficSampler.sampleRates()

        rxBytesPerSecond = traffic.rxBytesPerSecond
        txBytesPerSecond = traffic.txBytesPerSecond

        probes.append(probe)
        if probes.count > maxProbeHistory {
            probes.removeFirst(probes.count - maxProbeHistory)
        }

        if probe.success {
            lastSuccessAt = probe.timestamp
            consecutiveFailures = 0
        } else {
            lastFailureAt = probe.timestamp
            consecutiveFailures += 1
        }

        metrics = ProbeMetricsCalculator.calculate(from: probes)
        recomputeStatus()
    }

    private func recomputeStatus() {
        if let latestProbe = probes.last, latestProbe.success {
            status = .online
            return
        }

        if !pathSnapshot.isSatisfied {
            status = .offline
            return
        }

        status = consecutiveFailures >= 3 ? .offline : .degraded
    }

    private func currentProbeIntervalDuration() -> Duration {
        .milliseconds(Int64(probeIntervalSeconds * 1_000))
    }


    private nonisolated static func clampedProbeInterval(_ seconds: Double) -> Double {
        min(max(seconds, 1.0), 60.0)
    }
}
