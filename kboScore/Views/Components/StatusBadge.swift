//
//  StatusBadge.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

struct StatusBadge: View {
    let status: GameStatus
    var tintColor: Color?
    var backgroundColor: Color?

    init(status: GameStatus, tintColor: Color? = nil, backgroundColor: Color? = nil) {
        self.status = status
        self.tintColor = tintColor
        self.backgroundColor = backgroundColor
    }

    var body: some View {
        let resolvedTintColor = tintColor ?? status.tintColor

        Text(status.title)
            .font(.caption.weight(.bold))
            .foregroundStyle(resolvedTintColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(backgroundColor ?? resolvedTintColor.opacity(0.12))
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
