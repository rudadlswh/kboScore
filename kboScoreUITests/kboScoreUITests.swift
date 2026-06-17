//
//  kboScoreUITests.swift
//  기능 설명: 앱 주요 UI 흐름을 검증하는 UI 테스트를 담습니다.
//  회귀를 빠르게 찾고 핵심 사용자 흐름이 깨지지 않도록 테스트 의도를 코드 가까이에 둡니다.
//  테스트 데이터와 시뮬레이터 환경 차이에 따라 결과가 달라질 수 있어 고정 fixture와 명확한 대기 조건을 우선합니다.
//  TODO : 반복 실패가 발견되면 원인별 fixture와 경계 케이스를 보강합니다.
//  kboScoreUITests
//
//  Created by 조경민 on 3/25/26.
//

import XCTest

final class kboScoreUITests: XCTestCase {

    // setUpWithError 메서드는 이 타입의 주요 동작을 수행합니다.
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    // tearDownWithError 메서드는 이 타입의 주요 동작을 수행합니다.
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // testExample 메서드는 이 타입의 주요 동작을 수행합니다.
    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    // testLaunchPerformance 메서드는 이 타입의 주요 동작을 수행합니다.
    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
