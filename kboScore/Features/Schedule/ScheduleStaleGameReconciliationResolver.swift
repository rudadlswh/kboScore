//
//  ScheduleStaleGameReconciliationResolver.swift
//  kboScore
//  기능 설명: 오래된 일정 데이터에서 백엔드 보정이 필요한 경기를 판별합니다.
//  월별·일별 일정 상태를 일관되게 계산해 홈, 일정, 위젯이 같은 경기 선택 기준을 공유합니다.
//  우천 취소, 더블헤더, 시간 미정, 오래된 캐시가 섞일 수 있어 날짜 키와 동기화 순서를 엄격히 다룹니다.
//  TODO : 공식 일정 변경 감지와 보정 로직을 더 작은 단위로 검증합니다.
//
//  Created by Codex on 5/22/26.
//

import Foundation

// ScheduleStaleGameReconciliationResolver 구조체는 입력 상태를 해석해 필요한 결과 값을 결정합니다.
struct ScheduleStaleGameReconciliationResolver: Sendable {
    // staleGameDates 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated static func staleGameDates(
        in games: [GameDetail],
        today: Date,
        calendar: Calendar
    ) -> [String] {
        let dates = Set(
            games.compactMap { game -> String? in
                guard isStalePastGame(game, today: today, calendar: calendar) else {
                    return nil
                }
                return dayKey(for: game.scheduledStart, calendar: calendar)
            }
        )
        return dates.sorted(by: >)
    }

    // isStalePastGame 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    nonisolated static func isStalePastGame(
        _ game: GameDetail,
        today: Date,
        calendar: Calendar
    ) -> Bool {
        let gameDate = calendar.startOfDay(for: game.scheduledStart)
        let todayDate = calendar.startOfDay(for: today)
        guard gameDate < todayDate else {
            return false
        }

        switch game.status {
        case .upcoming:
            return true
        case .live, .rainDelay:
            return true
        case .final, .cancelled:
            return false
        }
    }

    // dayKey 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }
}
