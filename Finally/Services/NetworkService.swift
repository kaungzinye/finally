import Foundation
import Network

@Observable
final class NetworkService {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.kaungzinye.finally.network-monitor")

    private(set) var isOnline = true

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
