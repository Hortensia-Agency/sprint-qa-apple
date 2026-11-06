// Every string the widget shows, with its English default. Keys and text
// match the React Native widget (strings.tsx) so one translation file serves
// both. A host overrides any of them; {slots} are filled in.

public enum StringKey: String, CaseIterable, Sendable {
    case bubbleLabel
    case hideTarget
    case hideAction
    case hiddenNotice
    case close
    case done
    case tabReport
    case tabQueue
    case signInTitle
    case signInBody
    case signIn
    case signInNotMember
    case reportingOff
    case signInIncomplete
    case networkError
    case signInFailed
    case titleField
    case titlePlaceholder
    case detailsLabel
    case detailsPlaceholder
    case severityLabel
    case sevLow
    case sevMedium
    case sevHigh
    case sevBlocker
    case severityA11y
    case attachScreenshot
    case recordVoiceNote
    case recordAgain
    case stop
    case attachVideo
    case pickAnotherVideo
    case voiceNote
    case remove
    case removeItem
    case submit
    case voiceSaveFailed
    case micOff
    case videoPickFailed
    case summaryRequired
    case videoUploadFailedShort
    case videoRetryHint
    case reportFailed
    case sentHeld
    case thanks
    case queueLoadFailed
    case loadingQueue
    case queueBlocked
    case queueEmpty
    case stateWaitingToDeploy
    case stateReadyToTest
    case stateInReview
    case stateSentBack
    case stateDone
    case stateBlocked
    case taskLoadFailed
    case loadingTask
    case backToQueue
    case verifiedCount
    case voiceNotes
    case demoVideos
    case uploading
    case uploadingVideo
    case attachDemoVideo
    case notesPlaceholder
    case take
    case bugFound
    case verify
    case voiceNoteNoPlayer
    case pauseVoiceNote
    case playVoiceNote
    case transcriptOff
    case transcriptOverCap
    case transcriptProviderAuth
    case transcriptEmpty
    case transcribing
    case transcriptTooLong
    case transcriptFailed
    case takeScreenshot
    case takeScreenshotSub
    case recordVideo
    case recordVideoSub
    case narrateWithMic
    case choosePhoto
    case choosePhotoSub
    case chooseVideo
    case chooseVideoSub
    case captureBlocked
    case screenshotFailed
    case recordingFailed
    case selectAreaHint
    case cancel
    case fullPage
    case useSelection
    case reviewScreenshot
    case reviewVideo
    case discard
    case optional
    case pageLabel
    case includeFullScreenshot
    case voiceHint
    case reportForbidden
    case reportRateLimited
    case reportNeedsTitle
    case toolDraw
    case toolRectangle
    case toolEllipse
    case toolArrow
    case toolLine
    case toolText
    case toolHide
    case typeText
    case color
    case undo
    case redo
    case trimStart
    case trimEnd
    case trimLabel
    case countdownTitle
    case countdownMic
    case countdownMuted
    case annotate
    case stopShort
    case clear
    case tabDemo
    case demoIntro
    case demoTitle
    case demoTitlePlaceholder
    case demoDescription
    case demoDescriptionPlaceholder
    case demoRecordingReady
    case publishDemo
    case demoPublished
    case demoPublishFailed
    case demoNeedsTitle
    case screenshots
    case recordDemo
    case demoUploading
    case demoAttached
    case fixedBy
    case staleEnv
    case taskChanged
    case reviewStartFailed
    case alreadyVerified
    case verifyForbidden
    case verdictOffline
    case verdictFailed
    case previous
    case next
}

extension StringKey {
    static let defaults: [StringKey: String] = [
        .bubbleLabel: "Report a problem",
        .hideTarget: "Drop to hide",
        .hideAction: "Hide button",
        .hiddenNotice: "Button hidden. You can turn it back on in Settings.",
        .close: "Close",
        .done: "Done",
        .tabReport: "Report",
        .tabQueue: "Queue",
        .signInTitle: "Sign in to report a problem",
        .signInBody: "Use your Sprint account, or create one on the next screen. You only do this once on this device.",
        .signIn: "Continue with Sprint",
        .signInNotMember: "This account can't report on this project. Ask the team that sent you here for access.",
        .reportingOff: "Reporting is turned off for this app right now.",
        .signInIncomplete: "Sign-in didn't complete. Please try again.",
        .networkError: "Network error. Check your connection and try again.",
        .signInFailed: "Sign-in failed. Please try again.",
        .titleField: "Title",
        .titlePlaceholder: "What went wrong?",
        .detailsLabel: "Details",
        .detailsPlaceholder: "What you did, what you expected, what happened",
        .severityLabel: "Severity",
        .sevLow: "Low",
        .sevMedium: "Medium",
        .sevHigh: "High",
        .sevBlocker: "Blocker",
        .severityA11y: "{severity} severity",
        .attachScreenshot: "Attach a screenshot of this screen",
        .recordVoiceNote: "Record a voice note",
        .recordAgain: "Record again",
        .stop: "Stop {time}",
        .attachVideo: "Attach a video",
        .pickAnotherVideo: "Pick another video",
        .voiceNote: "Voice note",
        .remove: "Remove",
        .removeItem: "Remove {item}",
        .submit: "Send report",
        .voiceSaveFailed: "Couldn't save the voice note.",
        .micOff: "Microphone access is off. Allow it in Settings to record a voice note.",
        .videoPickFailed: "Couldn't pick that video.",
        .summaryRequired: "Add a title so the team knows what this is about.",
        .videoUploadFailedShort: "Video upload failed.",
        .videoRetryHint: "Your report is sent; tap Send report to retry the video.",
        .reportFailed: "Couldn't send the report. Check your connection and try again.",
        .sentHeld: "Sent. A team member will review it before it reaches the board.",
        .thanks: "Sent. The team has it.",
        .queueLoadFailed: "Couldn't load the queue. Pull the sheet down and open it again.",
        .loadingQueue: "Loading the queue",
        .queueBlocked: "You don't have access to this project's queue.",
        .queueEmpty: "Nothing is waiting for QA.",
        .stateWaitingToDeploy: "Waiting to deploy",
        .stateReadyToTest: "Ready to test",
        .stateInReview: "In review",
        .stateSentBack: "Sent back",
        .stateDone: "Done",
        .stateBlocked: "Blocked",
        .taskLoadFailed: "Couldn't load this task.",
        .loadingTask: "Loading the task",
        .backToQueue: "Queue",
        .verifiedCount: "{state}, {count} verified",
        .voiceNotes: "Voice notes",
        .demoVideos: "Demo videos",
        .uploading: "Uploading…",
        .uploadingVideo: "Uploading video…",
        .attachDemoVideo: "Attach a demo video",
        .notesPlaceholder: "Notes for the team (optional)",
        .take: "Take",
        .bugFound: "Bug found",
        .verify: "Verify",
        .voiceNoteNoPlayer: "Voice note (install expo-av to play)",
        .pauseVoiceNote: "Pause voice note",
        .playVoiceNote: "Play voice note",
        .transcriptOff: "Not transcribed: transcription is off for this workspace.",
        .transcriptOverCap: "Waiting: this month's transcription limit is reached.",
        .transcriptProviderAuth: "Waiting: the transcription provider refused our key.",
        .transcriptEmpty: "No speech found in this note.",
        .transcribing: "Transcribing",
        .transcriptTooLong: "Not transcribed: voice notes are limited to 2 minutes.",
        .transcriptFailed: "Transcription failed.",
        .takeScreenshot: "Take a screenshot",
        .takeScreenshotSub: "Select an area, then mark it up",
        .recordVideo: "Record the screen",
        .recordVideoSub: "Draw on screen, narrate, trim",
        .narrateWithMic: "Narrate with the microphone",
        .choosePhoto: "Choose a screenshot",
        .choosePhotoSub: "One you already took, from your photos",
        .chooseVideo: "Choose a screen recording",
        .chooseVideoSub: "One you already made, from your library",
        .captureBlocked: "Screen recording was cancelled or blocked.",
        .screenshotFailed: "The screenshot didn't work. Choose one from your photos instead.",
        .recordingFailed: "The recording didn't save. Try again.",
        .selectAreaHint: "Drag to select an area, or take the whole screen",
        .cancel: "Cancel",
        .fullPage: "Whole screen",
        .useSelection: "Use selection",
        .reviewScreenshot: "Screenshot",
        .reviewVideo: "Recording",
        .discard: "Discard",
        .optional: "Optional",
        .pageLabel: "Screen:",
        .includeFullScreenshot: "Include the full screenshot",
        .voiceHint: "Narrate the bug. It stops on its own at 2:00.",
        .reportForbidden: "You don't have access to file bugs on this project. Ask your team to add you to it.",
        .reportRateLimited: "Too many reports just now. Try again in a minute.",
        .reportNeedsTitle: "Add a title before sending.",
        .toolDraw: "Draw",
        .toolRectangle: "Rectangle",
        .toolEllipse: "Ellipse",
        .toolArrow: "Arrow",
        .toolLine: "Line",
        .toolText: "Text",
        .toolHide: "Hide",
        .typeText: "Type here",
        .color: "Color",
        .undo: "Undo",
        .redo: "Redo",
        .trimStart: "Trim start",
        .trimEnd: "Trim end",
        .trimLabel: "Plays from {start} to {end}",
        .countdownTitle: "Preparing to record",
        .countdownMic: "Your microphone is on.",
        .countdownMuted: "Your microphone is off.",
        .annotate: "Draw on screen",
        .stopShort: "Stop",
        .clear: "Clear",
        .tabDemo: "Demo",
        .demoIntro: "Record a short walkthrough for the project's demo library. It stays private until a manager shares it with the client.",
        .demoTitle: "Title",
        .demoTitlePlaceholder: "For example, the new checkout",
        .demoDescription: "Description (optional)",
        .demoDescriptionPlaceholder: "What this demo shows",
        .demoRecordingReady: "Recording ready, {time}",
        .publishDemo: "Publish demo",
        .demoPublished: "Published. A manager can share it with the client.",
        .demoPublishFailed: "Couldn't publish the demo.",
        .demoNeedsTitle: "Add a title for the demo.",
        .screenshots: "Screenshots",
        .recordDemo: "Record a demo",
        .demoUploading: "Uploading the recording…",
        .demoAttached: "Recording attached.",
        .fixedBy: "Fixed by {name}",
        .staleEnv: "The fix may be on a different build than the one this bug was reported on. Check the app is up to date first.",
        .taskChanged: "This task changed state. Reloading…",
        .reviewStartFailed: "Couldn't start the QA review.",
        .alreadyVerified: "You already verified this, or its state changed.",
        .verifyForbidden: "You don't have permission to verify on this project.",
        .verdictOffline: "Sprint isn't answering, so your verdict wasn't saved. Try again.",
        .verdictFailed: "Couldn't record your verdict.",
        .previous: "Previous",
        .next: "Next",
    ]
}
