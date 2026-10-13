import SwiftUI

struct SessionListView: View {
    @EnvironmentObject private var store: SessionStore

    @State private var healthImporter = HealthRouteImporter()
    @State private var isImporting = false
    @State private var importError: String?
    @State private var range: DayRange = .week
    @State private var isSelecting = false
    @State private var selection = Set<String>()
    @State private var shareItem: ShareItem?

    enum DayRange: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .week: return String(localized: "7 Days")
            case .month: return String(localized: "30 Days")
            }
        }
    }

    private var filteredSessions: [StoredSession] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -range.rawValue, to: Date()) else {
            return store.sessions
        }
        return store.sessions.filter { ($0.startDate ?? .distantPast) >= cutoff }
    }

    private var selectedSessions: [StoredSession] {
        filteredSessions.filter { selection.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredSessions.isEmpty {
                    ContentUnavailableView("No Sessions Yet",
                                           systemImage: "location.slash",
                                           description: Text("Record a track on your Apple Watch. Finished sessions appear here automatically."))
                } else {
                    List {
                        ForEach(filteredSessions) { session in
                            if isSelecting {
                                Button {
                                    toggleSelection(session.id)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: selection.contains(session.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selection.contains(session.id) ? Color.accentColor : Color.secondary)
                                        SessionRowView(session: session, points: store.track(for: session)?.points ?? [])
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink(value: session) {
                                    SessionRowView(session: session, points: store.track(for: session)?.points ?? [])
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                store.delete(filteredSessions[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationDestination(for: StoredSession.self) { session in
                SessionDetailView(session: session)
            }
            .safeAreaInset(edge: .top) {
                if !store.sessions.isEmpty {
                    Picker("Range", selection: $range) {
                        ForEach(DayRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                    .background(.bar)
                }
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
                ToolbarItem(placement: .topBarLeading) {
                    if !filteredSessions.isEmpty {
                        Button(isSelecting ? LocalizedStringKey("Done") : LocalizedStringKey("Select")) {
                            isSelecting.toggle()
                            if !isSelecting { selection.removeAll() }
                        }
                    }
                }
                if isSelecting {
                    ToolbarItem(placement: .bottomBar) {
                        Button(selection.count > 1 ? LocalizedStringKey("Merge & Export") : LocalizedStringKey("Export")) {
                            exportSelected()
                        }
                        .disabled(selection.isEmpty)
                    }
                }
            }
            .alert("Could Not Import", isPresented: isShowingImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(activityItems: [item.url])
            }
        }
    }

    private var isShowingImportError: Binding<Bool> {
        Binding(get: { importError != nil },
                set: { if !$0 { importError = nil } })
    }

    private func toggleSelection(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func exportSelected() {
        let chosen = selectedSessions
        guard !chosen.isEmpty else { return }
        if let url = store.exportGPX(for: chosen) {
            shareItem = ShareItem(url: url)
        }
        isSelecting = false
        selection.removeAll()
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
    let points: [TrackPoint]

    var body: some View {
        HStack(spacing: 10) {
            RouteThumbnail(points: points)

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
                    Text(session.isInterrupted ? LocalizedStringKey("Interrupted") : LocalizedStringKey("In progress"))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((session.isInterrupted ? Color.orange : Color.accentColor).opacity(0.18), in: Capsule())
                }
                }

                HStack(spacing: 12) {
                    Label(SessionFormat.duration(session.duration), systemImage: "clock")
                    Label {
                        Text(verbatim: "\(session.pointCount)")
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    Label {
                        Text(LocalizedStringKey(session.source == .health ? "Health" : "Watch"))
                    } icon: {
                        Image(systemName: session.source == .health ? "heart.text.square" : "applewatch")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
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
