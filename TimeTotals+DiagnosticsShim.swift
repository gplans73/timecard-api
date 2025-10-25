//
//  TimeTotalsShim.swift
//
//  This file provides a minimal shim definition of TimeTotals used by PerformanceDiagnostics.
//  It is intended to be used only when the real TimeTotals type is not available.
//
//  To use the real TimeTotals type, define the compile-time flag PERF_HAS_TIMETOTALS in your
//  build settings and remove this file from your target.
//

import Foundation

#if !PERF_HAS_TIMETOTALS

public struct TimeTotals: Sendable, Equatable {
    public var totalSeconds: TimeInterval
    public var regularSeconds: TimeInterval
    public var overtimeSeconds: TimeInterval

    public var totalHours: Double {
        totalSeconds / 3600
    }

    public init(
        totalSeconds: TimeInterval = 0,
        regularSeconds: TimeInterval = 0,
        overtimeSeconds: TimeInterval = 0
    ) {
        self.totalSeconds = totalSeconds
        self.regularSeconds = regularSeconds
        self.overtimeSeconds = overtimeSeconds
    }

    public static func + (lhs: TimeTotals, rhs: TimeTotals) -> TimeTotals {
        return TimeTotals(
            totalSeconds: lhs.totalSeconds + rhs.totalSeconds,
            regularSeconds: lhs.regularSeconds + rhs.regularSeconds,
            overtimeSeconds: lhs.overtimeSeconds + rhs.overtimeSeconds
        )
    }
}

#endif
