//
//  StatusBadge.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

struct StatusBadge: View {
    @Environment(AppModel.self) private var appModel
    let status: GameStatus
    var tintColor: Color?
    var backgroundColor: Color?

    init(status: GameStatus, tintColor: Color? = nil, backgroundColor: Color? = nil) {
        self.status = status
        self.tintColor = tintColor
        self.backgroundColor = backgroundColor
    }

    var body: some View {
        let palette = appModel.favoriteStadiumPalette
        let resolvedTintColor = tintColor ?? (palette == nil ? status.tintColor : Color.white)
        let resolvedBackground = backgroundColor ?? (
            palette != nil
                ? (tintColor == nil ? palette!.statusRed : status.stadiumTintColor(palette!).opacity(0.24))
                : resolvedTintColor.opacity(0.12)
        )

        Text(status.title)
            .font(.caption.weight(.bold))
            .foregroundStyle(resolvedTintColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(resolvedBackground)
            )
    }
}

#Preview {
    HStack {
        StatusBadge(status: .live)
        StatusBadge(status: .rainDelay)
        StatusBadge(status: .final)
    }
    .padding()
}
