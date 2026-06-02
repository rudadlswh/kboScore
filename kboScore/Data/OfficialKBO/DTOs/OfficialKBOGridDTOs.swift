//
//  OfficialKBOGridDTOs.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

struct OfficialGridCellDTO: Decodable {
    let text: String

    private enum CodingKeys: String, CodingKey {
        case text = "Text"
    }
}
