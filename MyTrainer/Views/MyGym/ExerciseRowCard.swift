import SwiftUI
import SwiftData

struct ExerciseRowCard: View {
    let item: DayExerciseItem
    let completedSets: [CompletedSet]
    let onToggleSet: (Int) -> Void
    let onAddBonus: () -> Void
    let onEdit: () -> Void

    private var typeInfo: WorkoutTypeInfo? {
        guard let exercise = item.exercise else { return nil }
        return WorkoutTypeInfo.info(for: exercise.appleWorkoutType)
    }

    private var accentColor: Color {
        typeInfo?.color ?? .gray
    }

    private var completedSetNumbers: Set<Int> {
        Set(completedSets.filter { !$0.isBonus }.map(\.setNumber))
    }

    private var bonusSets: [CompletedSet] {
        completedSets.filter(\.isBonus).sorted { $0.setNumber < $1.setNumber }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(width: 4)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.exercise?.name ?? "Unknown")
                                .font(.headline)

                            // Badge for customised entries
                            if item.isCustomised {
                                Text(item.dailyExercise?.isOneOff == true ? "Today only" : "Edited")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(accentColor.opacity(0.6))
                                    )
                            }
                        }

                        Text(item.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        if let info = typeInfo {
                            Label(info.displayName, systemImage: info.symbol)
                                .font(.caption)
                                .foregroundStyle(accentColor)
                        }

                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "pencil.circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Set bubbles
                HStack(spacing: 6) {
                    ForEach(1...max(item.sets, 1), id: \.self) { setNum in
                        SetBubbleView(
                            setNumber: setNum,
                            isCompleted: completedSetNumbers.contains(setNum),
                            isBonus: false,
                            color: accentColor,
                            action: { onToggleSet(setNum) }
                        )
                    }

                    ForEach(bonusSets) { bonus in
                        SetBubbleView(
                            setNumber: bonus.setNumber,
                            isCompleted: true,
                            isBonus: true,
                            color: accentColor.opacity(0.7),
                            action: {}
                        )
                    }

                    Button {
                        onAddBonus()
                    } label: {
                        Text("+ More")
                            .font(.caption2)
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .strokeBorder(accentColor.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.cardBackground))
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
    }
}
