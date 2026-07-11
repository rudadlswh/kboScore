//
//  StatusBadge.swift
//  kboScore
//  기능 설명: 경기 상태를 작은 배지 UI로 표시합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

// StatusBadge 구조체는 StatusBadge 타입의 역할과 값을 정의합니다.
struct StatusBadge: View {
    @Environment(AppModel.self) private var appModel
    let status: GameStatus
    var tintColor: Color?
    var backgroundColor: Color?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(status: GameStatus, tintColor: Color? = nil, backgroundColor: Color? = nil) {
        self.status = status
        self.tintColor = tintColor
        self.backgroundColor = backgroundColor
    }

    var body: some View {
        let palette = appModel.favoriteStadiumPalette
        let resolvedTintColor = tintColor ?? (palette == nil ? status.tintColor : Color.white)
        let resolvedBackground = backgroundColor ?? (
            palette != nil
                ? (tintColor == nil ? palette!.statusRed : status.stadiumTintColor(palette!).opacity(0.24))
                : resolvedTintColor.opacity(0.12)
        )

        Text(status.title)
            .font(.caption.weight(.bold))
            .foregroundStyle(resolvedTintColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(resolvedBackground)
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
