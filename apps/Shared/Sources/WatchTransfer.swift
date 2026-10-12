import Foundation

/// Metadata keys attached to WatchConnectivity file transfers between the
/// watch app and the iOS companion app.
enum WatchTransferKey {
    static let sessionID = "sessionID"
    static let startDate = "startDate"
    static let duration = "duration"
}
