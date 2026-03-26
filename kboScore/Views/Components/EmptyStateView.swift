//
//  EmptyStateView.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .cardSurface()
    }
}

#Preview {
    EmptyStateView(systemImage: "tray", title: "데이터가 없습니다", message: "조건에 맞는 항목이 아직 없습니다.")
        .padding()
}
