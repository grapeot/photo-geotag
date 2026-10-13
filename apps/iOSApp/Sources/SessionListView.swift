import SwiftUI

struct SessionListView: View {
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    ContentUnavailableView("No Sessions Yet",
                                           systemImage: "location.slash",
                                           description: Text("Record a track on your Apple Watch. Finished sessions appear here automatically."))
                } else {
                    List {
                        ForEach(store.sessions) { session in
                            NavigationLink(value: session) {
                                SessionRowView(session: session)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                store.delete(store.sessions[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationDestination(for: StoredSession.self) { session in
                SessionDetailView(session: session)
            }
        }
    }
}

struct SessionRowView: View {
    let session: StoredSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let start = session.startDate {
                    Text(start.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                } else {
                    Text("Unknown Date")
                        .font(.headline)
                }
                if !session.isFinal {
                    Text("In progress")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
            }

            HStack(spacing: 12) {
                Label(SessionFormat.duration(session.duration), systemImage: "clock")
                Label {
                    Text(verbatim: "\(session.pointCount)")
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

enum SessionFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let remainingSeconds = total % 60
        if minutes >= 60 {
            return String(format: "%dh %02dm", minutes / 60, minutes % 60)
        }
        return String(format: "%dm %02ds", minutes, remainingSeconds)
    }
}
