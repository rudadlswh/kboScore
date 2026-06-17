//
//  LiveKBORequestContracts.swift
//  kboScore
//  기능 설명: 실시간 KBO API 요청과 응답에 사용하는 공통 계약 모델을 정의합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

// OfficialKBOMonthlyScheduleRequestContract 구조체는 OfficialKBOMonthlyScheduleRequestContract 타입의 역할과 값을 정의합니다.
struct OfficialKBOMonthlyScheduleRequestContract: Sendable {
    let month: KBOMonthScheduleKey
    let url: URL?

    let contentType = "application/x-www-form-urlencoded; charset=UTF-8"
    let accept = "application/json"
    let requestedWith = "XMLHttpRequest"

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(baseURL: URL, month: KBOMonthScheduleKey) throws {
        self.month = month
        self.url = URL(string: "ws/Schedule.asmx/GetScheduleList", relativeTo: baseURL)?.absoluteURL
        if url == nil {
            throw LiveRepositoryError.invalidBaseURL
        }
    }

    nonisolated var seriesIDList: String {
        month.month == 3 ? "0,9" : "0"
    }

    nonisolated var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "leId", value: "1"),
            URLQueryItem(name: "srIdList", value: seriesIDList),
            URLQueryItem(name: "seasonId", value: String(month.year)),
            URLQueryItem(name: "gameMonth", value: String(format: "%02d", month.month)),
            URLQueryItem(name: "teamId", value: "")
        ]
    }

    nonisolated var bodyString: String {
        var components = URLComponents()
        components.queryItems = queryItems
        return components.percentEncodedQuery ?? ""
    }

    nonisolated var bodyData: Data {
        Data(bodyString.utf8)
    }
}

// OfficialKBOLiveGamesRequestContract 구조체는 OfficialKBOLiveGamesRequestContract 타입의 역할과 값을 정의합니다.
struct OfficialKBOLiveGamesRequestContract: Sendable {
    let date: Date
    let url: URL?

    let contentType = "application/x-www-form-urlencoded; charset=UTF-8"
    let accept = "application/json"
    let requestedWith = "XMLHttpRequest"

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(baseURL: URL, date: Date) throws {
        self.date = date
        self.url = URL(string: "ws/Main.asmx/GetKboGameList", relativeTo: baseURL)?.absoluteURL
        if url == nil {
            throw LiveRepositoryError.invalidBaseURL
        }
    }

    nonisolated var seriesIDList: String {
        if kboDate >= "20241026" {
            return "0,1,3,4,5,6,7,8,9"
        }
        if kboDate.prefix(4) >= "2021" {
            return "0,1,3,4,5,6,7,9"
        }
        return "0,1,3,4,5,7,9"
    }

    nonisolated var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "leId", value: "1"),
            URLQueryItem(name: "srId", value: seriesIDList),
            URLQueryItem(name: "date", value: kboDate)
        ]
    }

    nonisolated var bodyString: String {
        var components = URLComponents()
        components.queryItems = queryItems
        return components.percentEncodedQuery ?? ""
    }

    nonisolated var bodyData: Data {
        Data(bodyString.utf8)
    }

    nonisolated private var kboDate: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }
}
