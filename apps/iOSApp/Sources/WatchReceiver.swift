import Foundation
import WatchConnectivity

/// Receives finished GPX sessions transferred from the watch app.
final class WatchReceiver: NSObject, ObservableObject, WCSessionDelegate {
    private weak var store: SessionStore?

    func activate(store: SessionStore) {
        self.store = store
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
    }

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let sessionID = (file.metadata?[WatchTransferKey.sessionID] as? String) ?? UUID().uuidString
        let isFinal = watchTransferBool(file.metadata?[WatchTransferKey.isFinal], default: true)
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sessionID)-\(UUID().uuidString).gpx")
        do {
            try FileManager.default.copyItem(at: file.fileURL, to: temporaryURL)
        } catch {
            return
        }
        let store = self.store
        DispatchQueue.main.async {
            store?.importFile(from: temporaryURL, sessionID: sessionID, isFinal: isFinal)
        }
    }
}
