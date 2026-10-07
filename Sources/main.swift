import AppKit

MainActor.assumeIsolated {
    if CommandLine.arguments.contains(AppModel.backgroundArgument) {
        // No AppKit UI at all, which keeps the always-running process at a few MB.
        let model = AppModel(intercepts: true)
        model.start()
        withExtendedLifetime(model) { dispatchMain() }
    } else {
        let delegate = SettingsAppDelegate()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
    }
}
