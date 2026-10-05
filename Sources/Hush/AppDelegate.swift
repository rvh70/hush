import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Fallback check interval; CoreAudio listeners normally fire instantly.
    private let pollInterval: TimeInterval = 0.2
    /// After the mic is released, wait at least this long before resuming:
    /// voice mode briefly drops and reopens the mic when it starts.
    private let minResumeDelay: TimeInterval = 0.5
    /// Resume once the output is back to music quality, or after this at most.
    private let maxResumeDelay: TimeInterval = 4
    /// Output sample rates at or above this mean AirPods have left the call
    /// profile (16–24 kHz) and are back on high-quality playback.
    private let musicSampleRate: Double = 44_100

    private let media = MediaController()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var resumeTimer: Timer?
    private var polling = false
    private var pollAgain = false
    private var micClients: [String] = []

    private var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enabled") }
    }

    private var micActive: Bool { !micClients.isEmpty }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()

        MicMonitor.observe { [weak self] in self?.poll() }
        // Fallback in case a CoreAudio notification is ever missed.
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    // MARK: - Mic state

    private func poll() {
        // Pausing runs an Apple event, which can let CoreAudio callbacks in
        // before it returns; finish this pass first, then look again.
        guard !polling else {
            pollAgain = true
            return
        }
        polling = true
        handleMicChange()
        polling = false
        if pollAgain {
            pollAgain = false
            poll()
        }
    }

    private func handleMicChange() {
        let wasActive = micActive
        micClients = MicMonitor.activeInputClients()
        guard enabled, micActive != wasActive else {
            refreshIcon()
            return
        }

        if micActive {
            // A resume still waiting means the mic came back quickly: the music
            // is still paused and stays that way.
            if isResuming {
                cancelResume()
            } else {
                media.pauseAll()
            }
        } else if !media.paused.isEmpty {
            scheduleResume()
        }
        refreshIcon()
    }

    private var isResuming: Bool { resumeTimer != nil }

    /// Resumes once the output device is back at music quality, checking every
    /// 50 ms between the minimum and maximum delay.
    private func scheduleResume() {
        let start = Date()
        resumeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(start)
            guard elapsed >= self.minResumeDelay else { return }
            let rate = AudioOutput.sampleRate()
            guard rate >= self.musicSampleRate || elapsed >= self.maxResumeDelay else { return }
            self.cancelResume()
            self.media.resumeAll()
            self.refreshIcon()
        }
    }

    private func cancelResume() {
        resumeTimer?.invalidate()
        resumeTimer = nil
    }

    // MARK: - Menu bar

    private var isHushing: Bool { !media.paused.isEmpty }

    private func refreshIcon() {
        let symbol: String
        let description: String
        if !enabled {
            symbol = "speaker.slash"
            description = "Hush (off)"
        } else if isHushing {
            symbol = "mic.fill"
            description = "Hush (music paused)"
        } else {
            symbol = "music.note"
            description = "Hush (on)"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = description
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: enabled ? "Disable Hush" : "Enable Hush",
            action: #selector(toggleEnabled), keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Hush", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func statusText() -> String {
        guard enabled else { return "Hush is off" }
        if isHushing {
            let names = media.paused.map(\.name).joined(separator: ", ")
            return isResuming ? "Resuming \(names)…" : "Paused \(names) — mic in use"
        }
        if micActive { return "Mic in use (nothing was playing)" }
        return "Hush is on — listening for the mic"
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        if !enabled {
            cancelResume()
            // Turning Hush off mid-call should not start music in the call.
            if micActive { media.forget() } else { media.resumeAll() }
        } else if micActive {
            media.pauseAll()
        }
        refreshIcon()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Hush: launch at login failed: \(error)")
        }
    }
}
