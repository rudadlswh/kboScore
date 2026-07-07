//
//  ScheduleRefreshCoordinator.swift
//  kboScore
//  기능 설명: 일정 탭의 월별 새로고침 요청과 캐시 정책을 조정합니다.
//  월별·일별 일정 상태를 일관되게 계산해 홈, 일정, 위젯이 같은 경기 선택 기준을 공유합니다.
//  우천 취소, 더블헤더, 시간 미정, 오래된 캐시가 섞일 수 있어 날짜 키와 동기화 순서를 엄격히 다룹니다.
//  TODO : 공식 일정 변경 감지와 보정 로직을 더 작은 단위로 검증합니다.
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

    // hasCachedMonth 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    func hasCachedMonth(_ key: KBOMonthScheduleKey) -> Bool {
        cachedMonths[key] != nil
    }

    // firstGameDate 메서드는 이 타입의 주요 동작을 수행합니다.
    func firstGameDate(in key: KBOMonthScheduleKey) -> Date? {
        cachedMonths[key]?.games.first?.scheduledStart
    }

    // loadMonth 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func loadMonth(
        _ key: KBOMonthScheduleKey,
        forceRefresh: Bool,
        appModel: AppModel,
        callSite: String,
        reason: String
    ) async {
        let startedAt = Date()
        AppLog.info(.schedule, "[Schedule] refresh start month=\(key.yearMonthText) callSite=\(callSite) reason=\(reason) forceRefresh=\(forceRefresh)")
        if forceRefresh == false, let cachedEntry = cachedMonths[key] {
            logLocalMonth(
                key,
                callSite: callSite,
                reason: reason,
                cacheHit: true,
                durationMs: Self.durationMilliseconds(since: startedAt)
            )
            appModel.mergeScheduleTabMonthGamesForAttendance(
                cachedEntry.games,
                monthKey: key,
                reason: "scheduleTabMonthCacheHit"
            )
            await appModel.updateFavoriteTeamScheduleWidgetSnapshot(
                fromScheduleTabMonthGames: cachedEntry.games,
                monthKey: key,
                reason: "scheduleTabMonth"
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
                let entry = try await task.value
                cachedMonths[key] = entry
                failedMonths.remove(key)
                appModel.mergeScheduleTabMonthGamesForAttendance(
                    entry.games,
                    monthKey: key,
                    reason: "scheduleTabMonthInFlight"
                )
                await appModel.updateFavoriteTeamScheduleWidgetSnapshot(
                    fromScheduleTabMonthGames: entry.games,
                    monthKey: key,
                    reason: "scheduleTabMonth"
                )
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
            appModel.mergeScheduleTabMonthGamesForAttendance(
                entry.games,
                monthKey: key,
                reason: "scheduleTabMonthLoad"
            )
            await appModel.updateFavoriteTeamScheduleWidgetSnapshot(
                fromScheduleTabMonthGames: entry.games,
                monthKey: key,
                reason: "scheduleTabMonth"
            )
            #if DEBUG
            print("[ScheduleCache] callSite=\(callSite) reason=\(reason) month=\(monthKey) source=repository gameCount=\(entry.games.count) scheduleMonthLoad skippedGlobalMerge=true durationMs=\(Self.durationMilliseconds(since: startedAt))")
            #endif
            AppLog.info(.schedule, "[Schedule] refresh completed month=\(monthKey) source=supabase games=\(entry.games.count) \(statusCountsText(entry.games)) durationMs=\(Self.durationMilliseconds(since: startedAt))")
        } catch {
            failedMonths.insert(key)
            #if DEBUG
            print("[ScheduleCache] callSite=\(callSite) reason=\(reason) month=\(monthKey) source=repository failed durationMs=\(Self.durationMilliseconds(since: startedAt)) error=\(error)")
            #endif
            AppLog.warning(.schedule, "[Schedule] refresh failed month=\(monthKey) source=supabase durationMs=\(Self.durationMilliseconds(since: startedAt)) error=\(error)")
        }
    }

    // refreshTodayLiveIfNeeded 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
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
        AppLog.info(.schedule, "[Schedule] refresh today completed date=\(selectedDayKey) source=supabase games=\(refreshedGames.count) \(statusCountsText(refreshedGames))")
        await syncStartersIntoMonthCache(
            refreshedGames,
            monthKey: displayedMonthKey,
            appModel: appModel,
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

    // syncStartersIntoMonthCache 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    private func syncStartersIntoMonthCache(
        _ refreshedGames: [GameDetail],
        monthKey: KBOMonthScheduleKey,
        appModel: AppModel,
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
        var mergedCount = 0
        var unmatchedGameIDs: [String] = []

        for refreshedGame in refreshedGames {
            let aliases = refreshedGame.gameIdentityAliases
            guard let index = updatedGames.firstIndex(where: { cachedGame in
                cachedGame.gameIdentityAliases.isDisjoint(with: aliases) == false
            }) else {
                unmatchedGameIDs.append(refreshedGame.publicGameID ?? refreshedGame.providerGameID ?? refreshedGame.id.uuidString)
                continue
            }
            let existingGame = updatedGames[index]
            let mergedGame = GameMergeResolver.preferredGame(existing: existingGame, candidate: refreshedGame)
            if mergedGame != existingGame {
                updatedGames[index] = mergedGame
                didUpdate = true
            }
            mergedCount += 1
        }

        if didUpdate {
            let updatedEntry = await ScheduleMonthCacheEntry.build(key: monthKey, games: updatedGames)
            cachedMonths[monthKey] = updatedEntry
            await appModel.updateFavoriteTeamScheduleWidgetSnapshot(
                fromScheduleTabMonthGames: updatedEntry.games,
                monthKey: monthKey,
                reason: "scheduleTabMonth"
            )
        }
        logStarterSync(
            callSite: callSite,
            reason: reason,
            monthKey: monthKey,
            updated: didUpdate,
            refreshedCount: refreshedGames.count
        )
        #if DEBUG
        print("[ScheduleLiveOverlay] callSite=\(callSite) reason=\(reason) month=\(monthKey.yearMonthText) snapshotCount=\(refreshedGames.count) mergedCount=\(mergedCount) unmatchedGameIds=\(unmatchedGameIDs.joined(separator: ","))")
        #endif
        AppLog.info(.schedule, "[Schedule] merge completed month=\(monthKey.yearMonthText) source=supabase refreshed=\(refreshedGames.count) merged=\(mergedCount) updated=\(didUpdate) unmatched=\(unmatchedGameIDs.count) \(statusCountsText(updatedGames))")
    }

    // reconcileStalePastGamesIfNeeded 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // logDateSelectionLocalOnly 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // logLocalMonth 메서드는 이 타입의 주요 동작을 수행합니다.
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
        AppLog.info(.schedule, "[Schedule] refresh completed month=\(key.yearMonthText) source=local cacheHit=\(cacheHit) games=\(cachedMonths[key]?.games.count ?? 0) durationMs=\(durationMs)")
    }

    // logMonthCache 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // log 메서드는 이 타입의 주요 동작을 수행합니다.
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
        AppLog.debug(.schedule, "[Schedule] coordinator callSite=\(callSite) reason=\(reason) month=\(month ?? "<nil>") date=\(date ?? "<nil>") selectedPublicGameID=\(selectedGame?.publicGameID ?? "<nil>") selectedProviderGameID=\(selectedGame?.providerGameID ?? selectedGame?.officialProviderGameID ?? "<nil>") skippedDueToInFlight=\(skippedDueToInFlight) localOnly=\(localOnlyDateSelection) skippedReason=\(skippedReason ?? "<nil>") durationMs=\(durationMs.map(String.init) ?? "<nil>")")
    }

    // logStarterSync 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // durationMilliseconds 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func durationMilliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1_000)
    }

    // statusCountsText 메서드는 일정 병합 결과의 상태별 개수를 로그 문자열로 반환합니다.
    private func statusCountsText(_ games: [GameDetail]) -> String {
        let counts = Dictionary(grouping: games, by: \.status).mapValues(\.count)
        return "scheduled=\(counts[.upcoming, default: 0]) live=\(counts[.live, default: 0]) suspended=\(counts[.rainDelay, default: 0]) cancelled=\(counts[.cancelled, default: 0]) final=\(counts[.final, default: 0])"
    }
}
