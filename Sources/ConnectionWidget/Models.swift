import Foundation

enum ConnectionStatus: String, CaseIterable, Sendable {
    case online
    case degraded
    case offline

    var title: String {
        switch self {
        case .online: "Online"
        case .degraded: "Degraded"
        case .offline: "Offline"
        }
    }

    var symbolName: String {
        switch self {
        case .online: "wifi"
        case .degraded: "wifi.exclamationmark"
        case .offline: "wifi.slash"
        }
    }
}

struct ProbeSample: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let success: Bool
    let latencyMs: Double?
    let exitCode: Int32
    let detail: String
}

struct PathSnapshot: Sendable {
    let isSatisfied: Bool
    let isExpensive: Bool
    let isConstrained: Bool
    let interfaceName: String
}

struct ProbeMetrics: Sendable {
    var totalCount: Int = 0
    var successCount: Int = 0
    var failureCount: Int = 0
    var successRate: Double = 0
    var packetLossPercent: Double = 0
    var latestLatencyMs: Double?
    var minLatencyMs: Double?
    var avgLatencyMs: Double?
    var maxLatencyMs: Double?
    var jitterMs: Double?

    static let empty = ProbeMetrics()
}

enum ProbeMetricsCalculator {
    static func calculate(from probes: [ProbeSample]) -> ProbeMetrics {
        guard !probes.isEmpty else { return .empty }

        var metrics = ProbeMetrics()
        metrics.totalCount = probes.count
        metrics.successCount = probes.filter(\.success).count
        metrics.failureCount = metrics.totalCount - metrics.successCount
        metrics.successRate = (Double(metrics.successCount) / Double(metrics.totalCount)) * 100
        metrics.packetLossPercent = (Double(metrics.failureCount) / Double(metrics.totalCount)) * 100

        let successfulLatencies = probes.compactMap(\.latencyMs)
        metrics.latestLatencyMs = probes.last?.latencyMs

        guard !successfulLatencies.isEmpty else {
            return metrics
        }

        metrics.minLatencyMs = successfulLatencies.min()
        metrics.maxLatencyMs = successfulLatencies.max()
        metrics.avgLatencyMs = successfulLatencies.reduce(0, +) / Double(successfulLatencies.count)

        let jitterValues = zip(successfulLatencies.dropFirst(), successfulLatencies).map { abs($0 - $1) }
        if !jitterValues.isEmpty {
            metrics.jitterMs = jitterValues.reduce(0, +) / Double(jitterValues.count)
        }

        return metrics
    }
}
