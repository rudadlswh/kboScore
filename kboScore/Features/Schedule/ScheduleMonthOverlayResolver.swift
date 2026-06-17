//
//  ScheduleMonthOverlayResolver.swift
//  kboScore
//  기능 설명: 월간 일정 화면 위에 표시할 로딩/오류/빈 상태 오버레이를 결정합니다.
//  월별·일별 일정 상태를 일관되게 계산해 홈, 일정, 위젯이 같은 경기 선택 기준을 공유합니다.
//  우천 취소, 더블헤더, 시간 미정, 오래된 캐시가 섞일 수 있어 날짜 키와 동기화 순서를 엄격히 다룹니다.
//  TODO : 공식 일정 변경 감지와 보정 로직을 더 작은 단위로 검증합니다.
//
//  Created by Codex on 6/8/26.
//

import Foundation

// ScheduleMonthOverlayResolver 열거형는 입력 상태를 해석해 필요한 결과 값을 결정합니다.
enum ScheduleMonthOverlayResolver {
    // merge 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    static func merge(
        existingMonthGames: [GameDetail],
        incomingGames: [GameDetail],
        monthKey: KBOMonthScheduleKey,
        calendar: Calendar
    ) -> [GameDetail] {
        let monthIncomingGames = incomingGames.filter {
            isGame($0, in: monthKey, calendar: calendar)
        }
        guard existingMonthGames.isEmpty == false else {
            return monthIncomingGames.sorted { $0.scheduledStart < $1.scheduledStart }
        }

        var mergedGames = existingMonthGames.filter {
            isGame($0, in: monthKey, calendar: calendar)
        }

        for incomingGame in monthIncomingGames {
            let incomingAliases = incomingGame.gameIdentityAliases
            if let index = mergedGames.firstIndex(where: { existingGame in
                existingGame.gameIdentityAliases.isDisjoint(with: incomingAliases) == false
            }) {
                mergedGames[index] = incomingGame
            } else {
                mergedGames.append(incomingGame)
            }
        }

        return mergedGames.sorted { $0.scheduledStart < $1.scheduledStart }
    }

    // isGame 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private static func isGame(
        _ game: GameDetail,
        in monthKey: KBOMonthScheduleKey,
        calendar: Calendar
    ) -> Bool {
        let components = calendar.dateComponents([.year, .month], from: game.scheduledStart)
        return components.year == monthKey.year && components.month == monthKey.month
    }
}
