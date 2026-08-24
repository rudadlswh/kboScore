//
//  AttendanceClient.swift
//  kboScore
//  기능 설명: 직관 기록을 백엔드 attendance API와 동기화합니다.
//
//  Created by Codex on 7/6/26.
//

import Foundation

protocol AttendanceClient: Sendable {
    nonisolated func fetchAttendedGameIDs(installationID: UUID) async throws -> Set<UUID>
    nonisolated func fetchAttendanceRecords(installationID: UUID) async throws -> AttendanceRecords
    nonisolated func setAttendance(
        _ isAttended: Bool,
        installationID: UUID,
        gameID: UUID,
        publicGameID: String?,
        providerGameID: String?
    ) async throws
}

extension AttendanceClient {
    nonisolated func fetchAttendanceRecords(installationID: UUID) async throws -> AttendanceRecords {
        AttendanceRecords(gameIDs: try await fetchAttendedGameIDs(installationID: installationID), games: [])
    }
}

nonisolated struct AttendanceRecords: Sendable {
    let gameIDs: Set<UUID>
    let games: [GameDetail]
}

enum AttendanceClientFactory {
    nonisolated(unsafe) private static var didLogMissingBaseURL = false

    static func makeAppClient() -> any AttendanceClient {
        let attendanceEnvironmentValue = ProcessInfo.processInfo.environment["KBO_ATTENDANCE_BACKEND_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let attendanceBundleValue = (Bundle.main.object(forInfoDictionaryKey: "KBOAttendanceBackendBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let backendEnvironmentValue = ProcessInfo.processInfo.environment["KBO_BACKEND_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let backendBundleValue = (Bundle.main.object(forInfoDictionaryKey: "KBOBackendBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notificationEnvironmentValue = ProcessInfo.processInfo.environment["KBO_NOTIFICATION_REGISTRATION_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notificationBundleValue = (Bundle.main.object(forInfoDictionaryKey: "NotificationRegistrationURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let resolved = resolveBaseURL(
            attendanceEnvironmentValue: attendanceEnvironmentValue,
            attendanceBundleValue: attendanceBundleValue,
            backendEnvironmentValue: backendEnvironmentValue,
            backendBundleValue: backendBundleValue,
            notificationEnvironmentValue: notificationEnvironmentValue,
            notificationBundleValue: notificationBundleValue
        ) else {
            #if DEBUG
            if didLogMissingBaseURL == false {
                didLogMissingBaseURL = true
                print("[Attendance] config error=missingBackendBaseURL disabled=true")
            }
            #endif
            return NoOpAttendanceClient()
        }
        print("[Attendance] config build=\(AppBuildConfiguration.current) baseURL=\(resolved.url.absoluteString) disabled=false")
        return BackendAttendanceClient(baseURL: resolved.url)
    }

    nonisolated static func resolveBaseURL(
        attendanceEnvironmentValue: String?,
        attendanceBundleValue: String?,
        backendEnvironmentValue: String?,
        backendBundleValue: String?,
        notificationEnvironmentValue: String?,
        notificationBundleValue: String?,
        buildConfiguration: String = AppBuildConfiguration.current
    ) -> (source: String, url: URL)? {
        let isDebug = buildConfiguration == "Debug"
        let directCandidates: [(source: String, value: String?)]
        if isDebug {
            directCandidates = [
                ("attendanceEnvironment", attendanceEnvironmentValue),
                ("attendancePlist", attendanceBundleValue),
                ("backendPlist", backendBundleValue),
                ("backendEnvironment", backendEnvironmentValue)
            ]
        } else {
            directCandidates = [
                ("attendancePlist", attendanceBundleValue),
                ("backendPlist", backendBundleValue),
                ("attendanceEnvironment", attendanceEnvironmentValue),
                ("backendEnvironment", backendEnvironmentValue)
            ]
        }

        for candidate in directCandidates {
            if let resolved = resolveDirectCandidate(candidate, buildConfiguration: buildConfiguration) {
                if isDebug,
                   candidate.source.hasPrefix("backend"),
                   isProductionBackend(resolved.url) {
                    continue
                }
                return resolved
            }
        }

        if isDebug == false {
            let notificationCandidates: [(source: String, value: String?)] = [
                ("notificationEnvironment", notificationEnvironmentValue),
                ("notificationPlist", notificationBundleValue)
            ]
            for candidate in notificationCandidates {
                if let resolved = resolveNotificationCandidate(candidate, buildConfiguration: buildConfiguration) {
                    return resolved
                }
            }
        }

        #if targetEnvironment(simulator)
        let debugFallback = isDebug ? "http://localhost:8088" : nil
        #else
        let debugFallback: String? = nil
        #endif
        return resolveDirectCandidate(
            (source: "developmentFallback", value: debugFallback),
            buildConfiguration: buildConfiguration
        )
    }

    private nonisolated static func resolveDirectCandidate(
        _ candidate: (source: String, value: String?),
        buildConfiguration: String
    ) -> (source: String, url: URL)? {
        guard let rawValue = candidate.value,
              rawValue.isEmpty == false,
              rawValue.hasPrefix("$(") == false,
              let url = URL(string: rawValue),
              isAllowed(url, buildConfiguration: buildConfiguration) else {
            return nil
        }
        return (candidate.source, url)
    }

    private nonisolated static func resolveNotificationCandidate(
        _ candidate: (source: String, value: String?),
        buildConfiguration: String
    ) -> (source: String, url: URL)? {
        guard let rawValue = candidate.value,
              rawValue.isEmpty == false,
              rawValue.hasPrefix("$(") == false,
              let endpointURL = URL(string: rawValue),
              let baseURL = baseURL(fromNotificationEndpoint: endpointURL),
              isAllowed(baseURL, buildConfiguration: buildConfiguration) else {
            return nil
        }
        return (candidate.source, baseURL)
    }

    private nonisolated static func baseURL(fromNotificationEndpoint endpointURL: URL) -> URL? {
        guard let scheme = endpointURL.scheme,
              let host = endpointURL.host else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = endpointURL.port
        components.path = "/"
        return components.url
    }

    private nonisolated static func isAllowed(_ url: URL, buildConfiguration: String) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              url.host?.isEmpty == false else {
            return false
        }
        if buildConfiguration == "Debug" {
            return scheme == "http" || scheme == "https"
        }
        return scheme == "https"
    }

    private nonisolated static func isProductionBackend(_ url: URL) -> Bool {
        url.host?.lowercased() == "kboscore-back.onrender.com"
    }
}

struct NoOpAttendanceClient: AttendanceClient {
    nonisolated init() {}

    nonisolated func fetchAttendedGameIDs(installationID _: UUID) async throws -> Set<UUID> {
        throw AttendanceClientError.unconfigured
    }

    nonisolated func setAttendance(
        _: Bool,
        installationID _: UUID,
        gameID _: UUID,
        publicGameID _: String?,
        providerGameID _: String?
    ) async throws {
        throw AttendanceClientError.unconfigured
    }
}

struct BackendAttendanceClient: AttendanceClient {
    private let baseURL: URL
    private let session: URLSession

    nonisolated init(baseURL: URL, session: URLSession = .shared) {
        if baseURL.absoluteString.hasSuffix("/") {
            self.baseURL = baseURL
        } else {
            self.baseURL = URL(string: baseURL.absoluteString + "/") ?? baseURL
        }
        self.session = session
    }

    nonisolated func fetchAttendedGameIDs(installationID: UUID) async throws -> Set<UUID> {
        try await fetchAttendanceRecords(installationID: installationID).gameIDs
    }

    nonisolated func fetchAttendanceRecords(installationID: UUID) async throws -> AttendanceRecords {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("api/v1/attendance"), resolvingAgainstBaseURL: false) else {
            throw AttendanceClientError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "installationId", value: installationID.uuidString.lowercased())
        ]
        guard let url = components.url else {
            throw AttendanceClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        #if DEBUG
        print("[Attendance] list start endpoint=\(logEndpoint(for: url, installationID: installationID))")
        #endif
        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = try statusCode(from: response)
            try validate(statusCode)
            let decoded = try JSONDecoder().decode(AttendanceListResponse.self, from: data)
            let records = decoded.records.compactMap(\.game)
            #if DEBUG
            print("[Attendance] list response status=\(statusCode) count=\(decoded.gameIds.count) recordCount=\(records.count)")
            #endif
            return AttendanceRecords(gameIDs: Set(decoded.gameIds), games: records)
        } catch {
            #if DEBUG
            print("[Attendance] sync failed action=list gameID=none error=\(error)")
            #endif
            throw error
        }
    }

    nonisolated func setAttendance(
        _ isAttended: Bool,
        installationID: UUID,
        gameID: UUID,
        publicGameID: String?,
        providerGameID: String?
    ) async throws {
        let url = baseURL.appendingPathComponent("api/v1/attendance")
        var request = URLRequest(url: url)
        request.httpMethod = isAttended ? "POST" : "DELETE"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AttendanceRequest(
            installationId: installationID,
            gameId: gameID
        ))

        let action = isAttended ? "mark" : "unmark"
        #if DEBUG
        print("[Attendance] \(action) start dbGameID=\(gameID.uuidString) publicGameID=\(publicGameID ?? "none") providerGameID=\(providerGameID ?? "none") endpoint=\(url.absoluteString)")
        #endif
        do {
            let (_, response) = try await session.data(for: request)
            let statusCode = try statusCode(from: response)
            #if DEBUG
            print("[Attendance] \(action) response status=\(statusCode)")
            #endif
            try validate(statusCode)
        } catch {
            #if DEBUG
            print("[Attendance] sync failed action=\(action) dbGameID=\(gameID.uuidString) publicGameID=\(publicGameID ?? "none") providerGameID=\(providerGameID ?? "none") error=\(error)")
            #endif
            throw error
        }
    }

    private nonisolated func statusCode(from response: URLResponse) throws -> Int {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AttendanceClientError.invalidResponse
        }
        return httpResponse.statusCode
    }

    private nonisolated func validate(_ statusCode: Int) throws {
        guard (200..<300).contains(statusCode) else {
            throw AttendanceClientError.httpStatus(statusCode)
        }
    }

    private nonisolated func logEndpoint(for url: URL, installationID: UUID) -> String {
        let prefix = String(installationID.uuidString.prefix(8))
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.queryItems = [
            URLQueryItem(name: "installationIdPrefix", value: prefix)
        ]
        return components.url?.absoluteString ?? url.absoluteString
    }
}

enum AttendanceClientError: Error, Sendable {
    case unconfigured
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
}

nonisolated private struct AttendanceRequest: Encodable, Sendable {
    let installationId: UUID
    let gameId: UUID
}

nonisolated private struct AttendanceListResponse: Decodable, Sendable {
    let gameIds: [UUID]
    let records: [AttendanceGameDTO]

    private enum CodingKeys: String, CodingKey {
        case gameIds
        case records
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameIds = try container.decode([UUID].self, forKey: .gameIds)
        records = try container.decodeIfPresent([AttendanceGameDTO].self, forKey: .records) ?? []
    }
}

nonisolated private struct AttendanceGameDTO: Decodable, Sendable {
    let gameId: UUID
    let publicGameId: String?
    let gameDate: String?
    let scheduledAt: String?
    let stadium: String?
    let status: String?
    let isCancelled: Bool
    let isPostponed: Bool
    let awayTeam: AttendanceTeamDTO
    let homeTeam: AttendanceTeamDTO
    let awayScore: Int?
    let homeScore: Int?

    var game: GameDetail? {
        guard let scheduledStart = KBODateParser.parseTimestamp(scheduledAt) ?? KBODateParser.parseGameDate(gameDate) else {
            return nil
        }
        let mappedStatus: GameStatus = isCancelled || isPostponed
            ? .cancelled
            : KBODataMapper.mapGameStatus(code: status, text: nil)
        let publicGameNote = publicGameId.map { " public_game_id=\($0)" } ?? ""
        let venue = stadium?.trimmingCharacters(in: .whitespacesAndNewlines)
        return GameDetail(
            id: gameId,
            scheduledStart: scheduledStart,
            venue: (venue?.isEmpty == false ? venue : nil) ?? "장소 미정",
            awayTeam: awayTeam.team,
            homeTeam: homeTeam.team,
            awayScore: mappedStatus == .upcoming ? nil : awayScore,
            homeScore: mappedStatus == .upcoming ? nil : homeScore,
            status: mappedStatus,
            seasonClassification: .unknown,
            inningText: nil,
            bases: nil,
            balls: nil,
            strikes: nil,
            outs: nil,
            highlightText: nil,
            events: [],
            note: "supabase_game_id=\(gameId.uuidString)\(publicGameNote)",
            providerGameID: nil,
            awayStartingPitcherName: nil,
            homeStartingPitcherName: nil
        )
    }
}

nonisolated private struct AttendanceTeamDTO: Decodable, Sendable {
    let id: String
    let name: String
    let shortName: String

    var team: Team {
        Team(
            id: Team.canonicalID(for: id) ?? id.lowercased(),
            name: name,
            shortName: shortName,
            englishName: id.uppercased(),
            markText: shortName
        )
    }
}
