//
//  LiveActivityActionButton.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import SwiftUI

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
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(foregroundStyle)
        }
        .buttonStyle(.plain)
        .disabled(appModel.isLiveActivityActionEnabled(for: game) == false)
        .opacity(appModel.isLiveActivityActionEnabled(for: game) ? 1 : 0.55)
    }

    private var backgroundStyle: Color {
        appModel.isLiveActivityActionEnabled(for: game) ? appModel.currentTheme.accent : Color(.secondarySystemBackground)
    }

    private var foregroundStyle: Color {
        appModel.isLiveActivityActionEnabled(for: game) ? .white : .secondary
    }
}

#Preview {
    NavigationStack {
        LiveActivityActionButton(game: MockKBOData.makeBootstrap().games.first!)
            .padding()
    }
    .environment(AppModel.previewModel())
}
