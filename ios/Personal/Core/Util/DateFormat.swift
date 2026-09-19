import Foundation

/// Every date and duration the UI prints, in one place.
///
/// Timestamps are milliseconds since the epoch — the unit every `started_at`,
/// `finished_at` and `updated_at` column stores.
enum DateFormat {

    /// The list group header of the design system: "Tomorrow / Wednesday",
    /// "Today / Friday", "8 July / Tuesday". `primary` is the relative or
    /// absolute day, `secondary` the weekday.
    static func dayHeader(_ ms: Int64) -> (primary: String, secondary: String) {
        let date = date(ms)
        let weekday = weekdayFormatter.string(from: date)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return (primary: "Today", secondary: weekday)
        }
        if calendar.isDateInTomorrow(date) {
            return (primary: "Tomorrow", secondary: weekday)
        }
        if calendar.isDateInYesterday(date) {
            return (primary: "Yesterday", secondary: weekday)
        }
        return (primary: dayMonthFormatter.string(from: date), secondary: weekday)
    }

    /// "Tue 19 Sep" — the absolute date in a session caption, where the
    /// relative "Today / Yesterday" of ``dayHeader(_:)`` would be ambiguous
    /// next to a running timer.
    static func shortDate(_ ms: Int64) -> String {
        shortDateFormatter.string(from: date(ms))
    }

    /// "8 Sep" — the compact day a chart axis label has room for, where the
    /// full month name of ``dayHeader(_:)`` would collide with its neighbours.
    static func dayMonthShort(_ ms: Int64) -> String {
        dayMonthShortFormatter.string(from: date(ms))
    }

    /// The clock time of a session, in the user's own 12/24-hour setting.
    static func time(_ ms: Int64) -> String {
        timeFormatter.string(from: date(ms))
    }

    /// A running or finished duration as `HH:mm:ss` — the session timer.
    /// Negative input is clamped to zero; hours are not capped at 24.
    static func elapsed(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    /// The gap between two millisecond timestamps, as `HH:mm:ss`.
    static func elapsed(from startMs: Int64, to endMs: Int64) -> String {
        elapsed(Int((endMs - startMs) / 1000))
    }

    // MARK: - Plumbing

    private static func date(_ ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    /// "Wednesday".
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter
    }()

    /// "Tue 19 Sep" — the template lets the locale decide the order.
    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter
    }()

    /// "8 July" — the template lets the locale decide the order.
    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        return formatter
    }()

    /// "8 Sep" — the template lets the locale decide the order.
    private static let dayMonthShortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter
    }()

    /// "18:40" or "6:40 PM", whichever the device is set to.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
