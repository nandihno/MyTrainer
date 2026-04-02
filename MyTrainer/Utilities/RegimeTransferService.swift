import Foundation
import SwiftData

struct RegimeExportPayload: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let appVersion: String?
    let exercises: [ExerciseExportRecord]
    let scheduledExercises: [ScheduledExerciseExportRecord]
    let dailyExercises: [DailyExerciseExportRecord]
}

struct ExerciseExportRecord: Codable, Identifiable {
    let id: UUID
    let name: String
    let appleWorkoutType: Int
    let defaultSets: Int
    let defaultReps: Int
    let defaultDurationSeconds: Int
    let notes: String
}

struct ScheduledExerciseExportRecord: Codable, Identifiable {
    let id: UUID
    let exerciseID: UUID
    let dayOfWeek: Int
    let orderIndex: Int
    let sets: Int
    let reps: Int
    let durationSeconds: Int
    let isAlternative: Bool
}

struct DailyExerciseExportRecord: Codable, Identifiable {
    let id: UUID
    let exerciseID: UUID
    let date: Date
    let sets: Int
    let reps: Int
    let durationSeconds: Int
    let orderIndex: Int
    let scheduledExerciseID: UUID?
}

struct RegimeImportPreview {
    let payload: RegimeExportPayload

    var exerciseCount: Int { payload.exercises.count }
    var scheduledExerciseCount: Int { payload.scheduledExercises.count }
    var dailyExerciseCount: Int { payload.dailyExercises.count }
}

enum RegimeTransferError: LocalizedError {
    case noRegimeData
    case unsupportedFormatVersion(Int)
    case scheduledExerciseMissingExercise(UUID)
    case dailyExerciseMissingExercise(UUID)
    case dailyExerciseMissingScheduledExercise(UUID)

    var errorDescription: String? {
        switch self {
        case .noRegimeData:
            return "There is no regime data to export yet."
        case .unsupportedFormatVersion(let version):
            return "This file uses an unsupported regime format version (\(version))."
        case .scheduledExerciseMissingExercise:
            return "The regime file contains a scheduled workout that references a missing exercise."
        case .dailyExerciseMissingExercise:
            return "The regime file contains a daily workout that references a missing exercise."
        case .dailyExerciseMissingScheduledExercise:
            return "The regime file contains a daily override that references a missing scheduled workout."
        }
    }
}

struct RegimeTransferService {
    static let currentFormatVersion = 1

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func makeExportFile(
        exercises: [Exercise],
        scheduledExercises: [ScheduledExercise],
        dailyExercises: [DailyExercise]
    ) throws -> URL {
        guard !(exercises.isEmpty && scheduledExercises.isEmpty && dailyExercises.isEmpty) else {
            throw RegimeTransferError.noRegimeData
        }

        let payload = try buildPayload(
            exercises: exercises,
            scheduledExercises: scheduledExercises,
            dailyExercises: dailyExercises
        )
        let data = try encoder.encode(payload)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"

        let fileName = "MyTrainer-Regime-\(formatter.string(from: Date())).mytrainer-regime.json"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func previewImport(from data: Data) throws -> RegimeImportPreview {
        let payload = try decoder.decode(RegimeExportPayload.self, from: data)
        try validate(payload: payload)
        return RegimeImportPreview(payload: payload)
    }

    @discardableResult
    func importPayload(_ payload: RegimeExportPayload, into modelContext: ModelContext) throws -> RegimeImportPreview {
        try validate(payload: payload)

        var insertedExercises: [Exercise] = []
        var insertedScheduledExercises: [ScheduledExercise] = []
        var insertedDailyExercises: [DailyExercise] = []

        do {
            var importedExercises: [UUID: Exercise] = [:]
            for record in payload.exercises {
                let exercise = Exercise(
                    name: record.name,
                    appleWorkoutType: record.appleWorkoutType,
                    defaultSets: record.defaultSets,
                    defaultReps: record.defaultReps,
                    defaultDurationSeconds: record.defaultDurationSeconds,
                    notes: record.notes
                )
                modelContext.insert(exercise)
                insertedExercises.append(exercise)
                importedExercises[record.id] = exercise
            }

            var importedScheduledExercises: [UUID: ScheduledExercise] = [:]
            for record in payload.scheduledExercises {
                guard let exercise = importedExercises[record.exerciseID] else {
                    throw RegimeTransferError.scheduledExerciseMissingExercise(record.id)
                }

                let scheduledExercise = ScheduledExercise(
                    exercise: exercise,
                    dayOfWeek: record.dayOfWeek,
                    orderIndex: record.orderIndex,
                    sets: record.sets,
                    reps: record.reps,
                    durationSeconds: record.durationSeconds,
                    isAlternative: record.isAlternative
                )
                modelContext.insert(scheduledExercise)
                insertedScheduledExercises.append(scheduledExercise)
                importedScheduledExercises[record.id] = scheduledExercise
            }

            for record in payload.dailyExercises {
                guard let exercise = importedExercises[record.exerciseID] else {
                    throw RegimeTransferError.dailyExerciseMissingExercise(record.id)
                }

                let dailyExercise = DailyExercise(
                    exercise: exercise,
                    date: record.date,
                    sets: record.sets,
                    reps: record.reps,
                    durationSeconds: record.durationSeconds,
                    orderIndex: record.orderIndex
                )

                if let exportedScheduledID = record.scheduledExerciseID {
                    guard let importedScheduled = importedScheduledExercises[exportedScheduledID] else {
                        throw RegimeTransferError.dailyExerciseMissingScheduledExercise(record.id)
                    }
                    dailyExercise.scheduledExerciseID = importedScheduled.id
                }

                modelContext.insert(dailyExercise)
                insertedDailyExercises.append(dailyExercise)
            }

            try modelContext.save()
            return RegimeImportPreview(payload: payload)
        } catch {
            rollbackImports(
                exercises: insertedExercises,
                scheduledExercises: insertedScheduledExercises,
                dailyExercises: insertedDailyExercises,
                in: modelContext
            )
            throw error
        }
    }

    private func buildPayload(
        exercises: [Exercise],
        scheduledExercises: [ScheduledExercise],
        dailyExercises: [DailyExercise]
    ) throws -> RegimeExportPayload {
        let sortedExercises = exercises.sorted { lhs, rhs in
            if lhs.name == rhs.name {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let exerciseRecords = sortedExercises.map { exercise in
            ExerciseExportRecord(
                id: exercise.id,
                name: exercise.name,
                appleWorkoutType: exercise.appleWorkoutType,
                defaultSets: exercise.defaultSets,
                defaultReps: exercise.defaultReps,
                defaultDurationSeconds: exercise.defaultDurationSeconds,
                notes: exercise.notes
            )
        }

        let scheduledRecords = try scheduledExercises
            .sorted { lhs, rhs in
                scheduledSort(lhs: lhs, rhs: rhs)
            }
            .map { scheduledExercise in
                guard let exerciseID = scheduledExercise.exercise?.id else {
                    throw RegimeTransferError.scheduledExerciseMissingExercise(scheduledExercise.id)
                }

                return ScheduledExerciseExportRecord(
                    id: scheduledExercise.id,
                    exerciseID: exerciseID,
                    dayOfWeek: scheduledExercise.dayOfWeek,
                    orderIndex: scheduledExercise.orderIndex,
                    sets: scheduledExercise.sets,
                    reps: scheduledExercise.reps,
                    durationSeconds: scheduledExercise.durationSeconds,
                    isAlternative: scheduledExercise.isAlternative
                )
            }

        let dailyRecords = try dailyExercises
            .sorted { lhs, rhs in
                dailySort(lhs: lhs, rhs: rhs)
            }
            .map { dailyExercise in
                guard let exerciseID = dailyExercise.exercise?.id else {
                    throw RegimeTransferError.dailyExerciseMissingExercise(dailyExercise.id)
                }

                return DailyExerciseExportRecord(
                    id: dailyExercise.id,
                    exerciseID: exerciseID,
                    date: dailyExercise.date,
                    sets: dailyExercise.sets,
                    reps: dailyExercise.reps,
                    durationSeconds: dailyExercise.durationSeconds,
                    orderIndex: dailyExercise.orderIndex,
                    scheduledExerciseID: dailyExercise.scheduledExerciseID
                )
            }

        return RegimeExportPayload(
            formatVersion: Self.currentFormatVersion,
            exportedAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            exercises: exerciseRecords,
            scheduledExercises: scheduledRecords,
            dailyExercises: dailyRecords
        )
    }

    private func validate(payload: RegimeExportPayload) throws {
        guard payload.formatVersion == Self.currentFormatVersion else {
            throw RegimeTransferError.unsupportedFormatVersion(payload.formatVersion)
        }

        let exerciseIDs = Set(payload.exercises.map(\.id))
        let scheduledIDs = Set(payload.scheduledExercises.map(\.id))

        for scheduledExercise in payload.scheduledExercises {
            guard exerciseIDs.contains(scheduledExercise.exerciseID) else {
                throw RegimeTransferError.scheduledExerciseMissingExercise(scheduledExercise.id)
            }
        }

        for dailyExercise in payload.dailyExercises {
            guard exerciseIDs.contains(dailyExercise.exerciseID) else {
                throw RegimeTransferError.dailyExerciseMissingExercise(dailyExercise.id)
            }

            if let scheduledExerciseID = dailyExercise.scheduledExerciseID,
               !scheduledIDs.contains(scheduledExerciseID) {
                throw RegimeTransferError.dailyExerciseMissingScheduledExercise(dailyExercise.id)
            }
        }
    }

    private func scheduledSort(lhs: ScheduledExercise, rhs: ScheduledExercise) -> Bool {
        if lhs.dayOfWeek != rhs.dayOfWeek {
            return lhs.dayOfWeek < rhs.dayOfWeek
        }
        if lhs.isAlternative != rhs.isAlternative {
            return lhs.isAlternative == false
        }
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func dailySort(lhs: DailyExercise, rhs: DailyExercise) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func rollbackImports(
        exercises: [Exercise],
        scheduledExercises: [ScheduledExercise],
        dailyExercises: [DailyExercise],
        in modelContext: ModelContext
    ) {
        for dailyExercise in dailyExercises {
            modelContext.delete(dailyExercise)
        }

        for scheduledExercise in scheduledExercises {
            modelContext.delete(scheduledExercise)
        }

        for exercise in exercises {
            modelContext.delete(exercise)
        }

        try? modelContext.save()
    }
}
