//
//  SettingsView.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

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
            Toggle("경기 시작 알림", isOn: bindableAppModel.settings.notificationPreferences.gameStartEnabled)
            Toggle("점수 변경 알림", isOn: bindableAppModel.settings.notificationPreferences.scoreChangeEnabled)
            Toggle("리드 변경 알림", isOn: bindableAppModel.settings.notificationPreferences.leadChangeEnabled)
            Toggle("경기 종료 알림", isOn: bindableAppModel.settings.notificationPreferences.gameEndEnabled)
            Toggle("출루 알림", isOn: bindableAppModel.settings.notificationPreferences.onBaseEnabled)
            Toggle("이닝 교체 알림", isOn: bindableAppModel.settings.notificationPreferences.inningChangeEnabled)
            Toggle("응원팀 내용만 알림", isOn: bindableAppModel.settings.notificationPreferences.favoriteTeamOnlyEnabled)
            Toggle("지고 있을 때 알림 끄기", isOn: bindableAppModel.settings.notificationPreferences.muteWhenLosingEnabled)
            Toggle("우천/취소", isOn: bindableAppModel.settings.notificationPreferences.rainDelay)

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
            Toggle("경기 시작 알림", isOn: bindableAppModel.settings.notificationPreferences.gameStartEnabled)
                .settingsRowStyle(palette)
            Toggle("점수 변경 알림", isOn: bindableAppModel.settings.notificationPreferences.scoreChangeEnabled)
                .settingsRowStyle(palette)
            Toggle("리드 변경 알림", isOn: bindableAppModel.settings.notificationPreferences.leadChangeEnabled)
                .settingsRowStyle(palette)
            Toggle("경기 종료 알림", isOn: bindableAppModel.settings.notificationPreferences.gameEndEnabled)
                .settingsRowStyle(palette)
            Toggle("출루 알림", isOn: bindableAppModel.settings.notificationPreferences.onBaseEnabled)
                .settingsRowStyle(palette)
            Toggle("이닝 교체 알림", isOn: bindableAppModel.settings.notificationPreferences.inningChangeEnabled)
                .settingsRowStyle(palette)
            Toggle("응원팀 내용만 알림", isOn: bindableAppModel.settings.notificationPreferences.favoriteTeamOnlyEnabled)
                .settingsRowStyle(palette)
            Toggle("지고 있을 때 알림 끄기", isOn: bindableAppModel.settings.notificationPreferences.muteWhenLosingEnabled)
                .settingsRowStyle(palette)
            Toggle("우천/취소", isOn: bindableAppModel.settings.notificationPreferences.rainDelay)
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
}

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
                if let team {
                    TeamMarkView(team: team, size: 36)
                } else {
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

private struct SettingsFormModifier: ViewModifier {
    let palette: StadiumPalette?

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
    func settingsRowStyle(_ palette: StadiumPalette) -> some View {
        listRowBackground(palette.sectionBackground)
            .listRowSeparator(.hidden)
            .foregroundStyle(palette.textPrimary)
    }

    func applyDoosanDebugRowStyleIfNeeded() -> some View {
        modifier(DoosanDebugRowStyleModifier())
    }
}

private struct DoosanDebugRowStyleModifier: ViewModifier {
    @Environment(AppModel.self) private var appModel

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
