#if os(iOS)
import AVFoundation
import SprintQACore
import SwiftUI

struct VoiceNote: Equatable, Identifiable {
    let id = UUID()
    let url: URL
    let seconds: Int
}

func formatDuration(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return "\(s / 60):\(String(format: "%02d", s % 60))"
}

/// Records one voice note at a time as AAC in a temporary file.
@MainActor
final class VoiceRecorder: ObservableObject {
    /// Voice notes are transcribed, and the transcriber stops at two minutes.
    static let maxSeconds = 120

    /// Asking for the microphone without this key terminates the host app, so
    /// the widget offers voice notes only when the host declared it.
    static var available: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
    }

    @Published private(set) var recording = false
    @Published private(set) var seconds = 0
    var onNote: ((VoiceNote) -> Void)?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    /// Nil when recording started, else the message to show.
    func start(_ t: Strings) async -> String? {
        guard await Self.permission() else { return t(.micOff) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sprintqa-voice-\(UUID().uuidString).m4a")
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let r = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            guard r.record() else { throw CocoaError(.fileWriteUnknown) }
            recorder = r
            seconds = 0
            recording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            return nil
        } catch {
            Self.deactivate()
            return t(.micOff)
        }
    }

    func stop() {
        guard let r = recorder else { return }
        let length = Int(r.currentTime.rounded())
        r.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        recording = false
        Self.deactivate()
        onNote?(VoiceNote(url: r.url, seconds: max(1, length)))
    }

    private func tick() {
        guard let r = recorder else { return }
        seconds = Int(r.currentTime)
        if seconds >= Self.maxSeconds { stop() }
    }

    private static func permission() async -> Bool {
        if #available(iOS 17, *) { return await AVAudioApplication.requestRecordPermission() }
        return await withCheckedContinuation { c in
            AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) }
        }
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Plays one note at a time.
@MainActor
final class NotePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playing: UUID?
    private var player: AVAudioPlayer?

    func toggle(_ note: VoiceNote) {
        if playing == note.id {
            stop()
            return
        }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let p = try? AVAudioPlayer(contentsOf: note.url) else { return }
        p.delegate = self
        p.play()
        player = p
        playing = note.id
    }

    func stop() {
        player?.stop()
        player = nil
        if playing != nil { VoiceRecorder.deactivate() }
        playing = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}

/// Several voice notes per report, as on the web: record, play back, remove.
struct VoiceNotesSection: View {
    let palette: Palette
    @Binding var notes: [VoiceNote]
    @ObservedObject var recorder: VoiceRecorder
    let onError: (String?) -> Void
    @StateObject private var player = NotePlayer()
    @State private var starting = false

    var body: some View {
        let t = palette.strings
        VStack(alignment: .leading, spacing: 6) {
            Text(t(.voiceNote)).font(palette.font(.footnote, weight: .medium)).foregroundStyle(palette.color(.mutedForeground))
                .padding(.top, 14).padding(.horizontal, 2)
            Button(action: toggle) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: recorder.recording ? 2 : 4.5, style: .continuous)
                        .fill(palette.color(.destructive))
                        .frame(width: 9, height: 9)
                    Text(recorder.recording ? t(.stop, ["time": formatDuration(recorder.seconds)]) : t(.recordVoiceNote))
                        .font(palette.font(.body, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(recorder.recording ? palette.color(.destructive) : palette.color(.foreground))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: palette.radius.medium + 2, style: .continuous)
                        .fill(recorder.recording ? palette.color(.destructiveSoft) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: palette.radius.medium + 2, style: .continuous)
                        .stroke(recorder.recording ? palette.color(.destructive) : palette.color(.border))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(starting)
            .animation(.easeOut(duration: 0.15), value: recorder.recording)
            Text(t(.voiceHint)).font(palette.font(.caption)).foregroundStyle(palette.color(.subtleForeground))
            ForEach(notes) { n in
                HStack(spacing: 10) {
                    Button { player.toggle(n) } label: {
                        Image(systemName: player.playing == n.id ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.color(.signalForeground))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(palette.color(.signal)))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.playing == n.id ? t(.pauseVoiceNote) : t(.playVoiceNote))
                    Text("\(t(.voiceNote)) · \(formatDuration(n.seconds))")
                        .font(palette.font(.subheadline)).monospacedDigit()
                    Spacer(minLength: 4)
                    Button(t(.remove)) {
                        if player.playing == n.id { player.stop() }
                        try? FileManager.default.removeItem(at: n.url)
                        withAnimation(.easeOut(duration: 0.15)) { notes.removeAll { $0.id == n.id } }
                    }
                    .font(palette.font(.subheadline, weight: .medium))
                    .foregroundStyle(palette.color(.destructive))
                    .frame(minHeight: 44)
                    .accessibilityLabel(t(.removeItem, ["item": t(.voiceNote)]))
                }
                .padding(.leading, 2).padding(.trailing, 12)
                .background(RoundedRectangle(cornerRadius: palette.radius.medium + 2, style: .continuous).fill(palette.color(.bgElev2)))
                .transition(.opacity)
            }
        }
        .onAppear { recorder.onNote = { note in withAnimation(.easeOut(duration: 0.15)) { notes.append(note) } } }
        .onDisappear {
            recorder.stop()
            player.stop()
        }
    }

    private func toggle() {
        if recorder.recording {
            if palette.style.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            recorder.stop()
            return
        }
        player.stop()
        starting = true
        Task {
            let failure = await recorder.start(palette.strings)
            starting = false
            onError(failure)
            if failure == nil, palette.style.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
    }
}
#endif
