//
//  OfficialGameEntryMapper.swift
//  kboScore
//  기능 설명: KBO 공식 경기 목록 항목을 앱 경기 모델로 변환합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
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
