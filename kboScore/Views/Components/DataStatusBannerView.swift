//
//  DataStatusBannerView.swift
//  kboScore
//  기능 설명: 데이터 지연이나 오류 상태를 배너 형태로 표시합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//
//  Created by Codex on 3/26/26.
//

import SwiftUI

// DataStatusBannerView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
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
