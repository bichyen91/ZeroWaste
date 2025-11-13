//
//  ZeroWasteApp.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 6/9/25.
//

import SwiftUI
import SwiftData

@main
struct ZeroWasteApp: App {
    var body: some Scene {
        WindowGroup {
            LoginView()
                .modelContainer(for: [User.self, Item.self])
        }
    }
    
    init(){
        Task { _ = await NotificationManager.shared.requestAuthorization() }
        print(URL.applicationDirectory.path(percentEncoded: false))
    }
}
