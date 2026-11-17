import Foundation

/// A short, human description of when a note was last changed.
public enum TimeLabel {
    /// "Today 14:32", "Yesterday 16:45", "12 Nov 08:02", or "12 Nov 2025" for another year,
    /// in the words and formats of `locale`.
    public static func string(
        for date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        style.capitalizationContext = .beginningOfSentence
        let time = date.formatted(style.hour().minute())

        let isToday = calendar.isDate(date, inSameDayAs: now)
        let isYesterday = calendar.date(byAdding: .day, value: -1, to: now)
            .map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        if isToday || isYesterday {
            return "\(relativeDay(for: date, now: now, calendar: calendar, locale: locale)) \(time)"
        }

        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return "\(date.formatted(style.day().month(.abbreviated))) \(time)"
        }
        return date.formatted(style.day().month(.abbreviated).year())
    }

    /// The system's own word for today or yesterday, with a capital first letter.
    private static func relativeDay(for date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateTimeStyle = .named
        formatter.formattingContext = .beginningOfSentence
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date))
        let word = formatter.localizedString(from: DateComponents(day: days.day ?? 0))
        return word.prefix(1).uppercased(with: locale) + word.dropFirst()
    }
}
