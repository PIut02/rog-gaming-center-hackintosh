import SwiftUI
import AuraCore

struct DisplayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let display = model.display
        Form {
            Section {
                ForEach(DisplayProfile.allCases) { profile in
                    ProfileRow(profile: profile, isSelected: display.profile == profile) {
                        display.select(profile)
                    }
                }
            } header: {
                Text("Profile")
            } footer: {
                Text("Profiles adjust every connected display. Choosing Standard or quitting the app restores your normal calibration.")
                    .foregroundStyle(.secondary)
            }

            Section {
                TestPattern()
                    .frame(height: 96)
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            } header: {
                Text("Test Pattern")
            } footer: {
                Text("Compare profiles here: each gray step should stay distinguishable from its neighbors.")
                    .foregroundStyle(.secondary)
            }

            Section("Details") {
                LabeledContent("Displays", value: "\(display.displayCount)")
                LabeledContent("Gamma table", value: display.tableSize > 0 ? "\(display.tableSize) entries" : "Unavailable")
                if let error = display.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProfileRow: View {
    let profile: DisplayProfile
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: profile.symbol)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.title)
                    Text(profile.subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Stepped gray ramp, smooth ramp and primary ramps. Drawn normally: the active
/// profile is applied by the display hardware to everything on screen, including this.
private struct TestPattern: View {
    var body: some View {
        Canvas { ctx, size in
            let rowHeight = size.height / 4
            let steps = 24
            let stepWidth = size.width / CGFloat(steps)
            for i in 0..<steps {
                let v = Double(i) / Double(steps - 1)
                ctx.fill(Path(CGRect(x: CGFloat(i) * stepWidth, y: 0, width: stepWidth + 0.5, height: rowHeight)),
                         with: .color(Color(white: v)))
            }
            let ramps: [Color] = [.white, Color(red: 1, green: 0, blue: 0), Color(red: 0, green: 1, blue: 0)]
            let rows: [[Color]] = [
                [.black, ramps[0]],
                [.black, ramps[1], .black, Color(red: 0, green: 0, blue: 1)],
                [.black, ramps[2]],
            ]
            for (r, colors) in rows.enumerated() {
                let rect = CGRect(x: 0, y: rowHeight * CGFloat(r + 1), width: size.width, height: rowHeight)
                ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: colors),
                                                           startPoint: CGPoint(x: 0, y: rect.midY),
                                                           endPoint: CGPoint(x: size.width, y: rect.midY)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}
