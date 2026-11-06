# SprintQA for iOS

Sprint's QA widget for iOS and iPadOS apps: testers and reporters send bug reports from inside the app to a project in [Sprint](https://sprint.hortensia-agency.com). It is the native counterpart of `@sprint-logger/qa-rn` and talks to the same `/api/widget/*` routes.

What a person gets:

- A floating button they can drag anywhere, or onto Hide.
- A report sheet: select an area of the screen and mark it up, record the screen with narration and trim it, add voice notes, pick a screenshot or recording from Photos.
- For QA members, the queue: open a fixed task, watch its screenshots and videos, and Take, Verify or report Bug found. The Demo tab publishes walkthroughs to the project's demo library.
- Debug capture with bug recordings, when the project turns it on: network calls, printed and logged lines, and screen changes, redacted as the web widget does.

## Requirements

- iOS 16 or later. Swift 5.9 or later.
- No third-party dependencies.

## Install

In Xcode, File › Add Package Dependencies, then:

```
https://github.com/Hortensia-Agency/sprint-qa-apple
```

## Set up in Sprint

In the project's QA widget settings:

1. Turn the widget on and copy its key (`pk_qa_…`). The key is public and safe to ship in the app.
2. Under Allowed hosts and apps, add your app's URL scheme, for example `tapinn://`. Sign-in returns to the app through it. You don't need to register the scheme in Info.plist.

## Use

```swift
import SprintQA

SprintQA.configure(.init(
    widgetKey: "pk_qa_…",
    enabled: true,           // your build flag; false keeps the widget off entirely
    redirectScheme: "tapinn"
))

// Sign in with Sprint. Returns the text to show if it failed, nil otherwise.
let failure = await SprintQA.signIn()

// The screen the person is on, matched against the project's hidden routes.
SprintQA.route = "Checkout"

// The person's own choice to hide the button, for a switch in your settings.
SprintQA.isHidden = false
```

The token is stored in the Keychain for this device only. `SprintQA.signOut()` forgets it.

### Microphone

Voice notes and narrated recordings appear only when Info.plist declares why the app uses the microphone. Without it iOS would end the app when the widget asked, so the widget leaves them out.

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Record voice notes for bug reports.</string>
```

### Screen recording

Recording uses ReplayKit's in-app capture: it records your app only, and the first time iOS asks the person to allow it. The Simulator never delivers frames, so there the widget offers Choose a screen recording instead; check recording on a device. Reporters record at a lower quality so a two-minute clip fits their 20 MB upload limit.

### Network capture

`URLSession.shared` is captured while a bug video records. Add the capture to your own sessions:

```swift
let config = URLSessionConfiguration.default
SprintQA.captureNetwork(in: config)
```

Auth headers, cookies, sensitive query values and token-shaped strings are redacted before upload, with the same rules as the web widget (Sprint's shared fixture is in `Tests/SprintQACoreTests/Fixtures/capture-redact-parity.json`).

## Customize

Every color, the bubble, corners, font and text come from `SprintQA.style`. Set values whenever you like, at launch, from a settings screen or from remote config; anything on screen redraws. What you set wins over the project's Appearance settings in Sprint, which win over Sprint's own look.

```swift
let style = SprintQA.style
style.accent = UIColor(sprintQAHex: "#1F6FEB")            // the accent family, with readable text picked for it
style.colors[.primary] = .sprintQA(light: .black, dark: .white)
style.colors[.bgElev1] = UIColor { $0.userInterfaceStyle == .dark ? .black : .white }   // any dynamic UIColor
style.set(.indigo, for: .ring)                             // or a SwiftUI Color

style.bubble.icon = .image(UIImage(named: "FeedbackIcon")!)   // .symbol("flag.fill"), .url(logoURL)
style.bubble.background = .black
style.bubble.foreground = .white
style.bubble.size = 52
style.bubble.side = .leading
style.bubble.label = "Feedback"

style.radius = .init(small: 6, medium: 10, large: 16)
style.fontFamily = "Avenir Next"                           // scaled with Dynamic Type
style.colorScheme = .dark                                  // .light, .dark or .system
style.strings[.submit] = "Send to the team"
style.title = "Atlas feedback"
style.hiddenRoutes = ["Payment*"]
style.reset()                                              // back to the project's look
```

Token names are Sprint's (`Token.allCases`): background, bgElev1, foreground, mutedForeground, primary, signal, destructive, border and the rest.

## Develop

```
swift test                                    # core tests, on a Mac
xcodebuild -scheme SprintQA -destination 'generic/platform=iOS Simulator' build
swift scripts/generate-tokens.swift           # after updating tokens.json
```

`tokens.json` is a copy of Sprint's design tokens and `Tests/SprintQACoreTests/Fixtures/capture-redact-parity.json` a copy of Sprint's redaction cases; Sprint's own test suite fails when either drifts. `Example/` holds a demo app (launch arguments `-open`, `-reset`, `-rtl`) and a UI test that signs in against a Sprint dev server.

```
xcodebuild test -scheme SprintQA -destination 'platform=iOS Simulator,name=<device>' -only-testing:SprintQATests
```

## License

MIT
