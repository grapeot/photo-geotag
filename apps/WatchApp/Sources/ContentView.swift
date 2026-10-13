import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var recorder: WatchRecorder

    private var isRecording: Bool { recorder.state == .recording }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isRecording ? "location.fill" : "location")
                .font(.title3)
                .foregroundStyle(isRecording ? Color.red : Color.secondary)

            if isRecording {
                Text("Recording")
                    .font(.headline)
            } else {
                Text("Ready")
                    .font(.headline)
            }

            HStack(spacing: 4) {
                Text("Points")
                Text(verbatim: "\(recorder.pointCount)")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button(action: toggleRecording) {
                if isRecording {
                    Text("Stop")
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Start")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(isRecording ? .red : .green)

            if let status = recorder.statusMessage {
                Text(LocalizedStringKey(status))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .onAppear {
            recorder.recoverOrphanedRecordingIfNeeded()
        }
    }

    private func toggleRecording() {
        if isRecording {
            recorder.stop()
        } else {
            recorder.start()
        }
    }
}
