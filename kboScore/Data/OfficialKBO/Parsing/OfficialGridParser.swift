//
//  OfficialGridParser.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

extension OfficialKBOGameCenterClient {
    func decodeGridTable(from rawValue: String) -> OfficialGridTable? {
        guard let data = rawValue.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(OfficialGridTableDTO.self, from: data).table
    }
}
