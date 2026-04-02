import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private struct ShareSheetFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PendingRegimeImport: Identifiable {
    let id = UUID()
    let fileName: String
    let payload: RegimeExportPayload
    let preview: RegimeImportPreview
}

private struct LibraryTransferAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \ScheduledExercise.dayOfWeek) private var scheduledExercises: [ScheduledExercise]
    @Query(sort: \DailyExercise.date) private var dailyExercises: [DailyExercise]

    // Single active sheet to avoid double-presentation conflicts
    @State private var activeSheet: LibrarySheet?
    @State private var exportFile: ShareSheetFile?
    @State private var pendingImport: PendingRegimeImport?
    @State private var transferAlert: LibraryTransferAlert?
    @State private var isImportingRegime = false

    private let regimeTransferService = RegimeTransferService()

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

    private var canExportRegime: Bool {
        !(exercises.isEmpty && scheduledExercises.isEmpty && dailyExercises.isEmpty)
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            exportRegime()
                        } label: {
                            Label("Export Regime", systemImage: "square.and.arrow.up")
                        }
                        .disabled(!canExportRegime)

                        Button {
                            isImportingRegime = true
                        } label: {
                            Label("Import Regime", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }

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
            .sheet(item: $exportFile) { shareFile in
                ActivityShareSheet(activityItems: [shareFile.url])
            }
            .sheet(item: $pendingImport) { pending in
                importSummarySheet(for: pending)
            }
            .fileImporter(
                isPresented: $isImportingRegime,
                allowedContentTypes: [.json]
            ) { result in
                handleImportedFile(result)
            }
            .alert(item: $transferAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func importSummarySheet(for pending: PendingRegimeImport) -> some View {
        NavigationStack {
            Form {
                Section("File") {
                    Text(pending.fileName)
                        .textSelection(.enabled)
                }

                Section("Import Summary") {
                    LabeledContent("Exercises", value: "\(pending.preview.exerciseCount)")
                    LabeledContent("Weekly Schedule", value: "\(pending.preview.scheduledExerciseCount)")
                    LabeledContent("Daily Workouts", value: "\(pending.preview.dailyExerciseCount)")
                }

                Section {
                    Text("Importing will add a separate copy of this regime. Your current data will stay unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import Regime")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        pendingImport = nil
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importRegime(pending)
                    }
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

    private func exportRegime() {
        do {
            let fileURL = try regimeTransferService.makeExportFile(
                exercises: exercises,
                scheduledExercises: scheduledExercises,
                dailyExercises: dailyExercises
            )
            exportFile = ShareSheetFile(url: fileURL)
        } catch {
            presentTransferError(title: "Export Failed", error: error)
        }
    }

    private func handleImportedFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let hasScopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasScopedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                let preview = try regimeTransferService.previewImport(from: data)
                pendingImport = PendingRegimeImport(
                    fileName: url.lastPathComponent,
                    payload: preview.payload,
                    preview: preview
                )
            } catch {
                presentTransferError(title: "Import Failed", error: error)
            }

        case .failure(let error):
            guard !isUserCancelled(error) else { return }
            presentTransferError(title: "Import Failed", error: error)
        }
    }

    private func importRegime(_ pending: PendingRegimeImport) {
        do {
            let preview = try regimeTransferService.importPayload(pending.payload, into: modelContext)
            pendingImport = nil
            transferAlert = LibraryTransferAlert(
                title: "Import Complete",
                message: "Imported \(preview.exerciseCount) exercises, \(preview.scheduledExerciseCount) weekly schedule entries, and \(preview.dailyExerciseCount) daily workouts."
            )
        } catch {
            presentTransferError(title: "Import Failed", error: error)
        }
    }

    private func presentTransferError(title: String, error: Error) {
        transferAlert = LibraryTransferAlert(
            title: title,
            message: error.localizedDescription
        )
    }

    private func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }
}
