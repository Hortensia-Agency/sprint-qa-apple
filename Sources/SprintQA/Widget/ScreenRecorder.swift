#if os(iOS)
import AVFoundation
import CoreTransferable
import ReplayKit
import UniformTypeIdentifiers

/// A video on disk, recorded here or picked from the library.
struct VideoClip: Equatable {
    var url: URL
    var duration: Double
    var filename: String
    var mimeType: String
    var sizeBytes: Int

    /// Sprint's cap for a demo video.
    static let maxBytes = 150 * 1024 * 1024
    /// Sprint's cap for anything a widget reporter uploads.
    static let reporterMaxBytes = 20 * 1024 * 1024

    static func from(_ url: URL) async -> VideoClip? {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size > 0 else { return nil }
        let seconds = (try? await AVURLAsset(url: url).load(.duration)).map(CMTimeGetSeconds) ?? 0
        let ext = url.pathExtension.lowercased()
        let mime = ext == "mov" ? "video/quicktime" : "video/mp4"
        return VideoClip(url: url, duration: max(1, seconds), filename: "demo.\(ext.isEmpty ? "mp4" : ext)", mimeType: mime, sizeBytes: size)
    }
}

/// A video picked in Photos, copied out of the picker's sandbox.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("sprintqa-pick-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

/// Records the app's own screen with ReplayKit into an H.264 MP4, the format
/// desktop browsers play. ReplayKit asks for consent when capture starts, so
/// capture starts before the countdown and frames are dropped until `arm()`.
final class ScreenRecorder: @unchecked Sendable {
    static var available: Bool {
        #if targetEnvironment(simulator)
        // The Simulator starts in-app capture but never delivers a frame.
        return false
        #else
        return RPScreenRecorder.shared().isAvailable
        #endif
    }

    private let queue = DispatchQueue(label: "sprintqa.screen-recorder")
    private var writer: AVAssetWriter?
    private var video: AVAssetWriterInput?
    private var audio: AVAssetWriterInput?
    private var withMic = false
    private var compact = false
    private var armed = false
    private var started = false
    private var first = CMTime.zero
    private var last = CMTime.zero

    /// `compact` records smaller (1280 points on the long side, 1.2 Mbps) so a
    /// reporter's two minutes fit their 20 MB upload cap.
    func start(withMic: Bool, compact: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sprintqa-recording-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        queue.sync {
            self.writer = writer
            self.withMic = withMic
            self.compact = compact
            self.armed = false
            self.started = false
        }
        let rec = RPScreenRecorder.shared()
        rec.isMicrophoneEnabled = withMic
        try await rec.startCapture { [weak self] buffer, type, error in
            guard error == nil, let self else { return }
            self.queue.async { self.append(buffer, type) }
        }
    }

    /// The countdown is over: what comes next is the recording.
    func arm() {
        queue.async { self.armed = true }
    }

    /// Finishes the file, or nil when nothing was recorded.
    func stop() async -> VideoClip? {
        try? await RPScreenRecorder.shared().stopCapture()
        let finished: (AVAssetWriter, Double)? = await withCheckedContinuation { c in
            queue.async {
                guard let w = self.writer, self.started else {
                    self.reset(delete: true)
                    c.resume(returning: nil)
                    return
                }
                self.video?.markAsFinished()
                self.audio?.markAsFinished()
                w.endSession(atSourceTime: self.last)
                let seconds = CMTimeGetSeconds(CMTimeSubtract(self.last, self.first))
                w.finishWriting {
                    c.resume(returning: w.status == .completed ? (w, seconds) : nil)
                }
            }
        }
        guard let (w, seconds) = finished else { return nil }
        queue.sync { self.reset(delete: false) }
        guard var clip = await VideoClip.from(w.outputURL) else { return nil }
        clip.duration = max(1, seconds)
        clip.filename = "bug-\(Int(Date().timeIntervalSince1970)).mp4"
        return clip
    }

    func cancel() async {
        try? await RPScreenRecorder.shared().stopCapture()
        queue.sync {
            writer?.cancelWriting()
            reset(delete: true)
        }
    }

    private func reset(delete: Bool) {
        if delete, let url = writer?.outputURL { try? FileManager.default.removeItem(at: url) }
        writer = nil
        video = nil
        audio = nil
        armed = false
        started = false
    }

    private func append(_ buffer: CMSampleBuffer, _ type: RPSampleBufferType) {
        guard armed, let w = writer, CMSampleBufferDataIsReady(buffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(buffer)
        if !started {
            // The writer starts on the first video frame, sized from it.
            guard type == .video, let format = CMSampleBufferGetFormatDescription(buffer) else { return }
            let dims = CMVideoFormatDescriptionGetDimensions(format)
            let scale = min(1, (compact ? 1280 : 1920) / Double(max(dims.width, dims.height)))
            let even = { (v: Int32) in Int(Double(v) * scale) / 2 * 2 }
            let v = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: even(dims.width),
                AVVideoHeightKey: even(dims.height),
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: compact ? 1_200_000 : 5_000_000],
            ])
            v.expectsMediaDataInRealTime = true
            guard w.canAdd(v) else { return }
            w.add(v)
            video = v
            if withMic {
                let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 1,
                    AVSampleRateKey: 44_100,
                    AVEncoderBitRateKey: 64_000,
                ])
                a.expectsMediaDataInRealTime = true
                if w.canAdd(a) {
                    w.add(a)
                    audio = a
                }
            }
            guard w.startWriting() else { return }
            w.startSession(atSourceTime: time)
            first = time
            started = true
        }
        switch type {
        case .video:
            if let v = video, v.isReadyForMoreMediaData, v.append(buffer) { last = time }
        case .audioMic:
            if let a = audio, a.isReadyForMoreMediaData { a.append(buffer) }
        default:
            // The app's own sound stays out; narration is the microphone.
            break
        }
    }
}
#endif
