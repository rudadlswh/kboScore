//
//  KBOScoreLiveActivityWidgetBundle.swift
//  kboScoreLiveActivityExtension
//
//  Created by Codex on 3/26/26.
//

import SwiftUI
import WidgetKit

@main
struct KBOScoreLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        FavoriteTeamScheduleWidgetV2()
        KBOScoreLiveActivityWidget()
    }
}
