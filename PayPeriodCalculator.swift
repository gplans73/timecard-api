import Foundation

// MARK: - Sun→Sat pay period with Friday payday

public struct PayPeriod {
    public let start: Date      // Sunday 00:00 (start-of-day)
    public let end: Date        // Saturday 23:59:59
    public let payday: Date     // following Friday
    public let sequenceOdd: Int // 1,3,5,... (odd-numbered count from anchor)
    
    public var week1: ClosedRange<Date> {
        let cal = Calendar.current
        let wkEnd = cal.date(byAdding: .day, value: 6, to: start)!
        return start ... wkEnd
    }
    
    public var week2: ClosedRange<Date> {
        let cal = Calendar.current
        let w2Start = cal.date(byAdding: .day, value: 7, to: start)!
        let w2End   = cal.date(byAdding: .day, value: 13, to: start)!
        return w2Start ... w2End
    }
}

public final class SunSatFridayPayCalculator {
    private let cal: Calendar
    private let anchorPayday: Date       // e.g., Fri 2025-01-03
    
    private let periodDays = 14
    private let satToFriOffset = 6       // Sat → next Fri = +6
    
    /// - Parameter anchorPayday: a **real** payday in your cycle (a Friday).
    public init(calendar: Calendar = .current, anchorPayday: Date) {
        self.cal = calendar
        self.anchorPayday = cal.startOfDay(for: anchorPayday)
    }
    
    /// Pay period that contains `date`.
    public func payPeriod(containing date: Date = Date()) -> PayPeriod {
        let d0 = cal.startOfDay(for: date)
        let delta = cal.dateComponents([.day], from: anchorPayday, to: d0).day ?? 0
        let idxApprox = Int(floor(Double(delta) / Double(periodDays))) + 1
        
        func build(_ k: Int) -> PayPeriod {
            let payday = cal.date(byAdding: .day, value: (k - 1) * periodDays, to: anchorPayday)!
            let endSat = cal.date(byAdding: .day, value: -satToFriOffset, to: payday)! // Saturday
            let startSun = cal.date(byAdding: .day, value: -13, to: endSat)!           // previous Sunday
            
            // Normalize to full-day bounds (00:00 → 23:59:59 local)
            let start = cal.startOfDay(for: startSun)
            let end   = cal.date(bySettingHour: 23, minute: 59, second: 59, of: endSat)!
            let oddNo = (k - 1) * 2 + 1
            return PayPeriod(start: start, end: end, payday: payday, sequenceOdd: oddNo)
        }
        
        var pp = build(idxApprox)
        if d0 < pp.start { pp = build(idxApprox - 1) }
        else if d0 > pp.end { pp = build(idxApprox + 1) }
        return pp
    }
    
    /// Week range inside a period. 0 = Week 1, 1 = Week 2.
    public func week(in period: PayPeriod, index: Int) -> ClosedRange<Date> {
        index == 0 ? period.week1 : period.week2
    }
    
    /// For navigation: returns the period `offset` steps away (±n * 14 days).
    public func payPeriod(from period: PayPeriod, offset: Int) -> PayPeriod {
        let shift = offset * periodDays
        let ref = cal.date(byAdding: .day, value: shift, to: period.payday)!
        return payPeriod(containing: ref)
    }
}
