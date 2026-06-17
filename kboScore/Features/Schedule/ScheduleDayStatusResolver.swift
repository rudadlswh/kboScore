//
//  ScheduleDayStatusResolver.swift
//  kboScore
//  기능 설명: 일정 캘린더의 날짜별 경기 상태와 표시 배지를 결정합니다.
//  월별·일별 일정 상태를 일관되게 계산해 홈, 일정, 위젯이 같은 경기 선택 기준을 공유합니다.
//  우천 취소, 더블헤더, 시간 미정, 오래된 캐시가 섞일 수 있어 날짜 키와 동기화 순서를 엄격히 다룹니다.
//  TODO : 공식 일정 변경 감지와 보정 로직을 더 작은 단위로 검증합니다.
//
//  Created by Codex on 5/18/26.
//

import Foundation

// ScheduleDayStatusResolver 열거형는 입력 상태를 해석해 필요한 결과 값을 결정합니다.
nonisolated enum ScheduleDayStatusResolver {
    // dominantStatus 메서드는 이 타입의 주요 동작을 수행합니다.
    static func dominantStatus(for games: [GameDetail]) -> GameStatus? {
        if games.contains(where: { $0.status == .live }) {
            return .live
        }
        if games.contains(where: { $0.status == .rainDelay }) {
            return .rainDelay
        }
        if games.contains(where: { $0.status == .upcoming }) {
            return .upcoming
        }
        if games.contains(where: { $0.status == .final }) {
            return .final
        }
        if games.contains(where: { $0.status == .cancelled }) {
            return .cancelled
        }
        return nil
    }
}
