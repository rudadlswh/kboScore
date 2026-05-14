//
//  LiveKBORequestContracts.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

struct OfficialKBOMonthlyScheduleRequestContract: Sendable {
    let month: KBOMonthScheduleKey
    let url: URL?

    let contentType = "application/x-www-form-urlencoded; charset=UTF-8"
    let accept = "application/json"
    let requestedWith = "XMLHttpRequest"

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

struct OfficialKBOLiveGamesRequestContract: Sendable {
    let date: Date
    let url: URL?

    let contentType = "application/x-www-form-urlencoded; charset=UTF-8"
    let accept = "application/json"
    let requestedWith = "XMLHttpRequest"

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
