//
//  TeamBrand.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import SwiftUI
import UIKit

enum TeamThemeMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case systemDefault = "시스템 기본"
    case favoriteTeam = "마이팀 테마 사용"

    var id: String { rawValue }
}

enum TeamThemeID: String, Codable, Sendable {
    case doosan
    case hanwha
    case kia
    case kiwoom
    case kt
    case lg
    case lotte
    case nc
    case samsung
    case ssg
    case neutral
}

struct TeamTheme: Sendable {
    let id: TeamThemeID
    let accent: Color
    let accentSecondary: Color
    let heroStart: Color
    let heroEnd: Color
    let chipBackground: Color
    let badgeBackground: Color
    let badgeForeground: Color
    let scoreboardBackground: Color
    let shadowTint: Color

    nonisolated static let neutral = TeamTheme(
        id: .neutral,
        accent: Color(hex: 0x1C47AB),
        accentSecondary: Color(hex: 0x6797FF),
        heroStart: Color(hex: 0x1C47AB),
        heroEnd: Color(hex: 0x6797FF),
        chipBackground: Color(hex: 0x1C47AB).opacity(0.12),
        badgeBackground: Color(.secondarySystemBackground),
        badgeForeground: Color(hex: 0x1C47AB),
        scoreboardBackground: Color(.secondarySystemBackground),
        shadowTint: Color(hex: 0x1C47AB).opacity(0.12)
    )

    nonisolated static func resolve(for teamID: String?) -> TeamTheme {
        guard let identity = TeamIdentity.catalog[teamID ?? ""] else { return .neutral }
        return identity.theme
    }
}

struct TeamIdentity: Sendable {
    let id: String
    let displayName: String
    let shortLabel: String
    let monogram: String
    let logoAssetName: String
    let themeID: TeamThemeID
    let theme: TeamTheme

    var hasLogoAsset: Bool {
        UIImage(named: logoAssetName) != nil
    }

    nonisolated static let catalog: [String: TeamIdentity] = [
        "doosan": TeamIdentity(
            id: "doosan",
            displayName: "두산 베어스",
            shortLabel: "두산",
            monogram: "DOO",
            logoAssetName: "team-doosan",
            themeID: .doosan,
            theme: TeamTheme(
                id: .doosan,
                accent: Color(hex: 0xF7262A),
                accentSecondary: Color(hex: 0xFFB4AB),
                heroStart: Color(hex: 0x11102E),
                heroEnd: Color(hex: 0xF7262A),
                chipBackground: Color(hex: 0xF7262A).opacity(0.12),
                badgeBackground: Color(hex: 0x191836),
                badgeForeground: Color(hex: 0xFFB4AB),
                scoreboardBackground: Color(hex: 0x1D1C3A),
                shadowTint: Color(hex: 0x11102E).opacity(0.24)
            )
        ),
        "hanwha": TeamIdentity(
            id: "hanwha",
            displayName: "한화 이글스",
            shortLabel: "한화",
            monogram: "HAN",
            logoAssetName: "team-hanwha",
            themeID: .hanwha,
            theme: TeamTheme(
                id: .hanwha,
                accent: Color(hex: 0xFF7936),
                accentSecondary: Color(hex: 0xFF915D),
                heroStart: Color(hex: 0x0E0E0E),
                heroEnd: Color(hex: 0xFF7936),
                chipBackground: Color(hex: 0xFF7936).opacity(0.14),
                badgeBackground: Color(hex: 0x191919),
                badgeForeground: Color(hex: 0xFFF3EB),
                scoreboardBackground: Color(hex: 0x1F1F1F),
                shadowTint: Color(hex: 0xFF7936).opacity(0.14)
            )
        ),
        "kia": TeamIdentity(
            id: "kia",
            displayName: "KIA 타이거즈",
            shortLabel: "KIA",
            monogram: "KIA",
            logoAssetName: "team-kia",
            themeID: .kia,
            theme: TeamTheme(
                id: .kia,
                accent: Color(hex: 0xE51937),
                accentSecondary: Color(hex: 0x76D4E4),
                heroStart: Color(hex: 0x061520),
                heroEnd: Color(hex: 0xE51937),
                chipBackground: Color(hex: 0xE51937).opacity(0.12),
                badgeBackground: Color(hex: 0x10202D),
                badgeForeground: Color(hex: 0xD5E4F4),
                scoreboardBackground: Color(hex: 0x132633),
                shadowTint: Color(hex: 0xD5E4F4).opacity(0.10)
            )
        ),
        "kiwoom": TeamIdentity(
            id: "kiwoom",
            displayName: "키움 히어로즈",
            shortLabel: "키움",
            monogram: "KIW",
            logoAssetName: "team-kiwoom",
            themeID: .kiwoom,
            theme: TeamTheme(
                id: .kiwoom,
                accent: Color(hex: 0xE3007E),
                accentSecondary: Color(hex: 0x570514),
                heroStart: Color(hex: 0x131313),
                heroEnd: Color(hex: 0x570514),
                chipBackground: Color(hex: 0xE3007E).opacity(0.12),
                badgeBackground: Color(hex: 0x1C1B1B),
                badgeForeground: Color(hex: 0xF6D0E7),
                scoreboardBackground: Color(hex: 0x2A2A2A),
                shadowTint: Color(hex: 0x570514).opacity(0.20)
            )
        ),
        "kt": TeamIdentity(
            id: "kt",
            displayName: "KT 위즈",
            shortLabel: "KT",
            monogram: "KT",
            logoAssetName: "team-kt",
            themeID: .kt,
            theme: TeamTheme(
                id: .kt,
                accent: Color(hex: 0xEC1C24),
                accentSecondary: Color(hex: 0xBEC8CE),
                heroStart: Color(hex: 0x131313),
                heroEnd: Color(hex: 0xEC1C24),
                chipBackground: Color(hex: 0xEC1C24).opacity(0.12),
                badgeBackground: Color(hex: 0x201F1F),
                badgeForeground: Color(hex: 0xE5E2E1),
                scoreboardBackground: Color(hex: 0x353534),
                shadowTint: Color.black.opacity(0.18)
            )
        ),
        "lg": TeamIdentity(
            id: "lg",
            displayName: "LG 트윈스",
            shortLabel: "LG",
            monogram: "LG",
            logoAssetName: "team-lg",
            themeID: .lg,
            theme: TeamTheme(
                id: .lg,
                accent: Color(hex: 0xA50034),
                accentSecondary: Color(hex: 0xC6C6C6),
                heroStart: Color(hex: 0x131313),
                heroEnd: Color(hex: 0xA50034),
                chipBackground: Color(hex: 0xA50034).opacity(0.12),
                badgeBackground: Color(hex: 0x1C1B1B),
                badgeForeground: Color(hex: 0xF4ECEE),
                scoreboardBackground: Color(hex: 0x2A2A2A),
                shadowTint: Color.black.opacity(0.18)
            )
        ),
        "lotte": TeamIdentity(
            id: "lotte",
            displayName: "롯데 자이언츠",
            shortLabel: "롯데",
            monogram: "LOT",
            logoAssetName: "team-lotte",
            themeID: .lotte,
            theme: TeamTheme(
                id: .lotte,
                accent: Color(hex: 0xD11B2E),
                accentSecondary: Color(hex: 0x001B3C),
                heroStart: Color(hex: 0x001B3C),
                heroEnd: Color(hex: 0xD11B2E),
                chipBackground: Color(hex: 0xD11B2E).opacity(0.12),
                badgeBackground: Color(hex: 0xF7F9FC),
                badgeForeground: Color(hex: 0x001B3C),
                scoreboardBackground: Color.white,
                shadowTint: Color(hex: 0x001B3C).opacity(0.12)
            )
        ),
        "nc": TeamIdentity(
            id: "nc",
            displayName: "NC 다이노스",
            shortLabel: "NC",
            monogram: "NC",
            logoAssetName: "team-nc",
            themeID: .nc,
            theme: TeamTheme(
                id: .nc,
                accent: Color(hex: 0x00275D),
                accentSecondary: Color(hex: 0xE3C191),
                heroStart: Color(hex: 0x0F141B),
                heroEnd: Color(hex: 0x00275D),
                chipBackground: Color(hex: 0xE3C191).opacity(0.16),
                badgeBackground: Color(hex: 0x1B2027),
                badgeForeground: Color(hex: 0xF4E7D5),
                scoreboardBackground: Color(hex: 0x30353D),
                shadowTint: Color(hex: 0x00275D).opacity(0.20)
            )
        ),
        "samsung": TeamIdentity(
            id: "samsung",
            displayName: "삼성 라이온즈",
            shortLabel: "삼성",
            monogram: "SAM",
            logoAssetName: "team-samsung",
            themeID: .samsung,
            theme: TeamTheme(
                id: .samsung,
                accent: Color(hex: 0x0066B3),
                accentSecondary: Color(hex: 0xC6C6C6),
                heroStart: Color(hex: 0xF7F9FF),
                heroEnd: Color(hex: 0x0066B3),
                chipBackground: Color(hex: 0x0066B3).opacity(0.12),
                badgeBackground: Color(hex: 0xECEEF3),
                badgeForeground: Color(hex: 0x004E8B),
                scoreboardBackground: Color.white,
                shadowTint: Color(hex: 0x004E8B).opacity(0.12)
            )
        ),
        "ssg": TeamIdentity(
            id: "ssg",
            displayName: "SSG 랜더스",
            shortLabel: "SSG",
            monogram: "SSG",
            logoAssetName: "team-ssg",
            themeID: .ssg,
            theme: TeamTheme(
                id: .ssg,
                accent: Color(hex: 0xCE0E2D),
                accentSecondary: Color(hex: 0xA0A0A0),
                heroStart: Color(hex: 0xF9F9F9),
                heroEnd: Color(hex: 0xCE0E2D),
                chipBackground: Color(hex: 0xCE0E2D).opacity(0.12),
                badgeBackground: Color(hex: 0xF3F3F3),
                badgeForeground: Color(hex: 0xA3001F),
                scoreboardBackground: Color.white,
                shadowTint: Color(hex: 0x410006).opacity(0.12)
            )
        )
    ]
}

extension Team {
    var identity: TeamIdentity {
        TeamIdentity.catalog[id] ?? TeamIdentity(
            id: id,
            displayName: name,
            shortLabel: shortName,
            monogram: markText,
            logoAssetName: "team-\(id)",
            themeID: .neutral,
            theme: .neutral
        )
    }
}

private extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
