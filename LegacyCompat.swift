// LegacyCompat.swift
// Shims to keep older code compiling with the new Entry model.

// Note: We intentionally do not alias `TimeEntry` to `Entry` here because
// some targets still declare `TimeEntry` themselves, which would cause
// an "Invalid redeclaration of 'TimeEntry'" compiler error.

import Foundation
import SwiftUI
import SwiftData
import Network

// Since Entry is defined in Store.swift and this extension needs to be
// available across the module, we'll move this extension to Store.swift
// to avoid compilation order issues.

// This file is kept for documentation purposes and can be removed
// once all legacy code has been updated.

