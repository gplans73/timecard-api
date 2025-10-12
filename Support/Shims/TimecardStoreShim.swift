import Foundation
import Combine
import SwiftUI

// Temporary compatibility wrapper so existing SwiftUI views can continue to use:
//   @EnvironmentObject var store: TimecardStore
@MainActor
public final class TimecardStore: ObservableObject {
    // Backing store after the reorg. Adjust the init if JobsStore has parameters.
    public let jobs: JobsStore

    // Properties your views are reading/writing through `$store.<prop>`
    @Published public var autoHolidaysEnabled: Bool = false
    @Published public var entries: [TimeEntry] = []              // old code may have used [Entry]
    @Published public var payPeriodRange: ClosedRange<Date> = {
        let now = Date()
        return now ... now
    }()

    // If your UI uses a HolidayManager instance, keep one here.
    public var holidayManager = HolidayManager()

    public init(jobs: JobsStore = JobsStore()) {
        self.jobs = jobs
    }

    // Previews often did `.environmentObject(TimecardStore.sampleStore)`
    public static let sampleStore = TimecardStore()
}

// Backwards-compatibility: if older code used `Entry` instead of `TimeEntry`.
public typealias Entry = TimeEntry
