//
//  OfficialGameEntryBaseRunnerMapper.swift
//  kboScore
//  기능 설명: KBO 공식 경기 항목에서 주자 상태를 앱 모델로 변환합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

// BattingLineGroup 구조체는 BattingLineGroup 타입의 역할과 값을 정의합니다.
private struct BattingLineGroup {
    let label: String
    let lines: [GameCenterBattingLine]
}

// OfficialBaseRunnerOffenseSide 열거형는 OfficialBaseRunnerOffenseSide 타입의 역할과 값을 정의합니다.
enum OfficialBaseRunnerOffenseSide: Equatable, Sendable {
    case away
    case home
}

// OfficialBaseRunnerLineupResolver 열거형는 입력 상태를 해석해 필요한 결과 값을 결정합니다.
enum OfficialBaseRunnerLineupResolver {
    // normalizedBattingOrderNumber 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    static func normalizedBattingOrderNumber(_ value: String?) -> Int? {
        guard let value else { return nil }
        let digits = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0.isNumber }
        guard digits.isEmpty == false else { return nil }
        return Int(String(digits))
    }

    // offenseSide 메서드는 이 타입의 주요 동작을 수행합니다.
    static func offenseSide(inningHalfText: String?) -> OfficialBaseRunnerOffenseSide? {
        let normalizedHalf = inningHalfText?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedHalf?.contains("초") == true || normalizedHalf?.contains("top") == true {
            return .away
        }
        if normalizedHalf?.contains("말") == true || normalizedHalf?.contains("bottom") == true || normalizedHalf?.contains("bot") == true {
            return .home
        }
        return nil
    }

    // baseRunners 메서드는 이 타입의 주요 동작을 수행합니다.
    static func baseRunners(
        firstOrder: Int?,
        secondOrder: Int?,
        thirdOrder: Int?,
        inningHalfText: String?,
        battingSections: [GameCenterBattingSection]?
    ) -> GameCenterBaseRunners? {
        let occupiedOrders = [firstOrder, secondOrder, thirdOrder]
            .compactMap { $0 }
            .filter { $0 > 0 }
        guard occupiedOrders.isEmpty == false else {
            return nil
        }

        guard let battingSections, battingSections.count >= 2 else {
            return nil
        }

        let lineGroups = battingLineGroups(for: inningHalfText, battingSections: battingSections)
        guard lineGroups.isEmpty == false else {
            return nil
        }

        let first = runnerName(order: firstOrder, in: lineGroups)
        let second = runnerName(order: secondOrder, in: lineGroups)
        let third = runnerName(order: thirdOrder, in: lineGroups)
        guard first != nil || second != nil || third != nil else {
            return nil
        }

        return GameCenterBaseRunners(first: first, second: second, third: third)
    }

    // battingLineGroups 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func battingLineGroups(
        for inningHalfText: String?,
        battingSections: [GameCenterBattingSection]
    ) -> [BattingLineGroup] {
        switch offenseSide(inningHalfText: inningHalfText) {
        case .away:
            return [BattingLineGroup(label: "away", lines: battingSections[0].lines)]
        case .home:
            return [BattingLineGroup(label: "home", lines: battingSections[1].lines)]
        case nil:
            return [
                BattingLineGroup(label: "away", lines: battingSections[0].lines),
                BattingLineGroup(label: "home", lines: battingSections[1].lines)
            ]
        }
    }

    // runnerName 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func runnerName(order: Int?, in lineGroups: [BattingLineGroup]) -> String? {
        guard let order, order > 0 else {
            return nil
        }

        let matches = lineGroups.flatMap { group in
            group.lines
                .filter { normalizedBattingOrderNumber($0.battingOrder) == order }
                .compactMap { line -> (String, String)? in
                    guard let name = line.name.nilIfBlank else { return nil }
                    return (group.label, name)
                }
        }

        guard matches.count <= 1 else {
            return nil
        }

        return matches.first?.1
    }
}

extension OfficialGameEntry {
    // baseRunners 메서드는 이 타입의 주요 동작을 수행합니다.
    func baseRunners(from battingSections: [GameCenterBattingSection]?) -> GameCenterBaseRunners? {
        let occupiedOrders = [firstBaseOccupancy, secondBaseOccupancy, thirdBaseOccupancy]
            .compactMap { $0 }
            .filter { $0 > 0 }
        guard occupiedOrders.isEmpty == false else {
            #if DEBUG
            let reason = firstBaseOccupancy == nil && secondBaseOccupancy == nil && thirdBaseOccupancy == nil
                ? "missingBaseOrderFields"
                : "noOccupiedBases"
            print("[BaseRunners] source=official skipped=\(reason) baseOrderKeys=\(baseOrderSourceKeys.joined(separator: ","))")
            #endif
            return nil
        }

        guard let battingSections, battingSections.count >= 2 else {
            #if DEBUG
            print("[BaseRunners] source=official skipped=missingBattingSections count=\(battingSections?.count ?? 0) baseOrderKeys=\(baseOrderSourceKeys.joined(separator: ","))")
            #endif
            return nil
        }

        let lineGroups = battingLineGroupsForCurrentHalf(from: battingSections)
        guard lineGroups.isEmpty == false else {
            #if DEBUG
            print("[BaseRunners] source=official skipped=missingBattingSections reason=unknownInningHalf inningHalf=\(inningHalfText ?? "<nil>")")
            #endif
            return nil
        }

        let first = runnerName(order: firstBaseOccupancy, in: lineGroups, baseLabel: "1B")
        let second = runnerName(order: secondBaseOccupancy, in: lineGroups, baseLabel: "2B")
        let third = runnerName(order: thirdBaseOccupancy, in: lineGroups, baseLabel: "3B")

        #if DEBUG
        let reason = first == nil && second == nil && third == nil ? "battingSectionsFoundButNoMatchingOrder " : ""
        print("[BaseRunners] source=official \(reason)mapped first=\(first ?? "<nil>") second=\(second ?? "<nil>") third=\(third ?? "<nil>") baseOrderKeys=\(baseOrderSourceKeys.joined(separator: ","))")
        #endif

        guard first != nil || second != nil || third != nil else {
            return nil
        }

        return GameCenterBaseRunners(first: first, second: second, third: third)
    }

    // battingLineGroupsForCurrentHalf 메서드는 이 타입의 주요 동작을 수행합니다.
    private func battingLineGroupsForCurrentHalf(from battingSections: [GameCenterBattingSection]) -> [BattingLineGroup] {
        if OfficialBaseRunnerLineupResolver.offenseSide(inningHalfText: inningHalfText) == .away {
            return [BattingLineGroup(label: "away", lines: battingSections[0].lines)]
        }
        if OfficialBaseRunnerLineupResolver.offenseSide(inningHalfText: inningHalfText) == .home {
            return [BattingLineGroup(label: "home", lines: battingSections[1].lines)]
        }

        return [
            BattingLineGroup(label: "away", lines: battingSections[0].lines),
            BattingLineGroup(label: "home", lines: battingSections[1].lines)
        ]
    }

    // runnerName 메서드는 이 타입의 주요 동작을 수행합니다.
    private func runnerName(order: Int?, in lineGroups: [BattingLineGroup], baseLabel: String) -> String? {
        guard let order, order > 0 else {
            return nil
        }

        let matches = lineGroups.flatMap { group in
            group.lines
                .filter { OfficialBaseRunnerLineupResolver.normalizedBattingOrderNumber($0.battingOrder) == order }
                .compactMap { line -> (String, String)? in
                    guard let name = line.name.nilIfBlank else { return nil }
                    return (group.label, name)
                }
        }

        guard matches.count <= 1 else {
            #if DEBUG
            print("[BaseRunners] source=official skipped=ambiguousBattingOrderMatch base=\(baseLabel) order=\(order) matches=\(matches.map { "\($0.0):\($0.1)" }.joined(separator: ","))")
            #endif
            return nil
        }

        return matches.first?.1
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
