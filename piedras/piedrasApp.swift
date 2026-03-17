//
//  piedrasApp.swift
//  piedras
//
//  Created by Guinsoo on 2026/3/17.
//

import SwiftUI
import CoreData

@main
struct piedrasApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
