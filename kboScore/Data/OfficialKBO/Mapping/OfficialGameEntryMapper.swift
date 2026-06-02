//
//  OfficialGameEntryMapper.swift
//  kboScore
//
//  Created by Codex on 5/13/26.
//

extension OfficialGameEntry {
    var status: GameStatus {
        switch gameStateCode {
        case "1":
            return GameStatus.upcoming
        case "2":
            return GameStatus.live
        case "3":
            return GameStatus.final
        case "5":
            return GameStatus.rainDelay
        default:
            if cancelName?.contains("취소") == true {
                return GameStatus.cancelled
            }
            if cancelName?.contains("우천") == true || cancelName?.contains("중단") == true {
                return GameStatus.rainDelay
            }
            return GameStatus.upcoming
        }
    }

    var inningText: String? {
        switch status {
        case .upcoming:
            return nil
        case .final:
            return "종료"
        case .cancelled:
            return "취소"
        case .rainDelay:
            if let inningNumber, let inningHalfText {
                return "\(inningNumber)회\(inningHalfText)"
            }
            return status.title
        case .live:
            guard let inningNumber, let inningHalfText else { return status.title }
            return "\(inningNumber)회\(inningHalfText)"
        }
    }

    var awayScore: Int? {
        Int(awayScoreText ?? "")
    }

    var homeScore: Int? {
        Int(homeScoreText ?? "")
    }

    var balls: Int? {
        ballCount
    }

    var strikes: Int? {
        strikeCount
    }

    var outs: Int? {
        outCount
    }

    var bases: RunnerState? {
        guard firstBaseOccupancy != nil || secondBaseOccupancy != nil || thirdBaseOccupancy != nil else {
            return nil
        }

        return RunnerState(
            first: (firstBaseOccupancy ?? 0) > 0,
            second: (secondBaseOccupancy ?? 0) > 0,
            third: (thirdBaseOccupancy ?? 0) > 0
        )
    }
}
