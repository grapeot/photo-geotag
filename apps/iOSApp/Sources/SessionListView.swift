import SwiftUI

struct SessionListView: View {
    @EnvironmentObject private var store: SessionStore

    @State private var healthImporter = HealthRouteImporter()
    @State private var isImporting = false
    @State private var importError: String?

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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        importFromHealth()
                    } label: {
                        if isImporting {
                            ProgressView()
                        } else {
                            Label("Import from Health", systemImage: "heart.text.square")
                        }
                    }
                    .disabled(isImporting)
                }
            }
            .alert("Could Not Import", isPresented: isShowingImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private var isShowingImportError: Binding<Bool> {
        Binding(get: { importError != nil },
                set: { if !$0 { importError = nil } })
    }

    private func importFromHealth() {
        guard !isImporting else { return }
        isImporting = true
        importError = nil
        healthImporter.requestAuthorization { granted in
            guard granted else {
                importError = String(localized: "Health access was not granted.")
                isImporting = false
                return
            }
            let since = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            healthImporter.importRoutes(since: since) { routes in
                store.importHealthRoutes(routes)
                isImporting = false
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
