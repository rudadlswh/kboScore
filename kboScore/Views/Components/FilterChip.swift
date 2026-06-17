//
//  FilterChip.swift
//  kboScore
//  기능 설명: 홈, 일정, 알림 화면에서 사용하는 필터 칩 UI를 제공합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

// FilterChip 구조체는 FilterChip 타입의 역할과 값을 정의합니다.
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
