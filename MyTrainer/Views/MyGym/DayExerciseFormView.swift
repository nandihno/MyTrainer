import SwiftUI
import SwiftData

struct DayExerciseFormView: View {
    enum Mode: Identifiable {
        case add
        case edit(DayExerciseItem)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let item): return item.id
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let date: Date
    let existingOrderCount: Int
    let allExercises: [Exercise]

    @State private var selectedExercise: Exercise?
    @State private var sets: Int = 3
    @State private var reps: Int = 10
    @State private var isTimeBased: Bool = false
    @State private var durationMinutes: Int = 1
    @State private var durationText: String = "1"

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingItem: DayExerciseItem? {
        if case .edit(let item) = mode { return item }
        return nil
    }

    private var title: String {
        isEditing ? "Edit for Today" : "Add for Today"
    }

    private var canSave: Bool {
        selectedExercise != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    // Exercise picker (only when adding)
                    Section("Exercise") {
                        Picker("Choose exercise", selection: $selectedExercise) {
                            Text("Select an exercise").tag(nil as Exercise?)
                            ForEach(exercisesByType, id: \.0.id) { (typeInfo, exercises) in
                                Section(typeInfo.displayName) {
                                    ForEach(exercises) { exercise in
                                        Label(exercise.name, systemImage: typeInfo.symbol)
                                            .foregroundStyle(typeInfo.color)
                                            .tag(exercise as Exercise?)
                                    }
                                }
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .onChange(of: selectedExercise) { _, newExercise in
                            if let ex = newExercise {
                                prefillFromExercise(ex)
                            }
                        }
                    }
                } else {
                    // Show the exercise name when editing (read-only)
                    Section("Exercise") {
                        HStack {
                            if let info = editingTypeInfo {
                                Image(systemName: info.symbol)
                                    .foregroundStyle(info.color)
                            }
                            Text(selectedExercise?.name ?? "Unknown")
                                .font(.headline)
                        }
                    }
                }

                Section("Today's Settings") {
                    Text("Changes only apply to \(formattedDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)

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

                if isEditing, let item = editingItem {
                    Section {
                        if item.dailyExercise?.isOneOff == true {
                            Button("Remove from Today", role: .destructive) {
                                removeOneOff(item)
                            }
                        } else if item.dailyExercise != nil {
                            Button("Reset to Template", role: .destructive) {
                                resetOverride(item)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    // MARK: - Grouped exercises for picker

    private var exercisesByType: [(WorkoutTypeInfo, [Exercise])] {
        let grouped = Dictionary(grouping: allExercises) { $0.appleWorkoutType }
        return grouped.compactMap { typeID, exercises in
            guard let info = WorkoutTypeInfo.info(for: typeID) else { return nil }
            return (info, exercises.sorted { $0.name < $1.name })
        }
        .sorted { $0.0.displayName < $1.0.displayName }
    }

    private var editingTypeInfo: WorkoutTypeInfo? {
        guard let ex = selectedExercise else { return nil }
        return WorkoutTypeInfo.info(for: ex.appleWorkoutType)
    }

    private var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: date)
    }

    // MARK: - Load

    private func loadExisting() {
        guard let item = editingItem else { return }
        selectedExercise = item.exercise
        sets = item.sets
        reps = item.reps
        isTimeBased = item.isTimeBased
        if item.isTimeBased {
            durationMinutes = max(1, item.durationSeconds / 60)
            durationText = "\(durationMinutes)"
        }
    }

    private func prefillFromExercise(_ exercise: Exercise) {
        sets = exercise.defaultSets
        isTimeBased = exercise.isTimeBased
        if exercise.isTimeBased {
            reps = 0
            durationMinutes = max(1, exercise.defaultDurationSeconds / 60)
            durationText = "\(durationMinutes)"
        } else {
            reps = exercise.defaultReps
        }
    }

    // MARK: - Save

    private func save() {
        guard let exercise = selectedExercise else { return }

        let durationSeconds = isTimeBased ? durationMinutes * 60 : 0
        let finalReps = isTimeBased ? 0 : reps

        if let item = editingItem {
            // Editing existing
            if let daily = item.dailyExercise {
                // Already has a DailyExercise record — update it
                daily.sets = sets
                daily.reps = finalReps
                daily.durationSeconds = durationSeconds
            } else if let scheduled = item.scheduledExercise {
                // Template entry — create an override DailyExercise
                let override = DailyExercise(
                    exercise: exercise,
                    date: date,
                    sets: sets,
                    reps: finalReps,
                    durationSeconds: durationSeconds,
                    orderIndex: item.orderIndex,
                    scheduledExerciseID: scheduled.id
                )
                modelContext.insert(override)
            }
        } else {
            // Adding new one-off
            let daily = DailyExercise(
                exercise: exercise,
                date: date,
                sets: sets,
                reps: finalReps,
                durationSeconds: durationSeconds,
                orderIndex: existingOrderCount
            )
            modelContext.insert(daily)
        }

        dismiss()
    }

    // MARK: - Delete / Reset

    private func removeOneOff(_ item: DayExerciseItem) {
        if let daily = item.dailyExercise {
            modelContext.delete(daily)
        }
        dismiss()
    }

    private func resetOverride(_ item: DayExerciseItem) {
        if let daily = item.dailyExercise {
            modelContext.delete(daily)
        }
        dismiss()
    }
}
