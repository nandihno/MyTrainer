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
                            .font(.caption2)
                        Text(dayNumber(for: index))
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if isToday {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.primary)
                        } else if isSelected {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                    .foregroundStyle(
                        isToday ? Color(.systemBackground) :
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
