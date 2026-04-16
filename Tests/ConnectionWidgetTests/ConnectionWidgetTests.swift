import Foundation
import Testing
@testable import ConnectionWidget

@Test
func pingParserExtractsLatencyFromReplyLine() {
    let output = """
    PING google.com (8.8.8.8): 56 data bytes
    64 bytes from 8.8.8.8: icmp_seq=0 ttl=117 time=23.456 ms
    """
    let outcome = PingOutputParser.parse(output: output, exitCode: 0)

    switch outcome {
    case .success(let latency):
        #expect(abs(latency - 23.456) < 0.0001)
    case .failure(let reason):
        Issue.record("Expected success outcome but received failure: \(reason)")
    }
}

@Test
func pingParserMarksNoResponseOnExitCodeTwo() {
    let output = "Request timeout for icmp_seq 0"
    let outcome = PingOutputParser.parse(output: output, exitCode: 2)

    switch outcome {
    case .success(let latency):
        Issue.record("Expected failure outcome but parsed success with latency \(latency)")
    case .failure(let reason):
        #expect(reason == "No response")
    }
}

@Test
func metricsCalculatorAggregatesMixedProbeSeries() {
    let now = Date()
    let probes = [
        ProbeSample(timestamp: now, success: true, latencyMs: 20, exitCode: 0, detail: ""),
        ProbeSample(timestamp: now.addingTimeInterval(1), success: false, latencyMs: nil, exitCode: 2, detail: ""),
        ProbeSample(timestamp: now.addingTimeInterval(2), success: true, latencyMs: 30, exitCode: 0, detail: ""),
        ProbeSample(timestamp: now.addingTimeInterval(3), success: true, latencyMs: 50, exitCode: 0, detail: ""),
    ]

    let metrics = ProbeMetricsCalculator.calculate(from: probes)
    #expect(metrics.totalCount == 4)
    #expect(metrics.successCount == 3)
    #expect(metrics.failureCount == 1)
    #expect(abs(metrics.successRate - 75.0) < 0.0001)
    #expect(abs(metrics.packetLossPercent - 25.0) < 0.0001)
    #expect(metrics.minLatencyMs == 20)
    #expect(metrics.maxLatencyMs == 50)
    #expect(abs((metrics.avgLatencyMs ?? 0) - 33.333333) < 0.001)
    #expect(abs((metrics.jitterMs ?? 0) - 15.0) < 0.0001)
}

@Test
func pingTargetValidatorRejectsOptionLikeInput() {
    let result = PingTargetValidator.validate("-c 10 8.8.8.8")

    switch result {
    case .valid(let host):
        Issue.record("Expected invalid host but validator accepted: \(host)")
    case .invalid(let reason):
        #expect(reason.contains("start with '-'"))
    }
}

@Test
func pingTargetValidatorAcceptsStandardHostFormats() {
    let hostnameResult = PingTargetValidator.validate("google.com")
    let ipv4Result = PingTargetValidator.validate("8.8.8.8")
    let ipv6Result = PingTargetValidator.validate("2606:4700:4700::1111")

    switch hostnameResult {
    case .valid(let host):
        #expect(host == "google.com")
    case .invalid(let reason):
        Issue.record("Expected valid hostname but got invalid: \(reason)")
    }

    switch ipv4Result {
    case .valid(let host):
        #expect(host == "8.8.8.8")
    case .invalid(let reason):
        Issue.record("Expected valid IPv4 but got invalid: \(reason)")
    }

    switch ipv6Result {
    case .valid(let host):
        #expect(host == "2606:4700:4700::1111")
    case .invalid(let reason):
        Issue.record("Expected valid IPv6 but got invalid: \(reason)")
    }
}

@Test
@MainActor
func diagnosticsRedactionHidesTargetHost() {
    let monitor = ConnectivityMonitor(host: "internal.example.com")
    let fullDiagnostics = monitor.diagnosticsReport()
    let redactedDiagnostics = monitor.redactedDiagnosticsReport()

    #expect(fullDiagnostics.contains("targetHost=internal.example.com"))
    #expect(redactedDiagnostics.contains("targetHost=<redacted>"))
    #expect(!redactedDiagnostics.contains("targetHost=internal.example.com"))
}

@Test
func publicHostPolicyAllowsPublicIPv4Literal() {
    let decision = HostAccessPolicyEvaluator.evaluate(host: "8.8.8.8", policy: .publicInternetOnly)
    #expect(decision == .allowed(pinnedAddress: "8.8.8.8"))
}

@Test
func publicHostPolicyBlocksRFC1918IPv4Literal() {
    let decision = HostAccessPolicyEvaluator.evaluate(host: "192.168.1.50", policy: .publicInternetOnly)
    switch decision {
    case .allowed:
        Issue.record("Expected private IPv4 address to be blocked")
    case .blocked(let reason):
        #expect(reason.contains("non-public"))
    }
}

@Test
func publicHostPolicyBlocksIPv6ULALiteral() {
    let decision = HostAccessPolicyEvaluator.evaluate(host: "fd00::1", policy: .publicInternetOnly)
    switch decision {
    case .allowed:
        Issue.record("Expected ULA IPv6 address to be blocked")
    case .blocked(let reason):
        #expect(reason.contains("non-public"))
    }
}

@Test
func allowAnyPolicyAllowsPrivateIPv4Literal() {
    let decision = HostAccessPolicyEvaluator.evaluate(host: "192.168.1.50", policy: .allowAny)
    #expect(decision == .allowed(pinnedAddress: nil))
}

@Test
func publicHostPolicyPinsResolvedIPv6Literal() {
    let decision = HostAccessPolicyEvaluator.evaluate(host: "2606:4700:4700::1111", policy: .publicInternetOnly)
    #expect(decision == .allowed(pinnedAddress: "2606:4700:4700::1111"))
}
