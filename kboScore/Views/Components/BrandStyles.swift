//
//  BrandStyles.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

enum KBOLivePalette {
    static let primary = Color(red: 0.11, green: 0.28, blue: 0.67)
    static let secondary = Color(red: 0.29, green: 0.48, blue: 0.91)
    static let background = Color(.systemGroupedBackground)
    static let live = Color(red: 0.82, green: 0.15, blue: 0.24)
    static let upcoming = Color(red: 0.13, green: 0.44, blue: 0.88)
    static let final = Color(red: 0.39, green: 0.45, blue: 0.58)
    static let weather = Color(red: 0.88, green: 0.53, blue: 0.12)
    static let cancellation = Color(red: 0.44, green: 0.48, blue: 0.56)
}

enum DoosanPalette {
    static let primary = Color(red: 0.9686, green: 0.1490, blue: 0.1647) // #f7262a
    static let secondary = Color(red: 1.0, green: 0.7059, blue: 0.6706) // #ffb4ab
    static let statusRed = Color(red: 0.7529, green: 0.0, blue: 0.0784) // #c00014

    static let background = Color(red: 0.0667, green: 0.0627, blue: 0.1804) // #11102e
    static let sectionBackground = Color(red: 0.1137, green: 0.1098, blue: 0.2275) // #1d1c3a
    static let elevatedCard = Color(red: 0.1569, green: 0.1529, blue: 0.2706) // #282745
    static let elevatedCardStrong = Color(red: 0.1961, green: 0.1922, blue: 0.3176) // #323151
    static let recessedSurface = Color(red: 0.0431, green: 0.0392, blue: 0.1569) // #0b0a28
    static let glassSurface = Color(red: 0.2157, green: 0.2118, blue: 0.3373).opacity(0.60) // #373656 @ 60%
    static let navigationSurface = background
    static let tabBarSurface = Color(red: 0.0353, green: 0.0314, blue: 0.1294) // #090821
    static let tabBarSelectionSurface = Color(red: 0.1569, green: 0.1529, blue: 0.2706).opacity(0.96) // #282745
    static let bellControlSurface = Color(red: 0.0431, green: 0.0392, blue: 0.1569) // #0b0a28

    static let textPrimary = Color.white.opacity(0.96)
    static let textSecondary = Color(red: 0.7843, green: 0.7725, blue: 0.8078) // #c8c5ce
    static let ghostBorder = Color(red: 0.2784, green: 0.2745, blue: 0.3020).opacity(0.15) // #47464d @ 15%
    static let ambientShadow = Color(red: 0.0431, green: 0.0392, blue: 0.1569).opacity(0.40)
    static let weather = Color(red: 0.95, green: 0.72, blue: 0.28)
}

struct StadiumPalette: Sendable {
    let id: String
    let primary: Color
    let secondary: Color
    let statusRed: Color
    let background: Color
    let sectionBackground: Color
    let elevatedCard: Color
    let elevatedCardStrong: Color
    let recessedSurface: Color
    let glassSurface: Color
    let navigationSurface: Color
    let tabBarSurface: Color
    let tabBarSelectionSurface: Color
    let bellControlSurface: Color
    let textPrimary: Color
    let textSecondary: Color
    let ghostBorder: Color
    let ambientShadow: Color
    let weather: Color
    let winDayFill: Color

    var usesLightForegroundStyle: Bool {
        id == "samsung" || id == "ssg"
    }

    var tabBarForeground: Color {
        usesLightForegroundStyle ? textPrimary : Color.white.opacity(0.94)
    }

    func tabBarForeground(isSelected: Bool) -> Color {
        isSelected ? primary : tabBarForeground
    }

    static let doosan = StadiumPalette(
        id: "doosan",
        primary: DoosanPalette.primary,
        secondary: DoosanPalette.secondary,
        statusRed: DoosanPalette.statusRed,
        background: DoosanPalette.background,
        sectionBackground: DoosanPalette.sectionBackground,
        elevatedCard: DoosanPalette.elevatedCard,
        elevatedCardStrong: DoosanPalette.elevatedCardStrong,
        recessedSurface: DoosanPalette.recessedSurface,
        glassSurface: DoosanPalette.glassSurface,
        navigationSurface: DoosanPalette.navigationSurface,
        tabBarSurface: DoosanPalette.tabBarSurface,
        tabBarSelectionSurface: DoosanPalette.tabBarSelectionSurface,
        bellControlSurface: DoosanPalette.bellControlSurface,
        textPrimary: DoosanPalette.textPrimary,
        textSecondary: DoosanPalette.textSecondary,
        ghostBorder: DoosanPalette.ghostBorder,
        ambientShadow: DoosanPalette.ambientShadow,
        weather: DoosanPalette.weather,
        winDayFill: Color(red: 0.38, green: 0.78, blue: 1.0).opacity(0.30)
    )

    static let hanwha = StadiumPalette(
        id: "hanwha",
        primary: Color(red: 1.0, green: 0.5686, blue: 0.3647), // #ff915d
        secondary: Color(red: 1.0, green: 0.4745, blue: 0.2118), // #ff7936
        statusRed: Color(red: 0.9765, green: 0.3922, blue: 0.0), // #f96400
        background: Color(red: 0.0549, green: 0.0549, blue: 0.0549), // #0e0e0e
        sectionBackground: Color(red: 0.0745, green: 0.0745, blue: 0.0745), // #131313
        elevatedCard: Color(red: 0.0980, green: 0.0980, blue: 0.0980), // #191919
        elevatedCardStrong: Color(red: 0.1490, green: 0.1490, blue: 0.1490), // #262626
        recessedSurface: Color(red: 0.0353, green: 0.0353, blue: 0.0353), // #090909
        glassSurface: Color(red: 0.1490, green: 0.1490, blue: 0.1490).opacity(0.62),
        navigationSurface: Color(red: 0.0549, green: 0.0549, blue: 0.0549),
        tabBarSurface: Color(red: 0.0314, green: 0.0314, blue: 0.0314),
        tabBarSelectionSurface: Color(red: 0.1490, green: 0.1490, blue: 0.1490).opacity(0.96),
        bellControlSurface: Color(red: 0.0745, green: 0.0745, blue: 0.0745),
        textPrimary: Color(red: 0.9765, green: 0.9765, blue: 0.9765), // #f9f9f9
        textSecondary: Color(red: 0.7608, green: 0.7373, blue: 0.7176),
        ghostBorder: Color(red: 0.2824, green: 0.2824, blue: 0.2824).opacity(0.18),
        ambientShadow: Color(red: 1.0, green: 0.4745, blue: 0.2118).opacity(0.22),
        weather: Color(red: 1.0, green: 0.7333, blue: 0.3412),
        winDayFill: Color(red: 1.0, green: 0.5686, blue: 0.3647).opacity(0.30)
    )

    static let kia = StadiumPalette(
        id: "kia",
        primary: Color(red: 0.8980, green: 0.0980, blue: 0.2157), // #E51937
        secondary: Color(red: 0.4627, green: 0.8314, blue: 0.8941), // #76d4e4
        statusRed: Color(red: 0.8980, green: 0.0980, blue: 0.2157), // #E51937
        background: Color(red: 0.0235, green: 0.0824, blue: 0.1255), // #061520
        sectionBackground: Color(red: 0.0314, green: 0.1176, blue: 0.1765), // #081e2d
        elevatedCard: Color(red: 0.0471, green: 0.1569, blue: 0.2196), // #0c2838
        elevatedCardStrong: Color(red: 0.0706, green: 0.2039, blue: 0.2784), // #123447
        recessedSurface: Color(red: 0.0118, green: 0.0471, blue: 0.0745), // #030c13
        glassSurface: Color(red: 0.0706, green: 0.2039, blue: 0.2784).opacity(0.58),
        navigationSurface: Color(red: 0.0235, green: 0.0824, blue: 0.1255),
        tabBarSurface: Color(red: 0.0078, green: 0.0314, blue: 0.0510), // #02080d
        tabBarSelectionSurface: Color(red: 0.0471, green: 0.1569, blue: 0.2196).opacity(0.96),
        bellControlSurface: Color(red: 0.0118, green: 0.0471, blue: 0.0745),
        textPrimary: Color(red: 0.8353, green: 0.8941, blue: 0.9569), // #d5e4f4
        textSecondary: Color(red: 0.6588, green: 0.7412, blue: 0.8118),
        ghostBorder: Color(red: 0.8353, green: 0.8941, blue: 0.9569).opacity(0.12),
        ambientShadow: Color(red: 0.4627, green: 0.8314, blue: 0.8941).opacity(0.18),
        weather: Color(red: 0.4627, green: 0.8314, blue: 0.8941),
        winDayFill: Color(red: 0.4627, green: 0.8314, blue: 0.8941).opacity(0.30)
    )

    static let kt = StadiumPalette(
        id: "kt",
        primary: Color(red: 0.9255, green: 0.1098, blue: 0.1412), // #EC1C24
        secondary: Color(red: 1.0, green: 0.7059, blue: 0.6706), // #ffb4ab
        statusRed: Color(red: 0.9255, green: 0.1098, blue: 0.1412), // #EC1C24
        background: Color(red: 0.0745, green: 0.0745, blue: 0.0745), // #131313
        sectionBackground: Color(red: 0.0549, green: 0.0549, blue: 0.0549), // #0e0e0e
        elevatedCard: Color(red: 0.1255, green: 0.1216, blue: 0.1216), // #201f1f
        elevatedCardStrong: Color(red: 0.2078, green: 0.2078, blue: 0.2039), // #353534
        recessedSurface: Color(red: 0.0549, green: 0.0549, blue: 0.0549), // #0e0e0e
        glassSurface: Color(red: 0.2078, green: 0.2078, blue: 0.2039).opacity(0.60),
        navigationSurface: Color(red: 0.0745, green: 0.0745, blue: 0.0745),
        tabBarSurface: Color(red: 0.0549, green: 0.0549, blue: 0.0549),
        tabBarSelectionSurface: Color(red: 0.2078, green: 0.2078, blue: 0.2039).opacity(0.96),
        bellControlSurface: Color(red: 0.0549, green: 0.0549, blue: 0.0549),
        textPrimary: Color(red: 0.8980, green: 0.8863, blue: 0.8824), // #e5e2e1
        textSecondary: Color(red: 0.7451, green: 0.7843, blue: 0.8078), // #bec8ce
        ghostBorder: Color(red: 0.3686, green: 0.2471, blue: 0.2353).opacity(0.15), // #5e3f3c
        ambientShadow: Color.black.opacity(0.08),
        weather: Color(red: 0.7451, green: 0.7843, blue: 0.8078), // #bec8ce
        winDayFill: Color(red: 1.0, green: 0.7059, blue: 0.6706).opacity(0.30)
    )

    static let lg = StadiumPalette(
        id: "lg",
        primary: Color(red: 0.6471, green: 0.0, blue: 0.2039), // #A50034
        secondary: Color(red: 1.0, green: 0.6980, blue: 0.7216), // #FFB2B8
        statusRed: Color(red: 0.6471, green: 0.0, blue: 0.2039), // #A50034
        background: Color(red: 0.0745, green: 0.0745, blue: 0.0745), // #131313
        sectionBackground: Color(red: 0.1098, green: 0.1059, blue: 0.1059), // #1C1B1B
        elevatedCard: Color(red: 0.1255, green: 0.1216, blue: 0.1216), // #201F1F
        elevatedCardStrong: Color(red: 0.1647, green: 0.1647, blue: 0.1647), // #2A2A2A
        recessedSurface: Color(red: 0.0549, green: 0.0549, blue: 0.0549), // #0E0E0E
        glassSurface: Color(red: 0.1255, green: 0.1216, blue: 0.1216).opacity(0.80),
        navigationSurface: Color(red: 0.0745, green: 0.0745, blue: 0.0745),
        tabBarSurface: Color(red: 0.0549, green: 0.0549, blue: 0.0549),
        tabBarSelectionSurface: Color(red: 0.1647, green: 0.1647, blue: 0.1647).opacity(0.96),
        bellControlSurface: Color(red: 0.0549, green: 0.0549, blue: 0.0549),
        textPrimary: Color(red: 0.9569, green: 0.9255, blue: 0.9333), // soft light foreground
        textSecondary: Color(red: 0.7765, green: 0.7765, blue: 0.7765), // #C6C6C6
        ghostBorder: Color(red: 0.7765, green: 0.7765, blue: 0.7765).opacity(0.12),
        ambientShadow: Color.black.opacity(0.18),
        weather: Color(red: 0.7765, green: 0.7765, blue: 0.7765), // silver technical accent
        winDayFill: Color(red: 0.6471, green: 0.0, blue: 0.2039).opacity(0.30)
    )

    static let lotte = StadiumPalette(
        id: "lotte",
        primary: Color(red: 0.6627, green: 0.0, blue: 0.1137), // #a9001d
        secondary: Color(red: 0.8196, green: 0.1059, blue: 0.1804), // #d11b2e
        statusRed: Color(red: 0.8196, green: 0.1059, blue: 0.1804), // #d11b2e
        background: Color(red: 0.0, green: 0.1059, blue: 0.2353), // #001b3c
        sectionBackground: Color(red: 0.0235, green: 0.1412, blue: 0.2902), // #06244a
        elevatedCard: Color(red: 0.0431, green: 0.1922, blue: 0.3647), // #0b315d
        elevatedCardStrong: Color(red: 0.0745, green: 0.2353, blue: 0.4275), // #133c6d
        recessedSurface: Color(red: 0.0, green: 0.0784, blue: 0.1765), // #00142d
        glassSurface: Color(red: 0.0431, green: 0.1922, blue: 0.3647).opacity(0.70),
        navigationSurface: Color(red: 0.0, green: 0.1059, blue: 0.2353),
        tabBarSurface: Color(red: 0.0, green: 0.0784, blue: 0.1765),
        tabBarSelectionSurface: Color(red: 0.0431, green: 0.1922, blue: 0.3647).opacity(0.96),
        bellControlSurface: Color(red: 0.0, green: 0.0784, blue: 0.1765),
        textPrimary: Color(red: 0.9686, green: 0.9765, blue: 0.9882),
        textSecondary: Color(red: 0.7765, green: 0.7765, blue: 0.7765), // #c6c6c6
        ghostBorder: Color(red: 0.5843, green: 0.8078, blue: 0.9333).opacity(0.14), // #95ceee @ 14%
        ambientShadow: Color(red: 0.0, green: 0.1059, blue: 0.2353).opacity(0.24),
        weather: Color(red: 0.5843, green: 0.8078, blue: 0.9333), // #95ceee
        winDayFill: Color(red: 0.8196, green: 0.1059, blue: 0.1804).opacity(0.30)
    )

    static let nc = StadiumPalette(
        id: "nc",
        primary: Color(red: 0.6824, green: 0.7765, blue: 1.0), // #aec6ff
        secondary: Color(red: 0.8902, green: 0.7569, blue: 0.5686), // #e3c191
        statusRed: Color(red: 0.0, green: 0.1529, blue: 0.3647), // #00275d
        background: Color(red: 0.0588, green: 0.0784, blue: 0.1059), // #0f141b
        sectionBackground: Color(red: 0.0353, green: 0.0549, blue: 0.0824), // #090e15
        elevatedCard: Color(red: 0.1059, green: 0.1255, blue: 0.1529), // #1b2027
        elevatedCardStrong: Color(red: 0.1882, green: 0.2078, blue: 0.2392), // #30353d
        recessedSurface: Color(red: 0.0235, green: 0.0392, blue: 0.0627), // deep content well variant
        glassSurface: Color(red: 0.1059, green: 0.1255, blue: 0.1529).opacity(0.72),
        navigationSurface: Color(red: 0.0588, green: 0.0784, blue: 0.1059),
        tabBarSurface: Color(red: 0.0353, green: 0.0549, blue: 0.0824),
        tabBarSelectionSurface: Color(red: 0.1882, green: 0.2078, blue: 0.2392).opacity(0.96),
        bellControlSurface: Color(red: 0.0353, green: 0.0549, blue: 0.0824),
        textPrimary: Color(red: 0.9569, green: 0.9686, blue: 0.9804),
        textSecondary: Color(red: 0.8902, green: 0.7569, blue: 0.5686), // gold label accent
        ghostBorder: Color(red: 0.6824, green: 0.7765, blue: 1.0).opacity(0.14),
        ambientShadow: Color(red: 0.0, green: 0.1529, blue: 0.3647).opacity(0.22),
        weather: Color(red: 0.8902, green: 0.7569, blue: 0.5686), // restrained gold technical accent
        winDayFill: Color(red: 0.0, green: 0.1529, blue: 0.3647).opacity(0.32)
    )

    static let kiwoom = StadiumPalette(
        id: "kiwoom",
        primary: Color(red: 0.3412, green: 0.0196, blue: 0.0784), // #570514
        secondary: Color(red: 0.8902, green: 0.0, blue: 0.4941), // #E3007E
        statusRed: Color(red: 0.8902, green: 0.0, blue: 0.4941), // #E3007E
        background: Color(red: 0.0745, green: 0.0745, blue: 0.0745), // #131313
        sectionBackground: Color(red: 0.1098, green: 0.1059, blue: 0.1059), // #1c1b1b
        elevatedCard: Color(red: 0.1647, green: 0.1647, blue: 0.1647), // #2a2a2a
        elevatedCardStrong: Color(red: 0.2078, green: 0.2078, blue: 0.2039), // #353534
        recessedSurface: Color(red: 0.0941, green: 0.0941, blue: 0.0941), // dark nested well
        glassSurface: Color(red: 0.1647, green: 0.1647, blue: 0.1647).opacity(0.72),
        navigationSurface: Color(red: 0.0745, green: 0.0745, blue: 0.0745),
        tabBarSurface: Color(red: 0.1098, green: 0.1059, blue: 0.1059),
        tabBarSelectionSurface: Color(red: 0.2078, green: 0.2078, blue: 0.2039).opacity(0.96),
        bellControlSurface: Color(red: 0.1098, green: 0.1059, blue: 0.1059),
        textPrimary: Color(red: 0.9569, green: 0.9412, blue: 0.9529), // bright editorial foreground
        textSecondary: Color(red: 0.7216, green: 0.6706, blue: 0.7059), // muted on-surface-variant
        ghostBorder: Color(red: 0.8902, green: 0.0, blue: 0.4941).opacity(0.14),
        ambientShadow: Color(red: 0.3412, green: 0.0196, blue: 0.0784).opacity(0.20),
        weather: Color(red: 0.8902, green: 0.0, blue: 0.4941), // neon signal accent for technical emphasis
        winDayFill: Color(red: 0.3412, green: 0.0196, blue: 0.0784).opacity(0.34)
    )

    static let samsung = StadiumPalette(
        id: "samsung",
        primary: Color(red: 0.0, green: 0.3059, blue: 0.5451), // #004e8b
        secondary: Color(red: 0.7765, green: 0.7765, blue: 0.7765), // #c6c6c6
        statusRed: Color(red: 0.0, green: 0.4, blue: 0.7020), // #0066b3
        background: Color(red: 0.9686, green: 0.9765, blue: 1.0), // #f7f9ff
        sectionBackground: Color(red: 0.9255, green: 0.9333, blue: 0.9529), // #eceef3
        elevatedCard: Color.white, // #ffffff
        elevatedCardStrong: Color(red: 0.9647, green: 0.9725, blue: 0.9882), // lifted white-blue surface
        recessedSurface: Color(red: 0.9059, green: 0.9216, blue: 0.9529), // cool recessed well
        glassSurface: Color(red: 0.9686, green: 0.9765, blue: 1.0).opacity(0.80),
        navigationSurface: Color(red: 0.9686, green: 0.9765, blue: 1.0),
        tabBarSurface: Color(red: 0.9255, green: 0.9333, blue: 0.9529),
        tabBarSelectionSurface: Color.white.opacity(0.98),
        bellControlSurface: Color(red: 0.9373, green: 0.9529, blue: 0.9843),
        textPrimary: Color(red: 0.0941, green: 0.1098, blue: 0.1255), // #181c20
        textSecondary: Color(red: 0.3725, green: 0.4, blue: 0.4510), // readable steel metadata
        ghostBorder: Color(red: 0.7569, green: 0.7804, blue: 0.8275).opacity(0.15), // #c1c7d3 @ 15%
        ambientShadow: Color(red: 0.0, green: 0.3059, blue: 0.5451).opacity(0.08),
        weather: Color(red: 0.7765, green: 0.7765, blue: 0.7765), // silver accent
        winDayFill: Color(red: 0.0, green: 0.4, blue: 0.7020).opacity(0.24)
    )

    static let ssg = StadiumPalette(
        id: "ssg",
        primary: Color(red: 0.8078, green: 0.0549, blue: 0.1765), // #CE0E2D
        secondary: Color(red: 0.6275, green: 0.6275, blue: 0.6275), // #A0A0A0
        statusRed: Color(red: 0.6392, green: 0.0, blue: 0.1216), // #a3001f
        background: Color(red: 0.9765, green: 0.9765, blue: 0.9765), // #f9f9f9
        sectionBackground: Color(red: 0.9529, green: 0.9529, blue: 0.9529), // #f3f3f3
        elevatedCard: Color.white, // #ffffff
        elevatedCardStrong: Color(red: 0.9098, green: 0.9098, blue: 0.9098), // #e8e8e8
        recessedSurface: Color(red: 0.9529, green: 0.9529, blue: 0.9529), // #f3f3f3
        glassSurface: Color.white.opacity(0.80),
        navigationSurface: Color(red: 0.9765, green: 0.9765, blue: 0.9765),
        tabBarSurface: Color(red: 0.9529, green: 0.9529, blue: 0.9529),
        tabBarSelectionSurface: Color.white.opacity(0.96),
        bellControlSurface: Color(red: 0.9650, green: 0.9650, blue: 0.9650),
        textPrimary: Color(red: 0.1294, green: 0.1098, blue: 0.1137), // deep editorial near-black
        textSecondary: Color(red: 0.3922, green: 0.3882, blue: 0.3961), // silver-weighted metadata
        ghostBorder: Color(red: 0.9020, green: 0.7412, blue: 0.7333).opacity(0.15), // outline fallback @ 15%
        ambientShadow: Color(red: 0.2549, green: 0.0, blue: 0.0235).opacity(0.08), // #410006 tinted shadow
        weather: Color(red: 0.7412, green: 0.9137, blue: 1.0), // #bde9ff
        winDayFill: Color(red: 0.8078, green: 0.0549, blue: 0.1765).opacity(0.24)
    )
}

extension AppModel {
    var favoriteStadiumPalette: StadiumPalette? {
        switch settings.favoriteTeamID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "doosan":
            .doosan
        case "hanwha":
            .hanwha
        case "kia":
            .kia
        case "kiwoom":
            .kiwoom
        case "kt":
            .kt
        case "lg":
            .lg
        case "lotte":
            .lotte
        case "nc":
            .nc
        case "samsung":
            .samsung
        case "ssg":
            .ssg
        default:
            nil
        }
    }

    var isStadiumFavoriteSelected: Bool {
        favoriteStadiumPalette != nil
    }
}

extension GameStatus {
    var tintColor: Color {
        switch self {
        case .live:
            KBOLivePalette.live
        case .upcoming:
            KBOLivePalette.upcoming
        case .final:
            KBOLivePalette.final
        case .rainDelay:
            KBOLivePalette.weather
        case .cancelled:
            KBOLivePalette.cancellation
        }
    }

    var cardBackgroundColor: Color {
        switch self {
        case .live:
            KBOLivePalette.live.opacity(0.08)
        case .upcoming:
            KBOLivePalette.upcoming.opacity(0.06)
        case .final:
            KBOLivePalette.final.opacity(0.06)
        case .rainDelay:
            KBOLivePalette.weather.opacity(0.10)
        case .cancelled:
            KBOLivePalette.cancellation.opacity(0.08)
        }
    }

    var doosanTintColor: Color {
        switch self {
        case .live:
            DoosanPalette.statusRed
        case .upcoming:
            DoosanPalette.secondary
        case .final:
            DoosanPalette.textSecondary.opacity(0.86)
        case .rainDelay:
            DoosanPalette.weather
        case .cancelled:
            DoosanPalette.statusRed
        }
    }

    var doosanCardBackgroundColor: Color {
        switch self {
        case .live:
            DoosanPalette.elevatedCardStrong
        case .upcoming:
            DoosanPalette.elevatedCard
        case .final:
            DoosanPalette.sectionBackground
        case .rainDelay:
            DoosanPalette.elevatedCardStrong
        case .cancelled:
            DoosanPalette.sectionBackground
        }
    }

    func stadiumTintColor(_ palette: StadiumPalette) -> Color {
        switch self {
        case .live:
            palette.statusRed
        case .upcoming:
            palette.secondary
        case .final:
            palette.textSecondary.opacity(0.86)
        case .rainDelay:
            palette.weather
        case .cancelled:
            palette.statusRed
        }
    }

    func stadiumCardBackgroundColor(_ palette: StadiumPalette) -> Color {
        switch self {
        case .live:
            palette.elevatedCardStrong
        case .upcoming:
            palette.elevatedCard
        case .final:
            palette.sectionBackground
        case .rainDelay:
            palette.elevatedCardStrong
        case .cancelled:
            palette.sectionBackground
        }
    }
}

extension NotificationType {
    var tintColor: Color {
        switch self {
        case .scoreChange, .leadChange, .onBase, .inningChange:
            KBOLivePalette.primary
        case .gameStart:
            Color.gray
        case .gameEnd:
            Color(red: 0.59, green: 0.42, blue: 0.02)
        case .rainDelay:
            KBOLivePalette.live
        }
    }

    var doosanTintColor: Color {
        switch self {
        case .scoreChange, .leadChange, .onBase, .inningChange:
            DoosanPalette.primary
        case .gameStart:
            DoosanPalette.secondary
        case .gameEnd:
            DoosanPalette.textSecondary
        case .rainDelay:
            DoosanPalette.weather
        }
    }

    func stadiumTintColor(_ palette: StadiumPalette) -> Color {
        switch self {
        case .scoreChange, .leadChange, .onBase, .inningChange:
            palette.primary
        case .gameStart:
            palette.secondary
        case .gameEnd:
            palette.textSecondary
        case .rainDelay:
            palette.weather
        }
    }

    var systemImage: String {
        switch self {
        case .scoreChange:
            "chart.line.uptrend.xyaxis"
        case .onBase:
            "figure.baseball"
        case .gameStart:
            "play.circle.fill"
        case .leadChange:
            "arrow.left.arrow.right.circle.fill"
        case .gameEnd:
            "flag.fill"
        case .inningChange:
            "arrow.triangle.2.circlepath.circle.fill"
        case .rainDelay:
            "cloud.rain.fill"
        }
    }
}

struct CardSurface: ViewModifier {
    @Environment(AppModel.self) private var appModel
    let padding: CGFloat
    let cornerRadius: CGFloat
    let fillColor: Color?
    let showsGhostBorder: Bool

    func body(content: Content) -> some View {
        let stadiumPalette = appModel.favoriteStadiumPalette
        let resolvedFillColor = fillColor ?? (stadiumPalette?.elevatedCard ?? Color(.secondarySystemBackground))

        return content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(resolvedFillColor)
            )
            .overlay {
                if let stadiumPalette {
                    if showsGhostBorder {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(stadiumPalette.ghostBorder, lineWidth: 0.75)
                    }
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                }
            }
            .shadow(color: stadiumPalette?.ambientShadow.opacity(0.34) ?? .clear, radius: 12, y: 6)
    }
}

extension View {
    func cardSurface(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 20,
        fillColor: Color? = nil,
        showsGhostBorder: Bool = false
    ) -> some View {
        modifier(
            CardSurface(
                padding: padding,
                cornerRadius: cornerRadius,
                fillColor: fillColor,
                showsGhostBorder: showsGhostBorder
            )
        )
    }

    func doosanNavigationChrome(isEnabled: Bool) -> some View {
        modifier(DoosanNavigationChromeModifier(isEnabled: isEnabled))
    }

    func doosanInlineNavigationTitle(isEnabled: Bool) -> some View {
        modifier(DoosanInlineNavigationTitleModifier(isEnabled: isEnabled))
    }

    func stadiumNavigationChrome(_ palette: StadiumPalette?) -> some View {
        modifier(StadiumNavigationChromeModifier(palette: palette))
    }
}

private struct StadiumNavigationChromeModifier: ViewModifier {
    let palette: StadiumPalette?

    func body(content: Content) -> some View {
        if let palette {
            content
                .toolbarColorScheme(palette.usesLightForegroundStyle ? .light : .dark, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(palette.navigationSurface, for: .navigationBar)
        } else {
            content
        }
    }
}

private struct DoosanNavigationChromeModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(DoosanPalette.navigationSurface, for: .navigationBar)
        } else {
            content
        }
    }
}

private struct DoosanInlineNavigationTitleModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}

struct TeamMarkView: View {
    @Environment(AppModel.self) private var appModel
    let team: Team
    var size: CGFloat = 38
    var assetStyle: TeamImageAssetStyle = .officialLogoPreferred

    var body: some View {
        let identity = team.identity
        let stadiumPalette = appModel.favoriteStadiumPalette

        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(stadiumPalette?.recessedSurface ?? identity.theme.badgeBackground)

            if TeamLogoAssetResolver.hasPreferredAsset(for: identity, style: assetStyle) {
                Image(TeamLogoAssetResolver.preferredAssetName(for: identity, style: assetStyle))
                    .resizable()
                    .scaledToFit()
                    .padding(assetStyle == .mascotPreferred ? size * 0.08 : size * 0.16)
            } else {
                Text(identity.monogram)
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundStyle(stadiumPalette?.textSecondary ?? identity.theme.badgeForeground)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(
                    stadiumPalette?.ghostBorder ?? Color.primary.opacity(0.06),
                    lineWidth: stadiumPalette == nil ? 1 : 0.7
                )
        )
        .shadow(
            color: stadiumPalette?.ambientShadow.opacity(0.28) ?? identity.theme.shadowTint,
            radius: stadiumPalette == nil ? size * 0.12 : size * 0.14,
            y: stadiumPalette == nil ? size * 0.06 : size * 0.08
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TeamLogoAssetResolver.accessibilityLabel(for: identity, style: assetStyle))
    }
}

struct BasesDiamondView: View {
    let bases: RunnerState

    var body: some View {
        ZStack {
            DiamondBase(isFilled: bases.second)
                .offset(y: -16)
            DiamondBase(isFilled: bases.first)
                .offset(x: 16)
            DiamondBase(isFilled: bases.third)
                .offset(x: -16)
            DiamondBase(isFilled: false)
                .offset(y: 16)
        }
        .frame(width: 68, height: 68)
    }
}

struct OutCountView: View {
    @Environment(AppModel.self) private var appModel
    let outs: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < outs ? activeColor : inactiveColor)
                    .frame(width: 10, height: 10)
            }
        }
    }

    private var activeColor: Color {
        appModel.favoriteStadiumPalette?.statusRed ?? KBOLivePalette.live
    }

    private var inactiveColor: Color {
        appModel.favoriteStadiumPalette?.elevatedCardStrong ?? Color(.systemGray5)
    }
}

private struct DiamondBase: View {
    @Environment(AppModel.self) private var appModel
    let isFilled: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(borderColor, lineWidth: lineWidth)
            )
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(45))
    }

    private var fillColor: Color {
        if let stadiumPalette = appModel.favoriteStadiumPalette {
            return isFilled ? stadiumPalette.primary : stadiumPalette.recessedSurface
        }
        return isFilled ? KBOLivePalette.primary : Color(.systemBackground)
    }

    private var borderColor: Color {
        if let stadiumPalette = appModel.favoriteStadiumPalette {
            return stadiumPalette.secondary.opacity(0.45)
        }
        return KBOLivePalette.primary.opacity(0.35)
    }

    private var lineWidth: CGFloat {
        appModel.isStadiumFavoriteSelected ? 0.75 : 1
    }
}
