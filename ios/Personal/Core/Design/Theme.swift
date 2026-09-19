import SwiftUI
import UIKit

/// Design tokens from `docs/specs/ios-design-system.md` §2.
///
/// Screens compose these and add nothing ad hoc: no literal colours, fonts,
/// spacings or corner radii anywhere else in the app.
enum Theme {

    // MARK: - Colour

    /// Light / dark pairs. Dark-mode surfaces are translucent white over
    /// `canvas`, not grey cards on grey.
    enum Colors {

        // Surfaces
        static let canvas = Color(light: 0xF5_F5_F3, dark: 0x0A_0A_0A)
        static let surface = Color(light: 0xFF_FF_FF, dark: 0xFF_FF_FF, darkAlpha: 0.08)
        static let surfaceSecondary = Color(light: 0xEF_EF_ED, dark: 0xFF_FF_FF, darkAlpha: 0.12)
        /// The selected segment of the pill segmented control: white in light
        /// mode, white 16 % in dark (spec §3) — one step brighter than the
        /// `surfaceSecondary` track it sits on, which `surface` (8 %) is not.
        static let surfaceSelected = Color(light: 0xFF_FF_FF, dark: 0xFF_FF_FF, darkAlpha: 0.16)
        static let hairline = Color(light: 0xE8_E8_E6, dark: 0xFF_FF_FF, darkAlpha: 0.10)

        // Text
        static let textPrimary = Color(light: 0x11_11_11, dark: 0xF5_F5_F5)
        static let textSecondary = Color(light: 0x6B_6B_6B, dark: 0xA3_A3_A3)
        static let textTertiary = Color(light: 0x9C_9C_9C, dark: 0x6F_6F_6F)

        /// Primary CTA fill; its label is drawn in the inverse colour.
        static let ink = Color(light: 0x0A_0A_0A, dark: 0xFF_FF_FF)

        // Status — the `Soft` variants are the pill fills.
        static let success = Color(light: 0x1F_9D_4B, dark: 0x3D_D0_68)
        static let successSoft = Color(light: 0xE4_F5_EA, dark: 0x3D_D0_68, darkAlpha: 0.18)

        static let info = Color(light: 0x7C_3A_ED, dark: 0xA7_8B_FA)
        static let infoSoft = Color(light: 0xF1_E9_FD, dark: 0xA7_8B_FA, darkAlpha: 0.18)

        static let warning = Color(light: 0xB8_86_0B, dark: 0xE2_B9_3B)
        static let warningSoft = Color(light: 0xFB_F1_D3, dark: 0xE2_B9_3B, darkAlpha: 0.18)

        static let danger = Color(light: 0xE5_48_4D, dark: 0xF2_6B_70)
        static let dangerSoft = Color(light: 0xFD_E7_E8, dark: 0xF2_6B_70, darkAlpha: 0.18)

        static let link = Color(light: 0x2F_6F_ED, dark: 0x5B_8D_EF)
    }

    // MARK: - Typography

    /// SF Pro presets, named as the spec's type table.
    ///
    /// `Font.system(size:)` is a *scaled* font: it grows and shrinks with the
    /// user's Dynamic Type setting from the size given here. It carries no
    /// text style, so none of the per-style caps apply — at the accessibility
    /// sizes these keep growing, and the layouts have to hold.
    ///
    /// Named `Typography` rather than `Type`: Swift rejects a nested type named
    /// `Type` ("type member must not be named 'Type', since it would conflict
    /// with the 'foo.Type' expression").
    enum Typography {
        static let largeTitle = Font.system(size: 30, weight: .bold)
        /// Call sites apply `.tracking(Theme.Typography.largeTitleTracking)`
        /// alongside `largeTitle`; tracking is a view modifier, not a `Font`.
        static let largeTitleTracking: CGFloat = -0.4

        static let title = Font.system(size: 24, weight: .bold)
        static let section = Font.system(size: 20, weight: .semibold)
        static let headline = Font.system(size: 17, weight: .semibold)
        static let body = Font.system(size: 17, weight: .regular)
        static let secondary = Font.system(size: 15, weight: .regular)
        static let caption = Font.system(size: 13, weight: .regular)
        static let pill = Font.system(size: 12, weight: .semibold)
        static let numeric = Font.system(size: 28, weight: .semibold).monospacedDigit()
    }

    // MARK: - Spacing

    /// 4-pt grid.
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32

        /// Horizontal inset of every screen's content.
        static let screenInset: CGFloat = 16
        /// Inner padding of cards and grouped containers.
        static let cardPadding: CGFloat = 16
        /// Vertical gap between thumbnail rows (they use space, not hairlines).
        static let rowSpacing: CGFloat = 20
        /// Minimum height of a list or form row.
        static let rowMinHeight: CGFloat = 52
    }

    // MARK: - Radius

    enum Radius {
        static let card: CGFloat = 20
        static let thumb: CGFloat = 12
        static let input: CGFloat = 12
        static let sheet: CGFloat = 28

        /// Pills, chips and the tab bar have radius ∞ (spec §2). Components
        /// draw them with `Capsule()` rather than a number — this constant
        /// exists only for the rare shape that has to be built from a radius,
        /// and must then be clamped (`min(pill, height / 2)`).
        /// Defined by the design system; no screen uses it yet.
        static let pill: CGFloat = .infinity
    }

    // MARK: - Elevation

    /// Cards carry no shadow in light mode; only floating chrome does, and
    /// only as the fallback for Liquid Glass (spec §2: 0 0 24 pt, 8 % black).
    ///
    /// Defined by the design system; no screen uses it yet — the tab bar and
    /// the sheets all take the system's Liquid Glass material.
    enum Elevation {
        static let floatingColor = Color.black.opacity(0.08)
        static let floatingRadius: CGFloat = 24
        static let floatingX: CGFloat = 0
        static let floatingY: CGFloat = 0
    }

    // MARK: - Muscle-group accents

    /// One contextual accent per screen: the muscle group of what is shown.
    /// Unknown slugs fall back to `other`.
    static func accent(for muscleGroup: String) -> Color {
        let hex = muscleAccentHex(for: muscleGroup)
        return Color(light: hex, dark: hex)
    }

    /// The 14 %-alpha wash of `accent(for:)`, used for illustration tiles and
    /// chart areas.
    static func soft(for muscleGroup: String) -> Color {
        let hex = muscleAccentHex(for: muscleGroup)
        return Color(light: hex, dark: hex, lightAlpha: softAlpha, darkAlpha: softAlpha)
    }

    private static let softAlpha: Double = 0.14

    private static let fallbackAccentHex: UInt32 = 0x95_A5_A6

    private static let muscleAccents: [String: UInt32] = [
        "chest": 0xE0_57_4F,
        "back": 0x3B_7D_D8,
        "shoulders": 0xE0_8A_2E,
        "biceps": 0x9B_59_B6,
        "triceps": 0x8E_44_AD,
        "forearms": 0x7F_8C_8D,
        "core": 0x16_A0_85,
        "quads": 0x2E_CC_71,
        "hamstrings": 0x27_AE_60,
        "glutes": 0xD3_54_00,
        "calves": 0x1A_BC_9C,
        "full_body": 0x34_49_5E,
        "cardio": 0xE9_1E_63,
        "other": 0x95_A5_A6,
    ]

    private static func muscleAccentHex(for muscleGroup: String) -> UInt32 {
        muscleAccents[muscleGroup.lowercased()] ?? fallbackAccentHex
    }
}

// MARK: - Dynamic colour helper

/// Builds an opaque or translucent `UIColor` from a 24-bit RGB value.
///
/// `nonisolated` because it is called from `UIColor`'s trait-resolution
/// closure, which UIKit may run outside the main actor.
private nonisolated func themeUIColor(_ hex: UInt32, _ alpha: Double) -> UIColor {
    UIColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: CGFloat(alpha)
    )
}

fileprivate extension Color {
    /// A colour that resolves itself per interface style, so tokens need no
    /// `@Environment(\.colorScheme)` at the call site.
    nonisolated init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? themeUIColor(dark, darkAlpha)
                : themeUIColor(light, lightAlpha)
        })
    }
}

// MARK: - Elevation helper

extension View {
    /// The fallback shadow for floating chrome where Liquid Glass is not used
    /// (spec §2: x 0, y 0, blur 24 pt, 8 % black). Cards never call it.
    ///
    /// Defined by the design system; no screen uses it yet.
    func floatingShadow() -> some View {
        shadow(
            color: Theme.Elevation.floatingColor,
            radius: Theme.Elevation.floatingRadius,
            x: Theme.Elevation.floatingX,
            y: Theme.Elevation.floatingY)
    }
}
