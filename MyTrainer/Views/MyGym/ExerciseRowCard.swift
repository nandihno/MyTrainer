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
            RoundedRectangle(cornerRadius: 3)
                .fill(accentColor)
                .frame(width: 6)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.exercise?.name ?? "Unknown")
                                .font(.system(.headline, design: .rounded, weight: .bold))

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

                // Bubbles wrap via adaptive grid; "+ More" sits outside so it isn't squeezed
                VStack(alignment: .leading, spacing: 0) {
                    let bubbleColumns = [GridItem(.adaptive(minimum: 44), spacing: 0, alignment: .leading)]
                    LazyVGrid(columns: bubbleColumns, alignment: .leading, spacing: 0) {
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
                    }

                    Button {
                        onAddBonus()
                    } label: {
                        Text("+ More")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .strokeBorder(accentColor.opacity(0.4), lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                    .padding(.top, 4)
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.cardBackground))
                .shadow(color: .accentColor.opacity(0.08), radius: 8, y: 3)
        )
    }
}
