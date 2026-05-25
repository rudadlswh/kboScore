//
//  LiveKBOResponseCache.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

actor RepositoryResponseCache {
    private let diskCache: RepositoryDiskCache
    private var bootstrapEntry: RepositoryCacheEntry<KBOBootstrapData>?
    private var gamesEntry: RepositoryCacheEntry<[GameDetail]>?
    private var notificationsEntry: RepositoryCacheEntry<[NotificationItem]>?
    private var monthlyScheduleEntries: [KBOMonthScheduleKey: RepositoryCacheEntry<[GameDetail]>] = [:]
    private var teamRankEntries: [Int: RepositoryCacheEntry<[TeamRankRow]>] = [:]

    private var bootstrapTask: Task<KBOBootstrapData, Error>?
    private var gamesTask: Task<[GameDetail], Error>?
    private var notificationsTask: Task<[NotificationItem], Error>?
    private var monthlyScheduleTasks: [KBOMonthScheduleKey: Task<[GameDetail], Error>] = [:]

    init(configuration: RepositoryCacheConfiguration) {
        self.diskCache = RepositoryDiskCache(directoryURL: configuration.diskCacheDirectory)
    }

    func bootstrapValue(
        ttl: TimeInterval,
        fetch: @escaping @Sendable () async throws -> KBOBootstrapData
    ) async throws -> (value: KBOBootstrapData, cachedAt: Date, isCacheHit: Bool, isStale: Bool) {
        let now = Date()
        if let bootstrapEntry = await cachedBootstrapEntry(), now.timeIntervalSince(bootstrapEntry.timestamp) < ttl {
            return (bootstrapEntry.value, bootstrapEntry.timestamp, true, false)
        }

        if let bootstrapTask {
            let value = try await bootstrapTask.value
            let cachedAt = bootstrapEntry?.timestamp ?? .now
            return (value, cachedAt, false, false)
        }

        let task = Task {
            let value = try await fetch()
            await self.storeBootstrap(value, timestamp: .now)
            return value
        }
        bootstrapTask = task
        defer { bootstrapTask = nil }

        do {
            let value = try await task.value
            return (value, bootstrapEntry?.timestamp ?? .now, false, false)
        } catch {
            if let bootstrapEntry = await cachedBootstrapEntry() {
                return (bootstrapEntry.value, bootstrapEntry.timestamp, true, true)
            }
            throw error
        }
    }

    func gamesValue(
        ttl: TimeInterval,
        fetch: @escaping @Sendable () async throws -> [GameDetail]
    ) async throws -> (value: [GameDetail], cachedAt: Date, isCacheHit: Bool, isStale: Bool) {
        let now = Date()
        if let gamesEntry = await cachedGamesEntry(), now.timeIntervalSince(gamesEntry.timestamp) < ttl {
            return (gamesEntry.value, gamesEntry.timestamp, true, false)
        }

        if let gamesTask {
            let value = try await gamesTask.value
            let cachedAt = gamesEntry?.timestamp ?? .now
            return (value, cachedAt, false, false)
        }

        let task = Task {
            let value = try await fetch()
            await self.storeGames(value, timestamp: .now)
            return value
        }
        gamesTask = task
        defer { gamesTask = nil }

        do {
            let value = try await task.value
            return (value, gamesEntry?.timestamp ?? .now, false, false)
        } catch {
            if let gamesEntry = await cachedGamesEntry() {
                return (gamesEntry.value, gamesEntry.timestamp, true, true)
            }
            throw error
        }
    }

    func notificationsValue(
        ttl: TimeInterval,
        fetch: @escaping @Sendable () async throws -> [NotificationItem]
    ) async throws -> (value: [NotificationItem], cachedAt: Date, isCacheHit: Bool, isStale: Bool) {
        let now = Date()
        if let notificationsEntry = await cachedNotificationsEntry(), now.timeIntervalSince(notificationsEntry.timestamp) < ttl {
            return (notificationsEntry.value, notificationsEntry.timestamp, true, false)
        }

        if let notificationsTask {
            let value = try await notificationsTask.value
            let cachedAt = notificationsEntry?.timestamp ?? .now
            return (value, cachedAt, false, false)
        }

        let task = Task {
            let value = try await fetch()
            await self.storeNotifications(value, timestamp: .now)
            return value
        }
        notificationsTask = task
        defer { notificationsTask = nil }

        do {
            let value = try await task.value
            return (value, notificationsEntry?.timestamp ?? .now, false, false)
        } catch {
            if let notificationsEntry = await cachedNotificationsEntry() {
                return (notificationsEntry.value, notificationsEntry.timestamp, true, true)
            }
            throw error
        }
    }

    func monthlyScheduleValue(
        for month: KBOMonthScheduleKey,
        ttl: TimeInterval,
        fetch: @escaping @Sendable () async throws -> [GameDetail]
    ) async throws -> (value: [GameDetail], cachedAt: Date, isCacheHit: Bool, isStale: Bool) {
        let now = Date()
        if let entry = await cachedMonthlyScheduleEntry(for: month), now.timeIntervalSince(entry.timestamp) < ttl {
            return (entry.value, entry.timestamp, true, false)
        }

        if let task = monthlyScheduleTasks[month] {
            let value = try await task.value
            let cachedAt = monthlyScheduleEntries[month]?.timestamp ?? .now
            return (value, cachedAt, false, false)
        }

        let task = Task {
            let value = try await fetch()
            await self.storeMonthlySchedule(value, for: month, timestamp: .now)
            return value
        }
        monthlyScheduleTasks[month] = task
        defer { monthlyScheduleTasks[month] = nil }

        do {
            let value = try await task.value
            return (value, monthlyScheduleEntries[month]?.timestamp ?? .now, false, false)
        } catch {
            if let entry = await cachedMonthlyScheduleEntry(for: month) {
                return (entry.value, entry.timestamp, true, true)
            }
            throw error
        }
    }

    func refreshMonthlyScheduleValue(
        for month: KBOMonthScheduleKey,
        fetch: @escaping @Sendable () async throws -> [GameDetail]
    ) async throws -> (value: [GameDetail], cachedAt: Date, isCacheHit: Bool, isStale: Bool) {
        if let task = monthlyScheduleTasks[month] {
            let value = try await task.value
            let cachedAt = monthlyScheduleEntries[month]?.timestamp ?? .now
            return (value, cachedAt, false, false)
        }

        let task = Task {
            let value = try await fetch()
            await self.storeMonthlySchedule(value, for: month, timestamp: .now)
            return value
        }
        monthlyScheduleTasks[month] = task
        defer { monthlyScheduleTasks[month] = nil }

        do {
            let value = try await task.value
            return (value, .now, false, false)
        } catch {
            if let entry = await cachedMonthlyScheduleEntry(for: month) {
                return (entry.value, entry.timestamp, true, true)
            }
            throw error
        }
    }

    func upsertGames(_ incomingGames: [GameDetail]) async -> (inserted: Int, updated: Int, skippedExisting: Int) {
        guard incomingGames.isEmpty == false else {
            return (0, 0, 0)
        }

        let now = Date()
        let existingGames = (await cachedGamesEntry())?.value ?? []
        let result = Self.upsert(incomingGames: incomingGames, into: existingGames)
        await storeGames(result.games.sorted { $0.scheduledStart > $1.scheduledStart }, timestamp: now)

        if let bootstrapEntry = await cachedBootstrapEntry() {
            let bootstrapResult = Self.upsert(incomingGames: incomingGames, into: bootstrapEntry.value.games)
            let updatedBootstrap = KBOBootstrapData(
                teams: bootstrapEntry.value.teams,
                games: bootstrapResult.games.sorted { $0.scheduledStart > $1.scheduledStart },
                notifications: bootstrapEntry.value.notifications,
                settings: bootstrapEntry.value.settings
            )
            await storeBootstrap(updatedBootstrap, timestamp: now)
        }

        let affectedMonths = Set(incomingGames.map { KBOMonthScheduleKey(date: $0.scheduledStart) })
        for month in affectedMonths {
            if let monthlyEntry = await cachedMonthlyScheduleEntry(for: month) {
                let monthlyResult = Self.upsert(incomingGames: incomingGames, into: monthlyEntry.value)
                await storeMonthlySchedule(
                    monthlyResult.games.sorted { $0.scheduledStart < $1.scheduledStart },
                    for: month,
                    timestamp: now
                )
            }
        }

        return (result.inserted, result.updated, result.skippedExisting)
    }

    func localTeamRanks(season: Int) async -> [TeamRankRow] {
        let rows = await cachedTeamRankEntry(season: season)?.value ?? []
        return rows.sorted { $0.rank < $1.rank }
    }

    func replaceTeamRanks(_ ranks: [TeamRankRow], season: Int) async -> Int {
        let sorted = ranks.sorted { $0.rank < $1.rank }
        await storeTeamRanks(sorted, season: season, timestamp: .now)
        return sorted.count
    }

    private func cachedBootstrapEntry() async -> RepositoryCacheEntry<KBOBootstrapData>? {
        if let bootstrapEntry {
            return bootstrapEntry
        }

        let diskEntry = await diskCache.loadBootstrap()
        bootstrapEntry = diskEntry
        return diskEntry
    }

    private func cachedGamesEntry() async -> RepositoryCacheEntry<[GameDetail]>? {
        if let gamesEntry {
            return gamesEntry
        }

        let diskEntry = await diskCache.loadGames()
        gamesEntry = diskEntry
        return diskEntry
    }

    private func cachedNotificationsEntry() async -> RepositoryCacheEntry<[NotificationItem]>? {
        if let notificationsEntry {
            return notificationsEntry
        }

        let diskEntry = await diskCache.loadNotifications()
        notificationsEntry = diskEntry
        return diskEntry
    }

    private func cachedMonthlyScheduleEntry(for month: KBOMonthScheduleKey) async -> RepositoryCacheEntry<[GameDetail]>? {
        if let entry = monthlyScheduleEntries[month] {
            return entry
        }

        let diskEntry = await diskCache.loadMonthlySchedule(for: month)
        monthlyScheduleEntries[month] = diskEntry
        return diskEntry
    }

    private func cachedTeamRankEntry(season: Int) async -> RepositoryCacheEntry<[TeamRankRow]>? {
        if let entry = teamRankEntries[season] {
            return entry
        }

        let diskEntry = await diskCache.loadTeamRanks(season: season)
        teamRankEntries[season] = diskEntry
        return diskEntry
    }

    private func storeBootstrap(_ value: KBOBootstrapData, timestamp: Date) async {
        bootstrapEntry = RepositoryCacheEntry(value: value, timestamp: timestamp)
        await diskCache.storeBootstrap(value, timestamp: timestamp)
    }

    private func storeGames(_ value: [GameDetail], timestamp: Date) async {
        gamesEntry = RepositoryCacheEntry(value: value, timestamp: timestamp)
        await diskCache.storeGames(value, timestamp: timestamp)
    }

    private func storeNotifications(_ value: [NotificationItem], timestamp: Date) async {
        notificationsEntry = RepositoryCacheEntry(value: value, timestamp: timestamp)
        await diskCache.storeNotifications(value, timestamp: timestamp)
    }

    private func storeMonthlySchedule(_ value: [GameDetail], for month: KBOMonthScheduleKey, timestamp: Date) async {
        monthlyScheduleEntries[month] = RepositoryCacheEntry(value: value, timestamp: timestamp)
        await diskCache.storeMonthlySchedule(value, for: month, timestamp: timestamp)
    }

    private func storeTeamRanks(_ value: [TeamRankRow], season: Int, timestamp: Date) async {
        teamRankEntries[season] = RepositoryCacheEntry(value: value, timestamp: timestamp)
        await diskCache.storeTeamRanks(value, season: season, timestamp: timestamp)
    }

    private static func upsert(
        incomingGames: [GameDetail],
        into existingGames: [GameDetail]
    ) -> (games: [GameDetail], inserted: Int, updated: Int, skippedExisting: Int) {
        var updatedGames = existingGames
        var inserted = 0
        var updated = 0
        var skippedExisting = 0

        for candidate in incomingGames {
            let candidateAliases = candidate.gameIdentityAliases
            if let existingIndex = updatedGames.firstIndex(where: { existing in
                existing.gameIdentityAliases.isDisjoint(with: candidateAliases) == false
            }) {
                let merged = merge(existing: updatedGames[existingIndex], candidate: candidate)
                if merged != updatedGames[existingIndex] {
                    updatedGames[existingIndex] = merged
                    updated += 1
                } else {
                    skippedExisting += 1
                }
            } else {
                updatedGames.append(candidate)
                inserted += 1
            }
        }

        return (updatedGames, inserted, updated, skippedExisting)
    }

    private static func merge(existing: GameDetail, candidate: GameDetail) -> GameDetail {
        let stateSource = preferredStateSource(existing: existing, candidate: candidate)
        let supplementalSource = stateSource == candidate ? existing : candidate

        return GameDetail(
            id: existing.id,
            scheduledStart: stateSource.scheduledStart,
            venue: nonBlank(candidate.venue) ?? existing.venue,
            awayTeam: preferredTeam(candidate.awayTeam, fallback: existing.awayTeam),
            homeTeam: preferredTeam(candidate.homeTeam, fallback: existing.homeTeam),
            awayScore: stateSource.awayScore ?? supplementalSource.awayScore,
            homeScore: stateSource.homeScore ?? supplementalSource.homeScore,
            status: stateSource.status,
            seasonClassification: stateSource.seasonClassification == .unknown ? existing.seasonClassification : stateSource.seasonClassification,
            inningText: nonBlank(stateSource.inningText) ?? supplementalSource.inningText,
            bases: stateSource.bases,
            balls: stateSource.balls,
            strikes: stateSource.strikes,
            outs: stateSource.outs,
            highlightText: nonBlank(candidate.highlightText) ?? existing.highlightText,
            events: candidate.events.isEmpty ? existing.events : candidate.events,
            note: mergedNote(existing: existing.note, candidate: candidate.note),
            providerGameID: nonBlank(candidate.providerGameID) ?? existing.providerGameID,
            awayStartingPitcherName: nonBlank(candidate.awayStartingPitcherName) ?? existing.awayStartingPitcherName,
            homeStartingPitcherName: nonBlank(candidate.homeStartingPitcherName) ?? existing.homeStartingPitcherName,
            currentPitcherName: nonBlank(stateSource.currentPitcherName),
            currentBatterName: nonBlank(stateSource.currentBatterName)
        )
    }

    private static func preferredStateSource(existing: GameDetail, candidate: GameDetail) -> GameDetail {
        if shouldRecoverUnconfirmedFinal(existing: existing, candidate: candidate) {
            return candidate
        }
        let candidatePriority = statePriority(candidate)
        let existingPriority = statePriority(existing)
        if candidatePriority != existingPriority {
            return candidatePriority > existingPriority ? candidate : existing
        }
        let candidateFreshness = freshnessDate(candidate)
        let existingFreshness = freshnessDate(existing)
        if let candidateFreshness, let existingFreshness, candidateFreshness != existingFreshness {
            return candidateFreshness > existingFreshness ? candidate : existing
        }
        if candidateFreshness != nil, existingFreshness == nil {
            return candidate
        }
        if candidate.hasCompleteFinalScore != existing.hasCompleteFinalScore {
            return candidate.hasCompleteFinalScore ? candidate : existing
        }
        return candidate
    }

    private static func shouldRecoverUnconfirmedFinal(existing: GameDetail, candidate: GameDetail) -> Bool {
        guard existing.status == .final,
              hasConfirmedFinalStatus(existing) == false,
              isLiveLike(candidate) else {
            return false
        }
        let candidateFreshness = freshnessDate(candidate)
        let existingFreshness = freshnessDate(existing)
        if let candidateFreshness, let existingFreshness {
            return candidateFreshness >= existingFreshness
        }
        if candidateFreshness != nil, existingFreshness == nil {
            return true
        }
        return hasLiveProgress(candidate)
    }

    private static func hasConfirmedFinalStatus(_ game: GameDetail) -> Bool {
        game.status == .final && noteValue("final_confirmed_at", in: game.note) != nil
    }

    private static func isLiveLike(_ game: GameDetail) -> Bool {
        game.status.isLiveLike || hasLiveProgress(game)
    }

    private static func hasLiveProgress(_ game: GameDetail) -> Bool {
        nonBlank(game.currentPitcherName) != nil
            || nonBlank(game.currentBatterName) != nil
            || game.balls != nil
            || game.strikes != nil
            || game.outs != nil
    }

    private static func statePriority(_ game: GameDetail) -> Int {
        switch game.status {
        case .final, .cancelled:
            return 3
        case .live, .rainDelay:
            return 2
        case .upcoming:
            return 1
        }
    }

    private static func preferredTeam(_ candidate: Team, fallback: Team) -> Team {
        candidate.id.hasPrefix("unknown-") ? fallback : candidate
    }

    private static func mergedNote(existing: String?, candidate: String?) -> String? {
        let components = [candidate, existing]
            .compactMap(nonBlank)
        guard components.isEmpty == false else { return nil }

        var seen: Set<String> = []
        let merged = components
            .flatMap { $0.split(separator: " ").map(String.init) }
            .filter { seen.insert($0).inserted }
            .joined(separator: " ")
        return nonBlank(merged)
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func freshnessDate(_ game: GameDetail) -> Date? {
        let values = [
            noteValue("live_last_checked_at", in: game.note),
            noteValue("updated_at", in: game.note),
            noteValue("source_updated_at", in: game.note)
        ]
        return values.compactMap(KBODateParser.parseTimestamp).max()
    }

    private static func noteValue(_ key: String, in note: String?) -> String? {
        guard let note,
              let range = note.range(of: "\(key)=") else {
            return nil
        }
        let suffix = note[range.upperBound...]
        return suffix.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init)
    }
}
