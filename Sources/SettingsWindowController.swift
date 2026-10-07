import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let model: AppModel
    private let onClose: () -> Void
    private let tabView = NSTabView()

    private let enabledBox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let globalField = SettingsWindowController.numberField()
    private let minimumField = SettingsWindowController.numberField()
    private let measurePopup = NSPopUpButton()
    private let otherKeyBox = NSButton(checkboxWithTitle: "Other key resets timeout", target: nil, action: nil)
    private let injectedBox = NSButton(checkboxWithTitle: "Exclude injected events", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let accessibilityButton = NSButton(title: "Open Accessibility Settings", target: nil, action: nil)
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    private let keysTable = NSTableView()
    private let logTable = NSTableView()
    private var keyRows: [Int64] = []
    private var captureMonitor: Any?
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm:ss"
        return formatter
    }()

    init(model: AppModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 420), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        window.title = "Keyboard Chatter Blocker"
        window.minSize = NSSize(width: 480, height: 360)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        for (title, view) in [("General", generalView()), ("Configure Keys", keysView()), ("Chatter Log", logView())] {
            let item = NSTabViewItem()
            item.label = title
            item.view = view
            tabView.addTabViewItem(item)
        }
        window.contentView = tabView
        window.center()
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func windowWillClose(_ notification: Notification) {
        stopCapture()
        onClose()
    }

    func refresh() {
        let settings = model.settings
        enabledBox.state = settings.isEnabled ? .on : .off
        if globalField.currentEditor() == nil {
            globalField.integerValue = Int(settings.globalChatter)
        }
        if minimumField.currentEditor() == nil {
            minimumField.integerValue = Int(settings.minimumChatterTime)
        }
        measurePopup.selectItem(withTitle: settings.measureFrom.rawValue)
        otherKeyBox.state = settings.otherKeyResetsTimeout ? .on : .off
        injectedBox.state = settings.excludeInjected ? .on : .off
        if model.isRunning {
            statusLabel.stringValue = "Blocking chatter in the background"
        } else if !model.isTrusted {
            statusLabel.stringValue = "Waiting for Accessibility permission"
        } else {
            statusLabel.stringValue = "The background blocker isn't running. Run install.sh again, or log out and back in."
        }
        statusLabel.textColor = model.isRunning ? .systemGreen : .systemOrange
        accessibilityButton.isHidden = model.isRunning || model.isTrusted
        var errors: [String] = []
        if let error = model.errorMessage {
            errors.append(error)
        }
        if !model.invalidConfigLines.isEmpty {
            errors.append("Ignored config lines: \(model.invalidConfigLines.joined(separator: ", "))")
        }
        errorLabel.stringValue = errors.joined(separator: "\n")
        errorLabel.isHidden = errors.isEmpty
        keyRows = settings.keyThresholds.keys.sorted()
        keysTable.reloadData()
    }

    func refreshLog() {
        logTable.reloadData()
    }

    // MARK: Tabs

    private func generalView() -> NSView {
        for control in [enabledBox, otherKeyBox, injectedBox, globalField, minimumField, measurePopup] as [NSControl] {
            control.target = self
            control.action = #selector(generalChanged)
        }
        measurePopup.addItems(withTitles: MeasureFrom.allCases.map(\.rawValue))
        accessibilityButton.target = self
        accessibilityButton.action = #selector(openAccessibilitySettings)
        errorLabel.textColor = .systemRed
        let grid = NSGridView(views: [
            [NSGridCell.emptyContentView, enabledBox],
            [NSTextField(labelWithString: "Global chatter threshold (ms):"), globalField],
            [NSTextField(labelWithString: "Minimum chatter time (ms):"), minimumField],
            [NSTextField(labelWithString: "Measure from:"), measurePopup],
            [NSGridCell.emptyContentView, otherKeyBox],
            [NSGridCell.emptyContentView, injectedBox],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 10
        let configButton = NSButton(title: "Show Config File in Finder", target: self, action: #selector(showConfigFile))
        let stack = NSStackView(views: [grid, statusLabel, accessibilityButton, errorLabel, configButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        return Self.container(stack, fill: false)
    }

    private func keysView() -> NSView {
        let scroll = Self.tableScroll(keysTable, columns: [("key", "Key", 200), ("ms", "Chatter Threshold (ms)", 180)])
        keysTable.dataSource = self
        keysTable.delegate = self
        keysTable.allowsMultipleSelection = true
        let buttons = NSStackView(views: [
            NSButton(title: "Add Key…", target: self, action: #selector(addKey)),
            NSButton(title: "Remove", target: self, action: #selector(removeKeys)),
            NSTextField(labelWithString: "Double-click a threshold to edit it. Keys not listed use the global threshold."),
        ])
        return Self.container(Self.vertical([scroll, buttons]), fill: true)
    }

    private func logView() -> NSView {
        let scroll = Self.tableScroll(logTable, columns: [("time", "Time", 130), ("key", "Key", 150), ("elapsed", "Delay (ms)", 90)])
        logTable.dataSource = self
        logTable.delegate = self
        logTable.allowsMultipleSelection = true
        logTable.target = self
        logTable.doubleAction = #selector(configureLoggedKeys)
        let buttons = NSStackView(views: [
            NSButton(title: "Configure Key", target: self, action: #selector(configureLoggedKeys)),
            NSButton(title: "Clear", target: self, action: #selector(clearLog)),
            NSTextField(labelWithString: "Blocked presses, newest first."),
        ])
        return Self.container(Self.vertical([scroll, buttons]), fill: true)
    }

    // MARK: Actions

    @objc private func generalChanged() {
        var settings = model.settings
        settings.isEnabled = enabledBox.state == .on
        settings.globalChatter = UInt64(max(0, globalField.integerValue))
        settings.minimumChatterTime = UInt64(max(0, minimumField.integerValue))
        settings.measureFrom = MeasureFrom.allCases[max(0, measurePopup.indexOfSelectedItem)]
        settings.otherKeyResetsTimeout = otherKeyBox.state == .on
        settings.excludeInjected = injectedBox.state == .on
        model.settings = settings
    }

    @objc private func openAccessibilitySettings() {
        model.openAccessibilitySettings()
    }

    @objc private func showConfigFile() {
        NSWorkspace.shared.activateFileViewerSelecting([Settings.fileURL])
    }

    @objc private func thresholdEdited(_ sender: NSTextField) {
        let row = keysTable.row(for: sender)
        guard row >= 0, row < keyRows.count else { return }
        model.settings.keyThresholds[keyRows[row]] = UInt64(max(0, sender.integerValue))
    }

    @objc private func addKey() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Press the key to add"
        alert.addButton(withTitle: "Cancel")
        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak alert] event in
            MainActor.assumeIsolated {
                self?.model.addKey(Int64(event.keyCode))
                if let alert {
                    window.endSheet(alert.window)
                }
            }
            return nil
        }
        alert.beginSheetModal(for: window) { [weak self] _ in
            self?.stopCapture()
        }
    }

    @objc private func removeKeys() {
        var settings = model.settings
        for row in keysTable.selectedRowIndexes where row < keyRows.count {
            settings.keyThresholds[keyRows[row]] = nil
        }
        model.settings = settings
    }

    @objc private func configureLoggedKeys() {
        let rows = logTable.clickedRow >= 0 ? IndexSet(integer: logTable.clickedRow) : logTable.selectedRowIndexes
        let keys = rows.filter { $0 < model.log.count }.map { model.log[$0].key }
        guard !keys.isEmpty else { return }
        keys.forEach(model.addKey)
        tabView.selectTabViewItem(at: 1)
    }

    @objc private func clearLog() {
        model.clearLog()
    }

    private func stopCapture() {
        if let captureMonitor {
            NSEvent.removeMonitor(captureMonitor)
            self.captureMonitor = nil
        }
    }

    // MARK: Tables

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === keysTable ? keyRows.count : model.log.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier else { return nil }
        let field = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField ?? {
            let field = NSTextField(labelWithString: "")
            field.identifier = identifier
            field.lineBreakMode = .byTruncatingTail
            return field
        }()
        if tableView === keysTable {
            let key = keyRows[row]
            if identifier.rawValue == "ms" {
                field.stringValue = String(model.settings.keyThresholds[key] ?? 0)
                field.isEditable = true
                field.formatter = Self.numberFormatter()
                field.target = self
                field.action = #selector(thresholdEdited)
            } else {
                field.stringValue = KeyNames.name(key)
            }
        } else {
            let entry = model.log[row]
            switch identifier.rawValue {
            case "time": field.stringValue = timeFormatter.string(from: entry.date)
            case "key": field.stringValue = KeyNames.name(entry.key)
            default: field.stringValue = String(entry.elapsed)
            }
        }
        return field
    }

    // MARK: Layout helpers

    private static func numberFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = 0
        formatter.allowsFloats = false
        return formatter
    }

    private static func numberField() -> NSTextField {
        let field = NSTextField(string: "")
        field.formatter = numberFormatter()
        field.cell?.sendsActionOnEndEditing = true
        field.widthAnchor.constraint(equalToConstant: 80).isActive = true
        return field
    }

    private static func tableScroll(_ table: NSTableView, columns: [(String, String, CGFloat)]) -> NSScrollView {
        for (identifier, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.usesAlternatingRowBackgroundColors = true
        table.style = .fullWidth
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        return scroll
    }

    private static func vertical(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        views.first?.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private static func container(_ content: NSView, fill: Bool) -> NSView {
        let container = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            fill
                ? content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
                : content.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16),
        ])
        return container
    }
}
