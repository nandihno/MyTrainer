import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    // Single active sheet to avoid double-presentation conflicts
    @State private var activeSheet: LibrarySheet?

    private enum LibrarySheet: Identifiable {
        case addExercise
        case editExercise(Exercise)
        case addToSchedule(dayOfWeek: Int, isAlternative: Bool)

        var id: String {
            switch self {
            case .addExercise: return "add"
            case .editExercise(let e): return "edit-\(e.id)"
            case .addToSchedule(let d, let alt): return "schedule-\(d)-\(alt)"
            }
        }
    }

    private var groupedExercises: [(WorkoutTypeInfo, [Exercise])] {
        let grouped = Dictionary(grouping: exercises) { $0.appleWorkoutType }
        return grouped
            .compactMap { (rawValue, exercises) -> (WorkoutTypeInfo, [Exercise])? in
                guard let info = WorkoutTypeInfo.info(for: rawValue) else { return nil }
                return (info, exercises.sorted { $0.name < $1.name })
            }
            .sorted { $0.0.displayName < $1.0.displayName }
    }

    var body: some View {
        NavigationStack {
            List {
                if exercises.isEmpty {
                    ContentUnavailableView {
                        Label("No exercises", systemImage: "dumbbell")
                    } description: {
                        Text("Tap + to add your first exercise")
                    }
                } else {
                    ForEach(groupedExercises, id: \.0.id) { (typeInfo, typeExercises) in
                        Section {
                            DisclosureGroup {
                                ForEach(typeExercises) { exercise in
                                    Button {
                                        activeSheet = .editExercise(exercise)
                                    } label: {
                                        exerciseRow(exercise, typeInfo: typeInfo)
                                    }
                                    .tint(.primary)
                                }
                                .onDelete { offsets in
                                    deleteExercises(typeExercises, at: offsets)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: typeInfo.symbol)
                                        .foregroundStyle(typeInfo.color)
                                    Text(typeInfo.displayName)
                                        .font(.headline)
                                        .foregroundStyle(typeInfo.color)
                                    Spacer()
                                    Text("\(typeExercises.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    WeeklyScheduleEditorView(onAddExercise: { day, isAlternative in
                        activeSheet = .addToSchedule(dayOfWeek: day, isAlternative: isAlternative)
                    })
                } header: {
                    Text("Weekly Schedule")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.appBackground))
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        activeSheet = .addExercise
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .addExercise:
                    ExerciseFormView(exerciseToEdit: nil)
                case .editExercise(let exercise):
                    ExerciseFormView(exerciseToEdit: exercise)
                case .addToSchedule(let day, let isAlternative):
                    AddToScheduleSheet(dayOfWeek: day, exercises: exercises, isAlternative: isAlternative)
                }
            }
        }
    }

    private func exerciseRow(_ exercise: Exercise, typeInfo: WorkoutTypeInfo) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(typeInfo.color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading) {
                Text(exercise.name)
                    .font(.body)

                Text(exerciseSubtitle(exercise))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func exerciseSubtitle(_ exercise: Exercise) -> String {
        if exercise.isTimeBased {
            let dur = exercise.defaultDurationSeconds
            let formatted: String
            if dur >= 60 {
                let m = dur / 60
                let s = dur % 60
                formatted = s == 0 ? "\(m)m" : "\(m)m \(s)s"
            } else {
                formatted = "\(dur)s"
            }
            return "\(exercise.defaultSets) sets \u{00D7} \(formatted)"
        } else {
            return "\(exercise.defaultSets) sets \u{00D7} \(exercise.defaultReps) reps"
        }
    }

    private func deleteExercises(_ exercises: [Exercise], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(exercises[index])
        }
    }
}
