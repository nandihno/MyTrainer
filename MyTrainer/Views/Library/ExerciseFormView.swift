import SwiftUI
import SwiftData
import HealthKit

struct ExerciseFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let exerciseToEdit: Exercise?

    @State private var name: String = ""
    @State private var selectedWorkoutType: Int = Int(HKWorkoutActivityType.traditionalStrengthTraining.rawValue)
    @State private var isTimeBased: Bool = false
    @State private var sets: Int = 3
    @State private var reps: Int = 10
    @State private var durationMinutes: Int = 1
    @State private var notes: String = ""
    @State private var durationText: String = "1"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise Name", text: $name)
                }

                Section("Workout Type") {
                    Picker("Type", selection: $selectedWorkoutType) {
                        ForEach(WorkoutTypeInfo.allTypes) { info in
                            Label(info.displayName, systemImage: info.symbol)
                                .foregroundStyle(info.color)
                                .tag(info.typeID)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Exercise Type") {
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

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(exerciseToEdit == nil ? "New Exercise" : "Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private func loadExisting() {
        guard let exercise = exerciseToEdit else { return }
        name = exercise.name
        selectedWorkoutType = exercise.appleWorkoutType
        isTimeBased = exercise.isTimeBased
        sets = exercise.defaultSets
        reps = exercise.defaultReps
        durationMinutes = max(1, exercise.defaultDurationSeconds / 60)
        durationText = "\(durationMinutes)"
        notes = exercise.notes
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let durationSeconds = isTimeBased ? durationMinutes * 60 : 0

        if let exercise = exerciseToEdit {
            exercise.name = trimmedName
            exercise.appleWorkoutType = selectedWorkoutType
            exercise.defaultSets = sets
            exercise.defaultReps = isTimeBased ? 0 : reps
            exercise.defaultDurationSeconds = durationSeconds
            exercise.notes = notes
        } else {
            let exercise = Exercise(
                name: trimmedName,
                appleWorkoutType: selectedWorkoutType,
                defaultSets: sets,
                defaultReps: isTimeBased ? 0 : reps,
                defaultDurationSeconds: durationSeconds,
                notes: notes
            )
            modelContext.insert(exercise)
        }

        dismiss()
    }
}
