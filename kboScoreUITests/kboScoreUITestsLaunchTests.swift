//
//  kboScoreUITestsLaunchTests.swift
//  기능 설명: 앱 실행 성능과 초기 화면 로딩을 검증하는 UI 테스트를 담습니다.
//  회귀를 빠르게 찾고 핵심 사용자 흐름이 깨지지 않도록 테스트 의도를 코드 가까이에 둡니다.
//  테스트 데이터와 시뮬레이터 환경 차이에 따라 결과가 달라질 수 있어 고정 fixture와 명확한 대기 조건을 우선합니다.
//  TODO : 반복 실패가 발견되면 원인별 fixture와 경계 케이스를 보강합니다.
//  kboScoreUITests
//
//  Created by 조경민 on 3/25/26.
//

import XCTest

final class kboScoreUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    // setUpWithError 메서드는 이 타입의 주요 동작을 수행합니다.
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // testLaunch 메서드는 이 타입의 주요 동작을 수행합니다.
    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
