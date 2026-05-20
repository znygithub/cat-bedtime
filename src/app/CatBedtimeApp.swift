import Cocoa
import Darwin
import SwiftUI
import UserNotifications

// MARK: - Design Tokens (Lamplight)

enum Lamp {
    // Core palette
    static let nightDeep      = Color(red: 15/255, green: 22/255, blue: 19/255)
    static let nightSurface   = Color(red: 26/255, green: 35/255, blue: 32/255)
    static let nightElevated  = Color(red: 29/255, green: 42/255, blue: 39/255)
    static let amberMoon      = Color(red: 240/255, green: 197/255, blue: 94/255)
    static let tealTrust      = Color(red: 90/255, green: 181/255, blue: 165/255)
    static let sageOk         = Color(red: 108/255, green: 194/255, blue: 138/255)
    static let clayWarn       = Color(red: 217/255, green: 122/255, blue: 104/255)
    static let creamText      = Color(red: 242/255, green: 227/255, blue: 195/255)
    static let sandMuted      = Color(red: 176/255, green: 166/255, blue: 144/255)
    static let duskDim        = Color(red: 120/255, green: 111/255, blue: 99/255)
    static let ashGhost       = Color(red: 72/255, green: 66/255, blue: 58/255)

    // Glass layers
    static let glass1 = Color.white.opacity(0.04)
    static let glass2 = Color.white.opacity(0.07)
    static let glass3 = Color.white.opacity(0.12)

    // Borders
    static let borderSubtle  = Color.white.opacity(0.06)
    static let borderDefault = Color.white.opacity(0.08)
    static let borderHover   = Color.white.opacity(0.14)

    // NSColor equivalents for window background
    static let nsNightSurface = NSColor(red: 26/255, green: 35/255, blue: 32/255, alpha: 1)
    static let nsNightDeep    = NSColor(red: 15/255, green: 22/255, blue: 19/255, alpha: 1)

    // Rounded system font helper
    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Config Model

struct CatBedtimeConfig: Codable {
    var bedtime: String
    var wakeup: String
    var days: [String]
    var winddown_minutes: Int
    var activated_at: String
    var version: String

    static let defaultConfig = CatBedtimeConfig(
        bedtime: "23:00",
        wakeup: "07:00",
        days: ["1", "2", "3", "4", "5"],
        winddown_minutes: 15,
        activated_at: "",
        version: "1.0.0"
    )
}

// MARK: - ConfigManager

class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    private let zzzDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".timetosleep")
    private var configURL: URL {
        zzzDir.appendingPathComponent("config.json")
    }
    private var statsURL: URL {
        zzzDir.appendingPathComponent("stats.json")
    }
    private var skipURL: URL {
        zzzDir.appendingPathComponent("skip_tonight")
    }
    private var postponeURL: URL {
        zzzDir.appendingPathComponent("postpone_tonight")
    }
    private var onboardingInstallURL: URL {
        zzzDir.appendingPathComponent("onboarding_install_id")
    }

    @Published var config = CatBedtimeConfig.defaultConfig
    @Published var tonightPostponedBedtime: String?

    private let agentLabel = "com.timetosleep.daemon"
    private var plistPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist").path
    }

    init() {
        loadConfig()
        refreshTonightPostpone()
    }

    var configExists: Bool {
        FileManager.default.fileExists(atPath: configURL.path)
    }

    var shouldShowDashboardOnLaunch: Bool {
        configExists && completedOnboardingForCurrentInstall()
    }

    func loadConfig() {
        guard let data = try? Data(contentsOf: configURL),
              let cfg = try? JSONDecoder().decode(CatBedtimeConfig.self, from: data) else { return }
        config = cfg
    }

    func saveConfig() {
        ensureDir()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    func activateOnboarding() {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        config.activated_at = fmt.string(from: Date())
        config.version = "1.0.0"
        saveConfig()
        markOnboardingCompleteForCurrentInstall()
        initStats()
        installSchedule()
        NotificationScheduler.shared.requestPermission()
        NotificationScheduler.shared.clearPendingReminders()
    }

    private func currentInstallID() -> String {
        let bundleURL = Bundle.main.bundleURL
        let executableURL = Bundle.main.executableURL ?? bundleURL
        let attrs = (try? FileManager.default.attributesOfItem(atPath: executableURL.path)) ?? [:]
        let modified = attrs[.modificationDate] as? Date ?? Date.distantPast
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "\(bundleURL.path)|\(version)|\(Int(modified.timeIntervalSince1970))"
    }

    private func completedOnboardingForCurrentInstall() -> Bool {
        guard let data = try? Data(contentsOf: onboardingInstallURL),
              let saved = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return saved == currentInstallID()
    }

    private func markOnboardingCompleteForCurrentInstall() {
        ensureDir()
        try? "\(currentInstallID())\n".write(to: onboardingInstallURL, atomically: true, encoding: .utf8)
    }

    func updateConfigAndReschedule() {
        saveConfig()
        installSchedule(bedtimeForSchedule: effectiveBedtimeTonight())
        NotificationScheduler.shared.clearPendingReminders()
    }

    // MARK: Postpone tonight

    func effectiveBedtimeTonight() -> String {
        readPostponeTonight()?.bedtime ?? config.bedtime
    }

    func refreshTonightPostpone() {
        let hadStale = cleanupStalePostponeIfNeeded()
        tonightPostponedBedtime = readPostponeTonight()?.bedtime
        if hadStale {
            installSchedule(bedtimeForSchedule: config.bedtime)
        }
    }

    @discardableResult
    func postponeTonight(minutes delayMinutes: Int, reason: String) -> String? {
        guard delayMinutes > 0,
              let baseMin = minutes(from: effectiveBedtimeTonight()) else { return nil }

        ensureDir()
        let newMin = (baseMin + delayMinutes) % 1440
        let newBedtime = formatMinutes(newMin)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())
        let content = "\(today)\n\(newBedtime)\n\(reason)\n"
        try? content.write(to: postponeURL, atomically: true, encoding: .utf8)

        tonightPostponedBedtime = newBedtime
        DispatchQueue.global(qos: .utility).async { [self] in
            installSchedule(bedtimeForSchedule: newBedtime)
        }
        return newBedtime
    }

    private func readPostponeTonight() -> (bedtime: String, reason: String)? {
        guard let content = try? String(contentsOf: postponeURL, encoding: .utf8) else { return nil }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2 else { return nil }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())
        guard lines[0] == today else { return nil }

        let reason = lines.count > 2 ? lines[2] : ""
        return (lines[1], reason)
    }

    @discardableResult
    private func cleanupStalePostponeIfNeeded() -> Bool {
        guard FileManager.default.fileExists(atPath: postponeURL.path),
              let content = try? String(contentsOf: postponeURL, encoding: .utf8) else { return false }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let postponeDate = lines.first else { return false }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())
        guard postponeDate != today else { return false }

        try? FileManager.default.removeItem(at: postponeURL)
        return true
    }

    private func formatMinutes(_ totalMin: Int) -> String {
        let normalized = ((totalMin % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }

    // MARK: Stats

    func initStats() {
        ensureDir()
        guard !FileManager.default.fileExists(atPath: statsURL.path) else { return }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let now = fmt.string(from: Date())
        let json = "{\"records\":[],\"installed_at\":\"\(now)\"}"
        try? json.write(to: statsURL, atomically: true, encoding: .utf8)
    }

    // MARK: Skip tonight

    func writeSkipTonight(reason: String) {
        ensureDir()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())
        let content = "\(today)\n\(reason)\n"
        try? content.write(to: skipURL, atomically: true, encoding: .utf8)
    }

    // MARK: launchd schedule

    func installSchedule(bedtimeForSchedule: String? = nil) {
        let scheduleBedtime = bedtimeForSchedule ?? config.bedtime
        let daemonPath = findDaemonPath()
        let (hour, minute) = winddownStartTime(bedtime: scheduleBedtime)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let logPath = zzzDir.appendingPathComponent("daemon.log").path

        let plistDir = (plistPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: plistDir, withIntermediateDirectories: true)

        let plistXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(agentLabel)</string>

          <key>ProgramArguments</key>
          <array>
            <string>/bin/bash</string>
            <string>\(daemonPath)</string>
          </array>

          <key>StartCalendarInterval</key>
          <dict>
            <key>Hour</key>
            <integer>\(hour)</integer>
            <key>Minute</key>
            <integer>\(minute)</integer>
          </dict>

          <key>RunAtLoad</key>
          <true/>

          <key>StandardOutPath</key>
          <string>\(logPath)</string>
          <key>StandardErrorPath</key>
          <string>\(logPath)</string>

          <key>EnvironmentVariables</key>
          <dict>
            <key>HOME</key>
            <string>\(home)</string>
            <key>PATH</key>
            <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
          </dict>
        </dict>
        </plist>
        """

        try? plistXML.write(toFile: plistPath, atomically: true, encoding: .utf8)

        let gui = "gui/\(getuid())"
        // bootout existing (ignore errors)
        shellRun("/bin/launchctl", ["bootout", "\(gui)/\(agentLabel)"])
        // also remove legacy bootcheck
        shellRun("/bin/launchctl", ["bootout", "\(gui)/com.timetosleep.bootcheck"])
        let legacyPlist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.timetosleep.bootcheck.plist").path
        try? FileManager.default.removeItem(atPath: legacyPlist)
        // bootstrap new
        shellRun("/bin/launchctl", ["bootstrap", gui, plistPath])
    }

    // MARK: Helpers

    private func ensureDir() {
        try? FileManager.default.createDirectory(at: zzzDir, withIntermediateDirectories: true)
        let assetsDir = zzzDir.appendingPathComponent("assets")
        try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
    }

    private func findDaemonPath() -> String {
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("src/cli/daemon.sh").path,
           FileManager.default.fileExists(atPath: bundled) {
            return bundled
        }
        let installed = zzzDir.appendingPathComponent("src/cli/daemon.sh").path
        if FileManager.default.fileExists(atPath: installed) { return installed }
        // dev fallback: relative to binary
        let bundlePath = Bundle.main.bundlePath
        let devPath = (bundlePath as NSString)
            .deletingLastPathComponent + "/../src/cli/daemon.sh"
        let resolved = (devPath as NSString).standardizingPath
        if FileManager.default.fileExists(atPath: resolved) { return resolved }
        return installed
    }

    private func winddownStartTime(bedtime: String) -> (Int, Int) {
        let parts = bedtime.split(separator: ":")
        guard parts.count == 2,
              let bh = Int(parts[0]), let bm = Int(parts[1]) else { return (22, 45) }
        var startMin = bh * 60 + bm - config.winddown_minutes
        if startMin < 0 { startMin += 1440 }
        return (startMin / 60, startMin % 60)
    }

    private func shouldKickstartDaemonNow(bedtime: String, date: Date = Date()) -> Bool {
        guard let bedMin = minutes(from: bedtime),
              let wakeMin = minutes(from: config.wakeup) else { return false }

        let winddown = max(config.winddown_minutes, 1)
        let startMin = (bedMin - winddown + 1440) % 1440
        let nowMin = minutes(in: date)
        let today = isoWeekday(for: date)

        guard let sleepWeekday = catchupWeekday(
            nowMin: nowMin,
            bedMin: bedMin,
            wakeMin: wakeMin,
            startMin: startMin,
            today: today
        ) else { return false }

        return config.days.contains(String(sleepWeekday))
    }

    private func catchupWeekday(
        nowMin: Int,
        bedMin: Int,
        wakeMin: Int,
        startMin: Int,
        today: Int
    ) -> Int? {
        if time(nowMin, isInRangeFrom: startMin, to: bedMin) {
            return startMin > bedMin && nowMin >= startMin ? nextWeekday(today) : today
        }

        if time(nowMin, isInRangeFrom: bedMin, to: wakeMin) {
            return bedMin > wakeMin && nowMin < wakeMin ? previousWeekday(today) : today
        }

        return nil
    }

    private func minutes(from value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    private func minutes(in date: Date) -> Int {
        let cal = Calendar.current
        return cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
    }

    private func time(_ nowMin: Int, isInRangeFrom startMin: Int, to endMin: Int) -> Bool {
        if startMin < endMin {
            return nowMin >= startMin && nowMin < endMin
        }
        if startMin > endMin {
            return nowMin >= startMin || nowMin < endMin
        }
        return false
    }

    private func isoWeekday(for date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    private func previousWeekday(_ weekday: Int) -> Int {
        weekday == 1 ? 7 : weekday - 1
    }

    private func nextWeekday(_ weekday: Int) -> Int {
        weekday == 7 ? 1 : weekday + 1
    }

    @discardableResult
    private func shellRun(_ path: String, _ args: [String]) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus
    }
}

// MARK: - Notification Scheduler

final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

class NotificationScheduler {
    static let shared = NotificationScheduler()
    private let center = UNUserNotificationCenter.current()
    private let presenter = ForegroundNotificationPresenter()

    private init() {
        center.delegate = presenter
    }

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func clearPendingReminders() {
        center.getPendingNotificationRequests { [center] requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix("winddown-") }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    @discardableResult
    func sendImmediateNotification(title: String, subtitle: String, body: String) -> Bool {
        guard ensureNotificationAuthorization() else { return false }

        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        content.threadIdentifier = "cat-bedtime-winddown"

        let id = "daemon-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        let semaphore = DispatchSemaphore(value: 0)
        var succeeded = true

        center.add(request) { error in
            if let error = error {
                writeStderr("native notification failed: \(error.localizedDescription)")
                succeeded = false
            }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + 5) == .success else {
            writeStderr("native notification timed out")
            return false
        }
        return succeeded
    }

    private func ensureNotificationAuthorization() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var allowed = false
        var denialReason: String?
        let notificationCenter = center

        notificationCenter.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                allowed = true
            case .notDetermined:
                notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error = error {
                        denialReason = "notification authorization request failed: \(error.localizedDescription)"
                    } else if !granted {
                        denialReason = "notification authorization was not granted"
                    }
                    allowed = granted
                    semaphore.signal()
                }
                return
            case .denied:
                denialReason = "notification authorization denied"
                allowed = false
            @unknown default:
                denialReason = "notification authorization status is unsupported"
                allowed = false
            }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + 5) == .success else {
            writeStderr("notification settings lookup timed out")
            return false
        }
        if let denialReason {
            writeStderr(denialReason)
        }
        return allowed
    }
}

private enum NotificationCommand {
    static func exitIfRequested(arguments: [String] = CommandLine.arguments) {
        let args = Array(arguments.dropFirst())
        guard let mode = args.first, mode == "--notify" || mode == "--notify-l10n" else { return }

        L10n.prepareForAppLaunch()

        let title: String
        let subtitle: String
        let body: String

        if mode == "--notify-l10n" {
            guard args.count >= 5 else {
                writeStderr("usage: zzz-app --notify-l10n <titleKey> <subtitleKey> <subtitleArg|- > <bodyKey>")
                Darwin.exit(64)
            }
            title = L10n.t(args[1])
            if args[2] == "-" {
                subtitle = ""
            } else if let n = Int(args[3]) {
                subtitle = L10n.tf(args[2], n)
            } else {
                subtitle = L10n.t(args[2])
            }
            body = L10n.t(args[4])
        } else {
            guard args.count >= 4 else {
                writeStderr("usage: zzz-app --notify <title> <subtitle> <body>")
                Darwin.exit(64)
            }
            title = args[1]
            subtitle = args[2]
            body = args[3]
        }

        let ok = NotificationScheduler.shared.sendImmediateNotification(
            title: title,
            subtitle: subtitle,
            body: body
        )
        Darwin.exit(ok ? 0 : 1)
    }
}

private func writeStderr(_ message: String) {
    if let data = "\(message)\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

// MARK: - Navigation

enum AppScreen: Int, CaseIterable {
    case welcome, config, agreement, lockPreview, dashboard
}

class AppState: ObservableObject {
    @Published var screen: AppScreen = .welcome
}

class WindowSizeStore: ObservableObject {
    static let shared = WindowSizeStore()
    @Published var size = CGSize(width: 420, height: 560)
}

// MARK: - Cat Image Loader

func loadCatImage() -> NSImage? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let binDir = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
    var paths: [String] = []
    if let bundled = Bundle.main.resourceURL?
        .appendingPathComponent("assets/猫猫形象图.png").path {
        paths.append(bundled)
    }
    paths.append("\(home)/.timetosleep/assets/猫猫形象图.png")
    // dev: bin/Cat Bedtime.app -> bin/ -> project root/assets/
    paths.append((binDir as NSString).appendingPathComponent("../assets/猫猫形象图.png"))
    for p in paths {
        let resolved = (p as NSString).standardizingPath
        if let img = NSImage(contentsOfFile: resolved) { return img }
    }
    return nil
}

// MARK: - Progress Bar

struct ProgressDots: View {
    let total: Int
    let current: Int // 1-based

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Lamp.amberMoon : Lamp.glass2)
                    .frame(height: 5)
                    .shadow(color: i == current ? Lamp.amberMoon.opacity(0.15) : .clear, radius: 7)
            }
        }
        .frame(maxWidth: 240, alignment: .leading)
    }
}

// MARK: - Day Toggle Button

struct DayToggle: View {
    let label: String
    let isOn: Bool
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Lamp.rounded(compact ? 11 : 12, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(compact ? 0.65 : 0.72)
                .allowsTightening(true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, compact ? 2 : 5)
                .frame(height: compact ? 30 : 42)
                .background(isOn ? Lamp.amberMoon : Lamp.glass1)
                .foregroundColor(isOn ? Lamp.nightDeep : Lamp.duskDim)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isOn ? Color.clear : Lamp.borderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Primary Button Style

struct LampButtonStyle: ButtonStyle {
    var block = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Lamp.rounded(15, weight: .bold))
            .foregroundColor(Lamp.nightDeep)
            .padding(.vertical, 14)
            .padding(.horizontal, block ? 0 : 32)
            .frame(maxWidth: block ? .infinity : nil)
            .background(Lamp.amberMoon)
            .cornerRadius(14)
            .shadow(color: Lamp.amberMoon.opacity(0.12), radius: 10)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        configuration.label
            .font(Lamp.rounded(13, weight: .bold))
            .foregroundColor(Lamp.sandMuted)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? Lamp.glass2 : Lamp.glass1.opacity(0.001))
            .cornerRadius(10)
            .contentShape(shape)
            .overlay(
                shape.stroke(Lamp.borderDefault, lineWidth: 1)
            )
    }
}

// MARK: - Day Grid

private let dayKeys = ["1", "2", "3", "4", "5", "6", "7"]

struct DayGrid: View {
    @Binding var activeDays: Set<String>
    var compact: Bool = false

    private var usesShortLabels: Bool {
        compact || L10n.currentLanguage == "en"
    }

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(dayKeys, id: \.self) { key in
                let idx = Int(key) ?? 1
                let fullLabel = L10n.dayFull(idx)
                DayToggle(
                    label: usesShortLabels ? L10n.dayShort(idx) : fullLabel,
                    isOn: activeDays.contains(key),
                    compact: compact
                ) {
                    if activeDays.contains(key) {
                        activeDays.remove(key)
                    } else {
                        activeDays.insert(key)
                    }
                }
                .accessibilityLabel(Text(fullLabel))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - S1: Welcome

struct WelcomeView: View {
    @EnvironmentObject var state: AppState
    let catImage: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressDots(total: 3, current: 1)
                .padding(.bottom, 18)

            Text(L10n.t("welcome.title"))
                .font(Lamp.rounded(28, weight: .bold))
                .foregroundColor(Lamp.creamText)
                .padding(.bottom, 8)

            Text(L10n.t("welcome.body"))
                .font(Lamp.rounded(15, weight: .medium))
                .foregroundColor(Lamp.sandMuted)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if let img = catImage {
                    HStack {
                        Spacer()
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 220)
                        Spacer()
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Spacer()
                Button(L10n.t("welcome.cta")) { state.screen = .config }
                    .buttonStyle(LampButtonStyle())
                Spacer()
            }
        }
        .padding(.top, 28)
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - S2: Schedule Config

struct ScheduleConfigView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var mgr: ConfigManager
    @Binding var activeDays: Set<String>
    @Binding var bedtime: Date
    @Binding var wakeup: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressDots(total: 3, current: 2)
                .padding(.bottom, 24)

            // Sleep time
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("config.bedtime.title"))
                    .font(Lamp.rounded(17, weight: .semibold))
                    .foregroundColor(Lamp.creamText)
                Text(L10n.t("config.bedtime.hint"))
                    .font(Lamp.rounded(13))
                    .foregroundColor(Lamp.duskDim)
                    .italic()
                    .padding(.bottom, 12)
                DatePicker("", selection: $bedtime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .environment(\.locale, L10n.locale)
                    .colorScheme(.dark)
                    .accentColor(Lamp.amberMoon)
            }
            .padding(.bottom, 22)

            // Wake time
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("config.wakeup.title"))
                    .font(Lamp.rounded(17, weight: .semibold))
                    .foregroundColor(Lamp.creamText)
                Text(L10n.t("config.wakeup.hint"))
                    .font(Lamp.rounded(13))
                    .foregroundColor(Lamp.duskDim)
                    .italic()
                    .padding(.bottom, 12)
                DatePicker("", selection: $wakeup, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .environment(\.locale, L10n.locale)
                    .colorScheme(.dark)
                    .accentColor(Lamp.amberMoon)
            }
            .padding(.bottom, 22)

            // Day selection
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("config.days.title"))
                    .font(Lamp.rounded(17, weight: .semibold))
                    .foregroundColor(Lamp.creamText)
                    .padding(.bottom, 8)
                DayGrid(activeDays: $activeDays)
                    .frame(maxWidth: .infinity)
            }

            Spacer()

            Button(L10n.t("config.confirm")) {
                syncConfigFromPickers()
                state.screen = .agreement
            }
            .buttonStyle(LampButtonStyle(block: true))
            .padding(.top, 8)
        }
        .padding(.top, 52)
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func syncConfigFromPickers() {
        mgr.config.bedtime = formatTime(bedtime)
        mgr.config.wakeup = formatTime(wakeup)
        mgr.config.days = activeDays.sorted()
    }
}

// MARK: - S3: Agreement

struct AgreementView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var mgr: ConfigManager
    @State private var pledge = ""
    @State private var attempts = 0
    @State private var message = ""
    @State private var messageColor = Lamp.duskDim
    @State private var inputBorderColor = Lamp.borderDefault
    @State private var shaking = false

    private var requiredPhrase: String { L10n.pledgePhrase }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressDots(total: 3, current: 3)
                .padding(.bottom, 24)

            Text(L10n.t("agreement.title"))
                .font(Lamp.rounded(22, weight: .bold))
                .foregroundColor(Lamp.creamText)
                .padding(.bottom, 2)
            Text(L10n.t("agreement.subtitle"))
                .font(Lamp.rounded(13))
                .foregroundColor(Lamp.duskDim)
                .padding(.bottom, 18)

            // Summary card
            VStack(spacing: 0) {
                summaryRow(icon: "🛏️", label: L10n.t("agreement.sleep"), value: mgr.config.bedtime)
                summaryRow(icon: "🌅", label: L10n.t("agreement.leave"), value: mgr.config.wakeup)
                summaryRow(icon: "📅", label: L10n.t("agreement.days"), value: daysDisplayText())
                summaryRow(icon: "🔔", label: L10n.t("agreement.reminder"), value: L10n.tf("agreement.reminder_value", 15), showBorder: false)
            }
            .padding(16)
            .background(Lamp.glass1)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Lamp.borderDefault, lineWidth: 1)
            )
            .padding(.bottom, 16)

            // Pledge
            Text(L10n.ts("agreement.pledge_prompt", requiredPhrase))
                .font(Lamp.rounded(13, weight: .medium))
                .foregroundColor(Lamp.amberMoon)
                .textSelection(.enabled)
                .padding(.bottom, 10)

            TextField(L10n.t("agreement.pledge_placeholder"), text: $pledge, onCommit: tryConfirm)
                .textFieldStyle(.plain)
                .font(Lamp.rounded(15, weight: .medium))
                .foregroundColor(Lamp.creamText)
                .padding(12)
                .background(Lamp.glass1)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(inputBorderColor, lineWidth: 1)
                )
                .offset(x: shaking ? -3 : 0)
                .padding(.bottom, 4)

            Text(message)
                .font(Lamp.rounded(11))
                .foregroundColor(messageColor)
                .frame(height: 16)
                .padding(.bottom, 20)

            Spacer()

            Button(L10n.t("agreement.confirm")) { tryConfirm() }
                .buttonStyle(LampButtonStyle(block: true))
        }
        .padding(.top, 52)
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func tryConfirm() {
        if pledge.trimmingCharacters(in: .whitespaces) == requiredPhrase {
            inputBorderColor = Lamp.sageOk
            message = L10n.t("agreement.confirmed")
            messageColor = Lamp.sageOk
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                mgr.activateOnboarding()
                state.screen = .lockPreview
            }
        } else {
            attempts += 1
            inputBorderColor = Lamp.clayWarn
            messageColor = Lamp.clayWarn
            if attempts >= 3 {
                message = L10n.t("agreement.wrong_final")
            } else {
                message = L10n.tf("agreement.wrong_attempts", 3 - attempts)
            }
            // shake
            withAnimation(.linear(duration: 0.07).repeatCount(5, autoreverses: true)) {
                shaking = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                shaking = false
                inputBorderColor = Lamp.borderDefault
            }
        }
    }

    private func daysDisplayText() -> String {
        L10n.daysSummary(sorted: mgr.config.days.sorted())
    }

    private func summaryRow(icon: String, label: String, value: String, showBorder: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(icon)
                    .frame(width: 20)
                Text(label)
                    .font(Lamp.rounded(14))
                    .foregroundColor(Lamp.sandMuted)
                Spacer()
                Text(value)
                    .font(Lamp.rounded(14, weight: .bold))
                    .foregroundColor(Lamp.creamText)
            }
            .padding(.vertical, 8)
            if showBorder {
                Divider().background(Lamp.borderSubtle)
            }
        }
    }
}

// MARK: - S4: Lock Preview (launch zzz-overlay as child process)

struct LockPreviewView: View {
    @EnvironmentObject var state: AppState
    let catImage: NSImage?

    private let previewDurationSeconds = 18

    @State private var overlayProcess: Process?
    @State private var didAdvance = false

    var body: some View {
        ZStack {
            Lamp.nightSurface
            VStack(spacing: 12) {
                Spacer()
                Text(L10n.t("lock_preview.playing"))
                    .font(Lamp.rounded(14, weight: .medium))
                    .foregroundColor(Lamp.sandMuted)
                Spacer()
            }
        }
        .onAppear { launchOverlay() }
        .onDisappear { killOverlay() }
    }

    private func findOverlayBin() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let binDir = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
        var candidates: [String] = []
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("bin/zzz-overlay").path {
            candidates.append(bundled)
        }
        candidates.append("\(home)/.timetosleep/bin/zzz-overlay")
        // dev: bin/Cat Bedtime.app -> bin/zzz-overlay
        candidates.append((binDir as NSString).appendingPathComponent("zzz-overlay"))
        for p in candidates {
            let resolved = (p as NSString).standardizingPath
            if FileManager.default.isExecutableFile(atPath: resolved) {
                return resolved
            }
        }
        return nil
    }

    private func launchOverlay() {
        guard let path = findOverlayBin() else {
            // No overlay binary found, skip to dashboard
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                advanceToDashboard()
            }
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["--preview-exit-on-esc", "--preview-duration", "\(previewDurationSeconds)"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.terminationHandler = { _ in
            DispatchQueue.main.async {
                advanceToDashboard()
            }
        }
        try? proc.run()
        overlayProcess = proc

        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(previewDurationSeconds)) {
            advanceToDashboard()
        }
    }

    private func killOverlay() {
        guard let proc = overlayProcess else { return }
        proc.terminationHandler = nil
        if proc.isRunning {
            proc.terminate()
        }
        overlayProcess = nil
    }

    private func advanceToDashboard() {
        guard !didAdvance else { return }
        didAdvance = true
        killOverlay()
        state.screen = .dashboard
        resizeWindow(width: 520, height: 600)
    }
}

// MARK: - Dashboard layout helpers

private struct DashboardCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - S5: Dashboard

struct DashboardView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var mgr: ConfigManager
    @Binding var activeDays: Set<String>
    @Binding var bedtime: Date
    @Binding var wakeup: Date
    @State private var showDelay = false
    @State private var savedNotice = false
    @State private var delayNotice: String?
    @State private var visiblePostponedBedtime: String?
    @State private var dashboardCardHeight: CGFloat = 0

    private var postponedBedtime: String? {
        visiblePostponedBedtime ?? mgr.tonightPostponedBedtime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                MoonIcon()
                Text(L10n.t("app.name"))
                    .font(Lamp.rounded(20, weight: .bold))
                    .foregroundColor(Lamp.creamText)
                Spacer()
                Button(action: { showDelay = true }) {
                    HStack(spacing: 6) {
                        Text("⏰")
                        Text(L10n.t("dashboard.delay"))
                            .font(Lamp.rounded(13, weight: .semibold))
                    }
                    .foregroundColor(Lamp.sandMuted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Lamp.glass2)
                    .cornerRadius(999)
                    .overlay(
                        Capsule().stroke(Lamp.borderDefault, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 20)

            if let postponed = postponedBedtime {
                postponedBanner(postponed)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 2-col grid — intrinsic height only; both cards share measured height
            HStack(alignment: .top, spacing: 12) {
                dashboardScheduleCard
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: DashboardCardHeightKey.self,
                                value: geo.size.height
                            )
                        }
                    )
                dashboardWeeklyCard
            }
            .fixedSize(horizontal: false, vertical: true)
            .onPreferenceChange(DashboardCardHeightKey.self) { h in
                if h > 0 { dashboardCardHeight = h }
            }

            Spacer()

            // Confirm button
            VStack(spacing: 8) {
                if let delayNotice {
                    Text(delayNotice)
                        .font(Lamp.rounded(13, weight: .medium))
                        .foregroundColor(Lamp.tealTrust)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
                if savedNotice {
                    Text(L10n.t("dashboard.saved"))
                        .font(Lamp.rounded(13, weight: .medium))
                        .foregroundColor(Lamp.sageOk)
                        .transition(.opacity)
                }
                Button(L10n.t("dashboard.save")) { saveChanges() }
                    .buttonStyle(LampButtonStyle(block: true))
            }
            .padding(.horizontal, 8)
            .padding(.top, 16)
        }
        .padding(.top, 46)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showDelay) {
            DelayPopover(isPresented: $showDelay) { newBedtime in
                visiblePostponedBedtime = newBedtime
                withAnimation {
                    delayNotice = L10n.ts("delay.confirmed", newBedtime)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation { delayNotice = nil }
                }
            }
            .environmentObject(mgr)
        }
        .onAppear {
            resizeWindow(width: 520, height: 600)
            syncFromConfig()
            mgr.refreshTonightPostpone()
            visiblePostponedBedtime = mgr.tonightPostponedBedtime
        }
    }

    private func postponedBanner(_ postponed: String) -> some View {
        HStack(spacing: 10) {
            Text("⏰")
                .font(Lamp.rounded(18, weight: .bold))
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.ts("dashboard.tonight_postponed", postponed))
                    .font(Lamp.rounded(14, weight: .bold))
                    .foregroundColor(Lamp.creamText)
                Text(L10n.ts("dashboard.original_bedtime", mgr.config.bedtime))
                    .font(Lamp.rounded(11, weight: .medium))
                    .foregroundColor(Lamp.sandMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Lamp.tealTrust.opacity(0.16))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Lamp.tealTrust.opacity(0.28), lineWidth: 1)
        )
    }

    private var dashboardScheduleCard: some View {
        dashboardCard(minHeight: dashboardCardHeight) {
            HStack(spacing: 8) {
                Text("🌙")
                Text(L10n.t("dashboard.sleep_config"))
                    .font(Lamp.rounded(15, weight: .bold))
                    .foregroundColor(Lamp.creamText)
            }
            timeRow(label: L10n.t("dashboard.sleep"), time: $bedtime)
            if let postponed = postponedBedtime {
                HStack(spacing: 7) {
                    Text("✓")
                        .font(Lamp.rounded(12, weight: .bold))
                        .foregroundColor(Lamp.tealTrust)
                    Text(L10n.ts("dashboard.tonight_postponed", postponed))
                        .font(Lamp.rounded(12, weight: .semibold))
                        .foregroundColor(Lamp.tealTrust)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, -4)
            }
            timeRow(label: L10n.t("dashboard.wakeup"), time: $wakeup)
        }
    }

    private var dashboardWeeklyCard: some View {
        dashboardCard(minHeight: dashboardCardHeight) {
            HStack(spacing: 8) {
                Text("📅")
                Text(L10n.t("dashboard.weekly"))
                    .font(Lamp.rounded(15, weight: .bold))
                    .foregroundColor(Lamp.creamText)
            }
            DayGrid(activeDays: $activeDays, compact: true)
        }
    }

    private func dashboardCard<Content: View>(
        minHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(20)
            .frame(
                maxWidth: .infinity,
                minHeight: minHeight > 0 ? minHeight : nil,
                alignment: .topLeading
            )
            .background(Lamp.glass2)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Lamp.borderDefault, lineWidth: 1)
            )
    }

    private func syncFromConfig() {
        activeDays = Set(mgr.config.days)
        bedtime = parseTime(mgr.config.bedtime)
        wakeup = parseTime(mgr.config.wakeup)
    }

    private func saveChanges() {
        mgr.config.bedtime = formatTime(bedtime)
        mgr.config.wakeup = formatTime(wakeup)
        mgr.config.days = activeDays.sorted()
        mgr.updateConfigAndReschedule()
        withAnimation { savedNotice = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { savedNotice = false }
        }
    }

    private func timeRow(label: String, time: Binding<Date>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Lamp.rounded(13))
                .foregroundColor(Lamp.sandMuted)
                .frame(width: 52, alignment: .leading)
            DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .labelsHidden()
                .environment(\.locale, L10n.locale)
                .colorScheme(.dark)
                .accentColor(Lamp.amberMoon)
        }
    }
}

struct MoonIcon: View {
    private let size: CGFloat = 36

    var body: some View {
        Circle()
            .fill(Lamp.amberMoon)
            .frame(width: size, height: size)
            .mask {
                ZStack {
                    Rectangle()
                    Circle()
                        .frame(width: size * 0.72, height: size * 0.72)
                        .offset(x: size * 0.26, y: -size * 0.14)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .frame(width: size, height: size)
    }
}

// MARK: - Delay Popover

struct DelayPopover: View {
    @Binding var isPresented: Bool
    var onConfirmed: ((String) -> Void)? = nil
    @EnvironmentObject var mgr: ConfigManager

    @State private var reason = ""
    @State private var selectedMinutes: Int? = 30
    @State private var customMinutes = "45"
    @State private var showCustom = false
    @State private var isSubmitting = false
    @State private var confirmation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("delay.title"))
                .font(Lamp.rounded(17, weight: .bold))
                .foregroundColor(Lamp.creamText)
                .padding(.bottom, 4)

            Text(L10n.t("delay.hint"))
                .font(Lamp.rounded(13))
                .foregroundColor(Lamp.duskDim)
                .italic()
                .padding(.bottom, 14)

            Text(L10n.t("delay.reason_label"))
                .font(Lamp.rounded(12, weight: .semibold))
                .foregroundColor(Lamp.sandMuted)
                .padding(.bottom, 6)

            TextField(L10n.t("delay.reason_placeholder"), text: $reason)
                .textFieldStyle(.plain)
                .font(Lamp.rounded(13))
                .foregroundColor(Lamp.creamText)
                .padding(12)
                .background(Lamp.glass1)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Lamp.borderDefault, lineWidth: 1)
                )
                .padding(.bottom, 14)

            Text(L10n.t("delay.duration_label"))
                .font(Lamp.rounded(12, weight: .semibold))
                .foregroundColor(Lamp.sandMuted)
                .padding(.bottom, 6)

            HStack(spacing: 8) {
                delayOption(L10n.t("delay.15min"), minutes: 15)
                delayOption(L10n.t("delay.30min"), minutes: 30)
                delayOption(L10n.t("delay.custom"), minutes: 0)
            }
            .padding(.bottom, showCustom ? 0 : 16)

            if showCustom {
                HStack(spacing: 8) {
                    Text(L10n.t("delay.postpone"))
                        .font(Lamp.rounded(13))
                        .foregroundColor(Lamp.sandMuted)
                    TextField("45", text: $customMinutes)
                        .textFieldStyle(.plain)
                        .font(Lamp.rounded(15, weight: .bold))
                        .foregroundColor(Lamp.creamText)
                        .multilineTextAlignment(.center)
                        .frame(width: 80)
                        .padding(8)
                        .background(Lamp.glass1)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Lamp.borderDefault, lineWidth: 1)
                        )
                    Text(L10n.t("delay.minutes"))
                        .font(Lamp.rounded(13))
                        .foregroundColor(Lamp.sandMuted)
                }
                .padding(.vertical, 16)
            }

            HStack(spacing: 10) {
                Button(L10n.t("delay.cancel")) { isPresented = false }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(isSubmitting)
                Button(L10n.t("delay.submit")) { confirmDelay() }
                    .buttonStyle(LampButtonStyle(block: true))
                    .disabled(isSubmitting)
                    .opacity(isSubmitting ? 0.72 : 1)
            }

            if let confirmation {
                Text(confirmation)
                    .font(Lamp.rounded(13, weight: .semibold))
                    .foregroundColor(Lamp.tealTrust)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(24)
        .frame(width: 340)
        .background(Lamp.nightElevated)
        .animation(.easeInOut(duration: 0.18), value: confirmation)
    }

    private func delayOption(_ label: String, minutes: Int) -> some View {
        let isSelected = (minutes == 0 && showCustom) ||
            (minutes != 0 && selectedMinutes == minutes)
        return Button(action: {
            if minutes == 0 {
                showCustom = true
                selectedMinutes = nil
            } else {
                showCustom = false
                selectedMinutes = minutes
            }
        }) {
            Text(label)
                .font(Lamp.rounded(13, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? Lamp.amberMoon : Lamp.glass1)
                .foregroundColor(isSelected ? Lamp.nightDeep : Lamp.sandMuted)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Lamp.amberMoon : Lamp.borderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func confirmDelay() {
        guard !isSubmitting else { return }

        var minutes: Int
        if showCustom {
            minutes = Int(customMinutes) ?? 30
        } else if let sel = selectedMinutes {
            minutes = sel
        } else {
            return // nothing selected
        }
        if minutes <= 0 { minutes = 30 }

        let reasonText = reason.isEmpty ? L10n.tf("delay.default_reason", minutes) : reason
        guard let newBedtime = mgr.postponeTonight(minutes: minutes, reason: reasonText) else { return }

        withAnimation {
            isSubmitting = true
            confirmation = L10n.ts("delay.confirmed", newBedtime)
        }
        onConfirmed?(newBedtime)

        DispatchQueue.global(qos: .utility).async {
            NotificationScheduler.shared.sendImmediateNotification(
                title: L10n.t("notify.delay.title"),
                subtitle: L10n.ts("notify.delay.subtitle", newBedtime),
                body: L10n.t("notify.delay.body")
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            isPresented = false
        }
    }
}

// MARK: - Root Content View

struct ContentView: View {
    @StateObject private var state = AppState()
    @StateObject private var mgr = ConfigManager.shared
    @StateObject private var windowSize = WindowSizeStore.shared

    @State private var activeDays: Set<String> = ["1","2","3","4","5"]
    @State private var bedtime: Date = parseTime("23:00")
    @State private var wakeup: Date = parseTime("07:00")

    private let catImage = loadCatImage()

    var body: some View {
        ZStack {
            Lamp.nightSurface

            Group {
                switch state.screen {
                case .welcome:
                    WelcomeView(catImage: catImage)
                case .config:
                    ScheduleConfigView(activeDays: $activeDays, bedtime: $bedtime, wakeup: $wakeup)
                case .agreement:
                    AgreementView()
                case .lockPreview:
                    LockPreviewView(catImage: catImage)
                case .dashboard:
                    DashboardView(activeDays: $activeDays, bedtime: $bedtime, wakeup: $wakeup)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        }
        .frame(width: windowSize.size.width, height: windowSize.size.height)
        .environmentObject(state)
        .environmentObject(mgr)
        .onAppear {
            if mgr.configExists {
                mgr.loadConfig()
                activeDays = Set(mgr.config.days)
                bedtime = parseTime(mgr.config.bedtime)
                wakeup = parseTime(mgr.config.wakeup)
            }
            if mgr.shouldShowDashboardOnLaunch {
                state.screen = .dashboard
            }
        }
    }
}

// MARK: - Time Helpers

func parseTime(_ str: String) -> Date {
    let parts = str.split(separator: ":")
    guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else {
        return Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date()) ?? Date()
    }
    return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
}

func formatTime(_ date: Date) -> String {
    let cal = Calendar.current
    let h = cal.component(.hour, from: date)
    let m = cal.component(.minute, from: date)
    return String(format: "%02d:%02d", h, m)
}

func resizeWindow(width: CGFloat, height: CGFloat) {
    DispatchQueue.main.async {
        WindowSizeStore.shared.size = CGSize(width: width, height: height)
        guard let window = NSApplication.shared.windows.first else { return }
        lockWindowContentSize(window, width: width, height: height, center: false, animated: false)
    }
}

func lockWindowContentSize(_ window: NSWindow, width: CGFloat, height: CGFloat, center: Bool, animated: Bool) {
    let contentSize = NSSize(width: width, height: height)
    let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
    window.minSize = frameSize
    window.maxSize = frameSize
    window.contentMinSize = contentSize
    window.contentMaxSize = contentSize

    let currentFrame = window.frame
    let visibleFrame = NSScreen.main?.visibleFrame ?? currentFrame
    let midX = center ? visibleFrame.midX : currentFrame.midX
    let midY = center ? visibleFrame.midY : currentFrame.midY
    var newFrame = NSRect(
        x: midX - frameSize.width / 2,
        y: midY - frameSize.height / 2,
        width: frameSize.width,
        height: frameSize.height
    )

    if !center {
        if newFrame.minX < visibleFrame.minX { newFrame.origin.x = visibleFrame.minX }
        if newFrame.maxX > visibleFrame.maxX { newFrame.origin.x = visibleFrame.maxX - newFrame.width }
        if newFrame.minY < visibleFrame.minY { newFrame.origin.y = visibleFrame.minY }
        if newFrame.maxY > visibleFrame.maxY { newFrame.origin.y = visibleFrame.maxY - newFrame.height }
    }

    if animated {
        window.animator().setFrame(newFrame, display: true, animate: true)
    } else {
        window.setFrame(newFrame, display: true)
    }
}

// MARK: - App Bootstrap (AppKit)

final class FillHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    private var commandWMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        L10n.prepareForAppLaunch()
        installMainMenu()
        installAppIcon()
        NotificationScheduler.shared.requestPermission()

        let mgr = ConfigManager.shared
        if mgr.shouldShowDashboardOnLaunch {
            NotificationScheduler.shared.clearPendingReminders()
        }
        let isDashboard = mgr.shouldShowDashboardOnLaunch
        let initialWidth: CGFloat = isDashboard ? 520 : 420
        let initialHeight: CGFloat = isDashboard ? 600 : 560
        WindowSizeStore.shared.size = CGSize(width: initialWidth, height: initialHeight)

        let contentView = ContentView()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("app.name")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Lamp.nsNightSurface
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = true
        window.delegate = self

        if let minimizeButton = window.standardWindowButton(.miniaturizeButton) {
            minimizeButton.target = self
            minimizeButton.action = #selector(hideWindowToAppIcon(_:))
        }

        let hostingView = FillHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight)
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        lockWindowContentSize(window, width: initialWidth, height: initialHeight, center: true, animated: false)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            lockWindowContentSize(self.window, width: initialWidth, height: initialHeight, center: true, animated: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            lockWindowContentSize(self.window, width: initialWidth, height: initialHeight, center: true, animated: false)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        installCommandWMonitor()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return confirmQuit() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let commandWMonitor {
            NSEvent.removeMonitor(commandWMonitor)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    @objc func applicationDidBecomeActive(_ notification: Notification) {
        if !window.isVisible && !window.isMiniaturized {
            showMainWindow()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWindowToAppIcon(sender)
        return false
    }

    @objc private func hideWindowToAppIcon(_ sender: Any?) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.orderOut(sender)
    }

    private func installCommandWMonitor() {
        commandWMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCommandW = flags.contains(.command)
                && !flags.contains(.option)
                && !flags.contains(.control)
                && event.charactersIgnoringModifiers?.lowercased() == "w"
            if isCommandW {
                self?.hideWindowToAppIcon(event)
                return nil
            }
            return event
        }
    }

    private func showMainWindow() {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func installAppIcon() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else { return }
        NSApplication.shared.applicationIconImage = icon
    }

    private func confirmQuit() -> Bool {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = L10n.t("quit.title")
        alert.informativeText = L10n.t("quit.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.t("quit.confirm"))
        alert.addButton(withTitle: L10n.t("quit.cancel"))

        return alert.runModal() == .alertFirstButtonReturn
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(NSMenuItem(
            title: L10n.t("menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: L10n.t("menu.file"))
        fileMenuItem.submenu = fileMenu
        let closeWindow = NSMenuItem(
            title: L10n.t("menu.hide_window"),
            action: #selector(hideWindowToAppIcon(_:)),
            keyEquivalent: "w"
        )
        closeWindow.target = self
        fileMenu.addItem(closeWindow)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))

        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)

        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        NSApplication.shared.mainMenu = mainMenu
    }
}

// MARK: - main

@main
enum CatBedtimeMain {
    static func main() {
        NotificationCommand.exitIfRequested()

        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.run()
    }
}
