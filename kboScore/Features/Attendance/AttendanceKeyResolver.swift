//  기능 설명: 직관 기록 저장에 사용할 안정적인 경기 키를 생성합니다.
//  직관 기록 저장에 사용할 안정적인 경기 키를 생성합니다.을 명확히 분리해 변경 범위와 책임을 예측 가능하게 유지합니다.
//  입력 데이터 누락, 비동기 실행 순서, 플랫폼별 동작 차이를 고려해 방어적으로 처리합니다.
//  TODO : 반복되는 정책이나 화면 상태가 늘어나면 전용 모델과 테스트로 분리합니다.
import Foundation

// AttendanceKeyResolver 구조체는 입력 상태를 해석해 필요한 결과 값을 결정합니다.
struct AttendanceKeyResolver {
    // equivalentKeys 메서드는 이 타입의 주요 동작을 수행합니다.
    static func equivalentKeys(for game: GameDetail, equivalentGames: [GameDetail]) -> Set<String> {
        var keys = game.attendanceStorageAliases

        for candidate in equivalentGames {
            keys.formUnion(candidate.attendanceStorageAliases)
        }

        return keys
    }

    // canonicalStorageKey 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    static func canonicalStorageKey(for game: GameDetail, equivalentKeys: Set<String>) -> String {
        if let providerKey = equivalentKeys
            .filter({ $0.hasPrefix("provider:") })
            .sorted()
            .first(where: { key in
                let value = String(key.dropFirst("provider:".count))
                return UUID(uuidString: value) == nil
            }) {
            return providerKey
        }
        return game.attendanceStorageKey
    }

    // isAttended 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    static func isAttended(
        game: GameDetail,
        equivalentGames: [GameDetail],
        attendedKeys: Set<String>
    ) -> Bool {
        attendedKeys.isDisjoint(with: equivalentKeys(for: game, equivalentGames: equivalentGames)) == false
    }

    // toggledKeys 메서드는 이 타입의 주요 동작을 수행합니다.
    static func toggledKeys(
        for game: GameDetail,
        equivalentGames: [GameDetail],
        attendedKeys: Set<String>
    ) -> Set<String> {
        var updatedKeys = attendedKeys
        let equivalentKeys = equivalentKeys(for: game, equivalentGames: equivalentGames)
        let key = canonicalStorageKey(for: game, equivalentKeys: equivalentKeys)
        let isAttended = updatedKeys.isDisjoint(with: equivalentKeys) == false
        if isAttended {
            updatedKeys.subtract(equivalentKeys)
        } else {
            updatedKeys.insert(key)
        }
        return updatedKeys
    }
}
