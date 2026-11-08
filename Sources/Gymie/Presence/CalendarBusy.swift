import EventKit
import Foundation

/// Busy time from the macOS Calendar app (which already includes Google and Exchange
/// accounts added in System Settings), so no separate Google Calendar sign-in is needed.
@MainActor
final class CalendarBusy {
    struct Event: Equatable {
        var title: String
        var start: Date
        var end: Date
    }

    private let store = EKEventStore()

    var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var denied: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        return s == .denied || s == .restricted
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// The event you're in right now, if it marks you busy and you haven't declined it.
    func currentBlock(now: Date) -> Event? {
        events(from: now.addingTimeInterval(-12 * 3600), to: now.addingTimeInterval(60))
            .filter { $0.start <= now && now < $0.end }
            .max { $0.end < $1.end }
    }

    func nextMeeting(now: Date) -> Event? {
        events(from: now, to: now.addingTimeInterval(24 * 3600)).first { $0.start > now }
    }

    private func events(from: Date, to: Date) -> [Event] {
        guard authorized else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.availability != .free && !declined($0) }
            .sorted { $0.startDate < $1.startDate }
            .map { Event(title: $0.title ?? "Busy", start: $0.startDate, end: $0.endDate) }
    }

    private func declined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }
}
