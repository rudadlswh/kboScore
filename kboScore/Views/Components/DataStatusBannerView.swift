//
//  DataStatusBannerView.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import SwiftUI

struct DataStatusBannerView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KBOLivePalette.primary)

            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(KBOLivePalette.primary.opacity(0.12), lineWidth: 1)
        )
    }
}
