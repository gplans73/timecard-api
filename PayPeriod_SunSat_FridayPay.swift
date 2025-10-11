//
//  PayPeriod_SunSat_FridayPay.swift
//  Biweekly periods: Sunday .. Saturday, payday = following Friday.
//  Numbering matches your sheet: 1,3,5,... (odd numbers only).
//  Anchor: PP#1 payday = Fri Jan 3, 2025 (adjust in `anchorPayday` if needed).
//

import Foundation

public struct OddPayPeriod: Hashable {
    /// Odd-style number (1,3,5,...)
    public let numberOdd: Int
    public let start: Date   // Sunday
    public let end: Date     // Saturday
    public let payday: Date  // following Friday
}

public enum OddPayPeriodCalc {
    /// Anchor payday for PP#1. Change if your sheet uses a different first payday.
    public static var anchorPayday: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: DateComponents(year: 2025, month: 1, day: 3))! // Fri Jan 3, 2025
    }

    /// Return the period that contains `date`.
    /// - Parameters:
    ///   - date: Any date inside the Sun..Sat block.
    /// - Returns: OddPayPeriod with odd number, Sun start, Sat end, and next Friday payday.
    public static func period(containing date: Date, calendar inputCal: Calendar = .current) -> OddPayPeriod {
        var cal = inputCal
        cal.timeZone = inputCal.timeZone
        cal.locale  = inputCal.locale

        let periodLen = 14
        let daysFromEndToPay = 6 // Saturday -> next Friday

        // First period boundaries from anchor payday.
        let anchorEnd   = cal.date(byAdding: .day, value: -daysFromEndToPay, to: anchorPayday)!     // Saturday
        let anchorStart = cal.date(byAdding: .day, value: -13, to: anchorEnd)!                      // Sunday

        // Distance in days from start of first period to the query date (at start-of-day to avoid DST issues).
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: anchorStart),
                                      to:   cal.startOfDay(for: date)).day ?? 0

        // Floor division for possibly-negative values.
        let k: Int
        if days >= 0 {
            k = days / periodLen + 1
        } else {
            // floor((days)/14) for negatives
            k = ((days - (periodLen - 1)) / periodLen) + 1
        }

        func periodForIndex(_ idx: Int) -> OddPayPeriod {
            let payday = cal.date(byAdding: .day, value: (idx - 1) * periodLen, to: anchorPayday)!
            let end    = cal.date(byAdding: .day, value: -daysFromEndToPay, to: payday)!
            let start  = cal.date(byAdding: .day, value: -13, to: end)!
            let numberOdd = (idx - 1) * 2 + 1
            return OddPayPeriod(numberOdd: numberOdd, start: start, end: end, payday: payday)
        }

        var pp = periodForIndex(k)
        if date < pp.start { pp = periodForIndex(k - 1) }
        else if date > pp.end { pp = periodForIndex(k + 1) }

        return pp
    }
}
