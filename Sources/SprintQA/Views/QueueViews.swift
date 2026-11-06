#if os(iOS)
import AVKit
import PhotosUI
import SprintQACore
import SwiftUI

extension Palette {
    func severity(_ s: Severity) -> Color {
        switch s {
        case .low: return color(.subtleForeground)
        case .medium: return color(.warning)
        case .high: return color(.destructive).opacity(0.65)
        case .blocker: return color(.destructive)
        }
    }

    func state(_ state: String) -> Color {
        color(Token(rawValue: "state-\(state)") ?? .stateBacklog)
    }

    /// QA bookkeeping states read as the stage a person sees, as on the web.
    func stageLabel(_ state: String) -> String {
        let t = strings
        switch state {
        case "ready_for_qa": return t(.stateWaitingToDeploy)
        case "deployed": return t(.stateReadyToTest)
        case "in_qa", "verified_once", "verified_twice": return t(.stateInReview)
        case "in_progress", "needs_changes": return t(.stateSentBack)
        case "done": return t(.stateDone)
        case "blocked": return t(.stateBlocked)
        default:
            let s = state.replacingOccurrences(of: "_", with: " ")
            return s.prefix(1).uppercased() + s.dropFirst()
        }
    }

    func severityName(_ s: Severity) -> String {
        switch s {
        case .low: return strings(.sevLow)
        case .medium: return strings(.sevMedium)
        case .high: return strings(.sevHigh)
        case .blocker: return strings(.sevBlocker)
        }
    }
}

// MARK: Queue

struct QueueScreen: View {
    @ObservedObject var model: WidgetModel
    let palette: Palette
    @State private var result: QueueResponse?
    @State private var failed = false

    var body: some View {
        let t = palette.strings
        Group {
            if failed {
                empty(t(.queueLoadFailed))
            } else if let result {
                if result.blocked || result.tasks.isEmpty {
                    empty(result.blocked ? t(.queueBlocked) : t(.queueEmpty))
                } else {
                    VStack(spacing: 0) {
                        ForEach(result.tasks) { task in
                            row(task)
                            Divider()
                        }
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in skeletonRow }
                }
                .accessibilityElement()
                .accessibilityLabel(t(.loadingQueue))
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            result = try await model.client.queue()
        } catch {
            failed = true
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(palette.font(.subheadline)).foregroundStyle(palette.color(.mutedForeground))
            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 32)
    }

    private func row(_ task: QueueTask) -> some View {
        Button { model.openTask = task.id } label: {
            HStack(spacing: 12) {
                Circle().stroke(palette.state(task.state), lineWidth: 2).frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(palette.font(.body, weight: .medium)).lineLimit(2)
                        .foregroundStyle(palette.color(.foreground)).multilineTextAlignment(.leading)
                    Text(palette.stageLabel(task.state)).font(palette.font(.footnote)).foregroundStyle(palette.color(.mutedForeground))
                }
                Spacer(minLength: 8)
                if let s = task.severity {
                    Circle().fill(palette.severity(s)).frame(width: 8, height: 8)
                        .accessibilityLabel(palette.strings(.severityA11y, ["severity": palette.severityName(s)]))
                }
                Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.color(.subtleForeground))
            }
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var skeletonRow: some View {
        HStack(spacing: 12) {
            Circle().fill(palette.color(.bgElev2)).frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(palette.color(.bgElev2)).frame(height: 12).frame(maxWidth: 240)
                RoundedRectangle(cornerRadius: 3).fill(palette.color(.bgElev2)).frame(width: 110, height: 10)
            }
            Spacer()
        }
        .frame(minHeight: 56)
    }
}

// MARK: Detail

struct DetailScreen: View {
    @ObservedObject var model: WidgetModel
    let palette: Palette
    let taskId: Int
    @State private var detail: TaskDetail?
    @State private var failed = false
    @State private var busy = false
    @State private var notes = ""
    @State private var actionMessage: String?
    @State private var shown: LightboxIndex?
    @State private var movie: PhotosPickerItem?
    @State private var pickingMovie = false
    @State private var attaching = false

    var body: some View {
        let t = palette.strings
        VStack(alignment: .leading, spacing: 10) {
            Button { model.openTask = nil } label: {
                Label(t(.backToQueue), systemImage: "chevron.backward")
                    .font(palette.font(.subheadline, weight: .medium))
                    .foregroundStyle(palette.color(.signal))
                    .frame(minHeight: 44)
            }
            if failed {
                Text(t(.taskLoadFailed)).font(palette.font(.subheadline)).foregroundStyle(palette.color(.mutedForeground))
            } else if let d = detail {
                content(d)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 3).fill(palette.color(.bgElev2)).frame(height: 18).frame(maxWidth: 280)
                    RoundedRectangle(cornerRadius: 3).fill(palette.color(.bgElev2)).frame(width: 140, height: 12)
                    RoundedRectangle(cornerRadius: 8).fill(palette.color(.bgElev2)).frame(height: 64)
                }
                .accessibilityElement()
                .accessibilityLabel(t(.loadingTask))
            }
        }
        .task(id: model.detailReload) { await load() }
        .fullScreenCover(item: $shown) { i in
            Lightbox(palette: palette, items: gallery, index: i.value) { shown = nil }
        }
        .photosPicker(isPresented: $pickingMovie, selection: $movie, matching: .videos)
        .onChange(of: movie) { item in
            guard let item else { return }
            movie = nil
            Task { await attach(item) }
        }
    }

    @ViewBuilder private func content(_ d: TaskDetail) -> some View {
        let t = palette.strings
        Text(d.task.title).font(palette.font(.title3, weight: .semibold))
        HStack(spacing: 8) {
            Circle().stroke(palette.state(d.task.state), lineWidth: 2).frame(width: 12, height: 12)
            Text(t(.verifiedCount, ["state": palette.stageLabel(d.task.state), "count": d.activeVerifiedCount]))
                .font(palette.font(.subheadline)).foregroundStyle(palette.color(.mutedForeground))
        }
        if let fixer = d.fixer {
            Text(t(.fixedBy, ["name": fixer.name])).font(palette.font(.footnote)).foregroundStyle(palette.color(.mutedForeground))
        }
        if d.reproContext?.staleEnvRetest == true {
            Label(d.reproContext?.staleEnvRetestReason ?? t(.staleEnv), systemImage: "exclamationmark.triangle")
                .font(palette.font(.footnote)).foregroundStyle(palette.color(.warning))
        }
        if let description = d.task.description, !description.isEmpty {
            Text(description).font(palette.font(.body)).textSelection(.enabled)
        }

        let images = (d.screenshots ?? []).filter { $0.url != nil }
        if !images.isEmpty {
            heading(t(.screenshots))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { i, shot in
                        Button { shown = LightboxIndex(value: i) } label: {
                            AsyncImage(url: URL(string: shot.url ?? "")) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() } else { palette.color(.bgElev2) }
                            }
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: palette.radius.medium + 2, style: .continuous))
                        }
                        .accessibilityLabel(shot.filename)
                    }
                }
            }
        }

        if let audio = d.audioNotes, !audio.isEmpty {
            heading(t(.voiceNotes))
            ForEach(audio) { note in RemoteNoteRow(palette: palette, note: note) }
        }

        heading(t(.demoVideos))
        ForEach(Array((d.demoVideos ?? []).enumerated()), id: \.element.id) { i, v in
            Button { if v.url != nil { shown = LightboxIndex(value: images.count + i) } } label: {
                Label(v.filename, systemImage: "play.rectangle").lineLimit(1)
                    .font(palette.font(.subheadline)).foregroundStyle(palette.color(.signal))
                    .frame(minHeight: 36)
            }
            .disabled(v.url == nil)
        }
        if ScreenRecorder.available {
            SecondaryButton(palette: palette, title: t(.recordDemo)) { model.startRecording(.task(taskId)) }
        }
        SecondaryButton(palette: palette, title: attaching ? t(.uploading) : t(.attachDemoVideo)) { pickingMovie = true }
            .disabled(attaching)
        if let notice = model.detailNotice {
            Text(notice).font(palette.font(.footnote)).foregroundStyle(palette.color(.mutedForeground))
        }

        TextField(t(.notesPlaceholder), text: $notes, axis: .vertical)
            .font(palette.font(.body))
            .lineLimit(2...5)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: palette.radius.medium + 2, style: .continuous).fill(palette.color(.input))
                    .overlay(RoundedRectangle(cornerRadius: palette.radius.medium + 2, style: .continuous).stroke(palette.color(.border)))
            )
            .padding(.top, 6)
        if let actionMessage {
            Text(actionMessage).font(palette.font(.subheadline)).foregroundStyle(palette.color(.destructive))
        }
        HStack(spacing: 8) {
            verdictButton(t(.take), fill: palette.color(.bgElev2), text: palette.color(.foreground)) { await take() }
            verdictButton(t(.bugFound), fill: palette.color(.destructive), text: .white) { await verify(.bugFound) }
            verdictButton(t(.verify), fill: palette.color(.signal), text: palette.color(.signalForeground)) { await verify(.verified) }
        }
        .disabled(busy)
        .opacity(busy ? 0.6 : 1)
        .padding(.top, 4)
    }

    private var gallery: [LightboxItem] {
        guard let d = detail else { return [] }
        let images = (d.screenshots ?? []).compactMap { s in s.url.flatMap(URL.init(string:)).map { LightboxItem(url: $0, name: s.filename, video: false) } }
        let videos = (d.demoVideos ?? []).compactMap { v in v.url.flatMap(URL.init(string:)).map { LightboxItem(url: $0, name: v.filename, video: true) } }
        return images + videos
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(palette.font(.footnote, weight: .medium)).foregroundStyle(palette.color(.mutedForeground)).padding(.top, 8)
    }

    private func verdictButton(_ title: String, fill: Color, text: Color, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(title).font(palette.font(.subheadline, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(text)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: palette.radius.medium + 2, style: .continuous).fill(fill))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        do {
            detail = try await model.client.taskDetail(taskId: taskId)
            failed = false
        } catch {
            failed = true
        }
    }

    private func status(_ e: Error) -> Int { (e as? SprintQAError)?.status ?? 0 }

    private func take() async {
        busy = true
        actionMessage = nil
        defer { busy = false }
        do {
            try await model.client.take(taskId: taskId)
            await load()
        } catch {
            actionMessage = status(error) == 409 ? palette.strings(.taskChanged) : palette.strings(.reviewStartFailed)
        }
    }

    private func verify(_ verdict: SprintQAClient.Verdict) async {
        busy = true
        actionMessage = nil
        defer { busy = false }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await model.client.verify(taskId: taskId, verdict: verdict, notes: trimmed.isEmpty ? nil : trimmed)
            notes = ""
            if palette.style.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            await load()
        } catch {
            let t = palette.strings
            switch status(error) {
            case 409: actionMessage = t(.alreadyVerified)
            case 403: actionMessage = t(.verifyForbidden)
            case 0: actionMessage = t(.verdictOffline)
            default: actionMessage = t(.verdictFailed)
            }
        }
    }

    private func attach(_ item: PhotosPickerItem) async {
        attaching = true
        defer { attaching = false }
        let picked = try? await item.loadTransferable(type: PickedMovie.self)
        guard let url = picked?.url, let clip = await VideoClip.from(url), clip.sizeBytes <= VideoClip.maxBytes else {
            model.detailNotice = palette.strings(.videoPickFailed)
            return
        }
        await model.attachDemo(clip, to: taskId)
    }
}

private struct SecondaryButton: View {
    let palette: Palette
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(palette.font(.subheadline, weight: .medium))
                .foregroundStyle(palette.color(.foreground))
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: palette.radius.medium + 2, style: .continuous).stroke(palette.color(.border)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A voice note on a task, streamed, with its transcript.
private struct RemoteNoteRow: View {
    let palette: Palette
    let note: TaskDetail.AudioNote
    @StateObject private var player = StreamPlayer()

    var body: some View {
        let t = palette.strings
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Button { player.toggle(URL(string: note.url)) } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.color(.signalForeground))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(palette.color(.signal)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.playing ? t(.pauseVoiceNote) : t(.playVoiceNote))
                Text(t(.voiceNote)).font(palette.font(.subheadline))
                Spacer()
            }
            .background(RoundedRectangle(cornerRadius: palette.radius.medium + 2, style: .continuous).fill(palette.color(.bgElev2)))
            if let tr = note.transcript, tr.state != "canceled" {
                Text(transcriptLine(tr))
                    .font(palette.font(.footnote))
                    .foregroundStyle(tr.state == "done" ? palette.color(.foreground) : palette.color(.mutedForeground))
                    .textSelection(.enabled)
            }
        }
        .onDisappear { player.stop() }
    }

    private func transcriptLine(_ tr: TaskDetail.Transcript) -> String {
        let t = palette.strings
        switch tr.state {
        case "done": return tr.text.flatMap { $0.isEmpty ? nil : $0 } ?? t(.transcriptEmpty)
        case "transcribing": return t(.transcribing)
        case "parked":
            switch tr.parkReason {
            case "over_cap": return t(.transcriptOverCap)
            case "provider_auth": return t(.transcriptProviderAuth)
            default: return t(.transcriptOff)
            }
        default: return tr.failedReason == "too_long" ? t(.transcriptTooLong) : t(.transcriptFailed)
        }
    }
}

@MainActor
private final class StreamPlayer: ObservableObject {
    @Published private(set) var playing = false
    private var player: AVPlayer?
    private var end: NSObjectProtocol?

    func toggle(_ url: URL?) {
        if playing {
            stop()
            return
        }
        guard let url else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        let p = AVPlayer(url: url)
        end = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        p.play()
        player = p
        playing = true
    }

    func stop() {
        player?.pause()
        player = nil
        if let end { NotificationCenter.default.removeObserver(end) }
        end = nil
        playing = false
    }
}

// MARK: Lightbox

struct LightboxItem {
    let url: URL
    let name: String
    let video: Bool
}

struct LightboxIndex: Identifiable {
    let value: Int
    var id: Int { value }
}

/// A task's screenshots and demo videos, full screen, one at a time, with
/// previous and next as on the web. Swiping pages too.
struct Lightbox: View {
    let palette: Palette
    let items: [LightboxItem]
    @State var index: Int
    let onClose: () -> Void

    var body: some View {
        let t = palette.strings
        VStack(spacing: 8) {
            CaptureBar {
                Text("\(index + 1) / \(items.count)").font(.subheadline).monospacedDigit().foregroundStyle(.white)
                    .padding(.leading, 12)
                Spacer(minLength: 0)
                CapturePill(title: t(.close), action: onClose)
            }
            TabView(selection: $index) {
                ForEach(items.indices, id: \.self) { i in
                    page(items[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            if items.count > 1 {
                CaptureBar {
                    CapturePill(title: t(.previous)) { withAnimation(.easeOut(duration: 0.2)) { index = (index - 1 + items.count) % items.count } }
                    Spacer(minLength: 0)
                    CapturePill(title: t(.next)) { withAnimation(.easeOut(duration: 0.2)) { index = (index + 1) % items.count } }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private func page(_ item: LightboxItem) -> some View {
        if item.video {
            VideoPlayer(player: AVPlayer(url: item.url)).accessibilityLabel(item.name)
        } else {
            AsyncImage(url: item.url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else if phase.error != nil {
                    Text(item.name).foregroundStyle(.white)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .accessibilityLabel(item.name)
        }
    }
}
#endif
