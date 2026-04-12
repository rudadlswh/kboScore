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
        @Bindable var appModel = appModel

        NavigationStack {
            Form {
                Section("응원 팀") {
                    Picker("응원 팀 선택", selection: $appModel.settings.favoriteTeamID) {
                        Text("선택 안 함")
                            .tag(String?.none)

                        if let selectedTeamID = appModel.settings.favoriteTeamID,
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
                    Toggle("경기 시작", isOn: $appModel.settings.notificationPreferences.gameStart)
                    Toggle("점수 변경", isOn: $appModel.settings.notificationPreferences.scoreChange)
                    Toggle("리드 변경", isOn: $appModel.settings.notificationPreferences.leadChange)
                    Toggle("경기 종료", isOn: $appModel.settings.notificationPreferences.gameEnd)
                    Toggle("우천/취소", isOn: $appModel.settings.notificationPreferences.rainDelay)

                    LabeledContent("권한 상태", value: appModel.notificationAuthorizationStatus.rawValue)
                    LabeledContent("기기 토큰", value: appModel.apnsDeviceToken == nil ? "없음" : "등록됨")

                    Button("알림 권한 요청") {
                        Task {
                            await appModel.requestNotificationAuthorization()
                        }
                    }

                    LabeledContent("조용한 시간", value: appModel.settings.quietHours.description)

                    Toggle("라이브 액티비티", isOn: $appModel.settings.liveActivitiesEnabled)
                }

                Section("화면 모드") {
                    Picker("모드", selection: $appModel.settings.appearance) {
                        ForEach(AppearanceOption.allCases) { option in
                            Text(option.rawValue)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("팀 테마", selection: $appModel.settings.teamThemeMode) {
                        ForEach(TeamThemeMode.allCases) { mode in
                            Text(mode.rawValue)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("정보") {
                    InfoRow(title: "데이터 출처", value: "목 데이터 (실 API 연동 예정)")
                    InfoRow(title: "개인정보 처리방침", value: "준비 중")
                    InfoRow(title: "앱 버전", value: appVersion)
                }

                #if DEBUG
                Section("디버그") {
                    InfoRow(title: "활성 데이터", value: appModel.debugActiveDataSource)
                    InfoRow(title: "표시 데이터", value: appModel.debugDeliverySource)
                    InfoRow(title: "부트스트랩 API", value: appModel.debugBootstrapAPIEnabled)
                    InfoRow(title: "부트스트랩 ETag", value: appModel.debugBootstrapETag)
                    InfoRow(title: "부트스트랩 조회", value: appModel.debugBootstrapLastFetchText)
                    InfoRow(title: "부트스트랩 저장", value: appModel.debugBootstrapLastWriteText)
                    InfoRow(title: "부트스트랩 결과", value: appModel.debugBootstrapLastResult)
                    InfoRow(title: "로컬 JSON 소스", value: appModel.debugLocalBootstrapSource)
                    InfoRow(title: "문서 JSON 경로", value: appModel.debugLocalBootstrapPath)
                    InfoRow(title: "활성 로드 경로", value: appModel.debugLocalBootstrapResolvedPath ?? "아직 읽지 않음")
                    InfoRow(title: "로컬 JSON 읽기", value: appModel.debugLocalBootstrapLoadedText)
                    if let debugLocalBootstrapMessage = appModel.debugLocalBootstrapMessage {
                        InfoRow(title: "로컬 JSON 상태", value: debugLocalBootstrapMessage)
                    }
                    InfoRow(title: "기준 URL", value: appModel.debugBaseURL ?? "설정 안 됨")
                    InfoRow(title: "마지막 갱신", value: appModel.debugLastRefreshText)
                    InfoRow(title: "지연 상태", value: appModel.isShowingStaleData ? "지연됨" : "정상")
                    if let apnsDeviceToken = appModel.apnsDeviceToken {
                        InfoRow(title: "APNs 토큰", value: String(apnsDeviceToken.prefix(16)) + "…")
                    }
                    InfoRow(title: "등록 엔드포인트", value: appModel.notificationRegistrationEndpointDescription ?? "설정 안 됨")
                    InfoRow(title: "등록 상태", value: appModel.notificationRegistrationSyncStatus.rawValue)
                    InfoRow(title: "등록 시도", value: appModel.notificationRegistrationLastAttemptText)
                    InfoRow(title: "등록 payload", value: appModel.notificationRegistrationPayloadPreviewText)
                    Button("테스트 알림 예약") {
                        Task {
                            await appModel.scheduleDebugNotification()
                        }
                    }
                }
                #endif
            }
            .navigationTitle("설정")
            .notificationsToolbarButton()
            .formStyle(.grouped)
            .task {
                await appModel.refreshNotificationAuthorizationStatus()
            }
        }
    }

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppModel.previewModel())
}
