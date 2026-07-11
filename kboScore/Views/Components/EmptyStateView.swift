//
//  EmptyStateView.swift
//  kboScore
//  기능 설명: 목록이나 화면에 표시할 데이터가 없을 때 빈 상태 UI를 제공합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

// EmptyStateView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
struct EmptyStateView: View {
    @Environment(AppModel.self) private var appModel
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        let palette = appModel.favoriteStadiumPalette

        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(palette?.textSecondary ?? .secondary)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette?.textPrimary ?? .primary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(palette?.textSecondary ?? .secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .cardSurface(fillColor: palette?.sectionBackground ?? Color(.secondarySystemBackground))
    }
}

#Preview {
    EmptyStateView(systemImage: "tray", title: "데이터가 없습니다", message: "조건에 맞는 항목이 아직 없습니다.")
        .padding()
}
