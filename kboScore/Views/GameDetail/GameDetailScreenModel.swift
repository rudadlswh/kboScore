//
//  GameDetailScreenModel.swift
//  kboScore
//
//  Created by Codex on 4/8/26.
//

import Foundation
import Observation

enum GameDetailSection: String, CaseIterable, Identifiable {
    case overview = "개요"
    case review = "리뷰"
    case preview = "프리뷰"

    var id: String { rawValue }

    static func availableSections(for status: GameStatus) -> [GameDetailSection] {
        switch status {
        case .upcoming:
            [.overview, .preview]
        case .live, .final, .rainDelay, .cancelled:
            [.overview, .review]
        }
    }
}

@MainActor
@Observable
final class GameDetailScreenModel {
    private let client: OfficialKBOGameCenterClient
    private var lastLoadedGameKey: String?

    var selectedSection: GameDetailSection = .overview
    var detail: GameCenterDetailPayload?
    var isLoading = false
    var errorMessage: String?
    var hasAttemptedLoad = false

    init(client: OfficialKBOGameCenterClient? = nil) {
        self.client = client ?? OfficialKBOGameCenterClient()
    }

    func syncSelection(for status: GameStatus) {
        let availableSections = GameDetailSection.availableSections(for: status)
        guard availableSections.contains(selectedSection) == false else { return }
        selectedSection = availableSections.contains(.preview) ? .preview : .review
    }

    func load(for game: GameDetail, forceRefresh: Bool = false) async {
        let gameKey = [game.id.uuidString, game.officialGameCenterID ?? ""].joined(separator: "::")
        guard forceRefresh || lastLoadedGameKey != gameKey else { return }

        isLoading = true
        errorMessage = nil
        hasAttemptedLoad = true

        do {
            detail = try await client.fetchDetail(for: game)
            lastLoadedGameKey = gameKey
        } catch {
            detail = nil
            errorMessage = "공식 경기 상세 정보를 불러오지 못했습니다."
        }

        isLoading = false
    }
}
