// ThemeType.swift
// Central definition of ThemeType used across the app
import SwiftUI

enum ThemeType: String, CaseIterable, Identifiable {
    case system, light, dark, automatic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .automatic: return "Automatic"
        }
    }
    var icon: String {
        switch self {
        case .system: return "circle.dashed"
        case .light: return "sun.max"
        case .dark: return "moon"
        case .automatic: return "circle.lefthalf.filled"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system, .automatic: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
