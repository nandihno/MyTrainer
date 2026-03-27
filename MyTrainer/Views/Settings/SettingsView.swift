import SwiftUI

struct SettingsView: View {
    @AppStorage("userAge") private var age: Int = 30
    @AppStorage("userSex") private var sex: String = "Male"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Personal Info") {
                    HStack {
                        Text("Age")
                        Spacer()
                        TextField("Age", value: $age, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Picker("Sex", selection: $sex) {
                        Text("Male").tag("Male")
                        Text("Female").tag("Female")
                    }
                }

                Section {
                    Text("Your age and sex are used to assess your VO2 Max fitness level relative to typical ranges for your demographic.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.appBackground))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
