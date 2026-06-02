import Foundation

struct AttendanceKeyResolver {
    static func equivalentKeys(for game: GameDetail, equivalentGames: [GameDetail]) -> Set<String> {
        var keys = game.attendanceStorageAliases

        for candidate in equivalentGames {
            keys.formUnion(candidate.attendanceStorageAliases)
        }

        return keys
    }

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

    static func isAttended(
        game: GameDetail,
        equivalentGames: [GameDetail],
        attendedKeys: Set<String>
    ) -> Bool {
        attendedKeys.isDisjoint(with: equivalentKeys(for: game, equivalentGames: equivalentGames)) == false
    }

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
