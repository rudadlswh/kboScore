//
//  FavoriteTeamScheduleWidget.swift
//  kboScoreLiveActivityExtension
//  기능 설명: 마이팀 일정 위젯의 타임라인과 화면 구성을 담당합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//

import SwiftUI
import WidgetKit

// FavoriteTeamScheduleWidgetV2 구조체는 FavoriteTeamScheduleWidgetV2 타입의 역할과 값을 정의합니다.
struct FavoriteTeamScheduleWidgetV2: Widget {
    static let kind = FavoriteTeamScheduleWidgetShared.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Self.kind,
            provider: FavoriteTeamScheduleWidgetV2Provider()
        ) { entry in
            FavoriteTeamScheduleWidgetV2EntryView(entry: entry)
        }
        .configurationDisplayName("응원팀 일정")
        .description("응원팀 월간 일정을 홈 화면에서 확인합니다.")
        .supportedFamilies([.systemLarge])
    }
}

// FavoriteTeamScheduleWidgetV2Provider 구조체는 FavoriteTeamScheduleWidgetV2Provider 타입의 역할과 값을 정의합니다.
private struct FavoriteTeamScheduleWidgetV2Provider: TimelineProvider {
    // placeholder 메서드는 이 타입의 주요 동작을 수행합니다.
    func placeholder(in context: Context) -> FavoriteTeamScheduleWidgetV2Entry {
        .placeholder(date: Date())
    }

    // getSnapshot 메서드는 이 타입의 주요 동작을 수행합니다.
    func getSnapshot(in context: Context, completion: @escaping (FavoriteTeamScheduleWidgetV2Entry) -> Void) {
        if context.isPreview {
            completion(.preview(date: Date()))
            return
        }
        completion(makeEntry(date: Date()))
    }

    // getTimeline 메서드는 이 타입의 주요 동작을 수행합니다.
    func getTimeline(in context: Context, completion: @escaping (Timeline<FavoriteTeamScheduleWidgetV2Entry>) -> Void) {
        let entry = makeEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .after(entry.refreshAfter)))
    }

    // makeEntry 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    private func makeEntry(date: Date) -> FavoriteTeamScheduleWidgetV2Entry {
        let loadState = FavoriteTeamScheduleWidgetShared.loadState()
        logLoadedState(loadState)

        guard let favoriteTeamID = loadState.favoriteTeamID, favoriteTeamID.isEmpty == false else {
            return FavoriteTeamScheduleWidgetV2Entry(
                date: date,
                refreshAfter: date.addingTimeInterval(60 * 30),
                content: .noFavorite
            )
        }

        guard let snapshot = loadState.snapshot, snapshot.teamID == favoriteTeamID else {
            let reason = loadState.issue?.fallbackText ?? "일정 데이터를 불러올 수 없습니다"
            return FavoriteTeamScheduleWidgetV2Entry(
                date: date,
                refreshAfter: date.addingTimeInterval(60 * 30),
                content: .unavailable(reason)
            )
        }

        return FavoriteTeamScheduleWidgetV2Entry(
            date: date,
            refreshAfter: max(snapshot.refreshAfter, date.addingTimeInterval(60 * 15)),
            content: .content(snapshot)
        )
    }

    // logLoadedState 메서드는 위젯이 공유 저장소에서 읽은 일정 상태를 기록합니다.
    private func logLoadedState(_ loadState: FavoriteTeamScheduleWidgetSharedLoadState) {
        let snapshot = loadState.snapshot
        let monthKey = snapshot.map { Self.widgetMonthKey(for: $0.displayedMonth) } ?? "nil"
        let loadedCount = snapshot?.days.reduce(0) { partialResult, day in
            partialResult + (day.isInDisplayedMonth ? day.gameCount : 0)
        } ?? 0
        print(
            "[WidgetSchedule] load month=\(monthKey) " +
            "favoriteTeam=\(loadState.favoriteTeamID ?? "nil") " +
            "snapshotTeam=\(snapshot?.teamID ?? "nil") " +
            "loadedCount=\(loadedCount)"
        )
    }

    // widgetMonthKey 메서드는 KST 기준 yyyyMM 월 키를 만듭니다.
    private static func widgetMonthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyyMM"
        return formatter.string(from: date)
    }
}

// FavoriteTeamScheduleWidgetV2Entry 구조체는 FavoriteTeamScheduleWidgetV2Entry 타입의 역할과 값을 정의합니다.
private struct FavoriteTeamScheduleWidgetV2Entry: TimelineEntry {
// Content 열거형는 Content 타입의 역할과 값을 정의합니다.
    enum Content {
        case placeholder(FavoriteTeamScheduleWidgetSnapshot)
        case noFavorite
        case unavailable(String)
        case content(FavoriteTeamScheduleWidgetSnapshot)
    }

    let date: Date
    let refreshAfter: Date
    let content: Content

    // placeholder 메서드는 이 타입의 주요 동작을 수행합니다.
    static func placeholder(date: Date) -> FavoriteTeamScheduleWidgetV2Entry {
        FavoriteTeamScheduleWidgetV2Entry(
            date: date,
            refreshAfter: date.addingTimeInterval(60 * 30),
            content: .placeholder(FavoriteTeamScheduleWidgetV2Preview.sampleSnapshot(referenceDate: date))
        )
    }

    // preview 메서드는 이 타입의 주요 동작을 수행합니다.
    static func preview(date: Date) -> FavoriteTeamScheduleWidgetV2Entry {
        FavoriteTeamScheduleWidgetV2Entry(
            date: date,
            refreshAfter: date.addingTimeInterval(60 * 30),
            content: .content(FavoriteTeamScheduleWidgetV2Preview.sampleSnapshot(referenceDate: date))
        )
    }
}

// FavoriteTeamScheduleWidgetV2EntryView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct FavoriteTeamScheduleWidgetV2EntryView: View {
    let entry: FavoriteTeamScheduleWidgetV2Entry

    var body: some View {
        switch entry.content {
        case .placeholder(let snapshot):
            FavoriteTeamSchedulePlaceholderView(snapshot: snapshot)
        default:
            FavoriteTeamScheduleContentView(entry: entry)
                .unredacted()
        }
    }
}

// FavoriteTeamSchedulePlaceholderView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct FavoriteTeamSchedulePlaceholderView: View {
    let snapshot: FavoriteTeamScheduleWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(width: 88, height: 12)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(width: 132, height: 18)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(Self.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(snapshot.days) { day in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(day.isInDisplayedMonth ? Color(.systemGray6) : Color(.systemGray6).opacity(0.45))
                        .frame(height: 42)
                }
            }
        }
        .padding(16)
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    private static let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]
}

// FavoriteTeamScheduleContentView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct FavoriteTeamScheduleContentView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let entry: FavoriteTeamScheduleWidgetV2Entry

    var body: some View {
        Group {
            switch entry.content {
            case .noFavorite:
                FavoriteTeamScheduleMessageView(
                    title: "응원팀을 선택해 주세요",
                    message: "설정에서 응원팀을 선택하면 월간 일정이 표시됩니다."
                )
            case .unavailable(let reason):
                FavoriteTeamScheduleMessageView(
                    title: "일정 데이터를 불러올 수 없습니다",
                    message: reason
                )
            case .content(let snapshot):
                FavoriteTeamScheduleCalendarView(
                    snapshot: snapshot,
                    isFullColor: renderingMode == .fullColor
                )
            case .placeholder:
                EmptyView()
            }
        }
        .containerBackground(for: .widget) {
            renderingMode == .fullColor ? Color(.systemBackground) : Color.clear
        }
    }
}

// FavoriteTeamScheduleMessageView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct FavoriteTeamScheduleMessageView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
    }
}

// FavoriteTeamScheduleCalendarView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct FavoriteTeamScheduleCalendarView: View {
    let snapshot: FavoriteTeamScheduleWidgetSnapshot
    let isFullColor: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    private var theme: TeamTheme {
        TeamTheme.resolve(for: snapshot.teamID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(snapshot.days) { day in
                    FavoriteTeamScheduleDayCell(
                        day: day,
                        accent: theme.accent,
                        chipBackground: theme.chipBackground,
                        isFullColor: isFullColor
                    )
                }
            }

            if snapshot.state == .emptySchedule {
                Text("표시할 일정이 없습니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.teamName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(snapshot.monthTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 8)

            Text(snapshot.monthSummaryText)
                .font(.caption2.weight(.bold))
                .foregroundStyle(isFullColor ? theme.accent : .primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(isFullColor ? theme.chipBackground : Color.primary.opacity(0.12))
                )
                .widgetAccentable()
        }
    }
}

// FavoriteTeamScheduleDayCell 구조체는 FavoriteTeamScheduleDayCell 타입의 역할과 값을 정의합니다.
private struct FavoriteTeamScheduleDayCell: View {
    let day: FavoriteTeamScheduleWidgetSnapshot.Day
    let accent: Color
    let chipBackground: Color
    let isFullColor: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(day.date.formatted(.dateTime.day()))
                .font(.caption.weight(day.isToday ? .bold : .medium))
                .foregroundStyle(dayNumberColor)

            ZStack(alignment: .topTrailing) {
                if day.gameCount > 0 {
                    FavoriteTeamScheduleOpponentMark(
                        teamID: day.opponentTeamID,
                        status: day.dominantStatus,
                        favoriteTeamIsHome: day.favoriteTeamIsHome,
                        accent: accent,
                        isFullColor: isFullColor,
                        count: day.gameCount
                    )

                    if day.gameCount > 1 {
                        Text("\(day.gameCount)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule(style: .continuous).fill(accent))
                            .offset(x: 4, y: -4)
                            .widgetAccentable()
                    }
                }
            }
            .frame(height: 24)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(cellBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cellBorderColor, lineWidth: day.isToday ? 1 : 0)
        )
    }

    private var dayNumberColor: Color {
        day.isInDisplayedMonth ? .primary : .secondary.opacity(0.6)
    }

    private var cellBackground: Color {
        if day.isToday {
            return .clear
        }
        if let result = day.favoriteTeamResult {
            switch result {
            case .win:
                return Color(red: 0.13, green: 0.44, blue: 0.88).opacity(isFullColor ? 0.16 : 0.10)
            case .loss:
                return Color(red: 0.82, green: 0.15, blue: 0.24).opacity(isFullColor ? 0.14 : 0.10)
            case .tie:
                return chipBackground
            }
        }
        return .clear
    }

    private var cellBorderColor: Color {
        day.isToday ? Color(red: 0.13, green: 0.44, blue: 0.88).opacity(isFullColor ? 0.9 : 0.82) : .clear
    }
}

// FavoriteTeamScheduleOpponentMark 구조체는 FavoriteTeamScheduleOpponentMark 타입의 역할과 값을 정의합니다.
private struct FavoriteTeamScheduleOpponentMark: View {
    let teamID: String?
    let status: FavoriteTeamScheduleWidgetGameStatus?
    let favoriteTeamIsHome: Bool?
    let accent: Color
    let isFullColor: Bool
    let count: Int

    private var size: CGFloat {
        count > 1 ? 22 : 20
    }

    private var homeAwayLabel: String? {
        guard let favoriteTeamIsHome else { return nil }
        return favoriteTeamIsHome ? "H" : "A"
    }

    var body: some View {
        if let teamID, let identity = TeamIdentity.catalog[teamID] {
            Text(identity.monogram)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 5)
                .frame(height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .fill(isFullColor ? identity.theme.chipBackground : Color.primary.opacity(0.12))
                )
                .overlay(alignment: .bottomTrailing) {
                    if let homeAwayLabel {
                        FavoriteTeamScheduleHomeAwayBadge(label: homeAwayLabel, isFullColor: isFullColor)
                            .offset(x: 3, y: 3)
                    }
                }
                .accessibilityLabel(accessibilityLabel(teamName: identity.teamDisplayName))
                .widgetAccentable()
        } else {
            Circle()
                .fill(status?.color ?? accent)
                .frame(width: count > 1 ? 10 : 6, height: count > 1 ? 10 : 6)
                .widgetAccentable()
        }
    }

    // accessibilityLabel 메서드는 화면 표시와 디버그에 사용할 문구를 구성합니다.
    private func accessibilityLabel(teamName: String) -> String {
        guard let favoriteTeamIsHome else { return "\(teamName)" }
        return favoriteTeamIsHome ? "\(teamName), 홈 경기" : "\(teamName), 원정 경기"
    }
}

// FavoriteTeamScheduleHomeAwayBadge 구조체는 FavoriteTeamScheduleHomeAwayBadge 타입의 역할과 값을 정의합니다.
private struct FavoriteTeamScheduleHomeAwayBadge: View {
    let label: String
    let isFullColor: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 7, weight: .bold, design: .rounded))
            .foregroundStyle(isFullColor ? .secondary : .primary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                Capsule(style: .continuous)
                    .fill(isFullColor ? Color(.systemBackground).opacity(0.92) : Color.primary.opacity(0.16))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(isFullColor ? 0.10 : 0.08), lineWidth: 0.5)
            )
    }
}

// FavoriteTeamScheduleWidgetV2Preview 열거형는 FavoriteTeamScheduleWidgetV2Preview 타입의 역할과 값을 정의합니다.
private enum FavoriteTeamScheduleWidgetV2Preview {
    // sampleSnapshot 메서드는 이 타입의 주요 동작을 수행합니다.
    static func sampleSnapshot(referenceDate: Date) -> FavoriteTeamScheduleWidgetSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)) ?? referenceDate
        let monthInterval = calendar.dateInterval(of: .month, for: monthStart) ?? DateInterval(start: monthStart, duration: 60 * 60 * 24 * 30)
        let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) ?? monthInterval
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthInterval.start) ?? monthInterval.start
        let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthEnd) ?? monthInterval

        var days: [FavoriteTeamScheduleWidgetSnapshot.Day] = []
        var cursor = firstWeek.start
        var offset = 0
        while cursor < lastWeek.end {
            let isInMonth = calendar.isDate(cursor, equalTo: monthStart, toGranularity: .month)
            let isToday = calendar.isDateInToday(cursor)
            let sampleGame: (count: Int, teamID: String?, result: FavoriteTeamScheduleWidgetTeamResult?, status: FavoriteTeamScheduleWidgetGameStatus?)?
            let sampleHomeGame: Bool?
            switch offset {
            case 9:
                sampleGame = (1, "hanwha", .win, .final)
                sampleHomeGame = true
            case 13:
                sampleGame = (1, "doosan", nil, .upcoming)
                sampleHomeGame = false
            case 18:
                sampleGame = (2, "samsung", .loss, .final)
                sampleHomeGame = true
            default:
                sampleGame = nil
                sampleHomeGame = nil
            }

            days.append(
                FavoriteTeamScheduleWidgetSnapshot.Day(
                    date: cursor,
                    isInDisplayedMonth: isInMonth,
                    isToday: isToday,
                    gameCount: sampleGame?.count ?? 0,
                    dominantStatus: sampleGame?.status,
                    opponentTeamID: sampleGame?.teamID,
                    favoriteTeamIsHome: sampleHomeGame,
                    favoriteTeamResult: sampleGame?.result
                )
            )
            offset += 1
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? lastWeek.end
        }

        return FavoriteTeamScheduleWidgetSnapshot(
            generatedAt: referenceDate,
            refreshAfter: referenceDate.addingTimeInterval(60 * 60 * 6),
            teamID: "lg",
            teamName: "LG",
            teamShortName: "LG",
            displayedMonth: monthStart,
            monthTitle: {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "ko_KR")
                formatter.calendar = calendar
                formatter.dateFormat = "yyyy년 M월"
                return formatter.string(from: monthStart)
            }(),
            monthSummaryText: "이달 경기 4",
            state: .ready,
            days: days
        )
    }
}

private extension FavoriteTeamScheduleWidgetSharedLoadIssue {
    var fallbackText: String {
        switch self {
        case .appGroupUnavailable:
            "공유 컨테이너에 접근할 수 없습니다"
        case .noSharedFile:
            "공유 일정 파일이 없습니다"
        case .fileReadFailed, .fileDecodeFailed:
            "공유 일정 데이터를 읽을 수 없습니다"
        }
    }
}

private extension FavoriteTeamScheduleWidgetGameStatus {
    var color: Color {
        switch self {
        case .upcoming:
            Color(red: 0.13, green: 0.44, blue: 0.88)
        case .live:
            Color(red: 0.82, green: 0.15, blue: 0.24)
        case .final:
            Color(red: 0.39, green: 0.45, blue: 0.58)
        case .rainDelay:
            Color(red: 0.88, green: 0.53, blue: 0.12)
        case .cancelled:
            Color(red: 0.44, green: 0.48, blue: 0.56)
        }
    }
}

#Preview(as: .systemLarge) {
    FavoriteTeamScheduleWidgetV2()
} timeline: {
    FavoriteTeamScheduleWidgetV2Entry.preview(date: Date())
}
