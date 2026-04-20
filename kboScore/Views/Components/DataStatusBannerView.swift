//
//  DataStatusBannerView.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import SwiftUI

struct DataStatusBannerView: View {
    @Environment(AppModel.self) private var appModel
    let message: String

    var body: some View {
        let palette = appModel.favoriteStadiumPalette

        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette?.secondary ?? KBOLivePalette.primary)

            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(palette?.textSecondary ?? .secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette?.sectionBackground ?? Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    palette?.ghostBorder ?? KBOLivePalette.primary.opacity(0.12),
                    lineWidth: palette == nil ? 1 : 0.75
                )
        )
    }
}
