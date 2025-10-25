import SwiftUI

/// Minimal local definition to satisfy this view. If your project defines `TimeEntryType` elsewhere,
/// remove this and use the shared type instead.
private enum TimeEntryType {
    case regular
    case night
    case ot
    case dt
    case vacation
    case stat
}

struct TimecardPDFView: View {
    @EnvironmentObject var store: TimecardStore
    var weekOffset: Int = 0 // 0 = Week #1, 1 = Week #2

    // DateFormatter for MM-dd-yy
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MM-dd-yy"
        return df
    }()

    // Days of week starting Sunday
    private let weekdays = Calendar.current.weekdaySymbols // Sunday first

    // Computed: Dates for the current week (7 days), starting from weekStart
    private var weekDates: [Date] {
        let startDate = store.weekRange(offset: weekOffset).lowerBound
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: startDate) }
    }

    // Extract week number 1 or 2
    private var weekNumberString: String {
        return "Week #\(weekOffset + 1)"
    }
    
    // Pads a string with spaces up to a fixed length so it occupies consistent width with monospaced font
    private func padToLength(_ text: String, length: Int) -> String {
        let count = text.count
        if count >= length { return text }
        return text + String(repeating: " ", count: length - count)
    }

    // MARK: - Helper functions for displaying timecard data
    private func formatHours(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 2
        nf.minimumIntegerDigits = 1
        return nf.string(from: NSNumber(value: value)) ?? ""
    }
    
    private func displayJobText(for entry: Entry) -> String {
        let category: PayCategory = entry.isNightShift ? .night : store.category(for: entry.code)
        // For STAT entries, always display "Stat" for the job label
        if category == .stat {
            return "Stat"
        }
        return entry.jobNumber
    }

    private func entriesFor(day: Date) -> [Entry] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let dayRange = dayStart..<dayEnd
        
        return store.entries.filter { entry in
            guard dayRange.contains(entry.date),
                  !entry.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            let category: PayCategory = entry.isNightShift ? .night : store.category(for: entry.code)
            // Allow empty job number for STAT holidays so they appear in the PDF
            let hasJobOrIsStat = !entry.jobNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || category == .stat
            return hasJobOrIsStat
        }
    }
    
    private func regularEntriesFor(day: Date) -> [Entry] {
        return entriesFor(day: day).filter { entry in
            // First check if user selected "Overtime hours" - if so, exclude from regular table
            if entry.isOvertime {
                return false
            }
            // Otherwise, check code category (Night entries are excluded from the Regular table)
            let category: PayCategory = entry.isNightShift ? .night : store.category(for: entry.code)
            return category == .regular || category == .vacation || category == .stat
        }
    }
    
    private func overtimeEntriesFor(day: Date) -> [Entry] {
        return store.entries.filter { entry in
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: day)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let dayRange = dayStart..<dayEnd

            guard dayRange.contains(entry.date),
                  entry.hours != 600,
                  !entry.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

            if entry.isOvertime { return true }
            let category: PayCategory = entry.isNightShift ? .night : store.category(for: entry.code)
            return category == .ot || category == .dt || category == .onCall
        }
    }
    
    private func nightEntriesFor(day: Date) -> [Entry] {
        return entriesFor(day: day).filter { entry in
            // Exclude items explicitly marked as overtime
            if entry.isOvertime { return false }
            // Treat the Night toggle as night regardless of code
            let category: PayCategory = entry.isNightShift ? .night : store.category(for: entry.code)
            return category == .night
        }
    }
    
    // Helper function to calculate daily overtime and double-time based on total hours worked
    private func calculateDailyOvertimeAndDoubleTime(for date: Date) -> (overtime: Double, doubleTime: Double) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let dayRange = dayStart..<dayEnd

        // Include all worked entries for the day (exclude sentinels and empty codes)
        let dayEntries = store.entries.filter { entry in
            dayRange.contains(entry.date) &&
            entry.hours != 600 &&
            !entry.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let totalHours = dayEntries.reduce(0.0) { $0 + $1.hours }

        // Pull thresholds from the current overtime policy
        let policy = store.overtimePolicy
        let regularCap = policy.dailyRegularCap ?? Double.greatestFiniteMagnitude
        let otCap = policy.dailyOTCap ?? regularCap // if nil, no daily OT tier

        // Compute OT and DT from daily totals using policy thresholds
        let overtime: Double
        let doubleTime: Double
        if policy.dailyRegularCap == nil && policy.dailyOTCap == nil {
            // No daily rules (e.g., US federal weekly-only). Show 0 here; weekly handled elsewhere if needed.
            overtime = 0
            doubleTime = 0
        } else {
            overtime = max(0.0, min(totalHours, otCap) - regularCap)
            doubleTime = max(0.0, totalHours - otCap)
        }

        return (overtime: overtime, doubleTime: doubleTime)
    }

    // Added helpers for explicit OT and DT hours per day (used for Sunday rule)
    private func explicitOTHours(for date: Date) -> Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let range = start..<end
        let entries = store.entries.filter { e in
            range.contains(e.date) && e.hours != 600 && !e.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return entries.reduce(0.0) { sum, e in
            let cat: PayCategory = e.isNightShift ? .night : store.category(for: e.code)
            return (cat == .ot || e.isOvertime) ? sum + e.hours : sum
        }
    }

    private func explicitDTHours(for date: Date) -> Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let range = start..<end
        let entries = store.entries.filter { e in
            range.contains(e.date) && e.hours != 600 && !e.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return entries.reduce(0.0) { sum, e in
            let cat: PayCategory = e.isNightShift ? .night : store.category(for: e.code)
            return (cat == .dt) ? sum + e.hours : sum
        }
    }
    
    // Added new helper for explicit On Call hours per date
    private func explicitOnCallHours(for date: Date) -> Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let range = start..<end
        let entries = store.entries.filter { e in
            range.contains(e.date) && e.hours != 600 && !e.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return entries.reduce(0.0) { sum, e in
            let cat: PayCategory = e.isNightShift ? .night : store.category(for: e.code)
            return (cat == .onCall) ? sum + e.hours : sum
        }
    }

    // Added helper for capped explicit OT/DT for any date (applies 12-hr cap and rolls over excess OT to DT)
    private func explicitCappedOTDT(for date: Date) -> (ot: Double, dt: Double) {
        let ot = explicitOTHours(for: date)
        let dt = explicitDTHours(for: date)
        if ot > 12 { return (ot: 12.0, dt: dt + (ot - 12.0)) }
        return (ot: ot, dt: dt)
    }

    // New helper functions for weekly capped OT and DT totals
    private func weeklyCappedOT(forWeekDates weekDates: [Date]) -> String {
        let sum = weekDates.reduce(0.0) { $0 + explicitCappedOTDT(for: $1).ot }
        return sum > 0 ? formatHours(sum) : ""
    }

    private func weeklyCappedDT(forWeekDates weekDates: [Date]) -> String {
        let sum = weekDates.reduce(0.0) { $0 + explicitCappedOTDT(for: $1).dt }
        return sum > 0 ? formatHours(sum) : ""
    }

// Weekly OT/DT totals for the Notes column that mirror the overtime table logic
    private func weeklyOTForNotes(weekDates: [Date]) -> String {
        let policyMap = computeWeekOTDT(weekDates: weekDates)
        let total = weekDates.reduce(0.0) { sum, d in
            let key = Calendar.current.startOfDay(for: d)
            let policy = policyMap[key] ?? (0,0)
            let explicit = explicitCappedOTDT(for: d)
            let combinedOT = explicit.ot + policy.ot
            let cappedOT = min(combinedOT, 4.0)
            return sum + cappedOT
        }
        return total > 0 ? formatHours(total) : ""
    }

    private func weeklyDTForNotes(weekDates: [Date]) -> String {
        let policyMap = computeWeekOTDT(weekDates: weekDates)
        let total = weekDates.reduce(0.0) { sum, d in
            let key = Calendar.current.startOfDay(for: d)
            let policy = policyMap[key] ?? (0,0)
            let explicit = explicitCappedOTDT(for: d)
            let combinedOT = explicit.ot + policy.ot
            let combinedDT = explicit.dt + policy.dt
            let overflowToDT = max(0.0, combinedOT - 4.0)
            return sum + combinedDT + overflowToDT
        }
        return total > 0 ? formatHours(total) : ""
    }

    // Pay period capped OT/DT totals (use same logic as tables)
    private func payPeriodCappedOT() -> String {
        let calendar = Calendar.current
        let payRange = store.payPeriodRange
        let weeks = max(1, store.payPeriodWeeks)
        var totalOT: Double = 0.0

        // Iterate each week in the pay period and use the same logic as the overtime table
        for w in 0..<weeks {
            let weekRange = store.weekRange(offset: w)
            // Build the 7 dates for this week
            let weekDates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: weekRange.lowerBound)) }
            let policyMap = computeWeekOTDT(weekDates: weekDates)

            for d in weekDates {
                // Only include days that fall within the actual pay period range
                let dayStart = calendar.startOfDay(for: d)
                guard payRange.contains(dayStart) else { continue }
                let policy = policyMap[dayStart] ?? (0,0)
                let explicit = explicitCappedOTDT(for: dayStart)
                let combinedOT = explicit.ot + policy.ot
                let cappedOT = min(combinedOT, 4.0)
                totalOT += cappedOT
            }
        }

        return totalOT > 0 ? formatHours(totalOT) : ""
    }

    private func payPeriodCappedDT() -> String {
        let calendar = Calendar.current
        let payRange = store.payPeriodRange
        let weeks = max(1, store.payPeriodWeeks)
        var totalDT: Double = 0.0

        for w in 0..<weeks {
            let weekRange = store.weekRange(offset: w)
            let weekDates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: weekRange.lowerBound)) }
            let policyMap = computeWeekOTDT(weekDates: weekDates)

            for d in weekDates {
                let dayStart = calendar.startOfDay(for: d)
                guard payRange.contains(dayStart) else { continue }
                let policy = policyMap[dayStart] ?? (0,0)
                let explicit = explicitCappedOTDT(for: dayStart)
                let combinedOT = explicit.ot + policy.ot
                let combinedDT = explicit.dt + policy.dt
                let overflowToDT = max(0.0, combinedOT - 4.0)
                totalDT += combinedDT + overflowToDT
            }
        }

        return totalDT > 0 ? formatHours(totalDT) : ""
    }
    
    // Always-show variants for Summary Totals (display 0 or $0 instead of blank)
    private func payPeriodRegularPlusStatAlways() -> String {
        let totals = store.totals(for: store.payPeriodRange)
        let value = totals.regular + totals.stat
        return formatHours(value)
    }

    private func payPeriodOnCallAmountAlways() -> String {
        let totals = store.totals(for: store.payPeriodRange)
        let amount = totals.onCall
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$0"
    }

    private func payPeriodOnCallCountAlways() -> String {
        let range = store.payPeriodRange
        let count = store.entries.filter { entry in
            range.contains(entry.date) && (store.category(for: entry.code) == .onCall)
        }.count
        let amount = Double(count) * 50.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$0"
    }
    
    // Local computation of pay-period On Call stipend: $300 per week with any on-call activity
    private func payPeriodOnCallStipendAlways() -> String {
        let calendar = Calendar.current
        let payRange = store.payPeriodRange
        // Determine how many weeks in the pay period
        let weeks = max(1, store.payPeriodWeeks)
        var stipendWeeks = 0
        // Build week ranges starting at the pay period lowerBound
        var startOfWeek = calendar.startOfDay(for: payRange.lowerBound)
        for w in 0..<weeks {
            guard let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) else { break }
            let weekRange = startOfWeek..<min(endOfWeek, payRange.upperBound)
            let hasOnCall = store.entries.contains { entry in
                weekRange.contains(entry.date) && (store.category(for: entry.code) == .onCall)
            }
            if hasOnCall { stipendWeeks += 1 }
            startOfWeek = endOfWeek
        }
        let amount = Double(stipendWeeks) * 300.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$0"
    }

    private func totalHoursFor(day: Date, type: TimeEntryType) -> String {
        let entries = entriesFor(day: day)
        var totalHours = 0.0
        
        for entry in entries {
            let category: PayCategory = entry.isNightShift ? .night : store.category(for: entry.code)
            switch type {
            case .regular:
                if category == .regular { totalHours += entry.hours }
            case .night:
                if category == .night { totalHours += entry.hours }
            case .ot:
                if category == .ot { totalHours += entry.hours }
            case .dt:
                if category == .dt { totalHours += entry.hours }
            case .vacation:
                if category == .vacation { totalHours += entry.hours }
            case .stat:
                if category == .stat { totalHours += entry.hours }
            }
        }
        
        return totalHours > 0 ? formatHours(totalHours) : ""
    }

    private func totalHoursFor(type: TimeEntryType) -> String {
        let range = store.weekRange(offset: weekOffset)
        let totals = store.totals(for: range)
        let value: Double
        switch type {
        case .regular:  value = totals.regular
        case .night:    value = totals.night
        case .ot:       value = totals.ot
        case .dt:       value = totals.dt
        case .vacation: value = totals.vacation
        case .stat:     value = totals.stat
        }
        return value > 0 ? formatHours(value) : ""
    }
    
    private func totalHoursRegularIncludingStatForWeek() -> String {
        let totals = store.totals(for: store.weekRange(offset: weekOffset))
        let value = totals.regular + totals.stat
        return value > 0 ? formatHours(value) : ""
    }

    private func totalHoursRegularIncludingStatForPayPeriod() -> String {
        let totals = store.totals(for: store.payPeriodRange)
        let value = totals.regular + totals.stat
        return value > 0 ? formatHours(value) : ""
    }

    private func totalRegularTableHoursForWeek() -> String {
        let totals = store.totals(for: store.weekRange(offset: weekOffset))
        // The Regular Time table includes Regular + Vacation + Stat categories
        let value = totals.regular + totals.vacation + totals.stat
        return value > 0 ? formatHours(value) : ""
    }

    private func weekOnCallAmountString() -> String {
        let range = store.weekRange(offset: weekOffset)
        let hasOnCall = store.entries.contains { entry in
            range.contains(entry.date) && (store.category(for: entry.code) == .onCall)
        }
        guard hasOnCall else { return "" }
        let amount = 300.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }

    private func weekOnCallCountString() -> String {
        let range = store.weekRange(offset: weekOffset)
        let count = store.entries.filter { entry in
            range.contains(entry.date) && (store.category(for: entry.code) == .onCall)
        }.count
        let amount = Double(count) * 50.0
        guard amount > 0 else { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }

    private func totalHoursForPayPeriod(type: TimeEntryType) -> String {
        let totals = store.totals(for: store.payPeriodRange)
        let value: Double
        switch type {
        case .regular:  value = totals.regular
        case .night:    value = totals.night
        case .ot:       value = totals.ot
        case .dt:       value = totals.dt
        case .vacation: value = totals.vacation
        case .stat:     value = totals.stat
        }
        return value > 0 ? formatHours(value) : ""
    }
    
    private func payPeriodOnCallAmountString() -> String {
        let totals = store.totals(for: store.payPeriodRange)
        let amount = totals.onCall // sum of $300 per week with any On Call
        guard amount > 0 else { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }

    private func payPeriodOnCallCountString() -> String {
        let range = store.payPeriodRange
        let count = store.entries.filter { entry in
            range.contains(entry.date) && (store.category(for: entry.code) == .onCall)
        }.count
        let amount = Double(count) * 50.0
        guard amount > 0 else { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }
    
    // MARK: - OT/DT policy computation (8/40 with Sunday rest and DT > 12)
    private func computeWeekOTDT(weekDates: [Date]) -> [Date: (ot: Double, dt: Double)] {
        let cal = Calendar.current
        // Step 1: get worked hours per day (exclude vacation, stat, onCall)
        var dayWorked: [Date: Double] = [:]
        for d in weekDates {
            let start = cal.startOfDay(for: d)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            let range = start..<end
            let entries = store.entries.filter { e in
                range.contains(e.date) && e.hours != 600 && !e.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let worked = entries.reduce(0.0) { sum, e in
                let cat: PayCategory = e.isNightShift ? .night : store.category(for: e.code)
                // Only count actual worked categories toward OT/DT (regular and night). Exclude vacation/stat/onCall.
                if cat == .regular || cat == .night { return sum + e.hours } else { return sum }
            }
            dayWorked[start] = worked
        }

        // Step 2: apply daily rules (OT > 8 up to 12; DT > 12)
        var result: [Date: (ot: Double, dt: Double)] = [:]
        for d in weekDates {
            let key = cal.startOfDay(for: d)
            let hours = dayWorked[key] ?? 0
            let dailyOT = max(0.0, min(hours, 12.0) - 8.0) // up to 4 hours
            let dailyDT = max(0.0, hours - 12.0)
            result[key] = (ot: dailyOT, dt: dailyDT)
        }

        // Step 3: Sunday weekly rest = all hours on Sunday are at least OT (1.5x)
        if let sunday = weekDates.first {
            let sKey = cal.startOfDay(for: sunday)
            let hours = dayWorked[sKey] ?? 0
            // Ensure at least hours are counted as OT (but keep any DT already computed)
            let current = result[sKey] ?? (0,0)
            let ensuredOT = max(current.ot, max(0.0, min(hours, 12.0)))
            let dt = current.dt
            result[sKey] = (ot: ensuredOT, dt: dt)
        }

        // Step 4: Weekly rule: hours over 40 become OT after daily rules
        let totalWorked = dayWorked.values.reduce(0.0, +)
        let weeklyExcess = max(0.0, totalWorked - 40.0)
        if weeklyExcess > 0 {
            var remaining = weeklyExcess
            // Allocate from end of week backward so later days get weekly OT first
            for d in weekDates.reversed() {
                if remaining <= 0 { break }
                let key = cal.startOfDay(for: d)
                let hours = dayWorked[key] ?? 0
                var current = result[key] ?? (0,0)
                // Regular capacity left on this day after daily OT/DT
                let alreadyOTDT = current.ot + current.dt
                let regLeft = max(0.0, hours - alreadyOTDT)
                if regLeft > 0 {
                    let allocation = min(regLeft, remaining)
                    current.ot += allocation
                    remaining -= allocation
                    result[key] = current
                }
            }
        }

        return result
    }

    var body: some View {
        // A4 landscape: 297mm x 210mm = 842pt x 595pt - using smaller width to reduce blank space
        let pageSize = CGSize(width: 760, height: 595) // Increased width from 700 to 760 to accommodate Notes column
        let margin: CGFloat = 16

        let weekDates = self.weekDates
        let df = dateFormatter
        let weekdaysShort = ["Sun","Mon","Tues","Wed","Thurs","Fri","Sat"]
        let tableRightInset: CGFloat = margin + 12 // tweak this to nudge tables further left if needed
        let summaryHorizontalShift: CGFloat = 140 // move Summary Totals left into the red-box area

        _ = store.totals(for: store.weekRange(offset: weekOffset))
        let year = Calendar.current.component(.year, from: weekDates.first ?? store.weekStart)

        return ZStack {
            Color.white

            VStack(spacing: 0) {
                // Header
                HStack(alignment: .top, spacing: 0) {
                    // Left side - Logo and Employee info combined
                    HStack(spacing: 20) {
                        // Logo
                        Group {
                            if let img = store.companyLogoImage {
                                img.resizable()
                            } else {
                                Image(store.companyLogoName ?? "logo").resizable()
                            }
                        }
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        
                        // Employee info
                        HStack(spacing: 8) { // Added spacing between fields
                            // Employee field
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Employee")
                                    .font(.system(size: 11))
                                    .bold()
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 20)
                                    .overlay(
                                        VStack(spacing: 0) {
                                            Text(store.employeeName)
                                                .font(.system(size: 10))
                                                .padding(.horizontal, 4)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Spacer()
                                            Rectangle()
                                                .fill(Color.black)
                                                .frame(height: 1)
                                        }
                                    )
                            }
                            .frame(width: 280)
                            
                            // PP # field
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PP #")
                                    .font(.system(size: 11))
                                    .bold()
                                    .frame(maxWidth: .infinity, alignment: .center)
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 20)
                                    .overlay(
                                        VStack(spacing: 0) {
                                            Text(String(store.payPeriodNumber))
                                                .font(.system(size: 10))
                                                .padding(.horizontal, 4)
                                                .frame(maxWidth: .infinity, alignment: .center)
                                            Spacer()
                                            Rectangle()
                                                .fill(Color.black)
                                                .frame(height: 1)
                                        }
                                    )
                            }
                            .frame(width: 80)
                            
                            // Year field
                            VStack(alignment: .leading, spacing: 2) {
                                Text("YEAR")
                                    .font(.system(size: 11))
                                    .bold()
                                    .frame(maxWidth: .infinity, alignment: .center)
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 20)
                                    .overlay(
                                        VStack(spacing: 0) {
                                            Text(String(year))
                                                .font(.system(size: 10))
                                                .padding(.horizontal, 4)
                                                .frame(maxWidth: .infinity, alignment: .center)
                                            Spacer()
                                            Rectangle()
                                                .fill(Color.black)
                                                .frame(height: 1)
                                        }
                                    )
                            }
                            .frame(width: 80)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, margin)
                .padding(.top, margin)
                .frame(height: 60)

                // Main content - Compact layout with minimal spacing
                ZStack(alignment: .bottomTrailing) {
                    // Left side - Main timesheet tables
                    VStack(alignment: .leading, spacing: 0) {
                        // Regular Time section
                        HStack {
                            Text("Regular Time")
                                .font(.system(size: 12, weight: .bold))
                            Spacer()
                        }
                        .padding(.bottom, 4)
                        
                        // Regular time table
                        regularTimeTable(weekDates: weekDates, weekdaysShort: weekdaysShort, df: df)
                        
                        Spacer().frame(height: 12)
                        
                        // Overtime & Double-Time section
                        HStack {
                            Text("Overtime & Double-Time")
                                .font(.system(size: 12, weight: .bold))
                            Spacer()
                        }
                        .padding(.bottom, 4)
                        
                        overtimeTable(weekDates: weekDates, weekdaysShort: weekdaysShort, df: df)
                    }
                    .padding(.leading, margin)
                    .padding(.trailing, tableRightInset) // nudge tables left to align right edge with Summary panel

                    // Summary Totals (only show on last week of pay period), aligned to the right edge of the tables
                    if weekOffset == max(0, (store.payPeriodWeeks - 1)) {
                        VStack(spacing: 0) {
                            Text("Summary Totals")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 120, height: 20)
                                .background(Color.gray.opacity(0.3))
                                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                            
                            summaryRow("Regular Time:", payPeriodRegularPlusStatAlways(), width: 120)
                            summaryRow("OT:", payPeriodCappedOT(), width: 120)
                            summaryRow("DT:", payPeriodCappedDT(), width: 120)
                            summaryRow("VP:", totalHoursForPayPeriod(type: .vacation), width: 120)
                            summaryRow("NS:", totalHoursForPayPeriod(type: .night), width: 120)
                            summaryRow("STAT:", totalHoursForPayPeriod(type: .stat), width: 120)
                            if store.onCallEnabled {
                                summaryRow("On Call:", payPeriodOnCallStipendAlways(), width: 120)
                                summaryRow("# of On Call", payPeriodOnCallCountAlways(), width: 120)
                            }
                        }
                        .padding(.trailing, margin + summaryHorizontalShift) // shift left toward red-box area
                        .padding(.bottom, margin)   // small bottom margin from the tables
                    }
                }

                Spacer()
            }
            .frame(width: pageSize.width, height: pageSize.height)
        }
    }
    
    // MARK: - Regular Time Table
    private func regularTimeTable(weekDates: [Date], weekdaysShort: [String], df: DateFormatter) -> some View {
        let dayColumnWidth: CGFloat = 60
        let dateColumnWidth: CGFloat = 60
        let laborCodeColumnWidth: CGFloat = 23
        let shiftHoursWidth: CGFloat = 30
        let notesWidth: CGFloat = 120
        
        return VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                // Sun Date header
                VStack(alignment: .center, spacing: 1) {
                    Text("Sun")
                        .font(.system(size: 8))
                        .bold()
                    Text("Date")
                        .font(.system(size: 8))
                        .bold()
                }
                .frame(width: dayColumnWidth, height: 60)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // Date header
                Text(df.string(from: weekDates[0]))
                    .font(.system(size: 8))
                    .bold()
                    .frame(width: dateColumnWidth, height: 60)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // 14 labor code columns with vertical text
                ForEach(0..<14, id: \.self) { colIndex in
                    // Get unique job/code combinations for the week including regular and night entries
                    let allEntries = weekDates.flatMap { regularEntriesFor(day: $0) + nightEntriesFor(day: $0) }
                    let uniqueEntries = Array(Set(allEntries.map { "\(displayJobText(for: $0))|\($0.code)" }))
                        .sorted()
                        .map { combo -> (jobDisplay: String, code: String) in
                            let parts = combo.split(separator: "|", omittingEmptySubsequences: false)
                            let job = parts.indices.contains(0) ? String(parts[0]) : ""
                            let code = parts.indices.contains(1) ? String(parts[1]) : ""
                            return (jobDisplay: job, code: code)
                        }
                    
                    let jobDisplay = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobDisplay : ""
                    let labourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                    
                    let isPlaceholder = jobDisplay.isEmpty && labourCode.isEmpty
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(labourCode.isEmpty ? "Labour Code:" : padToLength(labourCode, length: 10))
                            .font(.system(size: 7, weight: .regular, design: .monospaced))
                            .foregroundColor(.black)
                        Text(jobDisplay.isEmpty ? "Job:" : padToLength(jobDisplay, length: 10))
                            .font(.system(size: 7, weight: .regular, design: .monospaced))
                            .foregroundColor(.black)
                    }
                    .frame(width: 60, height: laborCodeColumnWidth, alignment: .trailing)
                    .rotationEffect(.degrees(-90))
                    .padding(.bottom, 0)
                    .offset(y: 0) // Changed from 3 to 0 per instructions
                    .offset(y: isPlaceholder ? -15 : -5) // Changed from -18 to -21 per instructions and per requested replacement
                    .frame(width: laborCodeColumnWidth, height: 60, alignment: .bottom)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                
                // Shift Hours header
                VStack(spacing: 1) {
                    Text("Shift")
                        .font(.system(size: 7))
                        .bold()
                    Text("Hours")
                        .font(.system(size: 7))
                        .bold()
                }
                .frame(width: shiftHoursWidth, height: 60)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // Notes header replaced with only the week label text (no "Regular Time:")
                Text(weekNumberString)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: notesWidth, height: 60)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
            
            // Week rows
            ForEach(0..<7, id: \.self) { i in
                // ** Changed here per instructions: include night entries in daily rendering **
                let dayRegular = regularEntriesFor(day: weekDates[i])
                let dayNight = nightEntriesFor(day: weekDates[i])
                let dayEntries = dayRegular + dayNight
                let dayTotalHours = dayEntries.reduce(0.0) { $0 + $1.hours }
                
                HStack(spacing: 0) {
                    // Day column
                    VStack(alignment: .center, spacing: 1) {
                        Text(weekdaysShort[i])
                            .font(.system(size: 8))
                            .bold()
                    }
                    .frame(width: dayColumnWidth, height: 22)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // Date column
                    Text(df.string(from: weekDates[i]))
                        .font(.system(size: 8))
                        .frame(width: dateColumnWidth, height: 22)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // 14 data columns - display hours worked
                    ForEach(0..<14, id: \.self) { colIndex in
                        // Get unique job/code combinations for the week including regular and night entries
                        let allEntries = weekDates.flatMap { regularEntriesFor(day: $0) + nightEntriesFor(day: $0) }
                        let uniqueEntries = Array(Set(allEntries.map { "\(displayJobText(for: $0))|\($0.code)" }))
                            .sorted()
                            .map { combo -> (jobDisplay: String, code: String) in
                                let parts = combo.split(separator: "|", omittingEmptySubsequences: false)
                                let job = parts.indices.contains(0) ? String(parts[0]) : ""
                                let code = parts.indices.contains(1) ? String(parts[1]) : ""
                                return (jobDisplay: job, code: code)
                            }
                        
                        let columnJobDisplay = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobDisplay : ""
                        let columnLabourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                        
                        // Find matching entry for this day and column
                        let matchingEntry = dayEntries.first { entry in
                            displayJobText(for: entry) == columnJobDisplay && entry.code == columnLabourCode
                        }
                        
                        ZStack(alignment: .bottom) {
                            if let entry = matchingEntry {
                                // Display hours worked bottom-aligned
                                Text(formatHours(entry.hours))
                                    .font(.system(size: 6))
                                    .lineLimit(1)
                                    .bold()
                                    .padding(.bottom, 4)  // Changed from 2 to 4 per instructions
                            }
                        }
                        .frame(width: laborCodeColumnWidth, height: 22, alignment: .bottom)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    }
                    
                    // Shift hours column - display total hours for day (3)
                    ZStack(alignment: .bottomTrailing) {
                        Text(dayTotalHours > 0 ? formatHours(dayTotalHours) : "")
                            .font(.system(size: 6))
                            .padding(.trailing, 2)
                            .padding(.bottom, 4)  // Changed from 2 to 4 per instructions
                    }
                    .frame(width: shiftHoursWidth, height: 22)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // Notes column - replaced with label only for first and second row plus extended labels for rows 2 to 6
                    if i == 0 {
                        ZStack {
                            Color.white
                            HStack(spacing: 4) {
                                Text("Offive use only table")
                                    .font(.system(size: 10, weight: .bold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 4)
                            }
                        }
                        .frame(width: notesWidth, height: 22)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    } else if i == 1 {
                        ZStack {
                            Color.white
                            HStack {
                                Text("Regular Time:")
                                    .font(.system(size: 8))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 4)
                                Text(totalRegularTableHoursForWeek())
                                    .font(.system(size: 8))
                                    .frame(width: 35, alignment: .trailing)
                                    .padding(.trailing, 4)
                            }
                        }
                        .frame(width: notesWidth, height: 22)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    } else if i == 2 {
                        ZStack {
                            Color.white
                            HStack {
                                Text("OT:")
                                    .font(.system(size: 8))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 4)
                                Text(weeklyOTForNotes(weekDates: weekDates))
                                    .font(.system(size: 8))
                                    .frame(width: 35, alignment: .trailing)
                                    .padding(.trailing, 4)
                            }
                        }
                        .frame(width: notesWidth, height: 22)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    } else if i == 3 {
                        ZStack {
                            Color.white
                            HStack {
                                Text("DT:")
                                    .font(.system(size: 8))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 4)
                                Text(weeklyDTForNotes(weekDates: weekDates))
                                    .font(.system(size: 8))
                                    .frame(width: 35, alignment: .trailing)
                                    .padding(.trailing, 4)
                            }
                        }
                        .frame(width: notesWidth, height: 22)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    } else if i == 4 {
                        ZStack {
                            Color.white
                            HStack {
                                Text("VP:")
                                    .font(.system(size: 8))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 4)
                                Text(totalHoursFor(type: .vacation))
                                    .font(.system(size: 8))
                                    .frame(width: 35, alignment: .trailing)
                                    .padding(.trailing, 4)
                            }
                        }
                        .frame(width: notesWidth, height: 22)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    } else if i == 5 {
                        ZStack {
                            Color.white
                            HStack {
                                Text("NS:")
                                    .font(.system(size: 8))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 4)
                                Text(totalHoursFor(type: .night))
                                    .font(.system(size: 8))
                                    .frame(width: 35, alignment: .trailing)
                                    .padding(.trailing, 4)
                            }
                        }
                        .frame(width: notesWidth, height: 22)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    } else if i == 6 {
                        ZStack {
                            Color.white
                            HStack {
                                Text("STAT:")
                                    .font(.system(size: 8))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 4)
                                Text(totalHoursFor(type: .stat))
                                    .font(.system(size: 8))
                                    .frame(width: 35, alignment: .trailing)
                                    .padding(.trailing, 4)
                            }
                        }
                        .frame(width: notesWidth, height: 22)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    } else {
                        ZStack {
                            Color.white
                        }
                        .frame(width: notesWidth, height: 22)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    }
                }
            }
            

            // Total Regular row
            HStack(spacing: 0) {
                Text("Regular Time:")
                    .font(.system(size: 8))
                    .bold()
                    .frame(width: dayColumnWidth + dateColumnWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // Calculate column totals for regular time - NO CHANGE here to keep totals restricted to Regular table categories
                ForEach(0..<14, id: \.self) { colIndex in
                    // Get unique job/code combinations for the week including regular and night entries
                    let allEntries = weekDates.flatMap { regularEntriesFor(day: $0) + nightEntriesFor(day: $0) }
                    let uniqueEntries = Array(Set(allEntries.map { "\(displayJobText(for: $0))|\($0.code)" }))
                        .sorted()
                        .map { combo -> (jobDisplay: String, code: String) in
                            let parts = combo.split(separator: "|", omittingEmptySubsequences: false)
                            let job = parts.indices.contains(0) ? String(parts[0]) : ""
                            let code = parts.indices.contains(1) ? String(parts[1]) : ""
                            return (jobDisplay: job, code: code)
                        }
                    
                    let columnJobDisplay = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobDisplay : ""
                    let columnLabourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                    
                    // Calculate total hours for this column across all days
                    let columnTotal = weekDates.reduce(0.0) { total, date in
                        // ** Keep only regular entries here for totals (no change) **
                        let dayEntries = regularEntriesFor(day: date)
                        let matchingEntry = dayEntries.first { entry in
                            displayJobText(for: entry) == columnJobDisplay && entry.code == columnLabourCode
                        }
                        return total + (matchingEntry?.hours ?? 0.0)
                    }
                    
                    ZStack(alignment: .bottomTrailing) {
                        Text(columnTotal > 0 ? formatHours(columnTotal) : "")
                            .font(.system(size: 6))
                            .bold()
                            .padding(.trailing, 2)
                            .padding(.bottom, 4)  // Changed from 2 to 4 per instructions
                    }
                    .frame(width: laborCodeColumnWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                
                Text(totalRegularTableHoursForWeek())
                    .font(.system(size: 6))
                    .bold()
                    .frame(width: shiftHoursWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                ZStack {
                    Color.white
                    HStack {
                        Text("On Call:")
                            .font(.system(size: 8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 4)
                        Text(weekOnCallAmountString())
                            .font(.system(size: 8))
                            .frame(width: 35, alignment: .trailing)
                            .padding(.trailing, 4)
                    }
                }
                .frame(width: notesWidth, height: 18)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
            
            // Total Night row
            HStack(spacing: 0) {
                Text("TOTAL NIGHT")
                    .font(.system(size: 8))
                    .bold()
                    .frame(width: dayColumnWidth + dateColumnWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                ForEach(0..<14, id: \.self) { colIndex in
                    let allEntries = weekDates.flatMap { regularEntriesFor(day: $0) + nightEntriesFor(day: $0) }
                    let uniqueEntries = Array(Set(allEntries.map { "\(displayJobText(for: $0))|\($0.code)" }))
                        .sorted()
                        .map { combo -> (jobDisplay: String, code: String) in
                            let parts = combo.split(separator: "|", omittingEmptySubsequences: false)
                            let job = parts.indices.contains(0) ? String(parts[0]) : ""
                            let code = parts.indices.contains(1) ? String(parts[1]) : ""
                            return (jobDisplay: job, code: code)
                        }
                    let columnJobDisplay = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobDisplay : ""
                    let columnLabourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                    let columnTotal = weekDates.reduce(0.0) { total, date in
                        let dayEntries = nightEntriesFor(day: date)
                        let matchingEntry = dayEntries.first { entry in
                            displayJobText(for: entry) == columnJobDisplay && entry.code == columnLabourCode
                        }
                        return total + (matchingEntry?.hours ?? 0.0)
                    }
                    ZStack(alignment: .bottomTrailing) {
                        Text(columnTotal > 0 ? formatHours(columnTotal) : "")
                            .font(.system(size: 6))
                            .bold()
                            .padding(.trailing, 2)
                            .padding(.bottom, 4)  // Changed from 2 to 4 per instructions
                    }
                    .frame(width: laborCodeColumnWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                Text(totalHoursFor(type: .night))
                    .font(.system(size: 6))
                    .bold()
                    .frame(width: shiftHoursWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                ZStack {
                    Color.white
                    HStack {
                        Text("# of On Call")
                            .font(.system(size: 8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 4)
                        Text(weekOnCallCountString())
                            .font(.system(size: 8))
                            .frame(width: 35, alignment: .trailing)
                            .padding(.trailing, 4)
                    }
                }
                .frame(width: notesWidth, height: 18)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
        }
    }
    
    // MARK: - Overtime Table
    private func overtimeTable(weekDates: [Date], weekdaysShort: [String], df: DateFormatter) -> some View {
        let dayColumnWidth: CGFloat = 60
        let dateColumnWidth: CGFloat = 60
        let laborCodeColumnWidth: CGFloat = 23
        let overtimeWidth: CGFloat = 30
        let doubleTimeWidth: CGFloat = 30
        
        let policyMap = computeWeekOTDT(weekDates: weekDates)
        
        return VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                // Date header
                Text("Date:")
                    .font(.system(size: 8))
                    .bold()
                    .frame(width: dayColumnWidth, height: 60)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // Date value
                Text(df.string(from: weekDates[0]))
                    .font(.system(size: 8))
                    .bold()
                    .frame(width: dateColumnWidth, height: 60)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // 8 labor code columns with vertical text
                ForEach(0..<8, id: \.self) { colIndex in
                    // Get unique job/code combinations for the week
                    let allOvertimeEntries = weekDates.flatMap { overtimeEntriesFor(day: $0) }
                    let uniqueEntries = Array(Set(allOvertimeEntries.map { "\($0.jobNumber)|\($0.code)" }))
                        .sorted()
                        .map { combo -> (jobNumber: String, code: String) in
                            let parts = combo.split(separator: "|", omittingEmptySubsequences: false)
                            let job = parts.indices.contains(0) ? String(parts[0]) : ""
                            let code = parts.indices.contains(1) ? String(parts[1]) : ""
                            return (job, code)
                        }
                    
                    let jobNumber = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobNumber : ""
                    let labourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                    
                    let isPlaceholder = jobNumber.isEmpty && labourCode.isEmpty
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(labourCode.isEmpty ? "Labour Code:" : padToLength(labourCode, length: 10))
                            .font(.system(size: 7, weight: .regular, design: .monospaced))
                            .foregroundColor(.black)
                        Text(jobNumber.isEmpty ? "Job:" : padToLength(jobNumber, length: 8))
                            .font(.system(size: 7, weight: .regular, design: .monospaced))
                            .foregroundColor(.black)
                    }
                    .frame(width: 60, height: laborCodeColumnWidth, alignment: .trailing)
                    .rotationEffect(.degrees(-90))
                    .padding(.bottom, 0)
                    .offset(y: 0) // Changed from 3 to 0 per instructions
                    .offset(y: isPlaceholder ? -15 : -5) // Changed from -18 to -21 per instructions and per requested replacement
                    .frame(width: laborCodeColumnWidth, height: 60, alignment: .bottom)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                
                // Overtime header
                
                Text("Overtime")
                    .font(.system(size: 7))
                    .bold()
                    .rotationEffect(.degrees(-90))
                    .frame(width: overtimeWidth, height: 60)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    .padding(.bottom, 0)
                
                // Double-Time header
                Text("Double Time")
                    .font(.system(size: 7))
                    .bold()
                    .rotationEffect(.degrees(-90))
                    .frame(width: doubleTimeWidth, height: 60)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
            
            // Week rows
            ForEach(0..<7, id: \.self) { i in
                let day = weekDates[i]
                let dayOvertimeEntries: [Entry] = overtimeEntriesFor(day: day)
                let policy = policyMap[Calendar.current.startOfDay(for: day)] ?? (0,0)
                
                // Updated per instructions: add explicitOnCallHours to OT total calculation
                let explicit = explicitCappedOTDT(for: day)
                // Changed per instructions: removed adding onCall hours here
                // Apply OT cap of 4 hours and roll excess into DT
                let combinedOT = explicit.ot + policy.ot
                let combinedDT = explicit.dt + policy.dt
                let overflowToDT = max(0.0, combinedOT - 4.0)
                let dayOvertimeHours = min(combinedOT, 4.0)
                let dayDoubleTimeHours = combinedDT + overflowToDT
                
                HStack(spacing: 0) {
                    // Day column
                    Text(weekdaysShort[i])
                        .font(.system(size: 8))
                        .bold()
                        .frame(width: dayColumnWidth, height: 22)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // Date column
                    Text(df.string(from: weekDates[i]))
                        .font(.system(size: 8))
                        .frame(width: dateColumnWidth, height: 22)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // 8 data columns - display hours worked
                    ForEach(0..<8, id: \.self) { colIndex in
                        // Get unique job/code combinations for the week
                        let allOvertimeEntries = weekDates.flatMap { overtimeEntriesFor(day: $0) }
                        let uniqueEntries = Array(Set(allOvertimeEntries.map { "\($0.jobNumber)|\($0.code)" }))
                            .sorted()
                            .map { combo -> (jobNumber: String, code: String) in
                                let parts = combo.split(separator: "|", omittingEmptySubsequences: false)
                                let job = parts.indices.contains(0) ? String(parts[0]) : ""
                                let code = parts.indices.contains(1) ? String(parts[1]) : ""
                                return (job, code)
                            }
                        
                        let columnJobNumber = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobNumber : ""
                        let columnLabourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                        
                        // Find matching entry for this day and column
                        let matchingEntry = dayOvertimeEntries.first { entry in
                            entry.jobNumber == columnJobNumber && entry.code == columnLabourCode
                        }
                        
                        ZStack(alignment: .bottom) {
                            if let entry = matchingEntry {
                                // Display hours worked bottom-aligned
                                Text(formatHours(entry.hours))
                                    .font(.system(size: 6))
                                    .lineLimit(1)
                                    .bold()
                                    .padding(.bottom, 4)  // Changed from 2 to 4 per instructions
                            }
                        }
                        .frame(width: laborCodeColumnWidth, height: 22, alignment: .bottom)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    }
                    
                    // Overtime column - bottom-trailing
                    ZStack(alignment: .bottomTrailing) {
                        Text(dayOvertimeHours > 0 ? formatHours(dayOvertimeHours) : "")
                            .font(.system(size: 6))
                            .padding(.trailing, 2)
                            .padding(.bottom, 4)  // Changed from 2 to 4 per instructions
                    }
                    .frame(width: overtimeWidth, height: 22)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    
                    // Double-Time column - bottom-trailing
                    ZStack(alignment: .bottomTrailing) {
                        Text(dayDoubleTimeHours > 0 ? formatHours(dayDoubleTimeHours) : "")
                            .font(.system(size: 6))
                            .padding(.trailing, 2)
                            .padding(.bottom, 4)  // Changed from 2 to 4 per instructions
                    }
                    .frame(width: doubleTimeWidth, height: 22)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
            }
            
            // Total Overtime row
            HStack(spacing: 0) {
                // Label spanning the first two columns (day + date)
                Text("TOTAL OVERTIME")
                    .font(.system(size: 8))
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .frame(width: dayColumnWidth + dateColumnWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                // Calculate column totals for overtime
                ForEach(0..<8, id: \.self) { colIndex in
                    // Get unique job/code combinations for the week
                    let allOvertimeEntries = weekDates.flatMap { overtimeEntriesFor(day: $0) }
                    let uniqueEntries = Array(Set(allOvertimeEntries.map { "\($0.jobNumber)|\($0.code)" }))
                        .sorted()
                        .map { combo -> (jobNumber: String, code: String) in
                            let parts = combo.split(separator: "|", omittingEmptySubsequences: false)
                            let job = parts.indices.contains(0) ? String(parts[0]) : ""
                            let code = parts.indices.contains(1) ? String(parts[1]) : ""
                            return (job, code)
                        }
                    
                    let columnJobNumber = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].jobNumber : ""
                    let columnLabourCode = colIndex < uniqueEntries.count ? uniqueEntries[colIndex].code : ""
                    
                    // Calculate total hours for this column across all days
                    let columnTotal = weekDates.reduce(0.0) { total, date in
                        let dayEntries = overtimeEntriesFor(day: date)
                        let matchingEntry = dayEntries.first { entry in
                            entry.jobNumber == columnJobNumber && entry.code == columnLabourCode
                        }
                        return total + (matchingEntry?.hours ?? 0.0)
                    }
                    
                    ZStack(alignment: .bottomTrailing) {
                        Text(columnTotal > 0 ? formatHours(columnTotal) : "")
                            .font(.system(size: 6))
                            .bold()
                            .padding(.trailing, 2)
                            .padding(.bottom, 4)  // Changed from 2 to 4 per instructions
                    }
                    .frame(width: laborCodeColumnWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                
                // Updated weeklyOTTotal to exclude on-call hours as per instructions
                let weeklyOTTotal = weekDates.reduce(0.0) { sum, d in
                    let key = Calendar.current.startOfDay(for: d)
                    let policy = policyMap[key] ?? (0,0)
                    let explicit = explicitCappedOTDT(for: d)
                    let combinedOT = explicit.ot + policy.ot
                    let cappedOT = min(combinedOT, 4.0)
                    return sum + cappedOT
                }
                Text(formatHours(weeklyOTTotal))
                    .font(.system(size: 6))
                    .bold()
                    .frame(width: overtimeWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                
                let weeklyDTTotal = weekDates.reduce(0.0) { sum, d in
                    let key = Calendar.current.startOfDay(for: d)
                    let policy = policyMap[key] ?? (0,0)
                    let explicit = explicitCappedOTDT(for: d)
                    let combinedOT = explicit.ot + policy.ot
                    let combinedDT = explicit.dt + policy.dt
                    let overflowToDT = max(0.0, combinedOT - 4.0)
                    return sum + combinedDT + overflowToDT
                }
                Text(formatHours(weeklyDTTotal))
                    .font(.system(size: 6))
                    .bold()
                    .frame(width: doubleTimeWidth, height: 18)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
            
            // Approved by row
            HStack(spacing: 0) {
                // Merged Day + Date cell with label
                HStack {
                    Text("Approved by:")
                        .font(.system(size: 8))
                        .padding(.leading, 4)
                    Spacer()
                }
                .frame(width: dayColumnWidth + dateColumnWidth, height: 18)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))

                // 8 labor code columns (empty)
                ForEach(0..<8, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: laborCodeColumnWidth, height: 18)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                
                // Overtime column (empty)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: overtimeWidth, height: 18)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))

                // Double-Time column (empty)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: doubleTimeWidth, height: 18)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
        }
    }
}

// MARK: - Helpers
private func summaryRow(_ label: String, _ value: String, width: CGFloat) -> some View {
    HStack(spacing: 0) {
        Text(label)
            .font(.system(size: 8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
        Text(value)
            .font(.system(size: 8))
            .frame(width: 35, alignment: .trailing)
            .padding(.trailing, 4)
    }
    .frame(width: width, height: 16)
    .background(Color.white)
    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
}
#Preview {
    TimecardPDFView()
        .environmentObject(TimecardStore.sampleStore)
}

