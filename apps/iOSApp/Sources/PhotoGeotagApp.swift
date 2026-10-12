import SwiftUI

@main
struct PhotoGeotagApp: App {
    @StateObject private var store = SessionStore()
    @StateObject private var receiver = WatchReceiver()

    var body: some Scene {
        WindowGroup {
            SessionListView()
                .environmentObject(store)
                .environmentObject(receiver)
                .onAppear {
                    receiver.activate(store: store)
                }
        }
    }
}
