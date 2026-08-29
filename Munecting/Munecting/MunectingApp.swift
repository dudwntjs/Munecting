//
//  MunectingApp.swift
//  Munecting
//
//  Created by sun on 8/11/26.
//

import SwiftUI
import SwiftData

@main
struct MunectingApp: App {
    private let container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
        .modelContainer(container.modelContainer)
    }
}
