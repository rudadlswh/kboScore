//
//  OfficialGameEntryBaseRunnerMapper.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

private struct BattingLineGroup {
    let label: String
    let lines: [GameCenterBattingLine]
}

extension OfficialGameEntry {
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

    private func battingLineGroupsForCurrentHalf(from battingSections: [GameCenterBattingSection]) -> [BattingLineGroup] {
        let normalizedHalf = inningHalfText?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedHalf?.contains("초") == true || normalizedHalf?.contains("top") == true {
            return [BattingLineGroup(label: "away", lines: battingSections[0].lines)]
        }
        if normalizedHalf?.contains("말") == true || normalizedHalf?.contains("bottom") == true || normalizedHalf?.contains("bot") == true {
            return [BattingLineGroup(label: "home", lines: battingSections[1].lines)]
        }

        return [
            BattingLineGroup(label: "away", lines: battingSections[0].lines),
            BattingLineGroup(label: "home", lines: battingSections[1].lines)
        ]
    }

    private func runnerName(order: Int?, in lineGroups: [BattingLineGroup], baseLabel: String) -> String? {
        guard let order, order > 0 else {
            return nil
        }

        let orderText = String(order)
        let matches = lineGroups.flatMap { group in
            group.lines
                .filter { $0.battingOrderNumber == orderText }
                .compactMap { line -> (String, String)? in
                    guard let name = line.name.nilIfBlank else { return nil }
                    return (group.label, name)
                }
        }

        guard matches.count <= 1 else {
            #if DEBUG
            print("[BaseRunners] source=official skipped=ambiguousBattingOrderMatch base=\(baseLabel) order=\(orderText) matches=\(matches.map { "\($0.0):\($0.1)" }.joined(separator: ","))")
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
