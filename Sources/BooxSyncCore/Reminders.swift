import Foundation
import EventKit

public struct ReminderItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let due: Date?
    public let list: String
}

public enum RemindersResult: Equatable, Sendable {
    case items([ReminderItem])
    case denied
    case failed(String)
}

/// Reads incomplete reminders from the Reminders app (read only). macOS asks for permission the first time.
public final class RemindersProvider {
    private let store = EKEventStore()

    public init() {}

    private func ensureAccess() async -> Bool {
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess { return true }
        return (try? await store.requestFullAccessToReminders()) ?? false
    }

    public func listNames() async -> [String] {
        guard await ensureAccess() else { return [] }
        return store.calendars(for: .reminder).map(\.title).sorted()
    }

    /// `list == nil` means all lists. Overdue and dated reminders come first, then undated ones.
    public func fetch(list: String?) async -> RemindersResult {
        guard await ensureAccess() else { return .denied }
        let calendars = store.calendars(for: .reminder).filter { list == nil || $0.title == list }
        guard !calendars.isEmpty else { return .items([]) }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        let items: [ReminderItem] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let mapped = (reminders ?? []).map {
                    ReminderItem(id: $0.calendarItemIdentifier, title: $0.title ?? "", due: $0.dueDateComponents?.date, list: $0.calendar.title)
                }
                continuation.resume(returning: mapped)
            }
        }
        let sorted = items.filter { !$0.title.isEmpty }.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
        return .items(sorted)
    }
}
