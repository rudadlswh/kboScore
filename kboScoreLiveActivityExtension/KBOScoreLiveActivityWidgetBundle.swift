//
//  KBOScoreLiveActivityWidgetBundle.swift
//  kboScoreLiveActivityExtension
//  기능 설명: KBO Live Activity 위젯 번들을 정의합니다.
//  앱 밖에서도 마이팀 경기 흐름을 이어서 볼 수 있도록 Live Activity와 위젯용 스냅샷을 분리합니다.
//  확장 프로세스, App Group 저장소, 푸시 토큰, 시스템 권한 상태에 따라 갱신이 실패할 수 있습니다.
//  TODO : 실기기 권한 상태별 동작과 종료 조건을 더 촘촘히 검증합니다.
//
//  Created by Codex on 3/26/26.
//

import SwiftUI
import WidgetKit

// KBOScoreLiveActivityWidgetBundle 구조체는 KBOScoreLiveActivityWidgetBundle 타입의 역할과 값을 정의합니다.
@main
struct KBOScoreLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        FavoriteTeamScheduleWidgetV2()
        FavoriteTeamLockScreenScheduleWidget()
        FavoriteTeamNextGameCircularWidget()
        KBOScoreLiveActivityWidget()
    }
}
