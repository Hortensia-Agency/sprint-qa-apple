#if os(iOS)
import AVKit
import SprintQACore
import SwiftUI

/// The recording with two trim handles. Sprint's player clamps to them;
/// nothing is re-encoded.
struct VideoReview: View {
    let palette: Palette
    let clip: VideoClip
    @Binding var trim: ClosedRange<Double>?
    @State private var player: AVPlayer

    init(palette: Palette, clip: VideoClip, trim: Binding<ClosedRange<Double>?>) {
        self.palette = palette
        self.clip = clip
        _trim = trim
        _player = State(initialValue: AVPlayer(url: clip.url))
    }

    var body: some View {
        VStack(spacing: 10) {
            VideoPlayer(player: player)
                .frame(height: 320)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: palette.radius.medium + 4, style: .continuous))
                .accessibilityLabel(palette.strings(.reviewVideo))
            TrimTrack(palette: palette, duration: clip.duration, trim: $trim) { start in
                player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
        .onDisappear { player.pause() }
    }
}

private struct TrimTrack: View {
    let palette: Palette
    let duration: Double
    @Binding var trim: ClosedRange<Double>?
    let onSeek: (Double) -> Void

    @State private var start = 0.0
    @State private var end = 0.0
    @State private var from: Double?
    private let handle: CGFloat = 22

    private var minGap: Double { min(1, duration / 2) }

    var body: some View {
        let t = palette.strings
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let track = max(1, geo.size.width - handle * 2)
                let x = { (sec: Double) in handle + CGFloat(sec / duration) * track }
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.color(.bgElev2))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.color(.signalSoft))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(palette.color(.signal), lineWidth: 2))
                        .frame(width: x(end) - x(start) + handle * 2)
                        .offset(x: x(start) - handle)
                    grip(at: x(start) - handle, label: t(.trimStart), value: start) { delta in
                        set(start: (from ?? start) + delta / track * duration)
                    } adjust: { step in set(start: start + step) }
                    grip(at: x(end), label: t(.trimEnd), value: end) { delta in
                        set(end: (from ?? end) + delta / track * duration)
                    } adjust: { step in set(end: end + step) }
                }
            }
            .frame(height: 44)
            Text(t(.trimLabel, ["start": formatDuration(Int(start)), "end": formatDuration(Int(end.rounded()))]))
                .font(palette.font(.caption)).monospacedDigit()
                .foregroundStyle(palette.color(.mutedForeground))
        }
        .onAppear {
            start = trim?.lowerBound ?? 0
            end = trim?.upperBound ?? duration
        }
    }

    private func grip(at x: CGFloat, label: String, value: Double, drag: @escaping (Double) -> Void, adjust: @escaping (Double) -> Void) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(palette.color(.signal))
            .overlay(Capsule().fill(palette.color(.signalForeground)).frame(width: 3, height: 16))
            .frame(width: handle, height: 44)
            .contentShape(Rectangle().inset(by: -10))
            .offset(x: x)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if from == nil { from = value }
                        drag(Double(v.translation.width))
                    }
                    .onEnded { _ in from = nil }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(formatDuration(Int(value)))
            .accessibilityAdjustableAction { direction in
                adjust(direction == .increment ? 1 : -1)
            }
    }

    private func set(start s: Double) {
        start = min(max(0, s), end - minGap)
        commit(seek: start)
    }

    private func set(end e: Double) {
        end = max(min(duration, e), start + minGap)
        commit(seek: end)
    }

    private func commit(seek: Double) {
        trim = start <= 0.05 && end >= duration - 0.05 ? nil : start...end
        onSeek(seek)
    }
}
#endif
