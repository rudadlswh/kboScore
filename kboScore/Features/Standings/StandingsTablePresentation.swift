//
//  StandingsTablePresentation.swift
//  kboScore
//  기능 설명: 순위표 셀의 문구, 색상, 접근성 표현을 구성합니다.
//  KBO 순위 산정 규칙과 홈 화면 대체 요약에 필요한 계산을 화면 코드에서 분리합니다.
//  완료되지 않은 경기, 취소 경기, 동률, 원정/홈 득실 계산이 순위에 잘못 반영되지 않도록 제한합니다.
//  TODO : 실제 KBO 동률 규정 변경이나 포스트시즌 확률 로직 개선 시 계산 기준을 갱신합니다.
//
//  Created by Codex on 6/8/26.
//

import CoreGraphics
import Foundation

// StandingsTableMetrics 구조체는 StandingsTableMetrics 타입의 역할과 값을 정의합니다.
struct StandingsTableMetrics {
    let width: CGFloat
    let isCompact: Bool
    let isNarrow: Bool

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(width: CGFloat) {
        self.width = width
        isCompact = width < 370
        isNarrow = width < 350
    }

    var rowHeight: CGFloat { isCompact ? 48 : 52 }
    var horizontalPadding: CGFloat { isNarrow ? 4 : (isCompact ? 5 : 6) }
    var spacing: CGFloat { isNarrow ? 2 : (isCompact ? 3 : 4) }
    var rankMovementWidth: CGFloat { isNarrow ? 36 : (isCompact ? 40 : 42) }
    var rankWidth: CGFloat { isNarrow ? 18 : (isCompact ? 19 : 20) }
    var movementWidth: CGFloat { isNarrow ? 18 : (isCompact ? 19 : 20) }
    var logoSize: CGFloat { isNarrow ? 18 : (isCompact ? 20 : 22) }
    var gamesWidth: CGFloat { isNarrow ? 21 : (isCompact ? 22 : 24) }
    var countWidth: CGFloat { isNarrow ? 17 : (isCompact ? 18 : 19) }
    var percentageWidth: CGFloat { isNarrow ? 35 : (isCompact ? 37 : 39) }
    var gamesBehindWidth: CGFloat { isNarrow ? 29 : (isCompact ? 31 : 33) }
    var streakWidth: CGFloat { isNarrow ? 56 : 58 }
    var accentWidth: CGFloat { isCompact ? 78 : 120 }

    var teamColumnWidth: CGFloat {
        let maximumTeamWidth: CGFloat = isNarrow ? 64 : (isCompact ? 72 : 82)
        let minimumTeamWidth: CGFloat = isNarrow ? 50 : (isCompact ? 58 : 64)
        let remainingWidth = width - nonTeamColumnsWidth
        return min(max(remainingWidth, minimumTeamWidth), maximumTeamWidth)
    }

    private var nonTeamColumnsWidth: CGFloat {
        rankMovementWidth +
            gamesWidth +
            countWidth * 3 +
            percentageWidth +
            gamesBehindWidth +
            streakWidth +
            spacing * 8 +
            horizontalPadding * 2
    }
}

extension TeamIdentity {
    var standingsDisplayName: String {
        switch id {
        case "lg":
            "LG"
        case "kt":
            "KT"
        case "ssg":
            "SSG"
        case "samsung":
            "삼성"
        case "kia":
            "KIA"
        case "hanwha":
            "한화"
        case "nc":
            "NC"
        case "doosan":
            "두산"
        case "lotte":
            "롯데"
        case "kiwoom":
            "키움"
        default:
            shortLabel
        }
    }
}

extension TeamStandingsSnapshot {
    var broadcastWinPercentageText: String {
        if winPercentageText.hasPrefix("0.") {
            return String(winPercentageText.dropFirst())
        }
        return winPercentageText
    }

    // gamesBehindText 메서드는 이 타입의 주요 동작을 수행합니다.
    func gamesBehindText(leader: TeamStandingsSnapshot?) -> String {
        if let precomputedGamesBehind {
            guard precomputedGamesBehind > 0 else { return "-" }
            if precomputedGamesBehind.rounded(.towardZero) == precomputedGamesBehind {
                return String(format: "%.0f", precomputedGamesBehind)
            }
            return String(format: "%.1f", precomputedGamesBehind)
        }
        guard let leader else { return "-" }
        guard rank != leader.rank else { return "-" }

        let gamesBehind = Double((leader.wins - wins) + (losses - leader.losses)) / 2
        guard gamesBehind > 0 else { return "-" }

        if gamesBehind.rounded(.towardZero) == gamesBehind {
            return String(format: "%.0f", gamesBehind)
        }
        return String(format: "%.1f", gamesBehind)
    }
}
