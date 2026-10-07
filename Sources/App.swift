import AppKit
import SwiftUI

@main
struct KeyboardChatterBlockerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: !model.isRunning ? "exclamationmark.triangle" : model.settings.isEnabled ? "keyboard.fill" : "keyboard")
        }
        Window("Keyboard Chatter Blocker", id: "main") {
            MainView(model: model)
        }
        .defaultLaunchBehavior(.suppressed)
    }
}

struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Enabled", isOn: $model.settings.isEnabled)
        if !model.isRunning {
            Text("Waiting for Accessibility permission")
            Button("Open Accessibility Settings…") { model.openAccessibilitySettings() }
        }
        Divider()
        Button("Open Keyboard Chatter Blocker…") {
            NSApp.activate()
            openWindow(id: "main")
        }
        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

enum Pane: Hashable {
    case general, keys, log
}

struct MainView: View {
    @Bindable var model: AppModel
    @State private var pane = Pane.general

    var body: some View {
        TabView(selection: $pane) {
            Tab("General", systemImage: "gearshape", value: .general) {
                GeneralView(model: model)
            }
            Tab("Configure Keys", systemImage: "keyboard", value: .keys) {
                KeysView(model: model)
            }
            Tab("Chatter Log", systemImage: "list.bullet", value: .log) {
                ChatterLogView(model: model) { pane = .keys }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

struct GeneralView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: $model.settings.isEnabled)
                TextField("Global chatter threshold (ms)", value: $model.settings.globalChatter, format: .number)
                TextField("Minimum chatter time (ms)", value: $model.settings.minimumChatterTime, format: .number)
                Picker("Measure from", selection: $model.settings.measureFrom) {
                    ForEach(MeasureFrom.allCases, id: \.self) { Text($0.rawValue) }
                }
                Toggle("Other key resets timeout", isOn: $model.settings.otherKeyResetsTimeout)
                Toggle("Exclude injected events", isOn: $model.settings.excludeInjected)
            }
            Section {
                if model.isRunning {
                    Label("Intercepting keyboard events", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Waiting for Accessibility permission", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Open Accessibility Settings") { model.openAccessibilitySettings() }
                }
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                if !model.invalidConfigLines.isEmpty {
                    Text("Ignored config lines: \(model.invalidConfigLines.joined(separator: ", "))").foregroundStyle(.red)
                }
                Button("Show Config File in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Settings.fileURL])
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct KeyRow: Identifiable {
    let key: Int64
    var id: Int64 { key }
}

struct KeysView: View {
    @Bindable var model: AppModel
    @State private var isCapturing = false

    var body: some View {
        VStack(alignment: .leading) {
            Table(model.keyRows.map { KeyRow(key: $0.key) }) {
                TableColumn("Key") { row in
                    Text(KeyNames.name(row.key))
                }
                TableColumn("Chatter Threshold (ms)") { row in
                    TextField("", value: Binding(
                        get: { model.settings.keyThresholds[row.key] ?? model.settings.globalChatter },
                        set: { model.settings.keyThresholds[row.key] = $0 }
                    ), format: .number)
                }
                TableColumn("") { row in
                    Button("Remove") { model.settings.keyThresholds[row.key] = nil }
                }
                .width(80)
            }
            HStack {
                Button("Add Key…") { isCapturing = true }
                Spacer()
                Text("Keys not listed use the global threshold.").foregroundStyle(.secondary)
            }
        }
        .padding()
        .sheet(isPresented: $isCapturing) {
            KeyCaptureView { key in
                model.addKey(key)
                isCapturing = false
            }
        }
    }
}

struct KeyCaptureView: View {
    let onCapture: (Int64) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 16) {
            Text("Press the key to add").font(.headline)
            Button("Cancel") { dismiss() }
        }
        .padding(24)
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                onCapture(Int64(event.keyCode))
                return nil
            }
        }
        .onDisappear {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

struct ChatterLogView: View {
    @Bindable var model: AppModel
    let onConfigure: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Table(model.log) {
                TableColumn("Time") { entry in
                    Text(entry.date, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute().second())
                }
                TableColumn("Key") { entry in
                    Text(KeyNames.name(entry.key))
                }
                TableColumn("Delay (ms)") { entry in
                    Text(entry.elapsed, format: .number)
                }
                TableColumn("") { entry in
                    Button("Configure") {
                        model.addKey(entry.key)
                        onConfigure()
                    }
                }
                .width(90)
            }
            HStack {
                Text("Blocked presses, newest first.").foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { model.log.removeAll() }
            }
        }
        .padding()
    }
}
