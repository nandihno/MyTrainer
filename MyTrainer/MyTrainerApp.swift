import SwiftUI
import SwiftData

@main
struct MyTrainerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Exercise.self, ScheduledExercise.self, CompletedSet.self])
    }
}
