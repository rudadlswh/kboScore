//
//  OfficialKBOGridDTOs.swift
//  kboScore
//  기능 설명: KBO 공식 API 응답을 디코딩하기 위한 DTO를 정의합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

// OfficialGridCellDTO 구조체는 외부 응답과 내부 모델 변환에 사용하는 데이터 전송 값을 담습니다.
struct OfficialGridCellDTO: Decodable {
    let text: String

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case text = "Text"
    }
}
