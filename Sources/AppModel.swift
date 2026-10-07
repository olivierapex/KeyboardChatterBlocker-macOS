import AppKit
import ApplicationServices
import Observation

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let key: Int64
    let elapsed: UInt64
}

@MainActor @Observable
final class AppModel {
    var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            blocker.update(settings)
            save()
        }
    }
    var log: [LogEntry] = []
    var isRunning = false
    var invalidConfigLines: [String]
    var errorMessage: String?

    @ObservationIgnored private let blocker: KeyBlocker
    @ObservationIgnored private let interceptor: KeyboardInterceptor
    @ObservationIgnored private var permissionTimer: Timer?

    init() {
        let (loaded, invalid) = Settings.load()
        settings = loaded
        invalidConfigLines = invalid
        blocker = KeyBlocker(settings: loaded)
        interceptor = KeyboardInterceptor(blocker: blocker)
        blocker.onBlocked = { [weak self] key, elapsed in
            Task { @MainActor in self?.addLogEntry(key: key, elapsed: elapsed) }
        }
        if !FileManager.default.fileExists(atPath: Settings.fileURL.path) {
            save()
        }
        startWhenTrusted()
    }

    var keyRows: [(key: Int64, ms: UInt64)] {
        settings.keyThresholds.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    func addKey(_ key: Int64) {
        if settings.keyThresholds[key] == nil {
            settings.keyThresholds[key] = settings.globalChatter == 0 ? 100 : settings.globalChatter
        }
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func addLogEntry(key: Int64, elapsed: UInt64) {
        log.insert(LogEntry(key: key, elapsed: elapsed), at: 0)
        if log.count > 1000 {
            log.removeLast()
        }
    }

    private func save() {
        do {
            try settings.save()
        } catch {
            errorMessage = "Could not save \(Settings.fileURL.path): \(error.localizedDescription)"
        }
    }

    private func startWhenTrusted() {
        if AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
            start()
            return
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                timer.invalidate()
                self.start()
            }
        }
    }

    private func start() {
        isRunning = interceptor.start()
        if !isRunning {
            errorMessage = "Could not create the keyboard event tap. Remove and re-add the app under Privacy & Security > Accessibility."
        }
    }
}
