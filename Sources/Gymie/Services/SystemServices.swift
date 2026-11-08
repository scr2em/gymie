import AppKit
import Carbon.HIToolbox
import Security
import ServiceManagement
import UserNotifications

// MARK: - Notifications

/// A heads-up one minute before a break, with Start now and Snooze actions.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private static let category = "break-soon"
    private static let headsUpId = "gymie.heads-up"
    private var onStart: (() -> Void)?
    private var onSnooze: (() -> Void)?

    /// UNUserNotificationCenter needs a real app bundle; `swift run` has none.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func setUp(onStart: @escaping () -> Void, onSnooze: @escaping () -> Void) {
        self.onStart = onStart
        self.onSnooze = onSnooze
        guard let center else { return }
        center.delegate = self
        let start = UNNotificationAction(identifier: "start", title: "Start now", options: [.foreground])
        let snooze = UNNotificationAction(identifier: "snooze", title: "Snooze 20 min")
        let withSnooze = UNNotificationCategory(identifier: Self.category, actions: [start, snooze], intentIdentifiers: [])
        let noSnooze = UNNotificationCategory(identifier: Self.category + "-nosnooze", actions: [start], intentIdentifiers: [])
        center.setNotificationCategories([withSnooze, noSnooze])
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func headsUp(at: Date, canSnooze: Bool) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "Break in 1 minute"
        content.body = "Finish your thought. A 2-minute routine starts at \(at.formatted(date: .omitted, time: .shortened))."
        content.categoryIdentifier = canSnooze ? Self.category : Self.category + "-nosnooze"
        center.add(UNNotificationRequest(identifier: Self.headsUpId, content: content, trigger: nil))
    }

    func clearHeadsUp() {
        center?.removeDeliveredNotifications(withIdentifiers: [Self.headsUpId])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        Task { @MainActor in
            switch action {
            case "snooze": self.onSnooze?()
            case "start", UNNotificationDefaultActionIdentifier: self.onStart?()
            default: break
            }
            completionHandler()
        }
    }
}

// MARK: - Launch at login

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        guard Bundle.main.bundleIdentifier != nil, enabled != isEnabled else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Gymie: launch at login \(enabled ? "register" : "unregister") failed: \(error)")
        }
    }
}

// MARK: - Global hotkey (⌃⌥⌘B)

/// Carbon hotkeys work without Accessibility permission.
@MainActor
final class HotKey {
    static let display = "⌃⌥⌘B"
    var action: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register() {
        guard ref == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { hotKey.action?() } }
            return noErr
        }, 1, &spec, me, &handler)
        let id = EventHotKeyID(signature: OSType(0x4759_4D45), id: 1) // "GYME"
        RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(cmdKey | optionKey | controlKey), id,
                            GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil
        handler = nil
    }
}

// MARK: - Keychain

enum Keychain {
    private static let service = "Gymie GitHub token"

    static func read(account: String = "github") -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String, account: String = "github") -> Bool {
        delete(account: account)
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8),
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete(account: String = "github") {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
