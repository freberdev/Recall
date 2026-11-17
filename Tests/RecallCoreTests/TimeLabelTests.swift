import Foundation
import Testing
@testable import RecallCore

@Suite struct TimeLabelTests {
    static let stockholm = TimeZone(identifier: "Europe/Stockholm")!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = stockholm
        return calendar
    }

    static func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    let now = TimeLabelTests.moment(2026, 11, 16, 15, 0)

    func label(_ date: Date, locale: String = "en_GB") -> String {
        TimeLabel.string(for: date, now: now, calendar: Self.calendar, locale: Locale(identifier: locale))
    }

    @Test func todayShowsTheTime() {
        #expect(label(Self.moment(2026, 11, 16, 14, 32)) == "Today 14:32")
    }

    @Test func justAfterMidnightIsStillToday() {
        #expect(label(Self.moment(2026, 11, 16, 0, 5)) == "Today 00:05")
    }

    @Test func yesterdayShowsTheTime() {
        #expect(label(Self.moment(2026, 11, 15, 16, 45)) == "Yesterday 16:45")
    }

    @Test func earlierThisYearShowsDayMonthAndTime() {
        #expect(label(Self.moment(2026, 11, 12, 8, 2)) == "12 Nov 08:02")
    }

    @Test func anotherYearShowsDayMonthAndYear() {
        #expect(label(Self.moment(2025, 11, 12, 8, 2)) == "12 Nov 2025")
    }

    @Test func swedishUsesTheSystemsWordForToday() {
        let label = label(Self.moment(2026, 11, 16, 14, 32), locale: "sv_SE")
        #expect(label.hasPrefix("I"))
        #expect(label.lowercased().contains("dag"))
        #expect(label.hasSuffix("14:32"))
    }

    @Test func aTimestampFromTheFutureDoesNotBreak() {
        #expect(label(Self.moment(2026, 11, 17, 9, 0)) == "17 Nov 09:00")
    }
}
