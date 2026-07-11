//
//  HomeHeroGamePresentation.swift
//  kboScore
//  기능 설명: 홈 메인 경기 카드의 시간, 장소, 점수, 접근성 문구를 구성합니다.
//  오늘 경기와 경기 없는 날의 대체 정보를 홈에서 바로 판단할 수 있도록 표시용 요약을 별도로 구성합니다.
//  월요일 직전 주 요약, 마이팀 경기 우선순위, 빈 일정 상태가 겹칠 수 있어 선택 순서를 명확히 유지합니다.
//  TODO : 홈 요약 정책이 바뀌면 날짜별 스냅샷 테스트를 추가합니다.
//
//  Created by Codex on 6/8/26.
//

import Foundation

// HomeHeroGamePresentation 열거형는 HomeHeroGamePresentation 타입의 역할과 값을 정의합니다.
enum HomeHeroGamePresentation {
    // timeText 메서드는 이 타입의 주요 동작을 수행합니다.
    static func timeText(for summary: GameSummary) -> String {
        switch summary.status {
        case .upcoming:
            summary.scheduledStart.formatted(date: .omitted, time: .shortened)
        case .live, .rainDelay:
            KBOInningFormatter.korean(summary.inningText) ?? summary.status.title
        case .final, .cancelled:
            summary.status.title
        }
    }

    // venueText 메서드는 이 타입의 주요 동작을 수행합니다.
    static func venueText(for summary: GameSummary) -> String {
        let venue = summary.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard venue.isEmpty == false else { return "장소 미정" }
        guard let city = stadiumCity(for: venue) else { return venue }
        return "\(venue) · \(city)"
    }

    // accessibilityLabel 메서드는 화면 표시와 디버그에 사용할 문구를 구성합니다.
    static func accessibilityLabel(for summary: GameSummary) -> String {
        "\(summary.awayTeam.displayName) 대 \(summary.homeTeam.displayName), 원정 선발 \(pitcherText(summary.awayStartingPitcherName)), 홈 선발 \(pitcherText(summary.homeStartingPitcherName)), \(timeText(for: summary)), \(venueText(for: summary))"
    }

    // countText 메서드는 이 타입의 주요 동작을 수행합니다.
    static func countText(for summary: GameSummary) -> String? {
        let parts = [
            KBOCountDisplay.balls(summary.balls).map { "B \($0)" },
            KBOCountDisplay.strikes(summary.strikes).map { "S \($0)" },
            KBOCountDisplay.outs(summary.outs).map { "O \($0)" }
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // basesText 메서드는 이 타입의 주요 동작을 수행합니다.
    static func basesText(for summary: GameSummary) -> String? {
        guard let bases = summary.bases else { return nil }
        let occupied = [
            bases.first ? "1루" : nil,
            bases.second ? "2루" : nil,
            bases.third ? "3루" : nil
        ].compactMap { $0 }
        return occupied.isEmpty ? "주자 없음" : occupied.joined(separator: " ")
    }

    // pitcherText 메서드는 이 타입의 주요 동작을 수행합니다.
    static func pitcherText(_ pitcherName: String?) -> String {
        let trimmed = pitcherName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "선발 미정" : trimmed
    }

    // stadiumCity 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func stadiumCity(for venue: String) -> String? {
        let normalized = venue.replacingOccurrences(of: " ", with: "")
        if normalized.contains("잠실") || normalized.contains("고척") { return "서울" }
        if normalized.contains("사직") { return "부산" }
        if normalized.contains("랜더스필드") || normalized.contains("문학") { return "인천" }
        if normalized.contains("위즈파크") || normalized.contains("수원") { return "수원" }
        if normalized.contains("한화생명") || normalized.contains("대전") { return "대전" }
        if normalized.contains("라이온즈파크") || normalized.contains("대구") { return "대구" }
        if normalized.contains("챔피언스필드") || normalized.contains("광주") { return "광주" }
        if normalized.contains("창원") { return "창원" }
        return nil
    }
}
