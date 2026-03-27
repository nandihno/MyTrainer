import SwiftUI

struct WeekStripView: View {
    @Binding var selectedDay: Int
    let today: Int
    let weekDates: [Date]

    private let dayAbbreviations = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...7, id: \.self) { day in
                let index = day - 1
                let isToday = day == today
                let isSelected = day == selectedDay

                Button {
                    selectedDay = day
                } label: {
                    VStack(spacing: 4) {
                        Text(dayAbbreviations[index])
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                        Text(dayNumber(for: index))
                            .font(.system(.subheadline, design: .rounded, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if isToday {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentColor)
                        } else if isSelected {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                    .foregroundStyle(
                        isToday ? Color.black :
                        isSelected ? Color.accentColor :
                        Color.secondary
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func dayNumber(for index: Int) -> String {
        guard index < weekDates.count else { return "" }
        return "\(calendar.component(.day, from: weekDates[index]))"
    }
}
