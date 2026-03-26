//
//  StatusBadge.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

struct StatusBadge: View {
    let status: GameStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.bold))
            .foregroundStyle(status.tintColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(status.tintColor.opacity(0.12))
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
