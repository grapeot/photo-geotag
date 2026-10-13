import Foundation
import WatchConnectivity

/// Sends finalized GPX sessions from the watch to the iOS companion app.
///
/// Transfers requested before the `WCSession` finishes activating are queued and
/// flushed on activation, so a transfer fired at app launch (for example, while
/// recovering a track left by a previous session) is not silently dropped.
final class WatchSessionTransmitter: NSObject, WCSessionDelegate {
    static let shared = WatchSessionTransmitter()

    private struct PendingTransfer {
        let fileURL: URL
        let metadata: [String: Any]
    }

    private let lock = NSLock()
    private var pending: [PendingTransfer] = []

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func transfer(fileURL: URL,
                   sessionID: String,
                   startDate: Date?,
                   duration: TimeInterval,
                   sequence: Int = 0,
                   isFinal: Bool = true) {
        guard WCSession.isSupported() else { return }

        var metadata: [String: Any] = [
            WatchTransferKey.sessionID: sessionID,
            WatchTransferKey.duration: duration,
            WatchTransferKey.sequence: sequence,
            WatchTransferKey.isFinal: isFinal
        ]
        if let startDate {
            metadata[WatchTransferKey.startDate] = startDate.timeIntervalSince1970
        }

        let session = WCSession.default
        if session.activationState == .activated {
            session.transferFile(fileURL, metadata: metadata)
        } else {
            lock.lock()
            pending.append(PendingTransfer(fileURL: fileURL, metadata: metadata))
            lock.unlock()
            session.activate()
        }
    }

    private func flushPending() {
        lock.lock()
        let queued = pending
        pending.removeAll()
        lock.unlock()

        guard !queued.isEmpty else { return }
        let session = WCSession.default
        for item in queued {
            session.transferFile(item.fileURL, metadata: item.metadata)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        guard activationState == .activated else { return }
        flushPending()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    }
}
