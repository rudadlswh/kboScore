//
//  ScheduleRefreshCoordinator.swift
//  kboScore
//
//  Created by Codex on 6/10/26.
//

import Foundation

@MainActor
final class ScheduleRefreshCoordinator {
    private var cachedMonths: [KBOMonthScheduleKey: ScheduleMonthCacheEntry] = [:]
    private var failedMonths: Set<KBOMonthScheduleKey> = []
    private var inFlightMonthTasks: [String: Task<ScheduleMonthCacheEntry, Error>] = [:]
    private var inFlightDateKeys: Set<String> = []
    private var inFlightReconciliationKeys: Set<String> = []

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }

    var cachedMonthEntries: [String: ScheduleMonthCacheEntry] {
        Dictionary(uniqueKeysWithValues: cachedMonths.map { ($0.key.yearMonthText, $0.value) })
    }

    var failedMonthKeys: Set<String> {
        Set(failedMonths.map(\.yearMonthText))
    }

    func hasCachedMonth(_ key: KBOMonthScheduleKey) -> Bool {
        cachedMonths[key] != nil
    }

    func firstGameDate(in key: KBOMonthScheduleKey) -> Date? {
        cachedMonths[key]?.games.first?.scheduledStart
    }

    func loadMonth(
        _ key: KBOMonthScheduleKey,
        forceRefresh: Bool,
        appModel: AppModel,
        callSite: String,
        reason: String
    ) async {
        let startedAt = Date()
        if forceRefresh == false, cachedMonths[key] != nil {
            logLocalMonth(
                key,
                callSite: callSite,
                reason: reason,
                cacheHit: true,
                durationMs: Self.durationMilliseconds(since: startedAt)
            )
            return
        }

        let monthKey = key.yearMonthText
        logMonthCache(
            key,
            callSite: callSite,
            reason: reason,
            cacheHit: false,
            forceRefresh: forceRefresh
        )
        if let task = inFlightMonthTasks[monthKey] {
            log(
                callSite: callSite,
                reason: reason,
                month: monthKey,
                skippedDueToInFlight: true
            )
            do {
                cachedMonths[key] = try await task.value
                failedMonths.remove(key)
            } catch {
                failedMonths.insert(key)
            }
            return
        }

        log(callSite: callSite, reason: reason, month: monthKey)
        let task = Task<ScheduleMonthCacheEntry, Error> { @MainActor in
            let fetched = try await appModel.fetchScheduleTabMonth(
                for: key,
                bypassingCache: forceRefresh,
                callSite: callSite,
                reason: reason
            )
            return await ScheduleMonthCacheEntry.build(key: key, games: fetched)
        }
        inFlightMonthTasks[monthKey] = task
        defer { inFlightMonthTasks[monthKey] = nil }

        do {
            let entry = try await task.value
            cachedMonths[key] = entry
            failedMonths.remove(key)
            #if DEBUG
            print("[ScheduleCache] callSite=\(callSite) reason=\(reason) month=\(monthKey) source=repository gameCount=\(entry.games.count) scheduleMonthLoad skippedGlobalMerge=true durationMs=\(Self.durationMilliseconds(since: startedAt))")
            #endif
        } catch {
            failedMonths.insert(key)
            #if DEBUG
            print("[ScheduleCache] callSite=\(callSite) reason=\(reason) month=\(monthKey) source=repository failed durationMs=\(Self.durationMilliseconds(since: startedAt)) error=\(error)")
            #endif
        }
    }

    func refreshTodayLiveIfNeeded(
        selectedDate: Date,
        displayedMonthKey: KBOMonthScheduleKey,
        appModel: AppModel,
        callSite: String
    ) async {
        let selectedDayKey = ScheduleDateKeyFormatter.dayKey(for: selectedDate)
        let todayKey = ScheduleDateKeyFormatter.dayKey(for: appModel.currentScheduleRefreshDate())
        guard selectedDayKey == todayKey else { return }

        let dateKey = "\(selectedDayKey):todayLiveRefresh"
        guard inFlightDateKeys.contains(dateKey) == false else {
            log(
                callSite: callSite,
                reason: "todayLiveRefresh",
                month: displayedMonthKey.yearMonthText,
                date: selectedDayKey,
                skippedDueToInFlight: true
            )
            return
        }

        inFlightDateKeys.insert(dateKey)
        defer { inFlightDateKeys.remove(dateKey) }

        let refreshedGames = await appModel.refreshTodayScheduleGamesForScheduleCache(
            selectedDate: selectedDate,
            reason: "scheduleTodayLiveRefresh"
        )
        await syncStartersIntoMonthCache(
            refreshedGames,
            monthKey: displayedMonthKey,
            callSite: callSite,
            reason: "todayLiveRefresh"
        )
        log(
            callSite: callSite,
            reason: "todayLiveRefresh",
            month: displayedMonthKey.yearMonthText,
            date: selectedDayKey,
            localOnlyDateSelection: true
        )
    }

    private func syncStartersIntoMonthCache(
        _ refreshedGames: [GameDetail],
        monthKey: KBOMonthScheduleKey,
        callSite: String,
        reason: String
    ) async {
        guard refreshedGames.isEmpty == false else {
            logStarterSync(
                callSite: callSite,
                reason: reason,
                monthKey: monthKey,
                updated: false,
                refreshedCount: 0
            )
            return
        }
        guard let existingEntry = cachedMonths[monthKey] else {
            logStarterSync(
                callSite: callSite,
                reason: reason,
                monthKey: monthKey,
                updated: false,
                refreshedCount: refreshedGames.count
            )
            return
        }

        var updatedGames = existingEntry.games
        var didUpdate = false

        for refreshedGame in refreshedGames {
            let aliases = refreshedGame.gameIdentityAliases
            guard let index = updatedGames.firstIndex(where: { cachedGame in
                cachedGame.gameIdentityAliases.isDisjoint(with: aliases) == false
            }) else {
                continue
            }
            let existingGame = updatedGames[index]
            let mergedGame = GameMergeResolver.preferredGame(existing: existingGame, candidate: refreshedGame)
            if mergedGame != existingGame {
                updatedGames[index] = mergedGame
                didUpdate = true
            }
        }

        if didUpdate {
            cachedMonths[monthKey] = await ScheduleMonthCacheEntry.build(key: monthKey, games: updatedGames)
        }
        logStarterSync(
            callSite: callSite,
            reason: reason,
            monthKey: monthKey,
            updated: didUpdate,
            refreshedCount: refreshedGames.count
        )
    }

    func reconcileStalePastGamesIfNeeded(
        displayedMonthKey: KBOMonthScheduleKey,
        appModel: AppModel,
        callSite: String
    ) async {
        let visibleGames = cachedMonths[displayedMonthKey]?.games ?? []
        let dates = ScheduleStaleGameReconciliationResolver.staleGameDates(
            in: visibleGames,
            today: appModel.currentScheduleRefreshDate(),
            calendar: calendar
        )

        guard dates.isEmpty == false else {
            log(callSite: callSite, reason: "staleReconciliation", month: displayedMonthKey.yearMonthText, skippedReason: "noCandidates")
            return
        }

        let selectedDates = Array(dates.prefix(3))
        let reconciliationKey = "\(displayedMonthKey.yearMonthText):\(selectedDates.joined(separator: ","))"
        guard inFlightReconciliationKeys.contains(reconciliationKey) == false else {
            log(
                callSite: callSite,
                reason: "staleReconciliation",
                month: displayedMonthKey.yearMonthText,
                date: selectedDates.joined(separator: ","),
                skippedDueToInFlight: true
            )
            return
        }

        inFlightReconciliationKeys.insert(reconciliationKey)
        defer { inFlightReconciliationKeys.remove(reconciliationKey) }

        #if DEBUG
        let droppedOlderDateCount = dates.count - selectedDates.count
        print("[ScheduleRefresh] callSite=\(callSite) reason=staleReconciliation month=\(displayedMonthKey.yearMonthText) totalStaleDateCount=\(dates.count) selectedDateCount=\(selectedDates.count) droppedOlderDateCount=\(droppedOlderDateCount) selectedDates=\(selectedDates.joined(separator: ","))")
        #endif

        do {
            let reconciledDates = try await appModel.reconcileStaleScheduleGameDates(selectedDates)
            guard reconciledDates.isEmpty == false else { return }
            #if DEBUG
            print("[ScheduleRefresh] callSite=\(callSite) reason=staleReconciliation month=\(displayedMonthKey.yearMonthText) success dates=\(reconciledDates.joined(separator: ","))")
            #endif
            await loadMonth(
                displayedMonthKey,
                forceRefresh: true,
                appModel: appModel,
                callSite: callSite,
                reason: "postReconciliationMonthRefresh"
            )
        } catch {
            #if DEBUG
            print("[ScheduleRefresh] callSite=\(callSite) reason=staleReconciliation month=\(displayedMonthKey.yearMonthText) failure dates=\(selectedDates.joined(separator: ",")) error=\(error)")
            #endif
        }
    }

    func logDateSelectionLocalOnly(
        date: Date,
        selectedGame: GameDetail?,
        callSite: String
    ) {
        let startedAt = Date()
        log(
            callSite: callSite,
            reason: "dateSelection",
            date: ScheduleDateKeyFormatter.dayKey(for: date),
            selectedGame: selectedGame,
            localOnlyDateSelection: true,
            durationMs: Self.durationMilliseconds(since: startedAt)
        )
    }

    private func logLocalMonth(
        _ key: KBOMonthScheduleKey,
        callSite: String,
        reason: String,
        cacheHit: Bool,
        durationMs: Int
    ) {
        #if DEBUG
        print("[ScheduleMonthCache] callSite=\(callSite) reason=\(reason) month=\(key.yearMonthText) hit=\(cacheHit) source=local durationMs=\(durationMs)")
        #endif
    }

    private func logMonthCache(
        _ key: KBOMonthScheduleKey,
        callSite: String,
        reason: String,
        cacheHit: Bool,
        forceRefresh: Bool
    ) {
        #if DEBUG
        print("[ScheduleMonthCache] callSite=\(callSite) reason=\(reason) month=\(key.yearMonthText) hit=\(cacheHit) forceRefresh=\(forceRefresh)")
        #endif
    }

    private func log(
        callSite: String,
        reason: String,
        month: String? = nil,
        date: String? = nil,
        selectedGame: GameDetail? = nil,
        skippedDueToInFlight: Bool = false,
        localOnlyDateSelection: Bool = false,
        skippedReason: String? = nil,
        durationMs: Int? = nil
    ) {
        #if DEBUG
        let monthText = month.map { " month=\($0)" } ?? ""
        let dateText = date.map { " date=\($0)" } ?? ""
        let publicGameID = selectedGame?.publicGameID ?? "<nil>"
        let providerGameID = selectedGame?.providerGameID ?? selectedGame?.officialProviderGameID ?? "<nil>"
        let skippedText = skippedDueToInFlight ? " skippedDueToInFlight=true" : ""
        let localOnlyText = localOnlyDateSelection ? " skippedBecauseDateSelectionIsLocalOnly=true" : ""
        let skippedReasonText = skippedReason.map { " skippedReason=\($0)" } ?? ""
        let durationText = durationMs.map { " durationMs=\($0)" } ?? ""
        print("[ScheduleRefreshCoordinator] callSite=\(callSite) reason=\(reason)\(monthText)\(dateText) selectedPublicGameID=\(publicGameID) selectedProviderGameID=\(providerGameID)\(skippedText)\(localOnlyText)\(skippedReasonText)\(durationText)")
        #endif
    }

    private func logStarterSync(
        callSite: String,
        reason: String,
        monthKey: KBOMonthScheduleKey,
        updated: Bool,
        refreshedCount: Int
    ) {
        #if DEBUG
        print("[ScheduleMonthCache] starterSync callSite=\(callSite) reason=\(reason) month=\(monthKey.yearMonthText) updated=\(updated) refreshedCount=\(refreshedCount)")
        #endif
    }

    private static func durationMilliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1_000)
    }
}
