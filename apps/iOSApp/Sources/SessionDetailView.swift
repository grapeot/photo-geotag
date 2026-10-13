import SwiftUI
import MapKit

struct SessionDetailView: View {
    let session: StoredSession

    @EnvironmentObject private var store: SessionStore
    @State private var shareItem: ShareItem?
    @State private var launcher = WatchWorkoutLauncher()
    @State private var resumeMessage: String?

    private var canResumeOnWatch: Bool { !session.isFinal && session.isInterrupted }

    private var coordinates: [CLLocationCoordinate2D] {
        (store.track(for: session)?.points ?? []).map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Map {
                if coordinates.count > 1 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(.blue, lineWidth: 4)
                }
                if let first = coordinates.first {
                    Marker("Start", coordinate: first)
                }
                if let last = coordinates.last {
                    Marker("End", coordinate: last)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            summary
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let url = store.exportGPX(for: [session]) {
                        shareItem = ShareItem(url: url)
                    }
                } label: {
                    Label("Export GPX", systemImage: "square.and.arrow.up")
                }
            }
            if canResumeOnWatch {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        launcher.resumeOnWatch { success in
                            resumeMessage = success ? "Resume Requested" : "Could Not Reach Watch"
                        }
                    } label: {
                        Label("Resume on Apple Watch", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .alert(LocalizedStringKey(resumeMessage ?? ""), isPresented: isShowingResumeMessage) {
            Button("OK", role: .cancel) {}
        }
    }

    private var title: String {
        session.startDate?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "Unknown Date")
    }

    private var isShowingResumeMessage: Binding<Bool> {
        Binding(get: { resumeMessage != nil },
                set: { if !$0 { resumeMessage = nil } })
    }

    private var summary: some View {
        HStack(spacing: 24) {
            VStack {
                Text("Duration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(SessionFormat.duration(session.duration))
                    .font(.body)
                    .monospacedDigit()
            }
            VStack {
                Text("Points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: "\(session.pointCount)")
                    .font(.body)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.bar)
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
