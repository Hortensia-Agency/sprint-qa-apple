#if os(iOS)
import SprintQACore
import SwiftUI
import UIKit

/// Everything the overlay window draws: the bubble, the Hide target while
/// dragging, the "hidden" notice, and the sheet.
struct WidgetRoot: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject var style: SprintQAStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = model.palette
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.clear
                if model.bubbleVisible, let p = model.position {
                    if model.dragging, let c = model.hideCenter {
                        HideTarget(palette: palette, armed: model.overHide)
                            .position(c)
                            .transition(.opacity.combined(with: .offset(y: 24)))
                    }
                    Bubble(model: model, palette: palette)
                        .offset(x: p.x, y: p.y)
                        .transition(.opacity)
                }
                if let stage = model.capture {
                    Group {
                        switch stage {
                        case .area(let image):
                            AreaSelectView(palette: palette, image: image, insets: safeArea, onCancel: model.cancelArea, onPick: model.pickArea)
                        case .markup(let d):
                            MarkupEditor(palette: palette, image: d.image, crop: d.crop, marks: d.marks,
                                         insets: safeArea, onCancel: model.cancelMarkup, onDone: model.finishMarkup)
                        case .countdown:
                            RecordCountdown(palette: palette, withMic: model.withMic && VoiceRecorder.available,
                                            onDone: model.beginRecording, onCancel: model.cancelCountdown)
                        case .recording(_, let startedAt):
                            RecordBar(model: model, palette: palette, startedAt: startedAt, insets: safeArea)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .transition(.opacity)
                }
                if model.showHiddenNotice {
                    HiddenNotice(model: model, palette: palette)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.horizontal, 16)
                        .padding(.bottom, safeArea.bottom + 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: model.dragging)
            .animation(.easeOut(duration: 0.2), value: model.showHiddenNotice)
            .animation(.easeOut(duration: 0.15), value: model.bubbleVisible)
            .animation(.easeOut(duration: 0.2), value: model.capture == nil)
            .onAppear { model.updateLayout(size: geo.size, insets: safeArea) }
            .onChange(of: geo.size) { _ in model.updateLayout(size: geo.size, insets: safeArea) }
                    }
        .ignoresSafeArea()
        .sheet(isPresented: $model.sheetShown, onDismiss: model.sheetDismissed) {
            WidgetSheet(model: model, style: style)
        }
        .environment(\.layoutDirection, palette.rightToLeft ? .rightToLeft : .leftToRight)
        .preferredColorScheme(colorScheme(palette.interfaceStyle))
        .onChange(of: palette.interfaceStyle) { style in model.window?.overrideUserInterfaceStyle = style }
        .onAppear { model.window?.overrideUserInterfaceStyle = palette.interfaceStyle }
    }

    /// The window's insets: the root ignores the safe area, so its own reads zero.
    private var safeArea: EdgeInsets {
        let i = model.window?.safeAreaInsets ?? .zero
        return EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right)
    }

    private func colorScheme(_ style: UIUserInterfaceStyle) -> ColorScheme? {
        switch style {
        case .light: return .light
        case .dark: return .dark
        default: return nil
        }
    }
}

struct Bubble: View {
    @ObservedObject var model: WidgetModel
    let palette: Palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let size = palette.bubbleSize
        let label = palette.bubbleLabel.flatMap { $0.isEmpty ? nil : $0 }
        let strings = palette.strings
        HStack(spacing: 8) {
            BubbleIcon(icon: palette.bubbleIcon, size: size, color: Color(uiColor: palette.bubbleForeground))
            if let label {
                Text(label).font(palette.font(.subheadline, weight: .semibold)).lineLimit(1)
                    .padding(.trailing, 6)
            }
        }
        .foregroundStyle(Color(uiColor: palette.bubbleForeground))
        .frame(minWidth: size, minHeight: size, maxHeight: size)
        .padding(.horizontal, label == nil ? 0 : 10)
        .background(background(size: size))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
        .scaleEffect(model.pressed && !model.dragging ? 0.94 : 1)
        .animation(.easeOut(duration: 0.1), value: model.pressed)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { v in model.dragChanged(location: v.location, time: CACurrentMediaTime()) }
                .onEnded { _ in if model.dragEnded() { model.open() } }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? strings(.bubbleLabel))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.open() }
        .accessibilityAction(named: Text(strings(.hideAction))) { model.setHidden(true) }
    }

    @ViewBuilder private func background(size: CGFloat) -> some View {
        let fill = Color(uiColor: palette.bubbleBackground)
        if #available(iOS 26, *), model.style.bubble.glass, !reduceTransparency {
            Capsule().fill(fill.opacity(0.82)).glassEffect(.regular.tint(fill.opacity(0.35)), in: Capsule())
        } else {
            Capsule().fill(fill)
        }
    }
}

struct BubbleIcon: View {
    let icon: SprintQAStyle.Bubble.Icon
    let size: CGFloat
    let color: Color

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: size * 0.42, weight: .semibold))
        case .image(let image):
            Image(uiImage: image).resizable().scaledToFit().frame(width: size * 0.55, height: size * 0.55)
        case .url(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Image(systemName: "exclamationmark.bubble.fill").font(.system(size: size * 0.42, weight: .semibold))
                }
            }
            .frame(width: size * 0.6, height: size * 0.6)
            .clipShape(Circle())
        }
    }
}

struct HideTarget: View {
    let palette: Palette
    let armed: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 64, height: 64)
                .foregroundStyle(armed ? Color.white : palette.color(.foreground))
                .background(Circle().fill(armed ? palette.color(.destructive) : palette.color(.bgElev1).opacity(0.94)))
                .overlay(Circle().stroke(armed ? Color.clear : palette.color(.borderStrong), lineWidth: 1))
                .scaleEffect(armed ? 1.14 : 1)
                .animation(.easeOut(duration: 0.12), value: armed)
            Text(palette.strings(.hideTarget))
                .font(palette.font(.footnote, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(palette.color(.bgElev1).opacity(0.94)))
                .foregroundStyle(palette.color(.foreground))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct HiddenNotice: View {
    @ObservedObject var model: WidgetModel
    let palette: Palette

    var body: some View {
        let t = palette.strings
        HStack(spacing: 12) {
            Image(systemName: "eye.slash").foregroundStyle(palette.color(.mutedForeground))
            Text(t(.hiddenNotice)).font(palette.font(.subheadline)).foregroundStyle(palette.color(.foreground))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(t(.undo)) { model.undoHide() }
                .font(palette.font(.subheadline, weight: .semibold))
                .foregroundStyle(palette.color(.signal))
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.color(.bgElev1)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(palette.color(.border), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .background(GeometryReader { g in
            Color.clear.onAppear { model.noticeFrame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { model.noticeFrame = $0 }
        })
    }
}
#endif
