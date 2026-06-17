//
//  RepositoryFileSecurity.swift
//  kboScore
//  기능 설명: 번들/문서 저장소 파일 접근 시 경로 안전성을 검증합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

// RepositoryFileSecurity 열거형는 RepositoryFileSecurity 타입의 역할과 값을 정의합니다.
enum RepositoryFileSecurity {
    nonisolated static let protectionType = FileProtectionType.completeUntilFirstUserAuthentication

    // applyProtection 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    nonisolated static func applyProtection(
        to fileURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.setAttributes(
            [.protectionKey: protectionType],
            ofItemAtPath: fileURL.path
        )
    }

    // applyProtection 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    nonisolated static func applyProtection(
        toDirectory directoryURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.setAttributes(
            [.protectionKey: protectionType],
            ofItemAtPath: directoryURL.path
        )
    }

    // excludeFromBackup 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated static func excludeFromBackup(_ fileURL: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableFileURL = fileURL
        try mutableFileURL.setResourceValues(resourceValues)
    }
}
