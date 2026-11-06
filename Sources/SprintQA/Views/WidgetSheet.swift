#if os(iOS)
import SprintQACore
import SwiftUI
import UIKit

/// The system sheet: sign in, the report launcher, review and send, sent.
struct WidgetSheet: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject var style: SprintQAStyle

    var body: some View {
        let palette = model.palette
        Group {
            switch model.screen {
            case .signIn: SignInScreen(model: model, palette: palette)
            case .launcher: LauncherScreen(model: model, palette: palette)
            case .review: ReviewScreen(model: model, palette: palette)
            case .sent(let result): SentScreen(model: model, palette: palette, result: result)
            }
        }
        .transition(.opacity)
        .foregroundStyle(palette.color(.foreground))
        .tint(palette.color(.signal))
        .presentationDetents(detents, selection: $model.detent)
        .presentationDragIndicator(.visible)
        .modifier(SheetBackground(color: isReview ? palette.color(.background) : palette.color(.bgElev1)))
        .environment(\.layoutDirection, palette.rightToLeft ? .rightToLeft : .leftToRight)
    }

    private var isReview: Bool {
        if case .review = model.screen { return true }
        return false
    }

    private var detents: Set<PresentationDetent> {
        isReview ? [.large] : [.medium, .large]
    }
}

private struct SheetBackground: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackground(color)
        } else {
            content.background(color.ignoresSafeArea())
        }
    }
}

/// Close (or Discard) on the leading side, the title centered, an optional trailing action.
private struct SheetBar<Leading: View, Trailing: View>: View {
    let title: String
    let palette: Palette
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            Text(title).font(palette.font(.headline)).lineLimit(1).padding(.horizontal, 80)
            HStack {
                leading
                Spacer()
                trailing
            }
        }
        .frame(minHeight: 44)
        .padding(.top, 14)
        .padding(.horizontal, 16)
    }
}

private struct CloseButton: View {
    let palette: Palette
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.color(.mutedForeground))
                .frame(width: 36, height: 36)
                .background(Circle().fill(palette.color(.bgElev2)))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(palette.strings(.close))
    }
}

private struct PrimaryButton: View {
    let title: String
    let palette: Palette
    var token: Token = .primary
    var busy = false
    let action: () -> Void

    var body: some View {
        let fg: Token = token == .signal ? .signalForeground : .primaryForeground
        Button(action: action) {
            ZStack {
                Text(title).opacity(busy ? 0 : 1)
                if busy { ProgressView().tint(palette.color(fg)) }
            }
            .font(palette.font(.body, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(palette.color(fg))
            .background(RoundedRectangle(cornerRadius: palette.radius.medium + 4, style: .continuous).fill(palette.color(token)))
        }
        .buttonStyle(PressScale())
        .disabled(busy)
    }
}

private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

@MainActor private func sheetTitle(_ model: WidgetModel, _ palette: Palette) -> String {
    palette.strings.own(.title) ?? model.config?.projectName ?? ""
}

// MARK: Sign in

struct SignInScreen: View {
    @ObservedObject var model: WidgetModel
    let palette: Palette

    var body: some View {
        let t = palette.strings
        VStack(spacing: 0) {
            SheetBar(title: sheetTitle(model, palette), palette: palette) {
                CloseButton(palette: palette) { model.close() }
            } trailing: { EmptyView() }
            ScrollView {
                VStack(spacing: 14) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(palette.color(.foreground))
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(palette.color(.bgElev2)))
                        .padding(.top, 12)
                    Text(t(.signInTitle)).font(palette.font(.title3, weight: .semibold)).multilineTextAlignment(.center)
                    Text(t(.signInBody)).font(palette.font(.subheadline)).foregroundStyle(palette.color(.mutedForeground))
                        .multilineTextAlignment(.center).frame(maxWidth: 320)
                    PrimaryButton(title: t(.signIn), palette: palette, busy: model.signingIn) {
                        Task { await model.signIn() }
                    }
                    .padding(.top, 8)
                    if let error = model.signInError {
                        Text(error).font(palette.font(.subheadline)).foregroundStyle(palette.color(.destructive))
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: Launcher

struct LauncherScreen: View {
    @ObservedObject var model: WidgetModel
    let palette: Palette

    var body: some View {
        let t = palette.strings
        VStack(spacing: 0) {
            SheetBar(title: sheetTitle(model, palette), palette: palette) {
                CloseButton(palette: palette) { model.close() }
            } trailing: { EmptyView() }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let intro = t.own(.intro) {
                        Text(intro).font(palette.font(.subheadline)).foregroundStyle(palette.color(.mutedForeground))
                    }
                    HStack {
                        Text(model.route ?? "/").lineLimit(1)
                        Spacer()
                        Text(viewportLabel)
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(palette.color(.subtleForeground))
                    .padding(.horizontal, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(t(.pageLabel)) \(model.route ?? "/")")
                    if let message = model.launcherMessage {
                        Text(message).font(palette.font(.subheadline)).foregroundStyle(palette.color(.destructive))
                            .padding(.horizontal, 4)
                            .transition(.opacity)
                    }
                    VStack(spacing: 0) {
                        LaunchRow(palette: palette, symbol: "viewfinder", title: t(.takeScreenshot), subtitle: t(.takeScreenshotSub)) {
                            model.takeScreenshot()
                        }
                        Divider().padding(.leading, 58)
                        LaunchRow(palette: palette, symbol: "square.and.pencil", title: t(.tabReport), subtitle: t(.detailsPlaceholder)) {
                            model.writeItDown()
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: palette.radius.large + 6, style: .continuous).fill(palette.color(.bgElev2)))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private var viewportLabel: String {
        let b = model.window?.bounds ?? UIScreen.main.bounds
        return "\(Int(b.width)) × \(Int(b.height))"
    }
}

private struct LaunchRow: View {
    let palette: Palette
    let symbol: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.color(.bgElev1)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(palette.font(.body))
                    Text(subtitle).font(palette.font(.footnote)).foregroundStyle(palette.color(.mutedForeground))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.color(.subtleForeground))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress(palette: palette))
    }
}

private struct RowPress: ButtonStyle {
    let palette: Palette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(palette.color(.foreground))
            .background(configuration.isPressed ? palette.color(.bgHover) : Color.clear)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: Review and send

struct ReviewScreen: View {
    @ObservedObject var model: WidgetModel
    let palette: Palette

    @State private var title = ""
    @State private var details = ""
    @State private var severity: Severity = .medium
    @State private var sending = false
    @State private var error: String?
    @State private var editing = false
    @FocusState private var focus: Field?

    private enum Field { case title, details }

    var body: some View {
        let t = palette.strings
        VStack(spacing: 0) {
            SheetBar(title: t(.tabReport), palette: palette) {
                Button(t(.discard)) { model.close() }
                    .font(palette.font(.body))
                    .foregroundStyle(palette.color(.destructive))
                    .frame(minHeight: 44)
            } trailing: { EmptyView() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let draft = model.draft {
                        HStack(alignment: .top, spacing: 12) {
                            Button { editing = true } label: {
                                MarkedShot(image: draft.image, crop: draft.crop, marks: draft.marks)
                                    .frame(width: thumb(draft.crop).width, height: thumb(draft.crop).height)
                                    .clipShape(RoundedRectangle(cornerRadius: palette.radius.medium + 4, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: palette.radius.medium + 4, style: .continuous).stroke(palette.color(.border)))
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "pencil.tip.crop.circle")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(5)
                                            .background(Circle().fill(Color.black.opacity(0.55)))
                                            .padding(5)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(t(.reviewScreenshot))
                            VStack(alignment: .leading, spacing: 0) {
                                Button(t(.remove)) { withAnimation(.easeOut(duration: 0.15)) { model.draft = nil } }
                                    .font(palette.font(.subheadline))
                                    .foregroundStyle(palette.color(.mutedForeground))
                                    .frame(minHeight: 44)
                                    .accessibilityLabel(t(.removeItem, ["item": t(.reviewScreenshot)]))
                            }
                        }
                        .padding(.bottom, 8)
                        .fullScreenCover(isPresented: $editing) {
                            MarkupEditor(palette: palette, image: draft.image, crop: draft.crop, marks: draft.marks,
                                         onCancel: { editing = false },
                                         onDone: { marks in
                                             model.draft?.marks = marks
                                             editing = false
                                         })
                        }
                        if draft.isPartial {
                            Toggle(t(.includeFullScreenshot), isOn: Binding(
                                get: { model.draft?.includeFull ?? false },
                                set: { model.draft?.includeFull = $0 }
                            ))
                            .font(palette.font(.subheadline))
                            .foregroundStyle(palette.color(.mutedForeground))
                            .tint(palette.color(.signal))
                            .padding(.bottom, 4)
                        }
                    }
                    label(t(.titleField))
                    TextField(t(.titlePlaceholder), text: $title)
                        .font(palette.font(.body))
                        .focused($focus, equals: .title)
                        .onChange(of: title) { _ in if error != nil { withAnimation(.easeOut(duration: 0.15)) { error = nil } } }
                        .submitLabel(.next)
                        .onSubmit { focus = .details }
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(field)
                    label(t(.severityLabel))
                    SeverityPicker(palette: palette, value: $severity)
                    HStack {
                        label(t(.detailsLabel))
                        Spacer()
                        Text(t(.optional)).font(palette.font(.footnote)).foregroundStyle(palette.color(.subtleForeground)).padding(.top, 14)
                    }
                    ZStack(alignment: .topLeading) {
                        if details.isEmpty {
                            Text(t(.detailsPlaceholder)).font(palette.font(.body)).foregroundStyle(palette.color(.subtleForeground))
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .accessibilityHidden(true)
                        }
                        TextEditor(text: $details)
                            .font(palette.font(.body))
                            .scrollContentBackground(.hidden)
                            .focused($focus, equals: .details)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .frame(minHeight: 96)
                    }
                    .background(field)
                    if let route = model.route {
                        Text("\(t(.pageLabel)) \(route)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(palette.color(.subtleForeground))
                            .padding(.top, 10)
                    }
                    if let error {
                        Text(error).font(palette.font(.subheadline)).foregroundStyle(palette.color(.destructive))
                            .padding(.top, 12)
                            .transition(.opacity)
                    }
                    PrimaryButton(title: t.own("submit") ?? t(.submit), palette: palette, token: .signal, busy: sending) {
                        Task { await send() }
                    }
                    .padding(.top, 16)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { if model.draft == nil { focus = .title } }
    }

    /// The crop's own shape, at most 132 points on its long side.
    private func thumb(_ crop: CGRect) -> CGSize {
        let k = 132 / max(crop.width, crop.height)
        return CGSize(width: crop.width * k, height: crop.height * k)
    }

    private var field: some View {
        RoundedRectangle(cornerRadius: palette.radius.medium + 2, style: .continuous)
            .fill(palette.color(.input))
            .overlay(RoundedRectangle(cornerRadius: palette.radius.medium + 2, style: .continuous).stroke(palette.color(.border)))
    }

    private func label(_ s: String) -> some View {
        Text(s).font(palette.font(.footnote, weight: .medium)).foregroundStyle(palette.color(.mutedForeground))
            .padding(.top, 14).padding(.bottom, 6).padding(.horizontal, 2)
    }

    private func send() async {
        sending = true
        let failure = await model.send(title: title, details: details, severity: severity)
        sending = false
        withAnimation(.easeOut(duration: 0.15)) { error = failure }
        if failure != nil, title.trimmingCharacters(in: .whitespaces).isEmpty { focus = .title }
    }
}

struct SeverityPicker: View {
    let palette: Palette
    @Binding var value: Severity

    var body: some View {
        let t = palette.strings
        HStack(spacing: 2) {
            ForEach(Severity.allCases, id: \.self) { s in
                Button { withAnimation(.easeOut(duration: 0.12)) { value = s } } label: {
                    HStack(spacing: 6) {
                        Circle().fill(color(s)).frame(width: 7, height: 7)
                        Text(name(s, t)).font(palette.font(.footnote, weight: .medium))
                            .foregroundStyle(palette.color(value == s ? .foreground : .mutedForeground))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(RoundedRectangle(cornerRadius: palette.radius.small + 2, style: .continuous)
                        .fill(value == s ? palette.color(.bgHover) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t(.severityA11y, ["severity": name(s, t)]))
                .accessibilityAddTraits(value == s ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: palette.radius.medium + 2, style: .continuous).fill(palette.color(.bgElev1)))
        .overlay(RoundedRectangle(cornerRadius: palette.radius.medium + 2, style: .continuous).stroke(palette.color(.border)))
    }

    private func name(_ s: Severity, _ t: Strings) -> String {
        switch s {
        case .low: return t(.sevLow)
        case .medium: return t(.sevMedium)
        case .high: return t(.sevHigh)
        case .blocker: return t(.sevBlocker)
        }
    }

    private func color(_ s: Severity) -> Color {
        switch s {
        case .low: return palette.color(.subtleForeground)
        case .medium: return palette.color(.warning)
        case .high: return palette.color(.destructive).opacity(0.65)
        case .blocker: return palette.color(.destructive)
        }
    }
}

// MARK: Sent

struct SentScreen: View {
    @ObservedObject var model: WidgetModel
    let palette: Palette
    let result: SentResult
    @State private var retrying = false

    var body: some View {
        let t = palette.strings
        VStack(spacing: 0) {
            SheetBar(title: t(.tabReport), palette: palette) { EmptyView() } trailing: {
                Button(t(.done)) { model.close() }
                    .font(palette.font(.body, weight: .semibold))
                    .foregroundStyle(palette.color(.signal))
                    .frame(minHeight: 44)
            }
            VStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(palette.color(.success))
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(palette.color(.successSoft)))
                    .padding(.top, 28)
                Text(result.held ? t(.sentHeld) : (t.own("thanks") ?? t(.thanks)))
                    .font(palette.font(.title3, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                if !result.failed.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(palette.color(.signal))
                        Text(t(.attachmentUploadFailed))
                            .font(palette.font(.subheadline))
                        Spacer()
                        Button(t(.retry)) {
                            retrying = true
                            Task {
                                await model.retryUpload(result)
                                retrying = false
                            }
                        }
                        .font(palette.font(.subheadline, weight: .semibold))
                        .foregroundStyle(palette.color(.signal))
                        .disabled(retrying)
                        .frame(minHeight: 44)
                    }
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: palette.radius.medium + 4, style: .continuous).fill(palette.color(.signalSoft)))
                    .padding(.top, 14)
                }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .onAppear { UIAccessibility.post(notification: .announcement, argument: result.held ? palette.strings(.sentHeld) : palette.strings(.thanks)) }
    }
}
#endif
