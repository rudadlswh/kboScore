//
//  ScheduleDateKeyFormatter.swift
//  kboScore
//  기능 설명: 일정 데이터 그룹핑에 사용할 날짜 키를 KST 기준으로 생성합니다.
//  월별·일별 일정 상태를 일관되게 계산해 홈, 일정, 위젯이 같은 경기 선택 기준을 공유합니다.
//  우천 취소, 더블헤더, 시간 미정, 오래된 캐시가 섞일 수 있어 날짜 키와 동기화 순서를 엄격히 다룹니다.
//  TODO : 공식 일정 변경 감지와 보정 로직을 더 작은 단위로 검증합니다.
//
//  Created by Codex on 6/8/26.
//

import Foundation

// ScheduleDateKeyFormatter 열거형는 도메인 값을 화면 표시용 문자열로 변환합니다.
nonisolated enum ScheduleDateKeyFormatter {
    // dayKey 메서드는 이 타입의 주요 동작을 수행합니다.
    static func dayKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }
}
