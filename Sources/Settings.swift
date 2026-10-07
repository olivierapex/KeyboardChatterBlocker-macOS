import Foundation

enum MeasureFrom: String, CaseIterable, Sendable {
    case press = "Press"
    case release = "Release"
}

struct Settings: Equatable, Sendable {
    var isEnabled = true
    var globalChatter: UInt64 = 100
    var minimumChatterTime: UInt64 = 0
    var measureFrom = MeasureFrom.press
    var otherKeyResetsTimeout = false
    var excludeInjected = false
    var keyThresholds: [Int64: UInt64] = [:]

    static let fileURL = URL.applicationSupportDirectory.appending(path: "KeyboardChatterBlocker/config.txt", directoryHint: .notDirectory)

    /// Returns the loaded settings and the config lines that could not be applied.
    static func load() -> (Settings, [String]) {
        var settings = Settings()
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return (settings, [])
        }
        var invalid: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            if !settings.apply(line) {
                invalid.append(line)
            }
        }
        return (settings, invalid)
    }

    mutating func apply(_ line: String) -> Bool {
        guard let colon = line.firstIndex(of: ":") else {
            return false
        }
        let name = line[..<colon].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        let flag = value.lowercased() == "true"
        if name.hasPrefix("key.") {
            guard let key = KeyNames.code(String(name.dropFirst("key.".count))), let ms = UInt64(value) else {
                return false
            }
            keyThresholds[key] = ms
            return true
        }
        switch name {
        case "is_enabled":
            isEnabled = flag
        case "global_chatter":
            guard let ms = UInt64(value) else { return false }
            globalChatter = ms
        case "minimum_chatter_time":
            guard let ms = UInt64(value) else { return false }
            minimumChatterTime = ms
        case "measure_from":
            guard let mode = MeasureFrom.allCases.first(where: { $0.rawValue.lowercased() == value.lowercased() }) else { return false }
            measureFrom = mode
        case "other_key_resets_timeout":
            otherKeyResetsTimeout = flag
        case "exclude_injected":
            excludeInjected = flag
        default:
            return false
        }
        return true
    }

    var configString: String {
        var result = "# KeyboardChatterBlocker configuration file (macOS)\n\n"
        result += "is_enabled: \(isEnabled)\n"
        result += "global_chatter: \(globalChatter)\n"
        result += "minimum_chatter_time: \(minimumChatterTime)\n"
        result += "measure_from: \(measureFrom.rawValue)\n"
        result += "other_key_resets_timeout: \(otherKeyResetsTimeout)\n"
        result += "exclude_injected: \(excludeInjected)\n\n"
        for (key, ms) in keyThresholds.sorted(by: { $0.key < $1.key }) {
            result += "key.\(KeyNames.name(key)): \(ms)\n"
        }
        return result
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try configString.write(to: Self.fileURL, atomically: true, encoding: .utf8)
    }
}
