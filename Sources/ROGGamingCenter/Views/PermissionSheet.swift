import SwiftUI
import AuraHID

struct PermissionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            ROGEmblem(height: 44)
                .padding(.top, 6)

            VStack(spacing: 8) {
                Text("Allow Keyboard Access")
                    .font(.title2.weight(.semibold))
                Text("ROG Gaming Center talks to your keyboard's lighting controller and listens for the ROG and Fn keys. macOS requires Input Monitoring permission for both.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.hidAccess == .denied {
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Open Privacy & Security › Input Monitoring.")
                    step(2, "Turn on ROG Gaming Center.")
                    step(3, "Come back here. Access is detected automatically.")
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("Not Now") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if model.hidAccess == .denied {
                    Button("Open System Settings") { SystemActions.openInputMonitoringSettings() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Allow Access") { model.requestHIDAccess() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            Text(text).font(.callout)
        }
    }
}
