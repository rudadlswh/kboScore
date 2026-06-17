//
//  LiveKBOCacheConfiguration.swift
//  kboScore
//  기능 설명: 실시간 KBO 캐시의 만료 시간과 저장 정책을 정의합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

// RepositoryCacheConfiguration 구조체는 RepositoryCacheConfiguration 타입의 역할과 값을 정의합니다.
struct RepositoryCacheConfiguration: Sendable {
    let bootstrapTTL: TimeInterval
    let gamesTTL: TimeInterval
    let notificationsTTL: TimeInterval
    let monthlyScheduleTTL: TimeInterval
    let diskCacheDirectory: URL?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        bootstrapTTL: TimeInterval,
        gamesTTL: TimeInterval,
        notificationsTTL: TimeInterval,
        monthlyScheduleTTL: TimeInterval,
        diskCacheDirectory: URL? = nil
    ) {
        self.bootstrapTTL = bootstrapTTL
        self.gamesTTL = gamesTTL
        self.notificationsTTL = notificationsTTL
        self.monthlyScheduleTTL = monthlyScheduleTTL
        self.diskCacheDirectory = diskCacheDirectory
    }

    nonisolated static let `default` = RepositoryCacheConfiguration(
        bootstrapTTL: 15,
        gamesTTL: 12,
        notificationsTTL: 20,
        monthlyScheduleTTL: 60 * 60 * 24,
        diskCacheDirectory: nil
    )

    nonisolated static let supabaseStartup = RepositoryCacheConfiguration(
        bootstrapTTL: 60 * 10,
        gamesTTL: 20,
        notificationsTTL: 20,
        monthlyScheduleTTL: 60 * 60 * 24,
        diskCacheDirectory: nil
    )
}

// RepositoryCacheEntry 구조체는 RepositoryCacheEntry 타입의 역할과 값을 정의합니다.
struct RepositoryCacheEntry<Value: Sendable>: Sendable {
    let value: Value
    let timestamp: Date
}
