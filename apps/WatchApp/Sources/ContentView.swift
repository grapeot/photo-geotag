import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var recorder: WatchRecorder

    @State private var showResumeConfirmation = false

    private var isRecording: Bool { recorder.state == .recording }
    private var isInterrupted: Bool { recorder.state == .interrupted }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)

            Text(headline)

            HStack(spacing: 4) {
                Text("Points")
                Text(verbatim: "\(recorder.pointCount)")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if isInterrupted {
                Button {
                    showResumeConfirmation = true
                } label: {
                    Text("Resume")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button(action: recorder.discardInterrupted) {
                    Text("Discard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else if isRecording {
                Button(action: recorder.stop) {
                    Text("Stop")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button(action: recorder.start) {
                    Text("Start")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(recorder.isPreparing)

                Text("Starting will end any other workout that is running.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let status = recorder.statusMessage {
                Text(LocalizedStringKey(status))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .onAppear {
            recorder.recoverOnLaunch()
        }
        .alert("Resume Anyway?", isPresented: $showResumeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Continue") { recorder.resume() }
        } message: {
            Text("Another workout may be running. Resuming will end it.")
        }
        .alert("Cannot Start", isPresented: isShowingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(recorder.alertMessage ?? ""))
        }
    }

    private var isShowingAlert: Binding<Bool> {
        Binding(get: { recorder.alertMessage != nil },
                set: { if !$0 { recorder.alertMessage = nil } })
    }

    private var iconName: String {
        if isInterrupted { return "exclamationmark.triangle.fill" }
        if isRecording { return "location.fill" }
        return "location"
    }

    private var iconColor: Color {
        if isInterrupted { return .orange }
        if isRecording { return .red }
        return .secondary
    }

    private var headline: LocalizedStringKey {
        if isInterrupted { return "Interrupted" }
        if isRecording { return "Recording" }
        return "Ready"
    }
}
