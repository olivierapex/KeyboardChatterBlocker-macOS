import AppKit
import ApplicationServices

struct LogEntry {
    let date: Date
    let key: Int64
    let elapsed: UInt64
}

/// Shared by the background process, which intercepts keys, and the settings window process.
/// The two stay in sync through the config and chatter log files.
@MainActor
final class AppModel {
    var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            blocker?.update(settings)
            if !isReloading {
                save()
            }
            onStateChange?()
        }
    }
    private(set) var log: [LogEntry] = []
    /// In the background process: the event tap is running. In the settings process: the background process's tap is.
    private(set) var isRunning = false
    private(set) var isTrusted = false
    private(set) var errorMessage: String?
    private(set) var invalidConfigLines: [String]

    var onStateChange: (() -> Void)?
    var onLogChange: (() -> Void)?

    static let backgroundArgument = "--background"
    static let logURL = Settings.fileURL.deletingLastPathComponent().appending(path: "chatter_log.txt", directoryHint: .notDirectory)

    private let blocker: KeyBlocker?
    private let interceptor: KeyboardInterceptor?
    private var pollTimer: DispatchSourceTimer?
    private var watcher: DispatchSourceFileSystemObject?
    private var isReloading = false

    init(intercepts: Bool) {
        let (loaded, invalid) = Settings.load()
        settings = loaded
        invalidConfigLines = invalid
        if intercepts {
            let blocker = KeyBlocker(settings: loaded)
            blocker.onBlocked = { key, elapsed in
                Task { @MainActor in AppModel.appendLog(key: key, elapsed: elapsed) }
            }
            self.blocker = blocker
            interceptor = KeyboardInterceptor(blocker: blocker)
        } else {
            blocker = nil
            interceptor = nil
        }
        if !FileManager.default.fileExists(atPath: Settings.fileURL.path) {
            save()
        }
        if intercepts {
            Self.writeLog([])
        }
        log = Self.readLog()
        watchFiles()
    }

    func start() {
        guard interceptor != nil else {
            refreshStatus()
            poll(every: 2) { [weak self] in
                self?.refreshStatus()
                return false
            }
            return
        }
        if AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
            startInterceptor()
            return
        }
        poll(every: 1) { [weak self] in
            guard AXIsProcessTrusted() else { return false }
            self?.startInterceptor()
            return true
        }
    }

    func addKey(_ key: Int64) {
        if settings.keyThresholds[key] == nil {
            settings.keyThresholds[key] = settings.globalChatter == 0 ? 100 : settings.globalChatter
        }
    }

    func clearLog() {
        Self.writeLog([])
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func save() {
        do {
            try settings.save()
        } catch {
            errorMessage = "Could not save \(Settings.fileURL.path): \(error.localizedDescription)"
        }
    }

    /// A dispatch timer rather than a Timer, because the background process has no run loop, only the main queue.
    private func poll(every seconds: Double, until tick: @escaping () -> Bool) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + seconds, repeating: seconds)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                if tick() {
                    self?.pollTimer?.cancel()
                    self?.pollTimer = nil
                }
            }
        }
        timer.resume()
        pollTimer = timer
    }

    private func refreshStatus() {
        let running = Self.backgroundTapIsRunning()
        let trusted = AXIsProcessTrusted()
        if running != isRunning || trusted != isTrusted {
            isRunning = running
            isTrusted = trusted
            onStateChange?()
        }
    }

    private static func backgroundTapIsRunning() -> Bool {
        guard let executable = Bundle.main.executablePath else { return false }
        var count: UInt32 = 0
        CGGetEventTapList(0, nil, &count)
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
        CGGetEventTapList(count, &taps, &count)
        return taps.prefix(Int(count)).contains { tap in
            guard tap.enabled, tap.tappingProcess != getpid() else { return false }
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            guard proc_pidpath(tap.tappingProcess, &path, UInt32(path.count)) > 0 else { return false }
            return String(cString: path) == executable
        }
    }

    private func startInterceptor() {
        isTrusted = true
        isRunning = interceptor?.start() ?? false
        if !isRunning {
            errorMessage = "Could not create the keyboard event tap. Remove and re-add the app under Privacy & Security > Accessibility."
        }
        onStateChange?()
    }

    /// Both files are replaced atomically, which shows up as a write to their folder.
    private func watchFiles() {
        let folder = Settings.fileURL.deletingLastPathComponent()
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func reload() {
        let (loaded, invalid) = Settings.load()
        invalidConfigLines = invalid
        isReloading = true
        settings = loaded
        isReloading = false
        log = Self.readLog()
        onLogChange?()
    }

    private static func appendLog(key: Int64, elapsed: UInt64) {
        var entries = readLog()
        entries.insert(LogEntry(date: Date(), key: key, elapsed: elapsed), at: 0)
        writeLog(Array(entries.prefix(1000)))
    }

    private static func readLog() -> [LogEntry] {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ")
            guard parts.count == 3, let time = Double(parts[0]), let key = Int64(parts[1]), let elapsed = UInt64(parts[2]) else { return nil }
            return LogEntry(date: Date(timeIntervalSince1970: time), key: key, elapsed: elapsed)
        }
    }

    private static func writeLog(_ entries: [LogEntry]) {
        let text = entries.map { "\($0.date.timeIntervalSince1970) \($0.key) \($0.elapsed)\n" }.joined()
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: logURL, atomically: true, encoding: .utf8)
    }
}
