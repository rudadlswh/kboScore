//
//  SettingsView.swift
//  kboScore
//  기능 설명: 앱 설정, 응원팀, 알림 옵션 화면을 구성합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

// SettingsView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var bindableAppModel = appModel

        NavigationStack {
            Form {
                if let palette = appModel.favoriteStadiumPalette {
                    doosanSections(appModel: appModel, bindableAppModel: $bindableAppModel, palette: palette)
                } else {
                    defaultSections(appModel: appModel, bindableAppModel: $bindableAppModel)
                }
            }
            .navigationTitle("설정")
            .doosanInlineNavigationTitle(isEnabled: appModel.isStadiumFavoriteSelected)
            .stadiumNavigationChrome(appModel.favoriteStadiumPalette)
            .notificationsToolbarButton()
            .formStyle(.grouped)
            .modifier(SettingsFormModifier(palette: appModel.favoriteStadiumPalette))
            .task {
                await appModel.refreshNotificationAuthorizationStatus()
            }
        }
    }

    // defaultSections 메서드는 이 타입의 주요 동작을 수행합니다.
    @ViewBuilder
    private func defaultSections(appModel: AppModel, bindableAppModel: Bindable<AppModel>) -> some View {
        Section("응원 팀") {
            Picker("응원 팀 선택", selection: bindableAppModel.settings.favoriteTeamID) {
                if let selectedTeamID = bindableAppModel.settings.favoriteTeamID.wrappedValue,
                   appModel.teams.contains(where: { $0.id == selectedTeamID }) == false {
                    Text(Team.displayName(
                        forTeamID: selectedTeamID,
                        fallback: TeamIdentity.catalog[selectedTeamID]?.shortLabel ?? selectedTeamID
                    ))
                    .tag(Optional(selectedTeamID))
                }

                ForEach(appModel.teams) { team in
                    Text(team.displayName)
                        .tag(Optional(team.id))
                }
            }
            .pickerStyle(.navigationLink)
        }

        Section("알림 설정") {
            Toggle("경기 시작 알림", isOn: notificationPreferenceBinding(\.gameStartEnabled, appModel: appModel))
            Toggle("점수 변경 알림", isOn: notificationPreferenceBinding(\.scoreChangeEnabled, appModel: appModel))
            Toggle("리드 변경 알림", isOn: notificationPreferenceBinding(\.leadChangeEnabled, appModel: appModel))
            Toggle("경기 종료 알림", isOn: notificationPreferenceBinding(\.gameEndEnabled, appModel: appModel))
            Toggle("출루 알림", isOn: notificationPreferenceBinding(\.onBaseEnabled, appModel: appModel))
            Toggle("이닝 교체 알림", isOn: notificationPreferenceBinding(\.inningChangeEnabled, appModel: appModel))
            Toggle("상대팀 알림 끄기", isOn: notificationPreferenceBinding(\.favoriteTeamOnlyEnabled, appModel: appModel))
            Toggle("지고 있을 때 알림 끄기", isOn: notificationPreferenceBinding(\.muteWhenLosingEnabled, appModel: appModel))
            Toggle("우천/취소", isOn: notificationPreferenceBinding(\.rainDelay, appModel: appModel))

            LabeledContent("권한 상태", value: appModel.notificationAuthorizationStatus.rawValue)
//            LabeledContent("기기 토큰", value: appModel.apnsDeviceToken == nil ? "없음" : "등록됨")

            Button("알림 권한 요청") {
                Task {
                    await appModel.requestNotificationAuthorization()
                }
            }

            LabeledContent("조용한 시간", value: bindableAppModel.settings.quietHours.wrappedValue.description)

            Toggle("라이브 액티비티", isOn: bindableAppModel.settings.liveActivitiesEnabled)
        }

        Section("정보") {
            InfoRow(title: "데이터 출처", value: "목 데이터 (실 API 연동 예정)")
            InfoRow(title: "개인정보 처리방침", value: "준비 중")
            InfoRow(title: "앱 버전", value: appVersion)
        }

    }

    // doosanSections 메서드는 이 타입의 주요 동작을 수행합니다.
    @ViewBuilder
    private func doosanSections(appModel: AppModel, bindableAppModel: Bindable<AppModel>, palette: StadiumPalette) -> some View {
        Section {
            NavigationLink {
                DoosanFavoriteTeamSelectionView(selection: bindableAppModel.settings.favoriteTeamID, palette: palette)
            } label: {
                HStack {
                    Text("응원 팀 선택")
                    Spacer()
                    Text(currentFavoriteTeamDisplayName(appModel: appModel))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .settingsRowStyle(palette)
        } header: {
            SettingsSectionHeader(
                title: "응원 팀",
                subtitle: "마이팀, 일정, 알림에서 기준 팀으로 사용됩니다."
            )
        }

        Section {
            Toggle("경기 시작 알림", isOn: notificationPreferenceBinding(\.gameStartEnabled, appModel: appModel))
                .settingsRowStyle(palette)
            Toggle("점수 변경 알림", isOn: notificationPreferenceBinding(\.scoreChangeEnabled, appModel: appModel))
                .settingsRowStyle(palette)
            Toggle("리드 변경 알림", isOn: notificationPreferenceBinding(\.leadChangeEnabled, appModel: appModel))
                .settingsRowStyle(palette)
            Toggle("경기 종료 알림", isOn: notificationPreferenceBinding(\.gameEndEnabled, appModel: appModel))
                .settingsRowStyle(palette)
            Toggle("출루 알림", isOn: notificationPreferenceBinding(\.onBaseEnabled, appModel: appModel))
                .settingsRowStyle(palette)
            Toggle("이닝 교체 알림", isOn: notificationPreferenceBinding(\.inningChangeEnabled, appModel: appModel))
                .settingsRowStyle(palette)
            Toggle("상대팀 알림 끄기", isOn: notificationPreferenceBinding(\.favoriteTeamOnlyEnabled, appModel: appModel))
                .settingsRowStyle(palette)
            Toggle("지고 있을 때 알림 끄기", isOn: notificationPreferenceBinding(\.muteWhenLosingEnabled, appModel: appModel))
                .settingsRowStyle(palette)
            Toggle("우천/취소", isOn: notificationPreferenceBinding(\.rainDelay, appModel: appModel))
                .settingsRowStyle(palette)

            InfoRow(title: "권한 상태", value: appModel.notificationAuthorizationStatus.rawValue)
                .settingsRowStyle(palette)
//            InfoRow(title: "기기 토큰", value: appModel.apnsDeviceToken == nil ? "없음" : "등록됨")
//                .settingsRowStyle(palette)

            Button("알림 권한 요청") {
                Task {
                    await appModel.requestNotificationAuthorization()
                }
            }
            .settingsRowStyle(palette)

            InfoRow(title: "조용한 시간", value: bindableAppModel.settings.quietHours.wrappedValue.description)
                .settingsRowStyle(palette)

            Toggle("라이브 액티비티", isOn: bindableAppModel.settings.liveActivitiesEnabled)
                .settingsRowStyle(palette)
        } header: {
            SettingsSectionHeader(
                title: "알림 설정",
                subtitle: "실시간 이벤트 전달과 기기 권한 상태를 관리합니다."
            )
        }

        Section {
            InfoRow(title: "데이터 출처", value: "https://www.koreabaseball.com/")
                .settingsRowStyle(palette)
            InfoRow(title: "개인정보 처리방침", value: "준비 중")
                .settingsRowStyle(palette)
            InfoRow(title: "앱 버전", value: appVersion)
                .settingsRowStyle(palette)
        } header: {
            SettingsSectionHeader(
                title: "정보",
                subtitle: "앱 버전과 정책 관련 정보를 확인합니다."
            )
        }

    }

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }

    // currentFavoriteTeamDisplayName 메서드는 이 타입의 주요 동작을 수행합니다.
    private func currentFavoriteTeamDisplayName(appModel: AppModel) -> String {
        guard let favoriteTeamID = appModel.settings.favoriteTeamID else {
            return "미설정"
        }
        return appModel.teams.first(where: { $0.id == favoriteTeamID })?.displayName
            ?? Team.displayName(
                forTeamID: favoriteTeamID,
                fallback: TeamIdentity.catalog[favoriteTeamID]?.shortLabel ?? favoriteTeamID
            )
    }

    // notificationPreferenceBinding 메서드는 이 타입의 주요 동작을 수행합니다.
    private func notificationPreferenceBinding(
        _ keyPath: WritableKeyPath<NotificationPreferences, Bool>,
        appModel: AppModel
    ) -> Binding<Bool> {
        Binding {
            appModel.settings.notificationPreferences[keyPath: keyPath]
        } set: { newValue in
            var settings = appModel.settings
            settings.notificationPreferences[keyPath: keyPath] = newValue
            appModel.settings = settings
        }
    }
}

// DoosanFavoriteTeamSelectionView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct DoosanFavoriteTeamSelectionView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var selection: String?
    let palette: StadiumPalette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("응원 팀 선택")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(palette.textPrimary)

                Text("마이팀, 일정, 알림에서 기준 팀으로 사용됩니다.")
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)

                VStack(spacing: 8) {
                    if let selectedTeamID = selection,
                       appModel.teams.contains(where: { $0.id == selectedTeamID }) == false {
                        teamSelectionRow(
                            title: Team.displayName(
                                forTeamID: selectedTeamID,
                                fallback: TeamIdentity.catalog[selectedTeamID]?.shortLabel ?? selectedTeamID
                            ),
                            subtitle: "현재 선택된 팀",
                            team: nil,
                            value: selectedTeamID
                        )
                    }

                    ForEach(appModel.teams) { team in
                        teamSelectionRow(
                            title: team.displayName,
                            subtitle: team.shortName,
                            team: team,
                            value: team.id
                        )
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background {
            LinearGradient(
                colors: [palette.background, palette.sectionBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .navigationTitle("응원 팀 선택")
        .navigationBarTitleDisplayMode(.inline)
        .doosanInlineNavigationTitle(isEnabled: true)
        .stadiumNavigationChrome(palette)
        .tint(palette.primary)
    }

    // teamSelectionRow 메서드는 이 타입의 주요 동작을 수행합니다.
    private func teamSelectionRow(
        title: String,
        subtitle: String,
        team: Team?,
        value: String?
    ) -> some View {
        let isSelected = selection == value

        return Button {
            selection = value
        } label: {
            HStack(spacing: 12) {
                if team == nil {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(isSelected ? palette.primary : palette.textSecondary)
                        .frame(width: 36, height: 36)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isSelected ? palette.primary : palette.textSecondary.opacity(0.75))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? palette.elevatedCardStrong : palette.elevatedCard)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? palette.primary.opacity(0.35) : palette.ghostBorder, lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// SettingsFormModifier 구조체는 SwiftUI 뷰 스타일과 동작을 재사용 가능한 형태로 적용합니다.
private struct SettingsFormModifier: ViewModifier {
    let palette: StadiumPalette?

    // body 메서드는 SwiftUI 화면의 본문 구성을 반환합니다.
    func body(content: Content) -> some View {
        if let palette {
            content
                .scrollContentBackground(.hidden)
                .background(
                    LinearGradient(
                        colors: [palette.background, palette.sectionBackground],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .tint(palette.primary)
        } else {
            content
        }
    }
}

// InfoRow 구조체는 InfoRow 타입의 역할과 값을 정의합니다.
private struct InfoRow: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
            Spacer()
            Text(value)
                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// DebugRowsView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct DebugRowsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            InfoRow(title: "활성 데이터", value: appModel.debugActiveDataSource)
                .applyDoosanDebugRowStyleIfNeeded()
            InfoRow(title: "표시 데이터", value: appModel.debugDeliverySource)
                .applyDoosanDebugRowStyleIfNeeded()
            InfoRow(title: "부트스트랩 API", value: appModel.debugBootstrapAPIEnabled)
                .applyDoosanDebugRowStyleIfNeeded()
            InfoRow(title: "부트스트랩 ETag", value: appModel.debugBootstrapETag)
                .applyDoosanDebugRowStyleIfNeeded()
            InfoRow(title: "부트스트랩 조회", value: appModel.debugBootstrapLastFetchText)
                .applyDoosanDebugRowStyleIfNeeded()
            InfoRow(title: "부트스트랩 저장", value: appModel.debugBootstrapLastWriteText)
                .applyDoosanDebugRowStyleIfNeeded()
            InfoRow(title: "부트스트랩 결과", value: appModel.debugBootstrapLastResult)
                .applyDoosanDebugRowStyleIfNeeded()
            InfoRow(title: "로컬 JSON 소스", value: appModel.debugLocalBootstrapSource)
                .applyDoosanDebugRowStyleIfNeeded()
            InfoRow(title: "문서 JSON 경로", value: appModel.debugLocalBootstrapPath)
                .applyDoosanDebugRowStyleIfNeeded()
            InfoRow(title: "활성 로드 경로", value: appModel.debugLocalBootstrapResolvedPath ?? "아직 읽지 않음")
                .applyDoosanDebugRowStyleIfNeeded()
            InfoRow(title: "로컬 JSON 읽기", value: appModel.debugLocalBootstrapLoadedText)
                .applyDoosanDebugRowStyleIfNeeded()
            if let debugLocalBootstrapMessage = appModel.debugLocalBootstrapMessage {
                InfoRow(title: "로컬 JSON 상태", value: debugLocalBootstrapMessage)
                    .applyDoosanDebugRowStyleIfNeeded()
            }
            InfoRow(title: "기준 URL", value: appModel.debugBaseURL ?? "설정 안 됨")
                .applyDoosanDebugRowStyleIfNeeded()
            InfoRow(title: "마지막 갱신", value: appModel.debugLastRefreshText)
                .applyDoosanDebugRowStyleIfNeeded()
            InfoRow(title: "지연 상태", value: appModel.isShowingStaleData ? "지연됨" : "정상")
                .applyDoosanDebugRowStyleIfNeeded()
            if let apnsDeviceToken = appModel.apnsDeviceToken {
                InfoRow(title: "APNs 토큰", value: String(apnsDeviceToken.prefix(16)) + "…")
                    .applyDoosanDebugRowStyleIfNeeded()
            }
            InfoRow(title: "등록 엔드포인트", value: appModel.notificationRegistrationEndpointDescription ?? "설정 안 됨")
                .applyDoosanDebugRowStyleIfNeeded()
            InfoRow(title: "등록 상태", value: appModel.notificationRegistrationSyncStatus.rawValue)
                .applyDoosanDebugRowStyleIfNeeded()
            InfoRow(title: "등록 시도", value: appModel.notificationRegistrationLastAttemptText)
                .applyDoosanDebugRowStyleIfNeeded()
            InfoRow(title: "등록 payload", value: appModel.notificationRegistrationPayloadPreviewText)
                .applyDoosanDebugRowStyleIfNeeded()
            Button("테스트 알림 예약") {
                Task {
                    await appModel.scheduleDebugNotification()
                }
            }
            .applyDoosanDebugRowStyleIfNeeded()
        }
    }
}

// SettingsSectionHeader 구조체는 SettingsSectionHeader 타입의 역할과 값을 정의합니다.
private struct SettingsSectionHeader: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    let subtitle: String

    var body: some View {
        let palette = appModel.favoriteStadiumPalette

        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette?.textPrimary ?? .primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(palette?.textSecondary ?? .secondary)
        }
        .textCase(nil)
    }
}

private extension View {
    // settingsRowStyle 메서드는 이 타입의 주요 동작을 수행합니다.
    func settingsRowStyle(_ palette: StadiumPalette) -> some View {
        listRowBackground(palette.sectionBackground)
            .listRowSeparator(.hidden)
            .foregroundStyle(palette.textPrimary)
    }

    // applyDoosanDebugRowStyleIfNeeded 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func applyDoosanDebugRowStyleIfNeeded() -> some View {
        modifier(DoosanDebugRowStyleModifier())
    }
}

// DoosanDebugRowStyleModifier 구조체는 SwiftUI 뷰 스타일과 동작을 재사용 가능한 형태로 적용합니다.
private struct DoosanDebugRowStyleModifier: ViewModifier {
    @Environment(AppModel.self) private var appModel

    // body 메서드는 SwiftUI 화면의 본문 구성을 반환합니다.
    func body(content: Content) -> some View {
        if let palette = appModel.favoriteStadiumPalette {
            content.settingsRowStyle(palette)
        } else {
            content
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppModel.previewModel())
}
