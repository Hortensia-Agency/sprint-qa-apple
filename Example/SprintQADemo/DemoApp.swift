import SprintQA
import SwiftUI

// A bare host app for trying the widget against a Sprint dev server.
// SPRINT_QA_KEY and SPRINT_ORIGIN come from the environment, or from the
// app's defaults so it also works when opened from the home screen:
//   xcrun simctl spawn booted defaults write com.hortensia.sprintqa.demo SPRINT_QA_KEY pk_qa_…
@main
struct DemoApp: App {
    init() {
        let env = ProcessInfo.processInfo.environment
        let saved = UserDefaults.standard
        SprintQA.configure(.init(
            widgetKey: env["SPRINT_QA_KEY"] ?? saved.string(forKey: "SPRINT_QA_KEY") ?? "",
            enabled: true,
            redirectScheme: "sprintqademo",
            origin: URL(string: env["SPRINT_ORIGIN"] ?? saved.string(forKey: "SPRINT_ORIGIN") ?? "http://localhost:3001")!
        ))
        if CommandLine.arguments.contains("-reset") { SprintQA.signOut() }
    }

    var body: some Scene {
        WindowGroup { DemoView() }
    }
}

struct DemoView: View {
    @State private var status = SprintQA.isSignedIn ? "Signed in" : "Signed out"
    @State private var showBubble = !SprintQA.isHidden

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Lesson", value: "Morning lesson")
                    LabeledContent("Coach", value: "Idris")
                    LabeledContent("Total", value: "65 TND")
                }
                Section("QA widget") {
                    Toggle("Show the report button", isOn: $showBubble)
                        .onChange(of: showBubble) { SprintQA.isHidden = !$0 }
                    Button("Report a problem") { SprintQA.open() }
                    Button("Sign in with Sprint") {
                        Task {
                            let failure = await SprintQA.signIn()
                            status = failure ?? (SprintQA.isSignedIn ? "Signed in" : "Signed out")
                        }
                    }
                    Text(status).accessibilityIdentifier("status")
                }
            }
            .navigationTitle("Book a lesson")
            .onAppear {
                SprintQA.route = "BookLesson"
                // For screenshots without UI automation: open the sheet on launch.
                if CommandLine.arguments.contains("-open") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { SprintQA.open() }
                }
            }
        }
    }
}
