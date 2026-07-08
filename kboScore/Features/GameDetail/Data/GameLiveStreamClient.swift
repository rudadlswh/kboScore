//
//  GameLiveStreamClient.swift
//  kboScore
//

import Foundation

protocol GameLiveStreaming: Sendable {
    nonisolated var cacheIdentity: String { get }
    nonisolated func streamGame(gameId: String) -> AsyncThrowingStream<GameLiveStreamEvent, Error>
}

nonisolated enum GameLiveStreamEvent: Equatable, Sendable {
    case snapshot(GameLiveStateResponse)
    case statusChanged(GameLiveStateResponse)
    case heartbeat
}

nonisolated struct ServerSentEvent: Equatable, Sendable {
    var event: String?
    var data: String?
    var id: String?
}

nonisolated struct ServerSentEventParser: Sendable {
    private var eventName: String?
    private var dataLines: [String] = []
    private var eventID: String?

    mutating func parse(line: String) -> [ServerSentEvent] {
        let normalizedLine = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        guard normalizedLine.isEmpty == false else {
            return flush().map { [$0] } ?? []
        }
        guard normalizedLine.hasPrefix(":") == false else {
            return []
        }

        let parts = normalizedLine.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts.first ?? "")
        var value = parts.count > 1 ? String(parts[1]) : ""
        if value.hasPrefix(" ") {
            value.removeFirst()
        }

        var events: [ServerSentEvent] = []
        if field == "event", hasPendingMessage, let pending = flush() {
            events.append(pending)
        }

        switch field {
        case "event":
            eventName = value
            if value == "heartbeat", let heartbeat = flush() {
                events.append(heartbeat)
            }
        case "data":
            dataLines.append(value)
            if isCompleteJSONDataMessage, let event = flush() {
                events.append(event)
            }
        case "id":
            eventID = value
        default:
            break
        }
        return events
    }

    mutating func flush() -> ServerSentEvent? {
        guard eventName != nil || dataLines.isEmpty == false || eventID != nil else {
            return nil
        }
        defer {
            eventName = nil
            dataLines.removeAll()
            eventID = nil
        }
        return ServerSentEvent(
            event: eventName,
            data: dataLines.joined(separator: "\n"),
            id: eventID
        )
    }

    private var hasPendingMessage: Bool {
        eventName != nil || dataLines.isEmpty == false || eventID != nil
    }

    private var isCompleteJSONDataMessage: Bool {
        guard eventName == "snapshot" || eventName == "status_changed" else { return false }
        let data = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return data.hasPrefix("{") && data.hasSuffix("}")
    }
}

private actor GameLiveStreamSnapshotWatchdog {
    private let timeout: TimeInterval
    private var lastHeartbeatAt: Date?
    private var lastSnapshotAt: Date?
    private var lastLogAt: Date?

    init(timeout: TimeInterval, now: Date = Date()) {
        self.timeout = timeout
        self.lastSnapshotAt = now
    }

    func record(eventName: String?) {
        switch eventName {
        case "heartbeat":
            lastHeartbeatAt = Date()
        case "snapshot", "status_changed":
            lastSnapshotAt = Date()
        default:
            break
        }
    }

    func fallbackOnlyLogMessage(now: Date = Date()) -> String? {
        guard let lastSnapshotAt,
              now.timeIntervalSince(lastSnapshotAt) >= timeout,
              lastLogAt.map({ now.timeIntervalSince($0) >= timeout }) ?? true else {
            return nil
        }
        lastLogAt = now
        let formatter = ISO8601DateFormatter()
        let heartbeatText = lastHeartbeatAt.map(formatter.string(from:)) ?? "<nil>"
        let snapshotText = formatter.string(from: lastSnapshotAt)
        return "snapshot watchdog fallbackOnly seconds=\(Int(timeout)) lastHeartbeatAt=\(heartbeatText) lastSnapshotAt=\(snapshotText)"
    }
}

nonisolated enum GameLiveStreamClientFactory {
    static func makeAppClient() -> any GameLiveStreaming {
        let processValue = ProcessInfo.processInfo.environment["KBO_BACKEND_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleValue = (Bundle.main.object(forInfoDictionaryKey: "KBOBackendBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        #if DEBUG
        #if targetEnvironment(simulator)
        let candidates: [(source: String, value: String?)] = [
            ("default", "http://localhost:8088"),
            ("environment", processValue),
            ("plist", bundleValue)
        ]
        #else
        let candidates: [(source: String, value: String?)] = [
            ("environment", processValue),
            ("plist", bundleValue)
        ]
        #endif
        #else
        let candidates: [(source: String, value: String?)] = [
            ("environment", processValue),
            ("plist", bundleValue)
        ]
        #endif

        guard let resolved = candidates.compactMap(resolveCandidate).first else {
            #if DEBUG
            print("[GameLiveStreamClient] backendBaseURL source=none resolved=<none> client=noop")
            #endif
            return NoOpGameLiveStreamClient()
        }
        #if DEBUG
        print("[GameLiveStreamClient] backendBaseURL source=\(resolved.source) resolved=\(resolved.url.absoluteString)")
        #endif
        return BackendGameLiveStreamClient(baseURL: resolved.url)
    }

    private static func resolveCandidate(_ candidate: (source: String, value: String?)) -> (source: String, url: URL)? {
        guard let rawValue = candidate.value,
              rawValue.isEmpty == false,
              rawValue.hasPrefix("$(") == false,
              let url = URL(string: rawValue),
              isAllowed(url) else {
            #if DEBUG
            if let value = candidate.value, value.isEmpty == false, value.hasPrefix("$(") == false {
                print("[GameLiveStreamClient] backendBaseURL rejected source=\(candidate.source) value=\(value)")
            }
            #endif
            return nil
        }
        return (candidate.source, url)
    }

    private static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              url.host?.isEmpty == false else {
            return false
        }
        #if DEBUG
        #if os(iOS) && !targetEnvironment(simulator)
        if isLocalhost(url) {
            return false
        }
        #endif
        return scheme == "http" || scheme == "https"
        #else
        return scheme == "https"
        #endif
    }

    private static func isLocalhost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

struct NoOpGameLiveStreamClient: GameLiveStreaming {
    nonisolated init() {}
    nonisolated var cacheIdentity: String { "noop" }
    nonisolated func streamGame(gameId _: String) -> AsyncThrowingStream<GameLiveStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: GameBoxscoreClientError.invalidURL)
        }
    }
}

struct BackendGameLiveStreamClient: GameLiveStreaming {
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

    nonisolated var cacheIdentity: String { baseURL.absoluteString }

    nonisolated func streamGame(gameId: String) -> AsyncThrowingStream<GameLiveStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let encodedGameId = gameId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                          let url = URL(string: "api/v1/games/\(encodedGameId)/stream", relativeTo: baseURL)?.absoluteURL else {
                        Self.log("invalid request URL gameId=\(gameId)")
                        throw GameBoxscoreClientError.invalidURL
                    }

                    Self.log("request URL=\(url.absoluteString)")
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                    request.timeoutInterval = 30.0
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        Self.log("invalid HTTP response URL=\(url.absoluteString)")
                        throw GameBoxscoreClientError.invalidResponse
                    }
                    Self.log("HTTP status=\(httpResponse.statusCode) URL=\(url.absoluteString)")
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw GameBoxscoreClientError.httpStatus(httpResponse.statusCode)
                    }
                    Self.log("stream connected status=\(httpResponse.statusCode) URL=\(url.absoluteString)")

                    let watchdog = GameLiveStreamSnapshotWatchdog(timeout: 60)
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            var parser = ServerSentEventParser()
                            for try await line in bytes.lines {
                                try Task.checkCancellation()
                                for rawEvent in parser.parse(line: line) {
                                    await watchdog.record(eventName: rawEvent.event)
                                    if let event = try Self.decode(rawEvent) {
                                        continuation.yield(event)
                                    }
                                }
                            }
                            if let rawEvent = parser.flush() {
                                await watchdog.record(eventName: rawEvent.event)
                                if let event = try Self.decode(rawEvent) {
                                    continuation.yield(event)
                                }
                            }
                        }
                        group.addTask {
                            while Task.isCancelled == false {
                                try await Task.sleep(nanoseconds: 60_000_000_000)
                                if let message = await watchdog.fallbackOnlyLogMessage() {
                                    Self.log("\(message) gameId=\(gameId)")
                                }
                            }
                        }

                        try await group.next()
                        group.cancelAll()
                    }
                    continuation.finish()
                } catch is CancellationError {
                    Self.log("stream cancelled gameId=\(gameId)")
                    continuation.finish(throwing: CancellationError())
                } catch {
                    Self.log("stream failed gameId=\(gameId) error=\(error)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                Self.log("stream termination requested gameId=\(gameId)")
                task.cancel()
            }
        }
    }

    private static func decode(_ rawEvent: ServerSentEvent) throws -> GameLiveStreamEvent? {
        let eventName = rawEvent.event?.trimmingCharacters(in: .whitespacesAndNewlines)
        log("sse event received event=\(eventName ?? "<nil>")")
        switch eventName {
        case "snapshot":
            guard let data = rawEvent.data?.data(using: .utf8) else { return nil }
            log("snapshot raw data byte count=\(data.count)")
            do {
                let response = try JSONDecoder().decode(GameLiveStateResponse.self, from: data)
                log("snapshot decoded publicGameId=\(response.publicGameId) rawHash=\(response.rawHash)")
                return .snapshot(response)
            } catch {
                log("snapshot decode failure bytes=\(data.count) error=\(error)")
                throw error
            }
        case "status_changed":
            guard let data = rawEvent.data?.data(using: .utf8) else { return nil }
            log("snapshot raw data byte count=\(data.count)")
            do {
                let response = try JSONDecoder().decode(GameLiveStateResponse.self, from: data)
                log("snapshot decoded publicGameId=\(response.publicGameId) rawHash=\(response.rawHash)")
                return .statusChanged(response)
            } catch {
                log("snapshot decode failure bytes=\(data.count) error=\(error)")
                throw error
            }
        case "heartbeat":
            log("heartbeat received")
            return .heartbeat
        default:
            return nil
        }
    }

    private static func log(_ message: String) {
        AppLog.info(.gameDetail, "[GameLiveStreamClient] \(message)")
        #if DEBUG
        print("[GameLiveStreamClient] \(message)")
        #endif
    }
}
