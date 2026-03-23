import SwiftUI
import SwiftData

// MARK: - Unified wrapper for anything shown in the day list

struct DayExerciseItem: Identifiable {
    enum Source {
        case template(ScheduledExercise)          // from Library schedule
        case override(ScheduledExercise, DailyExercise) // template edited for this day
        case oneOff(DailyExercise)                // added just for this day
    }

    let id: String
    let source: Source

    var exercise: Exercise? {
        switch source {
        case .template(let s):      return s.exercise
        case .override(_, let d):   return d.exercise
        case .oneOff(let d):        return d.exercise
        }
    }

    var sets: Int {
        switch source {
        case .template(let s):      return s.sets
        case .override(_, let d):   return d.sets
        case .oneOff(let d):        return d.sets
        }
    }

    var reps: Int {
        switch source {
        case .template(let s):      return s.reps
        case .override(_, let d):   return d.reps
        case .oneOff(let d):        return d.reps
        }
    }

    var durationSeconds: Int {
        switch source {
        case .template(let s):      return s.durationSeconds
        case .override(_, let d):   return d.durationSeconds
        case .oneOff(let d):        return d.durationSeconds
        }
    }

    var isTimeBased: Bool { reps == 0 }

    var subtitle: String {
        if isTimeBased {
            return "\(sets) sets \u{00D7} \(formattedDuration)"
        } else {
            return "\(sets) sets \u{00D7} \(reps) reps"
        }
    }

    var orderIndex: Int {
        switch source {
        case .template(let s):      return s.orderIndex
        case .override(let s, _):   return s.orderIndex
        case .oneOff(let d):        return d.orderIndex
        }
    }

    /// Is this a one-off or overridden entry (i.e. not the pure template)?
    var isCustomised: Bool {
        switch source {
        case .template:  return false
        case .override:  return true
        case .oneOff:    return true
        }
    }

    var scheduledExercise: ScheduledExercise? {
        switch source {
        case .template(let s):      return s
        case .override(let s, _):   return s
        case .oneOff:               return nil
        }
    }

    var dailyExercise: DailyExercise? {
        switch source {
        case .template:             return nil
        case .override(_, let d):   return d
        case .oneOff(let d):        return d
        }
    }

    private var formattedDuration: String {
        let s = durationSeconds
        if s >= 60 {
            let m = s / 60
            let r = s % 60
            return r == 0 ? "\(m)m" : "\(m)m \(r)s"
        }
        return "\(s)s"
    }
}

// MARK: - View

struct MyGymView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allScheduledExercises: [ScheduledExercise]
    @Query private var allDailyExercises: [DailyExercise]
    @Query private var allCompletedSets: [CompletedSet]
    @Query private var allExercises: [Exercise]

    @State private var selectedDay: Int = 1
    @State private var todayDayOfWeek: Int = 1
    @State private var weekDates: [Date] = []

    // Sheets
    @State private var showAddSheet = false
    @State private var itemToEdit: DayExerciseItem?

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }

    // MARK: - Day exercise list (merged)

    private var itemsForDay: [DayExerciseItem] {
        let templateExercises = allScheduledExercises
            .filter { $0.dayOfWeek == selectedDay }
            .sorted { $0.orderIndex < $1.orderIndex }

        let dayStart = selectedDayStart
        let dailyForDate = allDailyExercises.filter {
            calendar.isDate($0.date, inSameDayAs: dayStart)
        }

        var items: [DayExerciseItem] = []

        // 1) Template entries — check for overrides
        for scheduled in templateExercises {
            if let override = dailyForDate.first(where: { $0.scheduledExerciseID == scheduled.id }) {
                items.append(DayExerciseItem(
                    id: "override-\(scheduled.id.uuidString)",
                    source: .override(scheduled, override)
                ))
            } else {
                items.append(DayExerciseItem(
                    id: "template-\(scheduled.id.uuidString)",
                    source: .template(scheduled)
                ))
            }
        }

        // 2) One-off additions
        let oneOffs = dailyForDate.filter { $0.scheduledExerciseID == nil }
            .sorted { $0.orderIndex < $1.orderIndex }
        for daily in oneOffs {
            items.append(DayExerciseItem(
                id: "oneoff-\(daily.id.uuidString)",
                source: .oneOff(daily)
            ))
        }

        return items
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

    // MARK: Completed sets

    private func completedSets(for item: DayExerciseItem) -> [CompletedSet] {
        allCompletedSets.filter { cs in
            cs.completedAt >= selectedDayStart && cs.completedAt < selectedDayEnd && matchesItem(cs, item)
        }
    }

    private func matchesItem(_ cs: CompletedSet, _ item: DayExerciseItem) -> Bool {
        switch item.source {
        case .template(let s):
            return cs.scheduledExercise?.id == s.id && cs.dailyExerciseID == nil
        case .override(let s, _):
            return cs.scheduledExercise?.id == s.id
        case .oneOff(let d):
            return cs.dailyExerciseID == d.id
        }
    }

    private var totalSetsForDay: Int {
        itemsForDay.reduce(0) { $0 + $1.sets }
    }

    private var completedSetsCountForDay: Int {
        itemsForDay.reduce(0) { total, item in
            total + completedSets(for: item).filter { !$0.isBonus }.count
        }
    }

    private var mostCommonTypeColor: Color {
        let types = itemsForDay.compactMap { $0.exercise?.appleWorkoutType }
        let counts = Dictionary(grouping: types, by: { $0 }).mapValues(\.count)
        guard let topType = counts.max(by: { $0.value < $1.value })?.key,
              let info = WorkoutTypeInfo.info(for: topType) else {
            return .accentColor
        }
        return info.color
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WeekStripView(
                    selectedDay: $selectedDay,
                    today: todayDayOfWeek,
                    weekDates: weekDates
                )

                if itemsForDay.isEmpty {
                    VStack(spacing: 16) {
                        ContentUnavailableView {
                            Label("No exercises for this day", systemImage: "calendar.badge.plus")
                        } description: {
                            Text("Add exercises in the Library tab or tap + to add one just for today")
                        }

                        Button {
                            showAddSheet = true
                        } label: {
                            Label("Add Exercise for Today", systemImage: "plus.circle.fill")
                                .font(.body.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(allExercises.isEmpty)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(itemsForDay) { item in
                                ExerciseRowCard(
                                    item: item,
                                    completedSets: completedSets(for: item),
                                    onToggleSet: { setNum in
                                        toggleSet(for: item, setNumber: setNum)
                                    },
                                    onAddBonus: {
                                        addBonusSet(for: item)
                                    },
                                    onEdit: {
                                        itemToEdit = item
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(allExercises.isEmpty)
                }
            }
            .onAppear { setupWeek() }
            .sheet(isPresented: $showAddSheet) {
                DayExerciseFormView(
                    mode: .add,
                    date: selectedDayStart,
                    existingOrderCount: itemsForDay.count,
                    allExercises: allExercises
                )
            }
            .sheet(item: $itemToEdit) { item in
                DayExerciseFormView(
                    mode: .edit(item),
                    date: selectedDayStart,
                    existingOrderCount: itemsForDay.count,
                    allExercises: allExercises
                )
            }
        }
    }

    // MARK: - Completion Summary

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

    // MARK: - Setup

    private func setupWeek() {
        let now = Date()
        let cal = calendar
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: now) else { return }
        weekDates = (0..<7).map { cal.date(byAdding: .day, value: $0, to: weekInterval.start)! }

        let weekday = cal.component(.weekday, from: now)
        todayDayOfWeek = weekday == 1 ? 7 : weekday - 1
        selectedDay = todayDayOfWeek
    }

    // MARK: - Set Actions

    private func toggleSet(for item: DayExerciseItem, setNumber: Int) {
        let existing = completedSets(for: item).first {
            $0.setNumber == setNumber && !$0.isBonus
        }
        if let existing {
            modelContext.delete(existing)
        } else {
            let cs: CompletedSet
            switch item.source {
            case .template(let s), .override(let s, _):
                cs = CompletedSet(scheduledExercise: s, setNumber: setNumber)
            case .oneOff(let d):
                cs = CompletedSet(dailyExerciseID: d.id, setNumber: setNumber)
            }
            modelContext.insert(cs)
        }
    }

    private func addBonusSet(for item: DayExerciseItem) {
        let existing = completedSets(for: item).filter(\.isBonus)
        let nextNumber = item.sets + existing.count + 1
        let cs: CompletedSet
        switch item.source {
        case .template(let s), .override(let s, _):
            cs = CompletedSet(scheduledExercise: s, setNumber: nextNumber, isBonus: true)
        case .oneOff(let d):
            cs = CompletedSet(dailyExerciseID: d.id, setNumber: nextNumber, isBonus: true)
        }
        modelContext.insert(cs)
    }
}
