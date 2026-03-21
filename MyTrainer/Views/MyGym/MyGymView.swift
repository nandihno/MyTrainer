import SwiftUI
import SwiftData

struct MyGymView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allScheduledExercises: [ScheduledExercise]
    @Query private var allCompletedSets: [CompletedSet]

    @State private var selectedDay: Int = 1
    @State private var todayDayOfWeek: Int = 1
    @State private var weekDates: [Date] = []

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }

    private var exercisesForDay: [ScheduledExercise] {
        allScheduledExercises
            .filter { $0.dayOfWeek == selectedDay }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private var todayStart: Date {
        calendar.startOfDay(for: Date())
    }

    private var selectedDayStart: Date {
        guard (selectedDay - 1) < weekDates.count else { return todayStart }
        return calendar.startOfDay(for: weekDates[selectedDay - 1])
    }

    private var selectedDayEnd: Date {
        calendar.date(byAdding: .day, value: 1, to: selectedDayStart)!
    }

    private func completedSets(for scheduled: ScheduledExercise) -> [CompletedSet] {
        allCompletedSets.filter { cs in
            cs.scheduledExercise?.id == scheduled.id &&
            cs.completedAt >= selectedDayStart &&
            cs.completedAt < selectedDayEnd
        }
    }

    private var totalSetsForDay: Int {
        exercisesForDay.reduce(0) { $0 + $1.sets }
    }

    private var completedSetsCountForDay: Int {
        exercisesForDay.reduce(0) { total, ex in
            total + completedSets(for: ex).filter { !$0.isBonus }.count
        }
    }

    private var mostCommonTypeColor: Color {
        let types = exercisesForDay.compactMap { $0.exercise?.appleWorkoutType }
        let counts = Dictionary(grouping: types, by: { $0 }).mapValues(\.count)
        guard let topType = counts.max(by: { $0.value < $1.value })?.key,
              let info = WorkoutTypeInfo.info(for: topType) else {
            return .accentColor
        }
        return info.color
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WeekStripView(
                    selectedDay: $selectedDay,
                    today: todayDayOfWeek,
                    weekDates: weekDates
                )

                if exercisesForDay.isEmpty {
                    ContentUnavailableView {
                        Label("No exercises for this day", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("Add exercises in the Library tab and assign them to this day")
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(exercisesForDay) { scheduled in
                                ExerciseRowCard(
                                    scheduledExercise: scheduled,
                                    completedSets: completedSets(for: scheduled),
                                    onToggleSet: { setNum in
                                        toggleSet(for: scheduled, setNumber: setNum)
                                    },
                                    onAddBonus: {
                                        addBonusSet(for: scheduled)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 80)
                    }
                }

                if completedSetsCountForDay > 0 {
                    completionSummary
                }
            }
            .background(Color(.appBackground))
            .navigationTitle("My Gym")
            .onAppear { setupWeek() }
        }
    }

    private var completionSummary: some View {
        VStack(spacing: 6) {
            Divider()
            HStack {
                Text("\(completedSetsCountForDay) of \(totalSetsForDay) sets completed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(mostCommonTypeColor)
                        .frame(
                            width: totalSetsForDay > 0
                                ? geo.size.width * CGFloat(completedSetsCountForDay) / CGFloat(totalSetsForDay)
                                : 0,
                            height: 4
                        )
                }
            }
            .frame(height: 4)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(Color(.appBackground))
    }

    private func setupWeek() {
        let now = Date()
        let cal = calendar
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: now) else { return }
        weekDates = (0..<7).map { cal.date(byAdding: .day, value: $0, to: weekInterval.start)! }

        let weekday = cal.component(.weekday, from: now)
        // Convert Sunday=1..Saturday=7 to Monday=1..Sunday=7
        todayDayOfWeek = weekday == 1 ? 7 : weekday - 1
        selectedDay = todayDayOfWeek
    }

    private func toggleSet(for scheduled: ScheduledExercise, setNumber: Int) {
        let existing = completedSets(for: scheduled).first {
            $0.setNumber == setNumber && !$0.isBonus
        }
        if let existing {
            modelContext.delete(existing)
        } else {
            let cs = CompletedSet(
                scheduledExercise: scheduled,
                setNumber: setNumber
            )
            modelContext.insert(cs)
        }
    }

    private func addBonusSet(for scheduled: ScheduledExercise) {
        let existing = completedSets(for: scheduled).filter(\.isBonus)
        let nextNumber = scheduled.sets + existing.count + 1
        let bonus = CompletedSet(
            scheduledExercise: scheduled,
            setNumber: nextNumber,
            isBonus: true
        )
        modelContext.insert(bonus)
    }
}
