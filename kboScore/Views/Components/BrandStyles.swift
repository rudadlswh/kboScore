//
//  BrandStyles.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

enum KBOLivePalette {
    static let primary = Color(red: 0.11, green: 0.28, blue: 0.67)
    static let secondary = Color(red: 0.29, green: 0.48, blue: 0.91)
    static let background = Color(.systemGroupedBackground)
    static let live = Color(red: 0.82, green: 0.15, blue: 0.24)
    static let upcoming = Color(red: 0.13, green: 0.44, blue: 0.88)
    static let final = Color(red: 0.39, green: 0.45, blue: 0.58)
    static let weather = Color(red: 0.88, green: 0.53, blue: 0.12)
    static let cancellation = Color(red: 0.44, green: 0.48, blue: 0.56)
}

extension GameStatus {
    var tintColor: Color {
        switch self {
        case .live:
            KBOLivePalette.live
        case .upcoming:
            KBOLivePalette.upcoming
        case .final:
            KBOLivePalette.final
        case .rainDelay:
            KBOLivePalette.weather
        case .cancelled:
            KBOLivePalette.cancellation
        }
    }

    var cardBackgroundColor: Color {
        switch self {
        case .live:
            KBOLivePalette.live.opacity(0.08)
        case .upcoming:
            KBOLivePalette.upcoming.opacity(0.06)
        case .final:
            KBOLivePalette.final.opacity(0.06)
        case .rainDelay:
            KBOLivePalette.weather.opacity(0.10)
        case .cancelled:
            KBOLivePalette.cancellation.opacity(0.08)
        }
    }
}

extension NotificationType {
    var tintColor: Color {
        switch self {
        case .scoreChange, .leadChange:
            KBOLivePalette.primary
        case .gameStart:
            Color.gray
        case .gameEnd:
            Color(red: 0.59, green: 0.42, blue: 0.02)
        case .rainDelay:
            KBOLivePalette.live
        }
    }

    var systemImage: String {
        switch self {
        case .scoreChange:
            "chart.line.uptrend.xyaxis"
        case .gameStart:
            "play.circle.fill"
        case .leadChange:
            "arrow.left.arrow.right.circle.fill"
        case .gameEnd:
            "flag.fill"
        case .rainDelay:
            "cloud.rain.fill"
        }
    }
}

struct CardSurface: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat
    let fillColor: Color

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.04), lineWidth: 1)
            )
    }
}

extension View {
    func cardSurface(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 20,
        fillColor: Color = Color(.secondarySystemBackground)
    ) -> some View {
        modifier(CardSurface(padding: padding, cornerRadius: cornerRadius, fillColor: fillColor))
    }
}

struct TeamMarkView: View {
    let team: Team
    var size: CGFloat = 38

    var body: some View {
        let identity = team.identity

        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(team.identity.theme.badgeBackground)

            if identity.hasLogoAsset {
                Image(identity.logoAssetName)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.16)
            } else {
                Text(identity.monogram)
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundStyle(identity.theme.badgeForeground)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: identity.theme.shadowTint, radius: size * 0.12, y: size * 0.06)
    }
}

struct BasesDiamondView: View {
    let bases: RunnerState

    var body: some View {
        ZStack {
            DiamondBase(isFilled: bases.second)
                .offset(y: -16)
            DiamondBase(isFilled: bases.first)
                .offset(x: 16)
            DiamondBase(isFilled: bases.third)
                .offset(x: -16)
            DiamondBase(isFilled: false)
                .offset(y: 16)
        }
        .frame(width: 68, height: 68)
    }
}

struct OutCountView: View {
    let outs: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < outs ? KBOLivePalette.live : Color(.systemGray5))
                    .frame(width: 10, height: 10)
            }
        }
    }
}

private struct DiamondBase: View {
    let isFilled: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(isFilled ? KBOLivePalette.primary : Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(KBOLivePalette.primary.opacity(0.35), lineWidth: 1)
            )
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(45))
    }
}
