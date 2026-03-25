import SwiftUI
import SwiftData

struct WeeklyScheduleEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allScheduledExercises: [ScheduledExercise]
    @Query private var allExercises: [Exercise]

    /// Callback to request showing the "Add to Schedule" sheet for a given day.
    /// Presenting is handled by the parent (LibraryView) to avoid double-sheet conflicts.
    var onAddExercise: (Int) -> Void

    private let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    private func exercises(for day: Int) -> [ScheduledExercise] {
        allScheduledExercises
            .filter { $0.dayOfWeek == day }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        ForEach(1...7, id: \.self) { day in
            DisclosureGroup {
                let dayExercises = exercises(for: day)
                if dayExercises.isEmpty {
                    Text("No exercises")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(dayExercises) { scheduled in
                        scheduledRow(scheduled)
                    }
                    .onDelete { offsets in
                        deleteExercises(for: day, at: offsets)
                    }
                    .onMove { source, destination in
                        moveExercises(for: day, from: source, to: destination)
                    }
                }

                Button {
                    onAddExercise(day)
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                        .font(.subheadline)
                }
                .disabled(allExercises.isEmpty)
            } label: {
                HStack {
                    Text(dayNames[day - 1])
                        .font(.headline)
                    Spacer()
                    Text("\(exercises(for: day).count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func scheduledRow(_ scheduled: ScheduledExercise) -> some View {
        HStack {
            if let info = WorkoutTypeInfo.info(for: scheduled.exercise?.appleWorkoutType ?? 0) {
                Circle()
                    .fill(info.color)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading) {
                Text(scheduled.exercise?.name ?? "Unknown")
                    .font(.body)
                Text(scheduled.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
        }
    }

    private func moveExercises(for day: Int, from source: IndexSet, to destination: Int) {
        var dayExercises = exercises(for: day)
        dayExercises.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in dayExercises.enumerated() {
            exercise.orderIndex = index
        }
    }

    private func deleteExercises(for day: Int, at offsets: IndexSet) {
        let dayExercises = exercises(for: day)
        for index in offsets {
            modelContext.delete(dayExercises[index])
        }
    }
}

struct AddToScheduleSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let dayOfWeek: Int
    let exercises: [Exercise]

    @State private var selectedExercise: Exercise?
    @State private var sets: Int = 3
    @State private var reps: Int = 10
    @State private var durationMinutes: Int = 1
    @State private var durationText: String = "1"
    @State private var isTimeBased: Bool = false

    @Query private var allScheduledExercises: [ScheduledExercise]

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    Picker("Exercise", selection: $selectedExercise) {
                        Text("Select an exercise").tag(nil as Exercise?)
                        ForEach(exercises.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { exercise in
                            Text(exercise.name).tag(exercise as Exercise?)
                        }
                    }
                }

                if selectedExercise != nil {
                    Section("Override Defaults") {
                        Picker("Mode", selection: $isTimeBased) {
                            Text("Reps-based").tag(false)
                            Text("Time-based").tag(true)
                        }
                        .pickerStyle(.segmented)

                        Stepper("Sets: \(sets)", value: $sets, in: 1...20)

                        if isTimeBased {
                            HStack {
                                Text("Duration")
                                Spacer()
                                TextField("min", text: $durationText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                                    .onChange(of: durationText) { _, newValue in
                                        let filtered = newValue.filter(\.isNumber)
                                        if filtered != newValue { durationText = filtered }
                                        durationMinutes = max(1, Int(filtered) ?? 1)
                                    }
                                Text("min")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Stepper("Reps: \(reps)", value: $reps, in: 1...100)
                        }
                    }
                }
            }
            .navigationTitle("Add to Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addToSchedule() }
                        .disabled(selectedExercise == nil)
                }
            }
            .onChange(of: selectedExercise) { _, newValue in
                if let ex = newValue {
                    sets = ex.defaultSets
                    reps = ex.defaultReps
                    isTimeBased = ex.isTimeBased
                    durationMinutes = max(1, ex.defaultDurationSeconds / 60)
                    durationText = "\(durationMinutes)"
                }
            }
        }
    }

    private func addToSchedule() {
        guard let exercise = selectedExercise else { return }
        let currentCount = allScheduledExercises.filter { $0.dayOfWeek == dayOfWeek }.count
        let scheduled = ScheduledExercise(
            exercise: exercise,
            dayOfWeek: dayOfWeek,
            orderIndex: currentCount,
            sets: sets,
            reps: isTimeBased ? 0 : reps,
            durationSeconds: isTimeBased ? durationMinutes * 60 : 0
        )
        modelContext.insert(scheduled)
        dismiss()
    }
}
