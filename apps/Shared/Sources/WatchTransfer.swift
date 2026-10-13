import Foundation

/// Metadata keys attached to WatchConnectivity file transfers between the
/// watch app and the iOS companion app.
enum WatchTransferKey {
    static let sessionID = "sessionID"
    static let startDate = "startDate"
    static let duration = "duration"
    /// Monotonic sequence number of an incremental snapshot within a session.
    static let sequence = "sequence"
    /// `true` when this is the finalized track; `false` for an in-progress
    /// snapshot. Absent metadata is treated as final.
    static let isFinal = "isFinal"
    /// Recording lifecycle state carried with a transfer: `recording` or
    /// `interrupted` (the watch lost its workout session to another workout).
    static let state = "state"
}

/// Values for `WatchTransferKey.state`.
enum WatchTransferState {
    static let recording = "recording"
    static let interrupted = "interrupted"
}

/// Reads a boolean from WCSession metadata, tolerating both bridged `Bool` and
/// `NSNumber` representations and defaulting to `defaultValue` when absent.
func watchTransferBool(_ value: Any?, default defaultValue: Bool) -> Bool {
    if let bool = value as? Bool { return bool }
    if let number = value as? NSNumber { return number.boolValue }
    return defaultValue
}
