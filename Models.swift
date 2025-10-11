//
//  Models.swift — TimeEntry with placeholder default for labour code
//
import Foundation

struct TimeEntry: Identifiable, Hashable {
    let id = UUID()
    var date: Date
    var jobNumber: String = ""              // user-entered job #
    var labourCode: String = "Labour Codes:"// default shown in picker
    var hoursWorked: Double = 0.0
    var notes: String = ""
}
