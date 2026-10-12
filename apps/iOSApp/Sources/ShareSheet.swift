import SwiftUI
import UIKit

/// Presents the system share sheet so a session's `.gpx` file can be exported
/// through AirDrop, the Files app, or another installed app.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}
