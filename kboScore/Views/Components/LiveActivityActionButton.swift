//
//  LiveActivityActionButton.swift
//  kboScore
//  기능 설명: Live Activity 시작과 종료 액션 버튼을 렌더링합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//
//  Created by Codex on 3/26/26.
//

import SwiftUI

// LiveActivityActionButton 구조체는 LiveActivityActionButton 타입의 역할과 값을 정의합니다.
struct LiveActivityActionButton: View {
    @Environment(AppModel.self) private var appModel
    let game: GameDetail

    var body: some View {
        Button {
            Task {
                await appModel.toggleLiveActivity(for: game)
            }
        } label: {
            Label(
                appModel.liveActivityButtonTitle(for: game),
                systemImage: appModel.liveActivityButtonSystemImage(for: game)
            )
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundStyle)
            )
            .foregroundStyle(foregroundStyle)
        }
        .buttonStyle(.plain)
        .disabled(appModel.isLiveActivityActionEnabled(for: game) == false)
        .opacity(appModel.isLiveActivityActionEnabled(for: game) ? 1 : 0.55)
    }

    private var backgroundStyle: AnyShapeStyle {
        if let palette = appModel.favoriteStadiumPalette {
            if appModel.isLiveActivityActionEnabled(for: game) {
                return AnyShapeStyle(
                    LinearGradient(
                        colors: [palette.secondary.opacity(0.95), palette.primary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            return AnyShapeStyle(palette.sectionBackground)
        }
        return AnyShapeStyle(
            appModel.isLiveActivityActionEnabled(for: game) ? appModel.currentTheme.accent : Color(.secondarySystemBackground)
        )
    }

    private var foregroundStyle: Color {
        if let palette = appModel.favoriteStadiumPalette {
            return appModel.isLiveActivityActionEnabled(for: game) ? palette.textPrimary : palette.textSecondary
        }
        return appModel.isLiveActivityActionEnabled(for: game) ? .white : .secondary
    }
}

#Preview {
    NavigationStack {
        LiveActivityActionButton(game: MockKBOData.makeBootstrap().games.first!)
            .padding()
    }
    .environment(AppModel.previewModel())
}
