import Foundation
import SwiftUI
import Combine
import SwiftData

// MARK: - Country and Province Enums
enum Country: String, CaseIterable {
    case canada = "Canada"
    case unitedStates = "United States"
    
    var displayName: String { rawValue }
}

enum USState: String, CaseIterable {
    case newMexico = "New Mexico"
    
    var displayName: String { rawValue }
}

enum Province: String, CaseIterable {
    case alberta = "Alberta"
    case britishColumbia = "British Columbia"
    case manitoba = "Manitoba"
    case newBrunswick = "New Brunswick"
    case newfoundlandAndLabrador = "Newfoundland and Labrador"
    case northwestTerritories = "Northwest Territories"
    case novaScotia = "Nova Scotia"
    case nunavut = "Nunavut"
    case ontario = "Ontario"
    case princeEdwardIsland = "Prince Edward Island"
    var displayName: String { rawValue }
    
    case quebec = "Quebec"
    case saskatchewan = "Saskatchewan"
    case yukon = "Yukon"
}

// MARK: - StatHoliday Struct
struct StatHoliday: Identifiable, Codable {
    let id = UUID()
    let name: String
    let date: Date
    let isObserved: Bool
    
    private enum CodingKeys: String, CodingKey {
        case name
        case date
        case isObserved
    }
    
    init(name: String, date: Date, isObserved: Bool = false) {
        self.name = name
        self.date = date
        self.isObserved = isObserved
    }
}

// MARK: - HolidayManager Class
class HolidayManager: ObservableObject {
    @Published var selectedCountry: Country = .canada
    @Published var selectedProvince: Province = .britishColumbia
    
    @Published var autoDetectRegion: Bool = false
    @Published var selectedState: USState = .newMexico
    
    // Debug logging toggle for holiday networking/decoding
    @AppStorage("holidayDebugLogging") var holidayDebugLogging: Bool = false
    
    // Human-readable region and cache status for Settings UI
    var regionStatusLine: String {
        let country: String
        switch selectedCountry {
        case .canada: country = "CA"
        case .unitedStates: country = "US"
        }
        var parts: [String] = [country]
        // Prefer state when US, province when Canada
        if selectedCountry == .unitedStates {
            parts.append(selectedState.displayName)
        } else {
            parts.append(selectedProvince.displayName)
        }
        return "Detected: " + parts.joined(separator: " / ")
    }

    var cachedYearsStatusLine: String {
        // Derive a set of cached years for the current region key
        let countryCode: String = {
            switch selectedCountry { case .canada: return "CA"; case .unitedStates: return "US" }
        }()
        let adminCode: String = {
            if selectedCountry == .unitedStates {
                // Use common USPS-style abbreviations when possible
                let name = selectedState.displayName
                // Simple mapping for the one we currently support
                if name == "New Mexico" { return "NM" }
                return name
            } else {
                let name = selectedProvince.displayName
                if name == "British Columbia" { return "BC" }
                return name
            }
        }()
        let prefix = "\(countryCode)-\(adminCode)-"
        // cachedHolidays may be private; expose years by filtering keys if available.
        // If not accessible, return an empty status.
        let keysMirror = Mirror(reflecting: self)
        if let cached = keysMirror.children.first(where: { $0.label == "cachedHolidays" })?.value as? [String: [StatHoliday]] {
            let years = cached.keys.compactMap { key -> Int? in
                guard key.hasPrefix(prefix) else { return nil }
                let comps = key.split(separator: "-")
                guard let last = comps.last, let y = Int(last) else { return nil }
                return y
            }
            let sorted = Array(Set(years)).sorted()
            guard !sorted.isEmpty else { return "Cached: none" }
            let list = sorted.map(String.init).joined(separator: ", ")
            return "Cached: \(list)"
        }
        return "Cached: none"
    }
    
    private let calendar = Calendar.current
    private var cachedHolidays: [String: [StatHoliday]] = [:]
    
    // MARK: - Cache management for detected region
    private func currentRegionCachePrefix() -> String {
        let countryCode: String = {
            switch selectedCountry { case .canada: return "CA"; case .unitedStates: return "US" }
        }()
        let adminCode: String = {
            if selectedCountry == .unitedStates {
                let name = selectedState.displayName
                if name == "New Mexico" { return "NM" }
                return name
            } else {
                let name = selectedProvince.displayName
                if name == "British Columbia" { return "BC" }
                return name
            }
        }()
        return "\(countryCode)-\(adminCode)-"
    }

    /// Removes cached holidays for all regions except the currently selected one.
    func purgeHolidayCacheExceptCurrentRegion() {
        let prefix = currentRegionCachePrefix()
        cachedHolidays = cachedHolidays.filter { key, _ in key.hasPrefix(prefix) }
    }
    
    func getStatHolidays(for year: Int) -> [StatHoliday] {
        var holidays: [StatHoliday] = []

        // Core Canadian statutory holidays (fixed or common across provinces)
        let newYears = dateComponents(year: year, month: 1, day: 1)
        let canadaDay = dateComponents(year: year, month: 7, day: 1)
        let christmas = dateComponents(year: year, month: 12, day: 25)

        // Good Friday (two days before Easter Sunday)
        let easter = easterSunday(year: year)
        let goodFriday = calendar.date(byAdding: .day, value: -2, to: easter) ?? easter

        // Victoria Day: Monday preceding May 25 (last Monday on or before May 24)
        let victoriaDay = lastWeekdayOnOrBefore(year: year, month: 5, day: 24, weekday: 2)

        // Labour Day: first Monday in September
        let labourDay = getNthWeekday(year: year, month: 9, weekday: 2, occurrence: 1)

        // Thanksgiving: second Monday in October
        let thanksgiving = getNthWeekday(year: year, month: 10, weekday: 2, occurrence: 2)

        // Remembrance Day: November 11
        let remembranceDay = dateComponents(year: year, month: 11, day: 11)

        // Append fixed-date holidays and their observed dates (if weekend)
        holidays.append(StatHoliday(name: "New Year's Day", date: newYears))
        if let observedNY = observedDate(for: newYears) {
            holidays.append(StatHoliday(name: "New Year's Day (Observed)", date: observedNY, isObserved: true))
        }

        holidays.append(StatHoliday(name: "Canada Day", date: canadaDay))
        if let observedCD = observedDate(for: canadaDay) {
            holidays.append(StatHoliday(name: "Canada Day (Observed)", date: observedCD, isObserved: true))
        }

        holidays.append(StatHoliday(name: "Remembrance Day", date: remembranceDay))
        if let observedRD = observedDate(for: remembranceDay) {
            holidays.append(StatHoliday(name: "Remembrance Day (Observed)", date: observedRD, isObserved: true))
        }

        holidays.append(StatHoliday(name: "Christmas Day", date: christmas))
        if let observedXmas = observedDate(for: christmas) {
            holidays.append(StatHoliday(name: "Christmas Day (Observed)", date: observedXmas, isObserved: true))
        }

        // Append moveable-date holidays (no observed variants needed)
        holidays.append(contentsOf: [
            StatHoliday(name: "Good Friday", date: goodFriday),
            StatHoliday(name: "Victoria Day", date: victoriaDay),
            StatHoliday(name: "Labour Day", date: labourDay),
            StatHoliday(name: "Thanksgiving Day", date: thanksgiving)
        ])

        // Province-specific additions (BC)
        if selectedProvince == .britishColumbia {
            // Family Day: third Monday in February (BC since 2019)
            let familyDay = getNthWeekday(year: year, month: 2, weekday: 2, occurrence: 3)
            holidays.append(StatHoliday(name: "Family Day", date: familyDay))

            // BC Day: first Monday in August
            let bcDay = getNthWeekday(year: year, month: 8, weekday: 2, occurrence: 1)
            holidays.append(StatHoliday(name: "BC Day", date: bcDay))

            // National Day for Truth and Reconciliation: September 30 (BC statutory since 2023)
            if year >= 2023 {
                let ndtr = dateComponents(year: year, month: 9, day: 30)
                holidays.append(StatHoliday(name: "National Day for Truth and Reconciliation", date: ndtr))
                if let observedNDTR = observedDate(for: ndtr) {
                    holidays.append(StatHoliday(name: "National Day for Truth and Reconciliation (Observed)", date: observedNDTR, isObserved: true))
                }
            }
        }

        return holidays.sorted { $0.date < $1.date }
    }
    
    /// Auto detects region via RegionLocator and updates selectedCountry, selectedProvince, selectedState.
    /// Logs detection and updates on main actor.
    func autoDetectAndApplyRegion() async {
        guard autoDetectRegion else { return }
        do {
            let region = try await RegionLocator.shared.detectRegion()
            let isoCountry = region.countryCode ?? ""
            let adminCode = region.adminCode ?? ""
            
            var detectedCountry: Country = .canada
            if isoCountry.uppercased() == "US" {
                detectedCountry = .unitedStates
            } else if isoCountry.uppercased() == "CA" {
                detectedCountry = .canada
            }
            
            await MainActor.run {
                self.selectedCountry = detectedCountry
                
                switch detectedCountry {
                case .canada:
                    // Map adminCode to Province if possible
                    if adminCode.uppercased() == "BC" {
                        self.selectedProvince = .britishColumbia
                    }
                    // Could add more mappings here if desired
                case .unitedStates:
                    // Map adminCode to State if possible
                    if adminCode.uppercased() == "NM" {
                        self.selectedState = .newMexico
                    }
                    // Could add more mappings here if desired
                }
                // After applying detected region, purge cached holidays for other regions
                self.purgeHolidayCacheExceptCurrentRegion()
                
                // Notify listeners that region changed so overtime policy can update
                NotificationCenter.default.post(name: .regionDidChange, object: nil)
                
                // Preload holidays for current and adjacent years for the detected region
                let currentYear = Calendar.current.component(.year, from: Date())
                Task { [weak self] in
                    guard let self = self else { return }
                    for year in (currentYear - 1)...(currentYear + 1) {
                        _ = await self.holidays(for: year)
                    }
                }
            }
            
            print("Detected region - Country: \(detectedCountry.rawValue), Admin code: \(adminCode)")
        } catch {
            print("Failed to detect region: \(error)")
        }
    }
    
    /// Returns cached holidays if present, else attempts to fetch from Nager.Date API asynchronously.
    /// Falls back to local getStatHolidays if fetch fails.
    func holidays(for year: Int) async -> [StatHoliday] {
        let countryKey = selectedCountry.rawValue.lowercased()
        let adminKey: String
        switch selectedCountry {
        case .canada:
            adminKey = selectedProvince.rawValue.lowercased()
        case .unitedStates:
            adminKey = selectedState.rawValue.lowercased()
        }
        let cacheKey = "\(countryKey)-\(adminKey)-\(year)"
        
        if let cached = cachedHolidays[cacheKey] {
            return cached
        }
        
        do {
            // Nager.Date API only accepts country code ISO, no state/province. Ignore adminKey for now.
            let countryCodeISO: String
            switch selectedCountry {
            case .canada:
                countryCodeISO = "CA"
            case .unitedStates:
                countryCodeISO = "US"
            }
            let fetchedHolidays = try await fetchNagerHolidays(countryCode: countryCodeISO, year: year)
            // Merge with locally computed holidays and de-duplicate by date (prefer remote titles)
            let local = getStatHolidays(for: year)
            var byDay: [String: StatHoliday] = [:]
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = TimeZone(secondsFromGMT: 0)
            for h in local { byDay[df.string(from: h.date)] = h }
            for h in fetchedHolidays { byDay[df.string(from: h.date)] = h }
            let merged = byDay.values.sorted { $0.date < $1.date }
            if holidayDebugLogging {
                print("[Holidays] cacheKey=\(cacheKey) remote=\(fetchedHolidays.count) local=\(local.count) merged=\(merged.count)")
            }
            cachedHolidays[cacheKey] = merged
            return merged
        } catch {
            if holidayDebugLogging {
                print("[Holidays] Remote fetch failed for \(cacheKey): \(error). Falling back to local calculation.")
            } else {
                print("[Holidays] Remote fetch failed. Using local holidays.")
            }
            let localHolidays = getStatHolidays(for: year)
            cachedHolidays[cacheKey] = localHolidays
            return localHolidays
        }
    }
    
    /// Fetches public holidays from Nager.Date API for a given country code and year.
    /// Decodes into StatHoliday array.
    private func fetchNagerHolidays(countryCode: String, year: Int) async throws -> [StatHoliday] {
        guard let url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(year)/\(countryCode)") else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        struct NagerHoliday: Decodable {
            let date: String
            let localName: String?
            let name: String
            let countryCode: String?
            let fixed: Bool?
            let global: Bool?
            let counties: [String]?
            let launchYear: Int?
            let type: String?      // Some API variants provide a single type
            let types: [String]?   // Others provide an array of types
        }
        
        let decoder = JSONDecoder()
        let nagerHolidays = try decoder.decode([NagerHoliday].self, from: data)
        
        if holidayDebugLogging {
            print("[Holidays] Fetched \(nagerHolidays.count) items from Nager for \(countryCode) \(year)")
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let statHolidays = nagerHolidays.compactMap { nh -> StatHoliday? in
            guard let d = dateFormatter.date(from: nh.date) else { return nil }
            let title = (nh.localName?.isEmpty == false) ? nh.localName! : nh.name
            return StatHoliday(name: title, date: d, isObserved: false)
        }
        
        return statHolidays.sorted { $0.date < $1.date }
    }
    
    private func dateComponents(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components) ?? Date()
    }
    
    private func getNthWeekday(year: Int, month: Int, weekday: Int, occurrence: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.weekday = weekday
        components.weekdayOrdinal = occurrence
        return calendar.date(from: components) ?? Date()
    }

    /// Compute Easter Sunday for a given year (Gregorian calendar) using Meeus/Jones/Butcher algorithm.
    private func easterSunday(year: Int) -> Date {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31 // 3 = March, 4 = April
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return dateComponents(year: year, month: month, day: day)
    }

    /// Last occurrence of `weekday` on or before the given day in a month (e.g., last Monday on/before May 24).
    private func lastWeekdayOnOrBefore(year: Int, month: Int, day: Int, weekday: Int) -> Date {
        var comp = DateComponents()
        comp.year = year
        comp.month = month
        comp.day = day
        let base = calendar.date(from: comp) ?? dateComponents(year: year, month: month, day: day)
        let baseWeekday = calendar.component(.weekday, from: base)
        let delta = (baseWeekday - weekday + 7) % 7 // days to step back to target weekday
        return calendar.date(byAdding: .day, value: -delta, to: base) ?? base
    }

    /// Returns the observed date for a fixed-date holiday when it falls on a weekend.
    /// Rule: If Saturday or Sunday, observed on the following Monday; otherwise nil.
    private func observedDate(for fixedDate: Date) -> Date? {
        let weekday = calendar.component(.weekday, from: fixedDate)
        // Sunday = 1, Monday = 2, ..., Saturday = 7
        switch weekday {
        case 1: // Sunday -> observed Monday
            return calendar.date(byAdding: .day, value: 1, to: fixedDate)
        case 7: // Saturday -> observed Monday
            return calendar.date(byAdding: .day, value: 2, to: fixedDate)
        default:
            return nil
        }
    }

    // MARK: - Query helpers
    func isStatHoliday(_ date: Date) -> Bool {
        let year = calendar.component(.year, from: date)
        // Include adjacent years to handle holidays near year boundaries
        let holidays = getStatHolidays(for: year - 1)
                    + getStatHolidays(for: year)
                    + getStatHolidays(for: year + 1)
        return holidays.contains { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func holidayName(for date: Date) -> String? {
        let year = calendar.component(.year, from: date)
        // Include adjacent years to handle holidays near year boundaries
        let holidays = getStatHolidays(for: year - 1)
                    + getStatHolidays(for: year)
                    + getStatHolidays(for: year + 1)
        return holidays.first { calendar.isDate($0.date, inSameDayAs: date) }?.name
    }
}

// MARK: - Overtime Policies
/// Describes how daily/weekly overtime should be computed for a region.
struct OvertimePolicy: Codable, Equatable {
    // Daily thresholds
    var dailyRegularCap: Double?   // e.g., 8.0 means OT starts after 8
    var dailyOTCap: Double?        // e.g., 12.0 means DT starts after 12 (OT applies between regularCap..OTCap)
    // Weekly thresholds (optional; not used yet in PDF view but available)
    var weeklyRegularCap: Double?  // e.g., 40.0 means OT after 40 in a week

    static let bcCanada: OvertimePolicy = .init(dailyRegularCap: 8, dailyOTCap: 12, weeklyRegularCap: nil)
    static let usFederalCommon: OvertimePolicy = .init(dailyRegularCap: nil, dailyOTCap: nil, weeklyRegularCap: 40) // OT after 40/wk (no daily OT federally)
    static let defaultInternational: OvertimePolicy = .init(dailyRegularCap: 8, dailyOTCap: 12, weeklyRegularCap: nil)
}

extension HolidayManager {
    /// Best-effort mapping from selected region to an overtime policy.
    func inferredOvertimePolicy() -> OvertimePolicy {
        switch selectedCountry {
        case .canada:
            // Many Canadian provinces use daily 8/12; customize per province as needed
            return .bcCanada
        case .unitedStates:
            // Default to federal-style weekly OT
            return .usFederalCommon
        }
    }
}

// MARK: - Labour codes
struct LabourCode: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String  // Changed from 'let' to 'var'
    var code: String  // Changed from 'let' to 'var'
}

// MARK: - Jobs
struct Job: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var code: String
}

// MARK: - Entry model
struct Entry: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    var jobNumber: String
    var code: String
    var hours: Double
    var notes: String
    var isOvertime: Bool
    var isNightShift: Bool

    init(
        id: UUID = UUID(),
        date: Date,
        jobNumber: String = "",
        code: String = "",
        hours: Double = 0,
        notes: String = "",
        isOvertime: Bool = false,
        isNightShift: Bool = false
    ) {
        self.id = id
        self.date = date
        self.jobNumber = jobNumber
        self.code = code
        self.hours = hours
        self.notes = notes
        self.isOvertime = isOvertime
        self.isNightShift = isNightShift
    }
}

// MARK: - Legacy Compatibility Extension
// Old code expects properties like `lgSummaryDate`.
// Map them to the new Entry properties.
extension Entry {
    var lgSummaryDate: Date { date }
    var lgSummaryCode: String { code }
    var lgSummaryHours: Double { hours }
    var lgSummaryNotes: String { notes }
}

// MARK: - Summary types
enum PayCategory: String, CaseIterable, Codable {
    case regular = "Regular Time"
    case ot      = "OT"
    case dt      = "DT"
    case vacation = "Vacation (VP)"
    case night   = "Night Shift (NS)"
    case stat    = "STAT Holiday"
    case onCall  = "On Call"
}

struct SummaryTotals: Codable {
    var regular: Double = 0
    var ot: Double = 0
    var dt: Double = 0
    var vacation: Double = 0
    var night: Double = 0
    var stat: Double = 0
    var onCall: Double = 0.0
    var onCallBonus: Double = 0.0

    var totalHours: Double { regular + ot + dt + vacation + night + stat }
}

// MARK: - TimecardStore
final class TimecardStore: ObservableObject {
    
    // MARK: - Official Labour Codes (single source of truth)
    static let officialLabourCodes: [LabourCode] = [
        LabourCode(name: "Cable Pull", code: "201"),
        LabourCode(name: "Head End", code: "206"),
        LabourCode(name: "Field Devices", code: "207"),
        LabourCode(name: "Testing/Verification", code: "223"),
        LabourCode(name: "System Commissioning System Training", code: "225"),
        LabourCode(name: "Clean-Up", code: "226"),
        LabourCode(name: "Travel Time", code: "227"),
        LabourCode(name: "Forman Supervision", code: "228"),
        LabourCode(name: "Down Time", code: "229"),
        LabourCode(name: "Shop Drawings", code: "394"),
        LabourCode(name: "Warranty", code: "WA"),
        LabourCode(name: "Estimating", code: "ES"),
        LabourCode(name: "Inhouse Training", code: "TR"),
        LabourCode(name: "Lab/Office", code: "RP"),
        LabourCode(name: "Service", code: "SJ"),
        LabourCode(name: "Vacation", code: "VP"),
        LabourCode(name: "Sick", code: "S"),
        LabourCode(name: "STAT", code: "H"),
        LabourCode(name: "On Call", code: "OC"),
    ]

    // Legacy items we must remove if encountered in persisted data
    static let deprecatedJobNames: Set<String> = ["Surrey", "Burnaby", "VGH", "Richmond"]
    
    // SwiftData context (wired from BootstrapView)
    var modelContext: ModelContext?
    
    // Prevent re-entrant persistence during initial load
    private var isSyncingFromStore = false

    // MARK: - Jobs seeding from bundled CSV
    /// Attempts to load a CSV named "JobsSeed.csv" from the app bundle.
    /// Expected columns: Code,Name (header optional). Returns parsed jobs or empty on failure.
    static func loadBundledJobsSeed() -> [Job] {
        guard let url = Bundle.main.url(forResource: "JobsSeed", withExtension: "csv") else { return [] }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parseJobsCSV(text)
    }

    /// Parse CSV/TSV/plain lines into jobs. Accepts headers Code,Name or no header.
    static func parseJobsCSV(_ text: String) -> [Job] {
        let lines = text.split(whereSeparator: { $0.isNewline })
        var jobs: [Job] = []
        for (idx, lineSub) in lines.enumerated() {
            let raw = String(lineSub)
            // Split on comma or tab; fallback to space-split CODE NAME...
            var parts = raw.components(separatedBy: [",", "\t"]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if parts.count < 2 {
                if let space = raw.firstIndex(of: " ") {
                    let code = String(raw[..<space]).trimmingCharacters(in: .whitespaces)
                    let name = String(raw[space...]).trimmingCharacters(in: .whitespaces)
                    if !code.isEmpty && !name.isEmpty { parts = [code, name] }
                }
            }
            guard parts.count >= 2 else { continue }
            // Skip header if present
            if idx == 0 && parts[0].localizedCaseInsensitiveContains("code") && parts[1].localizedCaseInsensitiveContains("name") {
                continue
            }
            let code = parts[0]
            let name = parts.dropFirst().joined(separator: " ")
            jobs.append(Job(name: name, code: code))
        }
        // Deduplicate by code (keep first occurrence)
        var seen: Set<String> = []
        var dedup: [Job] = []
        for j in jobs {
            let key = j.code.uppercased()
            if !seen.contains(key) { seen.insert(key); dedup.append(j) }
        }
        return dedup
    }

    /// Replaces current jobs with bundled seed if available. Returns true on success.
    @discardableResult
    func replaceJobsWithBundledSeed() -> Bool {
        let seed = Self.loadBundledJobsSeed()
        guard !seed.isEmpty else { return false }
        self.jobs = seed
        // Persist to AppStorage (handled by didSet) and mirror to KVS
        return true
    }

    // MARK: - SwiftData Integration
    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
        // Load existing data from SwiftData, or seed it from current in-memory state on first run
        loadFromSwiftDataOrSeed()
    }

    private func loadFromSwiftDataOrSeed() {
        guard let ctx = modelContext else { return }
        do {
            let allEntryModels = try ctx.fetch(FetchDescriptor<EntryModel>())
            let allLabourModels = try ctx.fetch(FetchDescriptor<LabourCodeModel>())

            let hasEntriesInStore = !allEntryModels.isEmpty
            let hasLabourInStore = !allLabourModels.isEmpty

            if hasEntriesInStore || hasLabourInStore {
                isSyncingFromStore = true
                self.entries = allEntryModels.map { Entry(id: $0.id, date: $0.date, jobNumber: $0.jobNumber, code: $0.code, hours: $0.hours, notes: $0.notes, isOvertime: $0.isOvertime, isNightShift: $0.isNightShift) }
                self.labourCodes = allLabourModels.map { LabourCode(id: $0.id, name: $0.name, code: $0.code) }

                // Prefer iCloud KVS snapshot if present
                if UbiquitousSettingsSync.isAvailable {
                    if let kvsJSON = NSUbiquitousKeyValueStore.default.string(forKey: "labourCodesJSON"),
                       let data = kvsJSON.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode([LabourCode].self, from: data),
                       !decoded.isEmpty {
                        self.labourCodes = decoded
                    }
                }

                // Migration: replace legacy/incorrect labour codes with official list
                let hasDeprecatedNames = Set(self.labourCodes.map { $0.name }).intersection(TimecardStore.deprecatedJobNames).isEmpty == false

                func labourCodesEqual(_ lhs: [LabourCode], _ rhs: [LabourCode]) -> Bool {
                    guard lhs.count == rhs.count else { return false }
                    for (l, r) in zip(lhs, rhs) {
                        if l.name != r.name || l.code != r.code { return false }
                    }
                    return true
                }

                if hasDeprecatedNames || !labourCodesEqual(self.labourCodes, TimecardStore.officialLabourCodes) {
                    self.labourCodes = TimecardStore.officialLabourCodes
                    // Persist the corrected list to SwiftData so UI reflects the update
                    persistCurrentDataToSwiftData()
                }

                isSyncingFromStore = false
            } else {
                // First run with empty store: seed from current defaults/state
                persistCurrentDataToSwiftData()
            }
        } catch {
            print("SwiftData fetch failed: \(error)")
        }
    }

    func persistCurrentDataToSwiftData() {
        guard let ctx = modelContext else { return }
        do {
            // Upsert Labour Codes
            let existingLabour = try ctx.fetch(FetchDescriptor<LabourCodeModel>())
            let labourByID: [UUID: LabourCodeModel] = Dictionary(uniqueKeysWithValues: existingLabour.map { ($0.id, $0) })
            let incomingLabourIDs = Set(labourCodes.map { $0.id })

            // Update or insert
            for lc in labourCodes {
                if let m = labourByID[lc.id] {
                    m.name = lc.name
                    m.code = lc.code
                } else {
                    let m = LabourCodeModel(id: lc.id, name: lc.name, code: lc.code)
                    ctx.insert(m)
                }
            }
            // Delete removed
            for m in existingLabour where !incomingLabourIDs.contains(m.id) {
                ctx.delete(m)
            }

            // Upsert Entries
            let existingEntries = try ctx.fetch(FetchDescriptor<EntryModel>())
            let entryByID: [UUID: EntryModel] = Dictionary(uniqueKeysWithValues: existingEntries.map { ($0.id, $0) })
            let incomingEntryIDs = Set(entries.map { $0.id })

            for e in entries {
                if let m = entryByID[e.id] {
                    m.date = e.date
                    m.jobNumber = e.jobNumber
                    m.code = e.code
                    m.hours = e.hours
                    m.notes = e.notes
                    m.isOvertime = e.isOvertime
                    m.isNightShift = e.isNightShift
                } else {
                    let m = EntryModel(id: e.id, date: e.date, jobNumber: e.jobNumber, code: e.code, hours: e.hours, notes: e.notes, isOvertime: e.isOvertime, isNightShift: e.isNightShift)
                    ctx.insert(m)
                }
            }
            for m in existingEntries where !incomingEntryIDs.contains(m.id) {
                ctx.delete(m)
            }

            try ctx.save()
        } catch {
            print("SwiftData persist failed: \(error)")
        }
    }

    // Header / meta
    @Published var companyLogoName: String? = "LogicalGroupLogo"
    
    @Published var payPeriodNumber: Int = { OddPayPeriodCalc.period(containing: Date()).numberOdd }()
    
    @AppStorage("username") private var storedUsername: String = ""
    var employeeName: String {
        get { return storedUsername }
        set { storedUsername = newValue }
    }
    
    // Email settings
    @AppStorage("defaultEmail") private var storedDefaultEmail: String = "timecard@logicalgroup.ca"
    
    var defaultEmail: String {
        get { return storedDefaultEmail }
        set { storedDefaultEmail = newValue }
    }
    
    var emailRecipients: [String] {
        storedDefaultEmail
            .split(whereSeparator: { ",;".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    @AppStorage("emailSubjectTemplate") private var storedEmailSubjectTemplate: String = "Timecard — {name} — {range}"
    
    var emailSubjectTemplate: String {
        get { return storedEmailSubjectTemplate }
        set { storedEmailSubjectTemplate = newValue }
    }
    
    func emailSubject(for weekStart: Date) -> String {
        let name = employeeName.isEmpty ? "Employee" : employeeName
        let range = weekStart.weekRangeLabel()
        let pp = String(payPeriodNumber)
        return emailSubjectTemplate
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{range}", with: range)
            .replacingOccurrences(of: "{pp}", with: pp)
    }
    
    @AppStorage("emailBodyTemplate") private var storedEmailBodyTemplate: String = "Dear Team,\n\nPlease find my timecard submission for pay period {pp} ({range}) attached.\n\nEmployee: {name}\nPay Period: {pp}\nWeek Range: {range}\n\nThank you for your review.\n\nBest regards,\n{name}"
    
    var emailBodyTemplate: String {
        get { return storedEmailBodyTemplate }
        set { storedEmailBodyTemplate = newValue }
    }
    
    func emailBody(for weekStart: Date) -> String {
        let name = employeeName.isEmpty ? "Employee" : employeeName
        let range = weekStart.weekRangeLabel()
        let pp = String(payPeriodNumber)
        return emailBodyTemplate
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{range}", with: range)
            .replacingOccurrences(of: "{pp}", with: pp)
    }
    
    // Email attachments
    @AppStorage("attachCSV") var attachCSV: Bool = true
    @AppStorage("attachPDF") var attachPDF: Bool = true

    // On Call feature toggle
    @AppStorage("onCallEnabled") var onCallEnabled: Bool = true
    
    // Holiday management
    @Published var holidayManager = HolidayManager()
    // Region-based overtime policy
    @Published var overtimePolicy: OvertimePolicy = OvertimePolicy.defaultInternational
    
    @AppStorage("autoHolidaysEnabled") var autoHolidaysEnabled: Bool = true
    
    // Accent color
    @AppStorage("accentColorHex") private var accentColorHex: String = ""
    
    var accentColor: Color {
        accentColorHex.isEmpty ? Color.accentColor : Color(hex: accentColorHex)
    }
    
    // Company logo
    @AppStorage("companyLogoPath") private var companyLogoPath: String = ""

    var companyLogoImage: Image? {
        if !companyLogoPath.isEmpty {
            #if canImport(UIKit)
            if let ui = UIImage(contentsOfFile: companyLogoPath) { return Image(uiImage: ui) }
            #else
            if let ns = NSImage(contentsOfFile: companyLogoPath) { return Image(nsImage: ns) }
            #endif
        }
        if let name = companyLogoName, !name.isEmpty { return Image(name) }
        return nil
    }

    func setCompanyLogo(data: Data) {
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let url = dir.appendingPathComponent("company_logo.png")
        do {
            try data.write(to: url, options: .atomic)
            self.companyLogoPath = url.path
            self.companyLogoName = nil
            objectWillChange.send()
        } catch {
            print("Failed to save company logo: \(error)")
        }
    }

    func resetCompanyLogoToDefault(assetName: String = "LogicalGroupLogo") {
        self.companyLogoPath = ""
        self.companyLogoName = assetName
        objectWillChange.send()
    }

    // Week management
    @AppStorage("payPeriodWeeks") var payPeriodWeeks: Int = 2

    @Published var weekStart: Date = Date() {
        didSet {
            // Recompute pay period number when the period start changes (odd-numbered scheme)
            self.payPeriodNumber = OddPayPeriodCalc.period(containing: weekStart).numberOdd
        }
    }

    @Published var selectedWeekIndex: Int = 0 {
        didSet {
            let maxIndex = max(0, payPeriodWeeks - 1)
            let clamped = max(0, min(maxIndex, selectedWeekIndex))
            if selectedWeekIndex != clamped {
                selectedWeekIndex = clamped
            }
        }
    }

    var selectedWeekStart: Date {
        let pp = self.currentPayPeriod
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: selectedWeekIndex * 7, to: pp.start) ?? pp.start
    }

    var selectedWeekRange: ClosedRange<Date> {
        weekRange(offset: selectedWeekIndex)
    }

    var selectedWeekTotals: SummaryTotals {
        totals(for: selectedWeekRange)
    }

    // Data
    @Published var entries: [Entry] = [] {
        didSet {
            if !isSyncingFromStore { persistCurrentDataToSwiftData() }
        }
    }

    // Jobs stored independently from labour codes
    @AppStorage("jobsJSON") private var storedJobsJSON: String = ""
    @AppStorage("jobsSeededFromBundleV1") private var jobsSeededFromBundleV1: Bool = false

    @Published var jobs: [Job] = [] {
        didSet {
            // Persist to AppStorage as JSON whenever jobs change
            if let data = try? JSONEncoder().encode(jobs),
               let json = String(data: data, encoding: .utf8) {
                storedJobsJSON = json
                // Mirror jobs to iCloud KVS as JSON
                if UbiquitousSettingsSync.isAvailable {
                    let kvs = NSUbiquitousKeyValueStore.default
                    kvs.set(json, forKey: "jobsJSON")
                    kvs.synchronize()
                }
            }
        }
    }
    
    // General notes for codes
    @AppStorage("codeGeneralNotes") var codeGeneralNotes: String = ""

    @Published var labourCodes: [LabourCode] = [] {
        didSet {
            if !isSyncingFromStore { persistCurrentDataToSwiftData() }
            
            // Mirror labour codes to iCloud KVS as JSON
            if let data = try? JSONEncoder().encode(labourCodes),
               let json = String(data: data, encoding: .utf8) {
                if UbiquitousSettingsSync.isAvailable {
                    NSUbiquitousKeyValueStore.default.set(json, forKey: "labourCodesJSON")
                    NSUbiquitousKeyValueStore.default.synchronize()
                }
            }
        }
    }

    @Published var codeCategory: [String: PayCategory] = [:]
    

    // MARK: - Pay Period
    var currentPayPeriod: (start: Date, end: Date) {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: weekStart)?.start ?? weekStart
        let weeks = max(1, payPeriodWeeks)
        let end = calendar.date(byAdding: .day, value: (weeks * 7) - 1, to: startOfWeek) ?? startOfWeek
        return (start: startOfWeek, end: end)
    }
    
    func payPeriodStarts(from startDate: Date, to endDate: Date) -> [Date] {
        let calendar = Calendar.current
        var starts: [Date] = []
        var current = startDate
        
        while current <= endDate {
            if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: current) {
                let weekStart = weekInterval.start
                let weekOfYear = calendar.component(.weekOfYear, from: weekStart)
                
                if weekOfYear % 2 == 1 {
                    starts.append(weekStart)
                    current = calendar.date(byAdding: .weekOfYear, value: 2, to: current) ?? endDate.addingTimeInterval(1)
                } else {
                    if let payPeriodStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) {
                        starts.append(payPeriodStart)
                    }
                    current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? endDate.addingTimeInterval(1)
                }
            } else {
                break
            }
        }
        
        return Array(Set(starts)).sorted()
    }
    
    func clonedStoreForPayPeriod(start: Date) -> TimecardStore {
        let clone = TimecardStore()
        clone.employeeName = self.employeeName
        clone.companyLogoName = self.companyLogoName
        clone.accentColorHex = self.accentColorHex
        clone.labourCodes = self.labourCodes
        clone.codeCategory = self.codeCategory
        clone.jobs = self.jobs
        clone.weekStart = start
        clone.selectedWeekIndex = 0
        
        let calendar = Calendar.current
        let weekOfYear = calendar.component(.weekOfYear, from: start)
        clone.payPeriodNumber = OddPayPeriodCalc.period(containing: start).numberOdd
        
        let payPeriodEnd = calendar.date(byAdding: .day, value: 13, to: start) ?? start
        let payPeriodRange = start...payPeriodEnd
        
        clone.entries = self.entries.filter { entry in
            payPeriodRange.contains(entry.date)
        }
        
        return clone
    }

    // MARK: - Remote Holiday Preload (Option 1: preload-and-cache)
    func preloadHolidaysForCurrentPeriod() async {
        // If auto-detect is enabled, attempt to detect and apply region first
        if holidayManager.autoDetectRegion {
            await holidayManager.autoDetectAndApplyRegion()
        }
        // Preload holidays for all years that intersect the current pay period
        let cal = Calendar.current
        let range = self.payPeriodRange
        let startYear = cal.component(.year, from: range.lowerBound)
        let endYear = cal.component(.year, from: range.upperBound)
        for year in startYear...endYear {
            _ = await holidayManager.holidays(for: year)
        }
        // After preloading, update entries according to current setting
        await MainActor.run {
            if self.autoHolidaysEnabled {
                self.addStatHolidaysForCurrentPeriod()
            }
        }
    }

    // MARK: - Holiday Methods
    func addStatHolidaysForCurrentPeriod() {
        guard autoHolidaysEnabled else { return }
        
        let calendar = Calendar.current
        let payPeriodRange = self.payPeriodRange
        
        let startYear = calendar.component(.year, from: payPeriodRange.lowerBound)
        let endYear = calendar.component(.year, from: payPeriodRange.upperBound)
        
        var holidays: [StatHoliday] = []
        for year in startYear...endYear {
            holidays.append(contentsOf: holidayManager.getStatHolidays(for: year))
        }
        
        let relevantHolidays = holidays.filter { holiday in
            payPeriodRange.contains(holiday.date)
        }
        
        for holiday in relevantHolidays {
            if !hasHolidayEntry(for: holiday.date) {
                let holidayEntry = Entry(
                    date: holiday.date,
                    jobNumber: "Stat",
                    code: "H",
                    hours: 8.0,
                    notes: holiday.name,
                    isOvertime: false,
                    isNightShift: false
                )
                entries.append(holidayEntry)
            }
        }
        
        // Normalize any existing holiday entries in this period to display as "Stat" / "H"
        for i in entries.indices {
            guard payPeriodRange.contains(entries[i].date) else { continue }
            let codeUpper = entries[i].code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if codeUpper == "H" || codeUpper == "STAT" {
                if entries[i].jobNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entries[i].jobNumber.lowercased() == "holiday" {
                    entries[i].jobNumber = "Stat"
                }
                entries[i].code = (codeUpper == "STAT") ? "H" : entries[i].code
            }
        }
        
        entries.sort { $0.date < $1.date }
        // Persist holiday insertions to SwiftData if available
        persistCurrentDataToSwiftData()
    }
    
    func removeStatHolidaysForCurrentPeriod() {
        let calendar = Calendar.current
        let payPeriodRange = self.payPeriodRange

        let startYear = calendar.component(.year, from: payPeriodRange.lowerBound)
        let endYear = calendar.component(.year, from: payPeriodRange.upperBound)

        var holidays: [StatHoliday] = []
        for year in startYear...endYear {
            holidays.append(contentsOf: holidayManager.getStatHolidays(for: year))
        }

        let relevantHolidays = holidays.filter { holiday in
            payPeriodRange.contains(holiday.date)
        }

        // Remove any entries on stat holiday dates with an H/STAT code
        entries.removeAll { entry in
            let isStatCode = entry.code.uppercased() == "H" || entry.code.uppercased() == "STAT"
            guard isStatCode else { return false }
            return relevantHolidays.contains { holiday in
                calendar.isDate(entry.date, inSameDayAs: holiday.date)
            }
        }

        entries.sort { $0.date < $1.date }
        // Persist removals to SwiftData if available
        persistCurrentDataToSwiftData()
    }
    
    private func hasHolidayEntry(for date: Date) -> Bool {
        let calendar = Calendar.current
        return entries.contains { entry in
            calendar.isDate(entry.date, inSameDayAs: date) &&
            (entry.code.uppercased() == "H" || entry.code.uppercased() == "STAT")
        }
    }
    
    func isStatHoliday(_ date: Date) -> Bool {
        return holidayManager.isStatHoliday(date)
    }
    
    func holidayName(for date: Date) -> String? {
        return holidayManager.holidayName(for: date)
    }

    // MARK: - Ranges and Calculations
    func weekRange(offset: Int) -> ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: offset * 7, to: cal.startOfDay(for: weekStart)) ?? weekStart
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        let startDay = cal.startOfDay(for: start)
        let endDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
        return startDay...endDay
    }

    var payPeriodRange: ClosedRange<Date> {
        let first = weekRange(offset: 0)
        let last = weekRange(offset: max(0, payPeriodWeeks - 1))
        return min(first.lowerBound, last.lowerBound)...max(first.upperBound, last.upperBound)
    }

    func entries(in range: ClosedRange<Date>) -> [Entry] {
        entries.filter {
            range.contains($0.date)
            && !$0.jobNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !$0.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func category(for code: String) -> PayCategory {
        let key = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let base = codeCategory[key] ?? .regular
        if !onCallEnabled && base == .onCall { return .regular }
        return base
    }

    func totals(for range: ClosedRange<Date>) -> SummaryTotals {
        var t = SummaryTotals()
        let validEntries = entries.filter { entry in
            range.contains(entry.date) &&
            !entry.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            entry.hours != 600
        }
        
        for entry in validEntries {
            let baseCat = category(for: entry.code)
            let effectiveCat: PayCategory = {
                if entry.isNightShift { return .night }
                if baseCat == .dt { return .dt }
                if baseCat == .onCall { return .onCall }
                if entry.isOvertime || baseCat == .ot { return .ot }
                if baseCat == .vacation { return .vacation }
                if baseCat == .stat { return .stat }
                return .regular
            }()

            if effectiveCat == .regular && entry.jobNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            switch effectiveCat {
            case .regular: t.regular += entry.hours
            case .ot: t.ot += entry.hours
            case .dt: t.dt += entry.hours
            case .vacation: t.vacation += entry.hours
            case .stat: t.stat += entry.hours
            case .night: t.night += entry.hours
            case .onCall: t.ot += entry.hours
            }
        }
        
        return t
    }

    // MARK: - CRUD helpers (SwiftData + in-memory)
    func addEntry(_ entry: Entry) {
        entries.append(entry)
    }
    func updateEntry(_ entry: Entry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        }
    }
    func deleteEntry(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    func addLabourCode(_ code: LabourCode) {
        labourCodes.append(code)
    }
    func updateLabourCode(_ code: LabourCode) {
        if let idx = labourCodes.firstIndex(where: { $0.id == code.id }) {
            labourCodes[idx] = code
        }
    }
    func deleteLabourCode(id: UUID) {
        labourCodes.removeAll { $0.id == id }
    }

    // MARK: - Jobs management
    
    /// Forces a reload of jobs from the bundled JobsSeed.csv file
    func reloadJobsFromCSV() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let seed = TimecardStore.loadBundledJobsSeed()
            print("Debug: Found \(seed.count) jobs in CSV")
            if !seed.isEmpty {
                print("Debug: First few jobs: \(seed.prefix(3).map { "\($0.code): \($0.name)" })")
                self.jobs = seed
                if let data = try? JSONEncoder().encode(self.jobs),
                   let json = String(data: data, encoding: .utf8) {
                    self.storedJobsJSON = json
                    // Mirror to iCloud KVS if available
                    if UbiquitousSettingsSync.isAvailable {
                        let kvs = NSUbiquitousKeyValueStore.default
                        kvs.set(json, forKey: "jobsJSON")
                        kvs.synchronize()
                    }
                }
                print("Debug: Successfully loaded \(self.jobs.count) jobs")
            } else {
                print("Debug: No jobs found in CSV or CSV not found")
            }
        }
    }
    
    /// Resets jobs completely and forces reload from CSV - for troubleshooting
    func resetJobsToCSV() {
        // Clear all job storage
        storedJobsJSON = ""
        jobsSeededFromBundleV1 = false
        
        // Clear iCloud KVS
        if UbiquitousSettingsSync.isAvailable {
            let kvs = NSUbiquitousKeyValueStore.default
            kvs.removeObject(forKey: "jobsJSON")
            kvs.synchronize()
        }
        
        // Force reload from CSV
        let seed = TimecardStore.loadBundledJobsSeed()
        if !seed.isEmpty {
            print("Debug: Reset complete - loaded \(seed.count) jobs from CSV")
            self.jobs = seed
            if let data = try? JSONEncoder().encode(self.jobs),
               let json = String(data: data, encoding: .utf8) {
                storedJobsJSON = json
                if UbiquitousSettingsSync.isAvailable {
                    let kvs = NSUbiquitousKeyValueStore.default
                    kvs.set(json, forKey: "jobsJSON")
                    kvs.synchronize()
                }
            }
            jobsSeededFromBundleV1 = true
        } else {
            print("Debug: No CSV found - falling back to labour codes")
            self.jobs = TimecardStore.officialLabourCodes.map { Job(name: $0.name, code: $0.code) }
            if let data = try? JSONEncoder().encode(self.jobs),
               let json = String(data: data, encoding: .utf8) {
                storedJobsJSON = json
            }
            jobsSeededFromBundleV1 = true
        }
    }
    
    /// Direct method to load the exact job data requested by user
    func loadJobDataDirectly() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let directJobs = [
                Job(name: "Warranty Job 2026", code: "26999"),
                Job(name: "Stuart Lake Hospital", code: "12215"),
                Job(name: "Burnaby Hospital Phase1", code: "12216"),
                Job(name: "Woodland Park PA", code: "92309"),
                Job(name: "Cartier House Phone", code: "92408"),
                Job(name: "Pine Grove NC and Phone", code: "92409"),
                Job(name: "Cartier House Arial", code: "92410"),
                Job(name: "Discovery Harbour Phone", code: "92415"),
                Job(name: "Fort Langley Phone", code: "92416"),
                Job(name: "Hilton Villa Phone", code: "92417"),
                Job(name: "Oyster Harbor Phone", code: "92418"),
                Job(name: "Wexford Creek Phone", code: "92419"),
                Job(name: "Cedar Springs Phone/Pend.", code: "92501"),
                Job(name: "Trillium Lodge Phone Intg", code: "92502"),
                Job(name: "North Star Inn Phone", code: "92503"),
                Job(name: "RCH Phase2 - Subcontract", code: "12306"),
                Job(name: "CMH Redevelopment", code: "12308"),
                Job(name: "RCH Phase2 Material", code: "12309"),
                Job(name: "False Creek Healthcare NC", code: "L2327"),
                Job(name: "Burnaby Hospital CM1", code: "L2335"),
                Job(name: "Snohomish PA", code: "L2336"),
                Job(name: "RH Modular CT Replacement", code: "L2406"),
                Job(name: "KGH MRI Reno TP3", code: "L2421"),
                Job(name: "Seven Nations NC", code: "L2439"),
                Job(name: "VCH DTES CHC NC", code: "L2442"),
                Job(name: "KBRH RM 323 NC", code: "L2445"),
                Job(name: "Yaletown House CCTV", code: "L2447"),
                Job(name: "VGH ED Expansion NC", code: "L2449"),
                Job(name: "SMH MRI Phase 1B & 2 NC", code: "L2451"),
                Job(name: "Fort Langley NC upgrade", code: "L2452"),
                Job(name: "Hilton Villa NC Upgrade", code: "L2453"),
                Job(name: "Wexford R5K Upgrade", code: "L2454"),
                Job(name: "CGH MI MP Fluoroscopy NC", code: "L2501"),
                Job(name: "SMH OR 4 and 5 NC", code: "L2504"),
                Job(name: "Cloverdale UPCC NC", code: "L2505"),
                Job(name: "RH ED MHSU NC ReRe + New", code: "L2506"),
                Job(name: "BCC Kelowna CT Sim ReReno", code: "L2508"),
                Job(name: "SMH Renal Center New NC", code: "L2511"),
                Job(name: "PAH Lv 5 and 6 NC Repl", code: "L2512"),
                Job(name: "VICC PSMA NC ReRe & New", code: "L2515"),
                Job(name: "Harmony House NC & Phone", code: "L2517"),
                Job(name: "RMH MTU NET New NC", code: "L2518"),
                Job(name: "GSS Hillside Village NC", code: "L2519"),
                Job(name: "GSS Hillside V Coll NCExp", code: "L2520"),
                Job(name: "South Surrey UPCC NC", code: "L2521"),
                Job(name: "VGH OR Renewal Phase 2 NC", code: "L2522"),
                Job(name: "St. John Hospital New NC", code: "L2523"),
                Job(name: "LGH Angiography NC ReRe", code: "L2524"),
                Job(name: "POCO UPCC New NC", code: "L2525"),
                Job(name: "LGH RRCM", code: "L2526"),
                Job(name: "SMH Cath Lab Reno New NC", code: "L2528"),
                Job(name: "BCC Surrey chemo. NC", code: "L2530"),
                Job(name: "Veterans Health Centre NC", code: "L2532"),
                Job(name: "FD Sinclair Elem. PA Exp.", code: "L2533"),
                Job(name: "UHNC CD Ph3 NC Expansion", code: "L2534"),
                Job(name: "KBRH R5K Field NC Upgrade", code: "L2535"),
                Job(name: "RH Nuclear Medicine NC", code: "L2536"),
                Job(name: "SMH Creekside 10 Bed NC", code: "L2537"),
                Job(name: "RH ED MHSU Net New NC", code: "L2538"),
                Job(name: "Harriet House NC (labour)", code: "L2539"),
                Job(name: "JPSOCS CT SCAN NC", code: "L2540"),
                Job(name: "City Center Surgery New N", code: "L2541"),
                Job(name: "EKRH Nursery Expansion NC", code: "L2542"),
                Job(name: "LGH 3.0T MRI KC ReRe New", code: "L2543"),
                Job(name: "Kitimat Hospital ReRe", code: "L2544"),
                Job(name: "PAH ICU Telemetry Ph1 NC", code: "L2546"),
                Job(name: "RH IV Therapy NC", code: "L2547"),
                Job(name: "RH Park and Rotunda Demo", code: "L2548"),
                Job(name: "Kwantlen Park SecondaryPA", code: "L2550"),
                Job(name: "KBH CT Scanner Reno NC", code: "L2552"),
                Job(name: "Martha Currie Elem PA LAB", code: "L2553"),
                Job(name: "Sunset Seniors Centre NC", code: "L2554"),
                Job(name: "RH X-Ray Reno NC", code: "L2555"),
                Job(name: "Victoria VGH NC Labor,O/H", code: "S2503"),
                Job(name: "Lillooet LIH - Labor,O/H", code: "S2504"),
                Job(name: "CCLC Conversion PA System", code: "L2506"),
                Job(name: "BHRP Nursing Tower 2-4", code: "12216A"),
                Job(name: "BHRP New Tower", code: "12216B"),
                Job(name: "BHRP Nursing Tower 0-1", code: "12216C"),
                Job(name: "BHRP SFB", code: "12216D"),
                Job(name: "Victoria VGH NC Material", code: "S2503M"),
                Job(name: "Lillooet LIH - Material", code: "S2504M")
            ]
            
            print("Debug: Loading \(directJobs.count) jobs directly")
            self.jobs = directJobs
            
            // Persist the data
            if let data = try? JSONEncoder().encode(self.jobs),
               let json = String(data: data, encoding: .utf8) {
                self.storedJobsJSON = json
                if UbiquitousSettingsSync.isAvailable {
                    let kvs = NSUbiquitousKeyValueStore.default
                    kvs.set(json, forKey: "jobsJSON")
                    kvs.synchronize()
                }
            }
            
            self.jobsSeededFromBundleV1 = true
            print("Debug: Successfully loaded \(self.jobs.count) jobs directly")
        }
    }
    
    // MARK: - Sample store
    static let sampleStore: TimecardStore = {
        let s = TimecardStore()
        let cal = Calendar.current
        let now = Date()
        s.employeeName = "Geoff Strench"
        s.companyLogoName = nil
        s.weekStart = cal.startOfDay(for:
            cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        )
        s.entries = [
            Entry(date: now, jobNumber: "Job #", code: "201", hours: 1.0, isOvertime: false),
            Entry(date: cal.date(byAdding: .day, value: 1, to: now)!, jobNumber: "L2222", code: "H", hours: 3.0, isOvertime: false),
        ]
        return s
    }()

    init() {
        // Initialize weekStart to current week
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        self.weekStart = cal.date(from: comps).map { cal.startOfDay(for: $0) } ?? cal.startOfDay(for: now)
        
        self.payPeriodNumber = OddPayPeriodCalc.period(containing: self.weekStart).numberOdd
        
        // Load Jobs list - prioritize CSV over labour codes
        // First, try to load from CSV if we haven't done so before
        if !jobsSeededFromBundleV1 {
            let seed = TimecardStore.loadBundledJobsSeed()
            if !seed.isEmpty {
                print("Debug: Loading \(seed.count) jobs from CSV")
                self.jobs = seed
                if let data = try? JSONEncoder().encode(self.jobs),
                   let json = String(data: data, encoding: .utf8) {
                    storedJobsJSON = json
                    // Mirror to iCloud KVS if available
                    if UbiquitousSettingsSync.isAvailable {
                        let kvs = NSUbiquitousKeyValueStore.default
                        kvs.set(json, forKey: "jobsJSON")
                        kvs.synchronize()
                    }
                }
                jobsSeededFromBundleV1 = true
            } else {
                print("Debug: No CSV found, will seed from labour codes")
                jobsSeededFromBundleV1 = true
            }
        }
        
        // Load from storage or seed from labour codes as fallback
        if storedJobsJSON.isEmpty {
            // Fallback: seed jobs from official labour codes only if no CSV was loaded
            print("Debug: Seeding jobs from labour codes as fallback")
            self.jobs = TimecardStore.officialLabourCodes.map { Job(name: $0.name, code: $0.code) }
            if let data = try? JSONEncoder().encode(self.jobs),
               let json = String(data: data, encoding: .utf8) {
                storedJobsJSON = json
            }
        } else {
            if let data = storedJobsJSON.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([Job].self, from: data) {
                self.jobs = decoded
                print("Debug: Loaded \(self.jobs.count) jobs from storage")
            } else {
                self.jobs = []
            }
        }
        
        // Overwrite labourCodes immediately after initializing weekStart
        self.labourCodes = TimecardStore.officialLabourCodes
        
        // Overlay with iCloud KVS if available on launch
        if UbiquitousSettingsSync.isAvailable {
            if let kvsJSON = NSUbiquitousKeyValueStore.default.string(forKey: "labourCodesJSON"),
               let data = kvsJSON.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([LabourCode].self, from: data),
               !decoded.isEmpty {
                self.labourCodes = decoded
            }
        }

        // Set up holiday manager defaults
        self.holidayManager.selectedCountry = .canada
        self.holidayManager.selectedProvince = .britishColumbia
        
        // Initialize overtime policy from region
        self.overtimePolicy = holidayManager.inferredOvertimePolicy()
        
        // Check if current labourCodes matches official list, else overwrite
        func labourCodesEqual(_ lhs: [LabourCode], _ rhs: [LabourCode]) -> Bool {
            guard lhs.count == rhs.count else { return false }
            for (l, r) in zip(lhs, rhs) {
                if l.name != r.name || l.code != r.code {
                    return false
                }
            }
            return true
        }
        if !labourCodesEqual(self.labourCodes, TimecardStore.officialLabourCodes) {
            self.labourCodes = TimecardStore.officialLabourCodes
        }
        
        // Initialize code categories
        self.codeCategory = [
            "OT": .ot, "O/T": .ot,
            "DT": .dt,
            "VP": .vacation, "VAC": .vacation,
            "NS": .night,
            "H": .stat, "STAT": .stat, "HOL": .stat, "ST": .stat, "SH": .stat,
            "201": .regular, "206": .regular, "207": .regular,
            "223": .regular, "224": .regular, "226": .regular,
            "227": .regular, "228": .regular, "229": .regular, "394": .regular,
            "WA": .regular, "ES": .regular, "TR": .regular, "RP": .regular, "SJ": .regular, "S": .regular,
            "ONC": .onCall,
            "OC": .onCall,
            "O/C": .onCall,
        ]
        
        if autoHolidaysEnabled {
            addStatHolidaysForCurrentPeriod()
        }
        
        // Observe iCloud KVS changes for jobs
        let kvs = NSUbiquitousKeyValueStore.default
        if UbiquitousSettingsSync.isAvailable {
            NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kvs, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                if let json = kvs.string(forKey: "jobsJSON"),
                   let data = json.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([Job].self, from: data) {
                    self.jobs = decoded
                }
            }
        }
        
        // Observe iCloud KVS changes for labourCodes
        if UbiquitousSettingsSync.isAvailable {
            NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kvs, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                if let json = kvs.string(forKey: "labourCodesJSON"),
                   let data = json.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([LabourCode].self, from: data),
                   !decoded.isEmpty {
                    self.labourCodes = decoded
                }
            }
        }
        
        // Observe region changes to refresh overtime policy
        NotificationCenter.default.addObserver(forName: .regionDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.overtimePolicy = self.holidayManager.inferredOvertimePolicy()
        }
    }
}


extension Date {
    func weekRangeLabel() -> String {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: self)?.start ?? self
        let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek) ?? self
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        
        let startString = formatter.string(from: startOfWeek)
        let endString = formatter.string(from: endOfWeek)
        
        return "\(startString) - \(endString)"
    }
    
    func fileSafeDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
}

extension Notification.Name {
    static let regionDidChange = Notification.Name("RegionDidChangeNotification")
}

