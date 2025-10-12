import Foundation
import Combine
import SwiftUI

/// Temporary compatibility wrapper so views can keep using `@EnvironmentObject var store: TimecardStore`.
@MainActor
public final class TimecardStore: ObservableObject {
    /// Your new store after the reorg (adjust the initializer if JobsStore requires params).
    public let jobs: JobsStore

    /// Views read/write a pay period range; keep a basic published value for now.
    @Published public var payPeriodRange: ClosedRange<Date> = {
        let now = Date()
        return now ... now
    }()

    public init(jobs: JobsStore = JobsStore()) {
        self.jobs = jobs
    }

    /// Previews often used this.
    public static let sampleStore = TimecardStore()
}
