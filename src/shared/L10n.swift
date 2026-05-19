import Foundation

/// Cat Bedtime localization — follows system preferred languages.
enum L10n {
    private static var catalog: [String: [String: String]] = [:]
    private static var loaded = false

    static let supported = ["zh-Hans", "zh-Hant", "en", "ja", "ko"]
    static let defaultLang = "en"

    static var currentLanguage: String = {
        resolveLanguage()
    }()

    static var locale: Locale {
        switch currentLanguage {
        case "zh-Hans": return Locale(identifier: "zh_CN")
        case "zh-Hant": return Locale(identifier: "zh_TW")
        case "ja": return Locale(identifier: "ja_JP")
        case "ko": return Locale(identifier: "ko_KR")
        default: return Locale(identifier: "en_US")
        }
    }

    // MARK: - Public API

    static func t(_ key: String) -> String {
        loadIfNeeded()
        if let entry = catalog[key], let value = entry[currentLanguage] ?? entry[Self.defaultLang] {
            return value
        }
        return key
    }

    static func tf(_ key: String, _ args: CVarArg...) -> String {
        let template = t(key)
        guard !args.isEmpty else { return template }
        return String(format: template, locale: locale, arguments: args)
    }

    /// SwiftUI-friendly localized string (replaces %@ with String args, %d with Int)
    static func ts(_ key: String, _ args: String...) -> String {
        var result = t(key)
        for arg in args {
            if let range = result.range(of: "%@") {
                result.replaceSubrange(range, with: arg)
            } else if let range = result.range(of: "%s") {
                result.replaceSubrange(range, with: arg)
            }
        }
        return result
    }

    static var pledgePhrase: String { t("pledge.required_phrase") }

    static func dayShort(_ index: Int) -> String { t("day.short.\(index)") }
    static func dayFull(_ index: Int) -> String { t("day.full.\(index)") }

    static func daysSummary(sorted: [String], useShort: Bool = false) -> String {
        if sorted == ["1", "2", "3", "4", "5", "6", "7"] { return t("days.every_day") }
        if sorted.isEmpty { return t("days.none") }
        if sorted == ["1", "2", "3", "4", "5"] { return t("days.weekdays") }
        let sep = t("days.list_sep")
        let lang = currentLanguage
        if lang == "en" || lang == "ja" || lang == "ko" {
            let names = sorted.compactMap { Int($0) }.map { useShort ? dayShort($0) : dayFull($0) }
            return names.joined(separator: sep)
        }
        // zh: 周一、周三
        let names = sorted.compactMap { Int($0) }.map { dayShort($0) }
        if lang == "zh-Hant" {
            return "週" + names.joined(separator: sep)
        }
        return "周" + names.joined(separator: sep)
    }

    static func countdownUntilWakeup(hours: Int, minutes: Int) -> String {
        if hours > 0 {
            return tf("lock.countdown_hours", hours, minutes)
        }
        return tf("lock.countdown_minutes", minutes)
    }

    // MARK: - Loading

    private static func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let url = locateCatalogURL(),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = json["strings"] as? [String: [String: String]] else {
            return
        }
        catalog = strings
    }

    private static func locateCatalogURL() -> URL? {
        let name = "messages.json"
        var candidates: [URL] = []
        if let resource = Bundle.main.resourceURL {
            candidates.append(resource.appendingPathComponent("locales/\(name)"))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        candidates.append(home.appendingPathComponent(".timetosleep/locales/\(name)"))
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let binDir = executable.deletingLastPathComponent()
        candidates.append(binDir.appendingPathComponent("../locales/\(name)"))
        candidates.append(binDir.appendingPathComponent("../../locales/\(name)"))
        for url in candidates {
            let path = url.standardizedFileURL.path
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private static func resolveLanguage() -> String {
        if let override = ProcessInfo.processInfo.environment["ZZZ_LANG"],
           supported.contains(override) {
            return override
        }
        for tag in Locale.preferredLanguages {
            let norm = tag.replacingOccurrences(of: "_", with: "-")
            let lower = norm.lowercased()
            if lower.hasPrefix("zh-hant") || ["zh-tw", "zh-hk", "zh-mo"].contains(lower) {
                return "zh-Hant"
            }
            if lower.hasPrefix("zh-hans") || ["zh-cn", "zh-sg"].contains(lower) {
                return "zh-Hans"
            }
            if lower == "zh" || lower.hasPrefix("zh-") {
                return "zh-Hans"
            }
            if lower.hasPrefix("ja") { return "ja" }
            if lower.hasPrefix("ko") { return "ko" }
            if lower.hasPrefix("en") { return "en" }
        }
        return defaultLang
    }
}
