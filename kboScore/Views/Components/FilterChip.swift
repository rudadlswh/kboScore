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
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, 15)
                .padding(.vertical, appModel.isStadiumFavoriteSelected ? 10 : 9)
                .frame(minHeight: appModel.isStadiumFavoriteSelected ? 44 : nil)
                .background(
                    Capsule()
                        .fill(backgroundStyle)
                )
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        if let palette = appModel.favoriteStadiumPalette {
            return isSelected ? palette.textPrimary : palette.textSecondary
        }
        return isSelected ? .white : Color.primary.opacity(0.7)
    }

    private var backgroundStyle: AnyShapeStyle {
        if let palette = appModel.favoriteStadiumPalette {
            if isSelected {
                return AnyShapeStyle(
                    LinearGradient(
                        colors: [palette.secondary.opacity(0.95), palette.primary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            return AnyShapeStyle(palette.elevatedCardStrong)
        }

        return AnyShapeStyle(isSelected ? appModel.currentTheme.accent : Color(.secondarySystemBackground))
    }
}

#Preview {
    HStack {
        FilterChip(title: "전체", isSelected: true, action: {})
        FilterChip(title: "라이브", isSelected: false, action: {})
    }
    .padding()
}
