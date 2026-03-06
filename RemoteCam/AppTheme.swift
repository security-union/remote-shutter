import SwiftUI

// MARK: - App Theme
// Cinematic camera palette: warm amber/gold + cool teal
// Inspired by Apple Pro camera features (ProRes, ProRAW, Cinematic Mode)

enum AppTheme {

    // MARK: - Primary Accent (Warm Amber/Gold)
    // Used for: buttons, links, interactive elements, highlights

    static let accent = Color(red: 0.85, green: 0.65, blue: 0.30)       // Warm gold
    static let accentLight = Color(red: 0.92, green: 0.75, blue: 0.42)   // Lighter gold
    static let accentSubtle = Color(red: 0.85, green: 0.65, blue: 0.30).opacity(0.12)

    // MARK: - Secondary (Cool Teal)
    // Used for: secondary actions, connected status, toggles

    static let secondary = Color(red: 0.30, green: 0.70, blue: 0.68)     // Teal
    static let secondarySubtle = Color(red: 0.30, green: 0.70, blue: 0.68).opacity(0.12)

    // MARK: - Semantic Colors

    static let success = Color.green                                       // Purchased, connected
    static let record = Color.red                                          // Record button only
    static let tip = Color(red: 0.85, green: 0.65, blue: 0.30)           // Tips — matches accent

    // MARK: - Glass

    static let glassBorder = Color.white.opacity(0.3)
    static let glassShadow = Color.black.opacity(0.08)

    // MARK: - Gradients

    static var backgroundGradient: some View {
        ZStack {
            Color(.systemGroupedBackground)
            RadialGradient(
                colors: [accent.opacity(0.1), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 400
            )
            RadialGradient(
                colors: [secondary.opacity(0.08), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 350
            )
        }
        .ignoresSafeArea()
    }
}
