//
//  FavoriteTeamOnboardingView.swift
//  kboScore
//
//  Created by Codex on 4/22/26.
//

import SwiftUI

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

struct FavoriteTeamOnboardingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedTeamID: String?
    private let teams = FavoriteTeamCatalog.teams

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
