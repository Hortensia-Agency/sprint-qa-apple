#if os(iOS)
import SprintQACore
import SwiftUI
import UIKit

// The full-screen steps of a screenshot: pick the area, then mark it up.
// Both sit over the captured frame, so their chrome is dark in either theme.

/// Pick the part of the screen the report is about, on the frozen capture.
struct AreaSelectView: View {
    let palette: Palette
    let image: UIImage
    /// The overlay ignores the safe area, so its insets come in from outside.
    var insets = EdgeInsets()
    let onCancel: () -> Void
    let onPick: (CGRect) -> Void

    @State private var selection: CGRect?
    @State private var anchor: CGPoint?
    @State private var canvas: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let t = palette.strings
        ZStack {
            GeometryReader { geo in
                let bounds = CGRect(origin: .zero, size: geo.size)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image).resizable().frame(width: geo.size.width, height: geo.size.height)
                        .accessibilityIgnoresInvertColors()
                    Path { p in
                        p.addRect(bounds)
                        if let selection { p.addRect(selection) }
                    }
                    .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                    if let s = selection {
                        Rectangle().stroke(palette.color(.signal), lineWidth: 2)
                            .frame(width: s.width, height: s.height)
                            .offset(x: s.minX, y: s.minY)
                        ForEach(Array(corners(s).enumerated()), id: \.offset) { _, c in
                            Circle().fill(Color.white)
                                .overlay(Circle().stroke(palette.color(.signal), lineWidth: 2))
                                .frame(width: 16, height: 16)
                                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                                .position(c)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag($0, in: bounds) }
                        .onEnded { _ in settle(in: bounds) }
                )
                .onAppear { canvas = geo.size }
                .onChange(of: geo.size) { canvas = $0 }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)

            VStack {
                if selection == nil {
                    Text(t(.selectAreaHint))
                        .font(palette.font(.subheadline, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color(white: 0.1).opacity(0.72)))
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
                Spacer()
                CaptureBar {
                    CapturePill(title: t(.cancel), action: onCancel)
                    Spacer(minLength: 0)
                    CapturePill(title: t(.fullPage)) { onPick(CGRect(origin: .zero, size: image.size)) }
                    CapturePill(title: t(.useSelection), prominent: true, disabled: !usable) {
                        if let selection { onPick(AreaSelection.crop(selection, view: canvas, image: image.size)) }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, insets.top + 8)
            .padding(.bottom, max(insets.bottom, 8))
            .animation(.easeOut(duration: 0.15), value: selection == nil)
        }
        .environment(\.colorScheme, .dark)
    }

    private var usable: Bool { selection.map(AreaSelection.isUsable) ?? false }

    private func corners(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
    }

    private func drag(_ v: DragGesture.Value, in bounds: CGRect) {
        if anchor == nil {
            // Grabbing a corner resizes from the opposite one; anywhere else starts a new selection.
            if let s = selection, let i = corners(s).firstIndex(where: { hypot($0.x - v.startLocation.x, $0.y - v.startLocation.y) < 32 }) {
                anchor = corners(s)[3 - i]
            } else {
                anchor = v.startLocation
            }
        }
        guard let anchor else { return }
        selection = AreaSelection.rect(anchor, soft(v.location, in: bounds))
    }

    /// Past the screen's edge the handle follows less and less.
    private func soft(_ p: CGPoint, in b: CGRect) -> CGPoint {
        func axis(_ v: Double, _ hi: Double) -> Double {
            if v < 0 { return BubbleLayout.rubberBand(v, dimension: hi) }
            if v > hi { return hi + BubbleLayout.rubberBand(v - hi, dimension: hi) }
            return v
        }
        return CGPoint(x: axis(p.x, b.width), y: axis(p.y, b.height))
    }

    private func settle(in bounds: CGRect) {
        anchor = nil
        guard let s = selection else { return }
        let inside = s.intersection(bounds)
        guard AreaSelection.isUsable(inside) else {
            selection = nil
            return
        }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) { selection = inside }
    }
}

/// Draw on the chosen part before it is sent. Marks live in the capture's
/// points, so reopening the editor from the report keeps them.
struct MarkupEditor: View {
    let palette: Palette
    let image: UIImage
    let crop: CGRect
    let insets: EdgeInsets
    let onCancel: () -> Void
    let onDone: ([Mark]) -> Void

    @State private var marks: [Mark]
    @State private var redo: [Mark] = []
    @State private var current: Mark?
    @State private var tool: Mark.Tool = .rect
    @State private var color = Mark.colors[0]
    @State private var choosingColor = false
    @State private var typing: Typing?
    @FocusState private var typingFocused: Bool

    private struct Typing {
        var at: CGPoint
        var scale: CGFloat
        var text = ""
    }

    private static let tools: [(Mark.Tool, String, StringKey)] = [
        (.pen, "scribble", .toolDraw),
        (.rect, "rectangle", .toolRectangle),
        (.ellipse, "circle", .toolEllipse),
        (.arrow, "arrow.up.right", .toolArrow),
        (.text, "textformat", .toolText),
        (.hide, "eye.slash", .toolHide),
    ]

    init(palette: Palette, image: UIImage, crop: CGRect, marks: [Mark], insets: EdgeInsets = EdgeInsets(),
         onCancel: @escaping () -> Void, onDone: @escaping ([Mark]) -> Void) {
        self.palette = palette
        self.image = image
        self.crop = crop
        self.insets = insets
        self.onCancel = onCancel
        self.onDone = onDone
        _marks = State(initialValue: marks)
    }

    var body: some View {
        let t = palette.strings
        VStack(spacing: 12) {
            CaptureBar {
                CapturePill(title: t(.cancel), action: onCancel)
                Spacer(minLength: 0)
                ToolButton(symbol: "arrow.uturn.backward", label: t(.undo)) {
                    guard let last = marks.popLast() else { return }
                    redo.append(last)
                }
                .disabled(marks.isEmpty)
                ToolButton(symbol: "arrow.uturn.forward", label: t(.redo)) {
                    guard let last = redo.popLast() else { return }
                    marks.append(last)
                }
                .disabled(redo.isEmpty)
                CapturePill(title: t(.done), prominent: true) {
                    commitTyping()
                    onDone(marks)
                }
            }

            GeometryReader { geo in
                let scale = min(geo.size.width / crop.width, geo.size.height / crop.height)
                MarkedShot(image: image, crop: crop, marks: current.map { marks + [$0] } ?? marks)
                    .frame(width: crop.width * scale, height: crop.height * scale)
                    .overlay(alignment: .topLeading) { typingField(scale: scale) }
                    .contentShape(Rectangle())
                    .gesture(draw(scale: scale))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement()
                    .accessibilityLabel(t(.reviewScreenshot))
            }

            CaptureBar {
                if choosingColor { swatches } else { toolbar }
            }
            .animation(.easeOut(duration: 0.15), value: choosingColor)
        }
        .padding(.horizontal, 12)
        .padding(.top, insets.top + 8)
        .padding(.bottom, max(insets.bottom, 8))
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var toolbar: some View {
        let t = palette.strings
        HStack(spacing: 4) {
            ForEach(Self.tools, id: \.0) { item in
                ToolButton(symbol: item.1, label: t(item.2), on: tool == item.0) {
                    commitTyping()
                    tool = item.0
                }
            }
            Spacer(minLength: 0)
            Button {
                choosingColor = true
            } label: {
                Swatch(color: color, selected: true)
            }
            .accessibilityLabel(t(.color))
            .accessibilityValue(UIColor(color).accessibilityName)
        }
        .transition(.opacity)
    }

    private var swatches: some View {
        HStack(spacing: 0) {
            ToolButton(symbol: "chevron.backward", label: palette.strings(.close)) { choosingColor = false }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Mark.colors.indices, id: \.self) { i in
                        let c = Mark.colors[i]
                        Button {
                            color = c
                            choosingColor = false
                        } label: {
                            Swatch(color: c, selected: c == color)
                        }
                        .accessibilityLabel(UIColor(c).accessibilityName)
                        .accessibilityAddTraits(c == color ? .isSelected : [])
                    }
                }
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder private func typingField(scale: CGFloat) -> some View {
        if let typing {
            TextField(palette.strings(.typeText), text: Binding(
                get: { self.typing?.text ?? "" },
                set: { self.typing?.text = $0 }
            ))
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color(uiColor: UIColor(color)))
            .focused($typingFocused)
            .submitLabel(.done)
            .onSubmit(commitTyping)
            .fixedSize()
            .frame(minWidth: 120, alignment: .leading)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.35)))
            .offset(x: (typing.at.x - crop.minX) * scale - 4, y: (typing.at.y - crop.minY) * scale - 14)
            .onChange(of: typingFocused) { if !$0 { commitTyping() } }
        }
    }

    private func point(_ p: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: crop.minX + p.x / scale, y: crop.minY + p.y / scale)
    }

    private func draw(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard tool != .text else { return }
                let p = point(v.location, scale: scale)
                if current == nil {
                    let start = point(v.startLocation, scale: scale)
                    // Three points wide on screen, whatever the zoom.
                    current = Mark(tool: tool, color: color, size: 3 / scale, points: tool == .pen ? [start] : [start, start])
                }
                if tool == .pen { current?.points.append(p) } else { current?.points[1] = p }
            }
            .onEnded { v in
                if tool == .text {
                    if typing != nil {
                        commitTyping()
                    } else {
                        typing = Typing(at: point(v.location, scale: scale), scale: scale)
                        typingFocused = true
                    }
                    return
                }
                if let m = current { commit(m) }
                current = nil
            }
    }

    private func commit(_ m: Mark) {
        guard !m.isTrivial else { return }
        marks.append(m)
        redo.removeAll()
    }

    private func commitTyping() {
        guard let ty = typing else { return }
        typing = nil
        commit(Mark(tool: .text, color: color, size: 18 / ty.scale, points: [ty.at], text: ty.text))
    }
}

// MARK: Chrome

/// The floating bar over a capture, solid under Reduce Transparency.
struct CaptureBar<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(6)
            .frame(minHeight: 56)
            .background {
                let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
                if reduceTransparency {
                    shape.fill(Color(white: 0.12))
                } else {
                    shape.fill(.regularMaterial).overlay(shape.fill(Color(white: 0.08).opacity(0.5)))
                }
            }
            .environment(\.colorScheme, .dark)
    }
}

struct CapturePill: View {
    let title: String
    var prominent = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(prominent ? Color(white: 0.08) : .white)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(0.14)))
        }
        .buttonStyle(PressScale())
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityAddTraits(disabled ? [] : .isButton)
    }
}

struct ToolButton: View {
    let symbol: String
    let label: String
    var on = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(on ? Color(white: 0.08) : .white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(on ? Color.white : Color.clear))
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct Swatch: View {
    let color: RGBA
    let selected: Bool

    var body: some View {
        Circle().fill(Color(uiColor: UIColor(color)))
            .frame(width: 26, height: 26)
            .overlay(Circle().stroke(Color.white.opacity(selected ? 1 : 0.35), lineWidth: selected ? 2.5 : 1))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif
