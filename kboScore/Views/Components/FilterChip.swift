//
//  FilterChip.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

struct FilterChip: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.7))
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(isSelected ? appModel.currentTheme.accent : Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack {
        FilterChip(title: "전체", isSelected: true, action: {})
        FilterChip(title: "라이브", isSelected: false, action: {})
    }
    .padding()
}
