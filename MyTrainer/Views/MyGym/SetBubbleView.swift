import SwiftUI

struct SetBubbleView: View {
    let setNumber: Int
    let isCompleted: Bool
    let isBonus: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isCompleted ? color : Color.clear)
                    .overlay(
                        Circle()
                            .strokeBorder(color, lineWidth: 2)
                    )
                    .frame(width: 32, height: 32)

                if isCompleted {
                    if isBonus {
                        Image(systemName: "plus")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    }
                } else {
                    Text("\(setNumber)")
                        .font(.caption2.bold())
                        .foregroundStyle(color)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
