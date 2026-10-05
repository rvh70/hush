import AppKit
import Foundation

/// Something Hush can pause and later resume.
protocol Player {
    var name: String { get }
    /// Pauses if currently playing, as fast as possible. Returns whether it paused.
    func pauseIfPlaying() -> Bool
    /// Resumes, but only if the player is still paused (the person may have
    /// stopped or changed things in the meantime).
    func resumeIfPaused()
}

/// Spotify or Music, driven over AppleScript. Never launches the app.
/// Scripts are compiled once up front so pausing costs a single Apple event.
final class ScriptablePlayer: Player {
    let name: String
    let bundleID: String
    private let pauseScript: NSAppleScript?
    private let resumeScript: NSAppleScript?

    init(name: String, bundleID: String) {
        self.name = name
        self.bundleID = bundleID
        pauseScript = Self.compile("""
            tell application id "\(bundleID)"
                if player state is playing then
                    pause
                    return "paused"
                end if
            end tell
            return "idle"
            """)
        resumeScript = Self.compile("""
            tell application id "\(bundleID)"
                if player state is paused then play
            end tell
            """)
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func pauseIfPlaying() -> Bool {
        isRunning && run(pauseScript) == "paused"
    }

    func resumeIfPaused() {
        if isRunning { run(resumeScript) }
    }

    private static func compile(_ source: String) -> NSAppleScript? {
        let script = NSAppleScript(source: source)
        script?.compileAndReturnError(nil)
        return script
    }

    @discardableResult
    private func run(_ script: NSAppleScript?) -> String? {
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if let error { NSLog("Hush: AppleScript failed for \(name): \(error)") }
        return result?.stringValue
    }
}

/// Whatever the system considers "now playing" (browsers, YouTube, Podcasts…),
/// via the private MediaRemote framework. Since macOS 15.4 Apple restricts its
/// read side for third-party apps, so `available` is checked at runtime and
/// this player is skipped when the system won't answer.
final class SystemNowPlayingPlayer: Player {
    let name = "System media"

    private typealias IsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool

    private let isPlayingFn: IsPlayingFn?
    private let sendCommandFn: SendCommandFn?
    private let queue = DispatchQueue(label: "nl.robintech.hush.mediaremote")

    private static let commandPlay: Int32 = 0
    private static let commandPause: Int32 = 1

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        isPlayingFn = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
            .map { unsafeBitCast($0, to: IsPlayingFn.self) }
        sendCommandFn = dlsym(handle, "MRMediaRemoteSendCommand")
            .map { unsafeBitCast($0, to: SendCommandFn.self) }
    }

    func pauseIfPlaying() -> Bool {
        guard isPlaying() else { return false }
        _ = sendCommandFn?(Self.commandPause, nil)
        return true
    }

    private func isPlaying() -> Bool {
        guard let isPlayingFn else { return false }
        let done = DispatchSemaphore(value: 0)
        var playing = false
        isPlayingFn(queue) { value in
            playing = value
            done.signal()
        }
        _ = done.wait(timeout: .now() + 0.5)
        return playing
    }

    func resumeIfPaused() {
        guard !isPlaying() else { return }
        _ = sendCommandFn?(Self.commandPlay, nil)
    }
}

/// Pauses whatever is playing and remembers it, so resume only restarts what
/// Hush itself paused.
final class MediaController {
    private let scriptable = [
        ScriptablePlayer(name: "Spotify", bundleID: "com.spotify.client"),
        ScriptablePlayer(name: "Music", bundleID: "com.apple.Music"),
    ]
    private let system = SystemNowPlayingPlayer()
    private(set) var paused: [Player] = []

    /// Pauses what is playing. Spotify and Music go first; the slower system
    /// now-playing check only runs when neither of them was playing, since it
    /// usually reports the same app.
    @discardableResult
    func pauseAll() -> [String] {
        var toResume = scriptable.filter { $0.pauseIfPlaying() } as [Player]
        if toResume.isEmpty, system.pauseIfPlaying() { toResume = [system] }
        paused = toResume
        return toResume.map(\.name)
    }

    func resumeAll() {
        paused.forEach { $0.resumeIfPaused() }
        paused = []
    }

    func forget() {
        paused = []
    }
}
