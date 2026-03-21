import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var showingAddExercise = false
    @State private var exerciseToEdit: Exercise?

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
                                        exerciseToEdit = exercise
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
                    WeeklyScheduleEditorView()
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
                        showingAddExercise = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddExercise) {
                ExerciseFormView(exerciseToEdit: nil)
            }
            .sheet(item: $exerciseToEdit) { exercise in
                ExerciseFormView(exerciseToEdit: exercise)
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
