//
//  HomeHeroGamePresentation.swift
//  kboScore
//
//  Created by Codex on 6/8/26.
//

import Foundation

enum HomeHeroGamePresentation {
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

    static func venueText(for summary: GameSummary) -> String {
        let venue = summary.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard venue.isEmpty == false else { return "장소 미정" }
        guard let city = stadiumCity(for: venue) else { return venue }
        return "\(venue) · \(city)"
    }

    static func accessibilityLabel(for summary: GameSummary) -> String {
        "\(summary.awayTeam.displayName) 대 \(summary.homeTeam.displayName), 원정 선발 \(pitcherText(summary.awayStartingPitcherName)), 홈 선발 \(pitcherText(summary.homeStartingPitcherName)), \(timeText(for: summary)), \(venueText(for: summary))"
    }

    static func countText(for summary: GameSummary) -> String? {
        let parts = [
            KBOCountDisplay.balls(summary.balls).map { "B \($0)" },
            KBOCountDisplay.strikes(summary.strikes).map { "S \($0)" },
            KBOCountDisplay.outs(summary.outs).map { "O \($0)" }
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static func basesText(for summary: GameSummary) -> String? {
        guard let bases = summary.bases else { return nil }
        let occupied = [
            bases.first ? "1루" : nil,
            bases.second ? "2루" : nil,
            bases.third ? "3루" : nil
        ].compactMap { $0 }
        return occupied.isEmpty ? "주자 없음" : occupied.joined(separator: " ")
    }

    static func pitcherText(_ pitcherName: String?) -> String {
        let trimmed = pitcherName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "선발 미정" : trimmed
    }

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
