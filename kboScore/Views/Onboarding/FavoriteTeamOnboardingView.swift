//
//  FavoriteTeamOnboardingView.swift
//  kboScore
//  기능 설명: 첫 실행 시 응원팀 선택 온보딩 화면을 구성합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//
//  Created by Codex on 4/22/26.
//

import SwiftUI

// FavoriteTeamCatalog 열거형는 FavoriteTeamCatalog 타입의 역할과 값을 정의합니다.
enum FavoriteTeamCatalog {
    nonisolated static let orderedTeamIDs: [String] = [
        "kia",
        "samsung",
        "lg",
        "doosan",
        "kt",
        "ssg",
        "lotte",
        "hanwha",
        "nc",
        "kiwoom"
    ]

    nonisolated static let teams: [Team] = orderedTeamIDs.compactMap { teamID in
        guard let identity = TeamIdentity.catalog[teamID] else { return nil }
        return Team(
            id: identity.id,
            name: identity.displayName,
            shortName: identity.shortLabel,
            englishName: identity.displayName,
            markText: identity.monogram
        )
    }
}

// FavoriteTeamOnboardingView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
struct FavoriteTeamOnboardingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedTeamID: String?
    private let teams = FavoriteTeamCatalog.teams

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init() {
        #if DEBUG
        print("[FavoriteTeamOnboarding] using static catalog count=\(FavoriteTeamCatalog.teams.count)")
        #endif
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("응원 팀을 선택해 주세요")
                        .font(.title2.weight(.bold))
                    Text("홈, 일정, 알림에서 기준 팀으로 사용됩니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(teams) { team in
                            Button {
                                selectedTeamID = team.id
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(team.displayName)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.primary)
                                        Text(team.shortName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: selectedTeamID == team.id ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(selectedTeamID == team.id ? appModel.currentTheme.accent : .secondary)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(.secondarySystemBackground))
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(selectedTeamID == team.id ? appModel.currentTheme.accent.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedTeamID == team.id ? .isSelected : [])
                        }
                    }
                }

                Button("시작하기") {
                    guard let selectedTeamID else { return }
                    appModel.completeFavoriteTeamOnboarding(with: selectedTeamID)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(appModel.currentTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
                .disabled(selectedTeamID == nil)
                .opacity(selectedTeamID == nil ? 0.45 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .background(KBOLivePalette.background.ignoresSafeArea())
            .navigationTitle("환영합니다")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    FavoriteTeamOnboardingView()
        .environment(AppModel.previewModel())
}
