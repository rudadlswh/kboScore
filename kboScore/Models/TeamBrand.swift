//
//  TeamBrand.swift
//  kboScore
//  기능 설명: 팀별 색상, 이미지, 경기장 팔레트 등 브랜드 정보를 정의합니다.
//  KBO 경기와 팀 규칙을 화면·저장소와 분리된 값 모델로 표현해 계산과 비교 기준을 일관되게 유지합니다.
//  동명이인, 보류 경기, 취소 경기, 누락 점수처럼 원천 데이터가 불완전한 상황을 고려합니다.
//  TODO : 새 시즌 규칙이나 추가 지표가 생기면 모델 확장 지점을 명확히 분리합니다.
//
//  Created by Codex on 3/26/26.
//

import SwiftUI

// TeamThemeMode 열거형는 TeamThemeMode 타입의 역할과 값을 정의합니다.
enum TeamThemeMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case systemDefault = "시스템 기본"
    case favoriteTeam = "마이팀 테마 사용"

    var id: String { rawValue }
}

// TeamThemeID 열거형는 TeamThemeID 타입의 역할과 값을 정의합니다.
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

// TeamTheme 구조체는 TeamTheme 타입의 역할과 값을 정의합니다.
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

    // resolve 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    nonisolated static func resolve(for teamID: String?) -> TeamTheme {
        guard let identity = TeamIdentity.catalog[teamID ?? ""] else { return .neutral }
        return identity.theme
    }
}

// TeamIdentity 구조체는 TeamIdentity 타입의 역할과 값을 정의합니다.
struct TeamIdentity: Sendable {
    let id: String
    let displayName: String
    let shortLabel: String
    let monogram: String
    let homeHeroWatermarkLabel: String
    let themeID: TeamThemeID
    let theme: TeamTheme

    nonisolated static let catalog: [String: TeamIdentity] = [
        "doosan": TeamIdentity(
            id: "doosan",
            displayName: "두산 베어스",
            shortLabel: "두산",
            monogram: "OB",
            homeHeroWatermarkLabel: "Bears",
            themeID: .doosan,
            theme: TeamTheme(
                id: .doosan,
                accent: Color(hex: 0x1A1D29),
                accentSecondary: Color(hex: 0xFDFCF8),
                heroStart: Color(hex: 0x12305C),
                heroEnd: Color(hex: 0x1A1D29),
                chipBackground: Color(hex: 0x1A1D29).opacity(0.12),
                badgeBackground: Color(hex: 0x12305C),
                badgeForeground: Color(hex: 0xFDFCF8),
                scoreboardBackground: Color(hex: 0x263247),
                shadowTint: Color(hex: 0x1A1D29).opacity(0.22)
            )
        ),
        "hanwha": TeamIdentity(
            id: "hanwha",
            displayName: "한화 이글스",
            shortLabel: "한화",
            monogram: "HAN",
            homeHeroWatermarkLabel: "Eagles",
            themeID: .hanwha,
            theme: TeamTheme(
                id: .hanwha,
                accent: Color(hex: 0xEF5F18),
                accentSecondary: Color(hex: 0xFDFCF8),
                heroStart: Color(hex: 0x0E0E0E),
                heroEnd: Color(hex: 0xEF5F18),
                chipBackground: Color(hex: 0xEF5F18).opacity(0.14),
                badgeBackground: Color(hex: 0x191919),
                badgeForeground: Color(hex: 0xFDFCF8),
                scoreboardBackground: Color(hex: 0x1F1F1F),
                shadowTint: Color(hex: 0xEF5F18).opacity(0.14)
            )
        ),
        "kia": TeamIdentity(
            id: "kia",
            displayName: "KIA 타이거즈",
            shortLabel: "기아",
            monogram: "KIA",
            homeHeroWatermarkLabel: "Tigers",
            themeID: .kia,
            theme: TeamTheme(
                id: .kia,
                accent: Color(hex: 0xD81F25),
                accentSecondary: Color(hex: 0xD81F25),
                heroStart: Color(hex: 0x061520),
                heroEnd: Color(hex: 0xD81F25),
                chipBackground: Color(hex: 0xD81F25).opacity(0.12),
                badgeBackground: Color(hex: 0x10202D),
                badgeForeground: Color(hex: 0xD81F25),
                scoreboardBackground: Color(hex: 0x132633),
                shadowTint: Color(hex: 0xD81F25).opacity(0.10)
            )
        ),
        "kiwoom": TeamIdentity(
            id: "kiwoom",
            displayName: "키움 히어로즈",
            shortLabel: "키움",
            monogram: "KIW",
            homeHeroWatermarkLabel: "Heroes",
            themeID: .kiwoom,
            theme: TeamTheme(
                id: .kiwoom,
                accent: Color(hex: 0x8E0320),
                accentSecondary: Color(hex: 0x5C3A21),
                heroStart: Color(hex: 0x131313),
                heroEnd: Color(hex: 0x8E0320),
                chipBackground: Color(hex: 0x8E0320).opacity(0.12),
                badgeBackground: Color(hex: 0x1C1B1B),
                badgeForeground: Color(hex: 0x5C3A21),
                scoreboardBackground: Color(hex: 0x2A2A2A),
                shadowTint: Color(hex: 0x8E0320).opacity(0.20)
            )
        ),
        "kt": TeamIdentity(
            id: "kt",
            displayName: "KT 위즈",
            shortLabel: "KT",
            monogram: "KT",
            homeHeroWatermarkLabel: "Wiz",
            themeID: .kt,
            theme: TeamTheme(
                id: .kt,
                accent: Color(hex: 0x0A0A0A),
                accentSecondary: Color(hex: 0xFDFCF8),
                heroStart: Color(hex: 0x131313),
                heroEnd: Color(hex: 0x0A0A0A),
                chipBackground: Color(hex: 0x0A0A0A).opacity(0.12),
                badgeBackground: Color(hex: 0x201F1F),
                badgeForeground: Color(hex: 0xFDFCF8),
                scoreboardBackground: Color(hex: 0x353534),
                shadowTint: Color.black.opacity(0.18)
            )
        ),
        "lg": TeamIdentity(
            id: "lg",
            displayName: "LG 트윈스",
            shortLabel: "LG",
            monogram: "LG",
            homeHeroWatermarkLabel: "Twins",
            themeID: .lg,
            theme: TeamTheme(
                id: .lg,
                accent: Color(hex: 0xC3042F),
                accentSecondary: Color(hex: 0x161616),
                heroStart: Color(hex: 0x131313),
                heroEnd: Color(hex: 0x161616),
                chipBackground: Color(hex: 0x161616).opacity(0.12),
                badgeBackground: Color(hex: 0x1C1B1B),
                badgeForeground: Color(hex: 0xC3042F),
                scoreboardBackground: Color(hex: 0x2A2A2A),
                shadowTint: Color.black.opacity(0.18)
            )
        ),
        "lotte": TeamIdentity(
            id: "lotte",
            displayName: "롯데 자이언츠",
            shortLabel: "롯데",
            monogram: "LOT",
            homeHeroWatermarkLabel: "Giants",
            themeID: .lotte,
            theme: TeamTheme(
                id: .lotte,
                accent: Color(hex: 0x002F6C),
                accentSecondary: Color(hex: 0xE60033),
                heroStart: Color(hex: 0xE60033),
                heroEnd: Color(hex: 0x002F6C),
                chipBackground: Color(hex: 0x002F6C).opacity(0.12),
                badgeBackground: Color(hex: 0xF7F9FC),
                badgeForeground: Color(hex: 0xE60033),
                scoreboardBackground: Color.white,
                shadowTint: Color(hex: 0x002F6C).opacity(0.12)
            )
        ),
        "nc": TeamIdentity(
            id: "nc",
            displayName: "NC 다이노스",
            shortLabel: "NC",
            monogram: "NC",
            homeHeroWatermarkLabel: "Dinos",
            themeID: .nc,
            theme: TeamTheme(
                id: .nc,
                accent: Color(hex: 0x191970),
                accentSecondary: Color(hex: 0xC7A079),
                heroStart: Color(hex: 0x0F141B),
                heroEnd: Color(hex: 0x191970),
                chipBackground: Color(hex: 0x191970).opacity(0.16),
                badgeBackground: Color(hex: 0x1B2027),
                badgeForeground: Color(hex: 0xC7A079),
                scoreboardBackground: Color(hex: 0x30353D),
                shadowTint: Color(hex: 0x191970).opacity(0.20)
            )
        ),
        "samsung": TeamIdentity(
            id: "samsung",
            displayName: "삼성 라이온즈",
            shortLabel: "삼성",
            monogram: "SAM",
            homeHeroWatermarkLabel: "Lions",
            themeID: .samsung,
            theme: TeamTheme(
                id: .samsung,
                accent: Color(hex: 0x0047AB),
                accentSecondary: Color(hex: 0xFDFCF8),
                heroStart: Color(hex: 0xFDFCF8),
                heroEnd: Color(hex: 0x0047AB),
                chipBackground: Color(hex: 0x0047AB).opacity(0.12),
                badgeBackground: Color(hex: 0xECEEF3),
                badgeForeground: Color(hex: 0xFDFCF8),
                scoreboardBackground: Color.white,
                shadowTint: Color(hex: 0x0047AB).opacity(0.12)
            )
        ),
        "ssg": TeamIdentity(
            id: "ssg",
            displayName: "SSG 랜더스",
            shortLabel: "SSG",
            monogram: "SSG",
            homeHeroWatermarkLabel: "Landers",
            themeID: .ssg,
            theme: TeamTheme(
                id: .ssg,
                accent: Color(hex: 0xB80F0A),
                accentSecondary: Color(hex: 0xFDFCF8),
                heroStart: Color(hex: 0xFDFCF8),
                heroEnd: Color(hex: 0xB80F0A),
                chipBackground: Color(hex: 0xB80F0A).opacity(0.12),
                badgeBackground: Color(hex: 0xF3F3F3),
                badgeForeground: Color(hex: 0xFDFCF8),
                scoreboardBackground: Color.white,
                shadowTint: Color(hex: 0xB80F0A).opacity(0.12)
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
            homeHeroWatermarkLabel: shortName,
            themeID: .neutral,
            theme: .neutral
        )
    }
}

private extension Color {
    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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
