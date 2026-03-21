import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("My Gym", systemImage: "figure.strengthtraining.traditional") {
                MyGymView()
            }

            Tab("Reports", systemImage: "chart.bar.fill") {
                ReportsView()
            }

            Tab("Library", systemImage: "books.vertical.fill") {
                LibraryView()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Exercise.self, ScheduledExercise.self, CompletedSet.self], inMemory: true)
}
