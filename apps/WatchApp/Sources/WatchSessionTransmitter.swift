import Foundation
import WatchConnectivity

/// Sends finalized GPX sessions from the watch to the iOS companion app.
final class WatchSessionTransmitter: NSObject, WCSessionDelegate {
    static let shared = WatchSessionTransmitter()

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func transfer(fileURL: URL, sessionID: String, startDate: Date?, duration: TimeInterval) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        var metadata: [String: Any] = [
            WatchTransferKey.sessionID: sessionID,
            WatchTransferKey.duration: duration
        ]
        if let startDate {
            metadata[WatchTransferKey.startDate] = startDate.timeIntervalSince1970
        }
        session.transferFile(fileURL, metadata: metadata)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    }
}
