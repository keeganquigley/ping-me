import Foundation
import Darwin
enum PingTargetValidationResult: Equatable, Sendable {
    case valid(host: String)
    case invalid(reason: String)
}

enum PingTargetValidator {
    private static let allowedScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.:")

    static func validate(_ rawHost: String) -> PingTargetValidationResult {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            return .invalid(reason: "Host is empty")
        }
        guard host.count <= 253 else {
            return .invalid(reason: "Host is too long")
        }
        guard !host.hasPrefix("-") else {
            return .invalid(reason: "Host cannot start with '-'")
        }
        guard host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return .invalid(reason: "Host cannot contain whitespace")
        }
        guard host.unicodeScalars.allSatisfy({ allowedScalars.contains($0) }) else {
            return .invalid(reason: "Host contains unsupported characters")
        }
        guard host.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else {
            return .invalid(reason: "Host must include at least one alphanumeric character")
        }
        return .valid(host: host)
    }
}
enum HostAccessPolicy: Sendable {
    case allowAny
    case publicInternetOnly
}

enum HostAccessPolicyDecision: Equatable, Sendable {
    /// `pinnedAddress` is the numeric IP the caller must use for subsequent network
    /// operations, preventing a DNS-rebinding TOCTOU where a second resolution could
    /// return a private address after policy approval. It is `nil` only when the
    /// policy is `.allowAny` and no resolution was performed.
    case allowed(pinnedAddress: String?)
    case blocked(reason: String)
}

enum HostAccessPolicyEvaluator {
    static func evaluate(host: String, policy: HostAccessPolicy) -> HostAccessPolicyDecision {
        guard policy == .publicInternetOnly else {
            return .allowed(pinnedAddress: nil)
        }

        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_DGRAM,
            ai_protocol: IPPROTO_UDP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var resultPointer: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &resultPointer)
        guard status == 0, let firstResult = resultPointer else {
            let message = String(cString: gai_strerror(status))
            return .blocked(reason: "Unable to resolve host under public-host policy (\(message))")
        }
        defer { freeaddrinfo(resultPointer) }

        var hasUsableAddress = false
        var pinnedAddress: String?

        for pointer in sequence(first: firstResult, next: { $0.pointee.ai_next }) {
            guard let addressPointer = pointer.pointee.ai_addr else { continue }

            switch Int32(pointer.pointee.ai_family) {
            case AF_INET:
                hasUsableAddress = true
                let sockaddr = addressPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                if !isPublicIPv4(sockaddr.sin_addr) {
                    return .blocked(reason: "Host resolves to a non-public IPv4 address")
                }
                if pinnedAddress == nil {
                    pinnedAddress = numericHost(for: addressPointer, length: pointer.pointee.ai_addrlen)
                }
            case AF_INET6:
                hasUsableAddress = true
                let sockaddr = addressPointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                if !isPublicIPv6(sockaddr.sin6_addr) {
                    return .blocked(reason: "Host resolves to a non-public IPv6 address")
                }
                if pinnedAddress == nil {
                    pinnedAddress = numericHost(for: addressPointer, length: pointer.pointee.ai_addrlen)
                }
            default:
                continue
            }
        }

        guard hasUsableAddress else {
            return .blocked(reason: "No usable IP address found for host")
        }

        guard let pinnedAddress else {
            return .blocked(reason: "Unable to pin a resolved address for host")
        }

        return .allowed(pinnedAddress: pinnedAddress)
    }

    private static func numericHost(for address: UnsafePointer<sockaddr>, length: socklen_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(NI_MAXHOST))
        let status = buffer.withUnsafeMutableBufferPointer { bufferPointer -> Int32 in
            bufferPointer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: bufferPointer.count) { cCharPointer in
                getnameinfo(
                    address,
                    length,
                    cCharPointer,
                    socklen_t(bufferPointer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
            }
        }
        guard status == 0 else { return nil }
        let terminatorIndex = buffer.firstIndex(of: 0) ?? buffer.count
        return String(decoding: buffer.prefix(terminatorIndex), as: UTF8.self)
    }

    private static func isPublicIPv4(_ address: in_addr) -> Bool {
        let value = UInt32(bigEndian: address.s_addr)
        let first = UInt8((value >> 24) & 0xFF)
        let second = UInt8((value >> 16) & 0xFF)

        if first == 10 { return false }
        if first == 172 && (16...31).contains(Int(second)) { return false }
        if first == 192 && second == 168 { return false }
        if first == 127 { return false }
        if first == 169 && second == 254 { return false }
        if first == 100 && (64...127).contains(Int(second)) { return false }
        if first == 0 { return false }
        if first >= 224 { return false }
        return true
    }

    private static func isPublicIPv6(_ address: in6_addr) -> Bool {
        let bytes = withUnsafeBytes(of: address) { Array($0) }
        guard bytes.count == 16 else { return false }

        if bytes.allSatisfy({ $0 == 0 }) { return false }
        if bytes[0] == 0x00 && bytes[15] == 0x01 && bytes[1...14].allSatisfy({ $0 == 0 }) { return false }
        if bytes[0] == 0xFC || bytes[0] == 0xFD { return false }
        if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 { return false }
        if bytes[0] == 0xFF { return false }

        let isIPv4Mapped =
            bytes[0...9].allSatisfy({ $0 == 0 }) &&
            bytes[10] == 0xFF &&
            bytes[11] == 0xFF
        if isIPv4Mapped {
            var mapped = in_addr()
            mapped.s_addr = UInt32(bytes[12]) << 24 |
                UInt32(bytes[13]) << 16 |
                UInt32(bytes[14]) << 8 |
                UInt32(bytes[15])
            return isPublicIPv4(mapped)
        }

        return true
    }
}

enum PingParseOutcome: Equatable, Sendable {
    case success(latencyMs: Double)
    case failure(reason: String)
}

enum PingOutputParser {
    private static let perReplyLatencyRegex = try! NSRegularExpression(
        pattern: #"time=([0-9]+(?:\.[0-9]+)?)\s*ms"#,
        options: []
    )

    private static let summaryLatencyRegex = try! NSRegularExpression(
        pattern: #"round-trip min/avg/max(?:/stddev)? = ([0-9]+(?:\.[0-9]+)?)/"#,
        options: []
    )

    static func parse(output: String, exitCode: Int32) -> PingParseOutcome {
        if let latency = extractLatency(using: perReplyLatencyRegex, from: output)
            ?? extractLatency(using: summaryLatencyRegex, from: output)
        {
            return .success(latencyMs: latency)
        }

        if exitCode == 2 {
            return .failure(reason: "No response")
        }

        if exitCode == 0 {
            return .failure(reason: "Response received but latency could not be parsed")
        }

        return .failure(reason: "Ping failed with exit code \(exitCode)")
    }

    private static func extractLatency(using regex: NSRegularExpression, from output: String) -> Double? {
        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, options: [], range: range),
              let latencyRange = Range(match.range(at: 1), in: output)
        else {
            return nil
        }
        return Double(output[latencyRange])
    }
}

struct PingProber: Sendable {
    static func probe(
        host: String,
        waitTimeMs: Int,
        policy: HostAccessPolicy = .allowAny,
        at timestamp: Date = Date()
    ) async -> ProbeSample {
        switch PingTargetValidator.validate(host) {
        case .valid(let validatedHost):
            switch HostAccessPolicyEvaluator.evaluate(host: validatedHost, policy: policy) {
            case .allowed(let pinnedAddress):
                // Pin to the resolved IP when the policy performed a lookup so that a
                // second DNS resolution inside ping cannot swap in a private address.
                let probeTarget = pinnedAddress ?? validatedHost
                return await runProbe(host: probeTarget, waitTimeMs: waitTimeMs, at: timestamp)
            case .blocked(let reason):
                return ProbeSample(
                    timestamp: timestamp,
                    success: false,
                    latencyMs: nil,
                    exitCode: -3,
                    detail: "Blocked by host policy: \(reason)"
                )
            }
        case .invalid(let reason):
            return ProbeSample(
                timestamp: timestamp,
                success: false,
                latencyMs: nil,
                exitCode: -2,
                detail: "Invalid host: \(reason)"
            )
        }
    }

    private static func runProbe(host: String, waitTimeMs: Int, at timestamp: Date) async -> ProbeSample {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            // `--` ends option parsing so a hostile host (should the validator ever
            // regress) cannot be interpreted as a ping flag.
            process.arguments = ["-n", "-c", "1", "-W", "\(waitTimeMs)", "--", host]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                return ProbeSample(
                    timestamp: timestamp,
                    success: false,
                    latencyMs: nil,
                    exitCode: -1,
                    detail: "Failed to run ping: \(error.localizedDescription)"
                )
            }

            process.waitUntilExit()
            let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            var combinedData = Data()
            combinedData.append(outputData)
            combinedData.append(errorData)

            let output = String(decoding: combinedData, as: UTF8.self)
            let parseOutcome = PingOutputParser.parse(output: output, exitCode: process.terminationStatus)

            switch parseOutcome {
            case .success(let latencyMs):
                return ProbeSample(
                    timestamp: timestamp,
                    success: true,
                    latencyMs: latencyMs,
                    exitCode: process.terminationStatus,
                    detail: "Reply in \(String(format: "%.1f", latencyMs)) ms"
                )
            case .failure(let reason):
                return ProbeSample(
                    timestamp: timestamp,
                    success: false,
                    latencyMs: nil,
                    exitCode: process.terminationStatus,
                    detail: reason
                )
            }
        }.value
    }
}
