import Foundation

/// Decides which key presses to let through. Called from the event tap thread, configured from the main thread.
final class KeyBlocker: @unchecked Sendable {
    private let lock = NSLock()
    private var settings: Settings
    private var lastPressTime: [Int64: UInt64] = [:]
    private var lastReleaseTime: [Int64: UInt64] = [:]
    private var keysDown: Set<Int64> = []
    private var keysDownBlocked: Set<Int64> = []
    private var lastPressed: Int64 = -1

    /// Receives the key code and the elapsed milliseconds of each blocked press. Set before the tap starts.
    var onBlocked: (@Sendable (Int64, UInt64) -> Void)?

    init(settings: Settings) {
        self.settings = settings
    }

    func update(_ settings: Settings) {
        lock.withLock { self.settings = settings }
    }

    func allowKeyDown(_ key: Int64, now: UInt64, isRepeat: Bool, isInjected: Bool) -> Bool {
        let blockedAfter: UInt64? = lock.withLock {
            guard settings.isEnabled, !(settings.excludeInjected && isInjected) else {
                return nil
            }
            let keyLimit = settings.keyThresholds[key]
            if !settings.otherKeyResetsTimeout && settings.globalChatter == 0 && keyLimit == nil {
                return nil
            }
            // A held key is not chatter.
            if isRepeat || keysDown.contains(key) {
                return nil
            }
            keysDown.insert(key)
            let last = (settings.measureFrom == .release ? lastReleaseTime[key] : lastPressTime[key]) ?? 0
            if settings.otherKeyResetsTimeout {
                let isOtherKey = key != lastPressed
                lastPressed = key
                if isOtherKey {
                    lastPressTime[key] = now
                    return nil
                }
            }
            if last > now {
                lastPressTime[key] = now
                return nil
            }
            let elapsed = now - last
            if elapsed >= (keyLimit ?? settings.globalChatter) || elapsed < settings.minimumChatterTime {
                lastPressTime[key] = now
                return nil
            }
            keysDownBlocked.insert(key)
            return elapsed
        }
        guard let blockedAfter else {
            return true
        }
        onBlocked?(key, blockedAfter)
        return false
    }

    /// Key-ups are always let through, as on Windows: a stray key-up is harmless.
    func keyUp(_ key: Int64, now: UInt64, isInjected: Bool) {
        lock.withLock {
            if settings.excludeInjected && isInjected {
                return
            }
            keysDown.remove(key)
            if keysDownBlocked.remove(key) == nil {
                lastReleaseTime[key] = now
            }
        }
    }
}
