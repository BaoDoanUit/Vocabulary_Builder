//
//  Theme.swift
//  vocabulary_builder
//
//  Mirrors the web app's theme tokens. See IOS_PORTING_GUIDE.md §8. Using
//  semantic colours where possible so dark mode is free.
//

import SwiftUI

enum Theme {
    // Primary teal[700] = #00796B
    static let primary = Color(red: 0.0, green: 0.475, blue: 0.42)
    // Teal[500] = #009688
    static let secondary = Color(red: 0.0, green: 0.588, blue: 0.533)
    // Amber[700] = #FFA000
    static let warning = Color(red: 1.0, green: 0.627, blue: 0.0)
    // Blue[600] = #1E88E5
    static let info = Color(red: 0.118, green: 0.533, blue: 0.898)
    // Pink/Rose for quiz wrong answer / destructive
    static let danger = Color(red: 0.957, green: 0.247, blue: 0.365)

    static let cardRadius: CGFloat = 16
    static let pillRadius: CGFloat = 999

    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let pageBackground = Color(.systemGroupedBackground)
}
