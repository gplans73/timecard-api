//
//  PayPeriodBC.swift
//  Biweekly pay period helper for British Columbia (BC) schedule
//
//  Assumptions (per user spec):
//  - Biweekly periods (14 days)
//  - Start: Thursday; End: second Wednesday (13 days later)
//  - Payday: Wednesday of the following week (7 days after End)
//  - Periods numbered 1...26 starting from the first Thursday of the year
//  - Dates earlier than the first-Thursday anchor belong to the previous year's last period
//
import Foundation

public struct BCPayPeriod: Hashable {
    public let number: Int        // 1...26 (or 27 in rare years)
    public let start: Date        // Thursday
    public let end: Date          // Wednesday (start + 13d)
    public let payday: Date       // end + 7d (next Wednesday)
    public let yearAnchor: Int    // the year used to compute anchors
}

public enum BCPayPeriodCalc {
    /// Returns the pay period that contains `date`.
    public static func period(containing date: Date, calendar inputCal: Calendar = .current) -> BCPayPeriod {
        var cal = inputCal
        cal.timeZone = inputCal.timeZone
        cal.locale = inputCal.locale

        // Find anchor: first Thursday on or after Jan 1 of the "anchor year".
        func firstThursday(of year: Int) -> Date {
            let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
            // Advance forward to the first Thursday (weekday 5 in US calendar where 1=Sunday).
            let weekday = cal.component(.weekday, from: jan1)
            let thursday = 5
            let delta = (thursday - weekday + 7) % 7
            return cal.date(byAdding: .day, value: delta, to: jan1)!
        }

        let y = cal.component(.year, from: date)
        var anchorYear = y
        var firstThu = firstThursday(of: anchorYear)

        // If the date is before the first-Thursday anchor, treat it as belonging to the previous year's schedule.
        if date < firstThu {
            anchorYear = y - 1
            firstThu = firstThursday(of: anchorYear)
        }

        // Compute index from anchor
        let days = cal.dateComponents([.day], from: firstThu, to: date).day ?? 0
        let index = max(0, days / 14) // integer division
        var start = cal.date(byAdding: .day, value: index * 14, to: firstThu)!
        var end = cal.date(byAdding: .day, value: 13, to: start)!

        // If date is after the last computed end, and we crossed into next period boundary, fix up.
        while date > end {
            start = cal.date(byAdding: .day, value: 14, to: start)!
            end = cal.date(byAdding: .day, value: 13, to: end)!
        }

        // Number within the anchor year (1-based)
        let number = (cal.dateComponents([.day], from: firstThu, to: start).day ?? 0) / 14 + 1

        let payday = cal.date(byAdding: .day, value: 7, to: end)!
        return BCPayPeriod(number: number, start: start, end: end, payday: payday, yearAnchor: anchorYear)
    }
}

// Convenience display
public extension DateFormatter {
    static let bcShort: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
