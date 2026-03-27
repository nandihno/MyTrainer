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
                            .strokeBorder(color, lineWidth: 2.5)
                    )
                    .frame(width: 44, height: 44)

                if isCompleted {
                    if isBonus {
                        Image(systemName: "plus")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                } else {
                    Text("\(setNumber)")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(color)
                }
            }
            // Extra invisible padding expands the tap area beyond the circle
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
