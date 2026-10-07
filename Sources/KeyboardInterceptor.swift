import CoreGraphics
import Foundation

/// Global keyboard event tap, the macOS counterpart of the Windows low-level keyboard hook.
final class KeyboardInterceptor: @unchecked Sendable {
    private let blocker: KeyBlocker
    private var tap: CFMachPort?

    init(blocker: KeyBlocker) {
        self.blocker = blocker
    }

    /// Fails when the app has not been granted Accessibility permission.
    func start() -> Bool {
        if tap != nil {
            return true
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                Unmanaged<KeyboardInterceptor>.fromOpaque(refcon!).takeUnretainedValue().handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        // A dedicated thread keeps typing responsive even when the UI is busy.
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "KeyboardChatterBlocker.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown, .keyUp:
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1_000_000
            let isInjected = event.getIntegerValueField(.eventSourceStateID) != Int64(CGEventSourceStateID.hidSystemState.rawValue)
            if type == .keyUp {
                blocker.keyUp(key, now: now, isInjected: isInjected)
            } else if !blocker.allowKeyDown(key, now: now, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0, isInjected: isInjected) {
                return nil
            }
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}
