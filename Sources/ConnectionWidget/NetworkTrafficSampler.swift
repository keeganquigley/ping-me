import Foundation
import Darwin

private struct InterfaceCounterSnapshot: Sendable {
    let timestamp: Date
    let receivedBytes: UInt64
    let transmittedBytes: UInt64
}

actor NetworkTrafficSampler {
    private var previousSnapshot: InterfaceCounterSnapshot?

    func sampleRates() -> (rxBytesPerSecond: Double, txBytesPerSecond: Double) {
        guard let current = captureSnapshot() else {
            return (0, 0)
        }

        defer { previousSnapshot = current }

        guard let previousSnapshot else {
            return (0, 0)
        }

        let interval = current.timestamp.timeIntervalSince(previousSnapshot.timestamp)
        guard interval > 0 else {
            return (0, 0)
        }

        let rxDelta = current.receivedBytes >= previousSnapshot.receivedBytes
            ? current.receivedBytes - previousSnapshot.receivedBytes
            : 0
        let txDelta = current.transmittedBytes >= previousSnapshot.transmittedBytes
            ? current.transmittedBytes - previousSnapshot.transmittedBytes
            : 0

        return (
            rxBytesPerSecond: Double(rxDelta) / interval,
            txBytesPerSecond: Double(txDelta) / interval
        )
    }

    private func captureSnapshot() -> InterfaceCounterSnapshot? {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0,
              let firstAddress = ifaddrPointer
        else {
            return nil
        }
        defer { freeifaddrs(ifaddrPointer) }

        var receivedBytes: UInt64 = 0
        var transmittedBytes: UInt64 = 0

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let flags = Int32(pointer.pointee.ifa_flags)
            guard (flags & Int32(IFF_UP)) == Int32(IFF_UP),
                  (flags & Int32(IFF_LOOPBACK)) == 0
            else {
                continue
            }

            guard let address = pointer.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let ifDataPointer = pointer.pointee.ifa_data
            else {
                continue
            }

            let networkData = ifDataPointer.assumingMemoryBound(to: if_data.self).pointee
            receivedBytes &+= UInt64(networkData.ifi_ibytes)
            transmittedBytes &+= UInt64(networkData.ifi_obytes)
        }

        return InterfaceCounterSnapshot(
            timestamp: Date(),
            receivedBytes: receivedBytes,
            transmittedBytes: transmittedBytes
        )
    }
}
