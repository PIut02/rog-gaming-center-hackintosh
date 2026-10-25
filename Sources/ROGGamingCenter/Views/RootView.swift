import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            Group {
                switch model.selection {
                case .dashboard: DashboardView()
                case .lighting: LightingView()
                case .display: DisplayView()
                case .status: StatusView()
                }
            }
            .navigationTitle(model.selection.title)
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(WindowAccessor(
            onWindow: { window in
                if model.suppressInitialWindow {
                    model.suppressInitialWindow = false
                    window.close()
                    // The close observer isn't attached yet, so drop to menu-bar-only here.
                    model.mainWindowWillClose()
                } else {
                    model.mainWindow = window
                }
            },
            onClose: { model.mainWindowWillClose() }
        ))
        .sheet(isPresented: $model.isPermissionSheetPresented) {
            PermissionSheet()
        }
        .onAppear {
            model.openMainWindowAction = { openWindow(id: "main") }
        }
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let selection = Binding<SidebarItem?>(
            get: { model.selection },
            set: { if let item = $0 { model.selection = item } }
        )
        List(selection: selection) {
            ForEach(SidebarItem.allCases) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                // Below ~30pt the eye's thin strokes break up on 1x displays.
                ROGEmblem(height: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text("ROG").font(.system(size: 13, weight: .heavy)).italic()
                    Text("Gaming Center").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarStatus()
        }
    }
}

private struct SidebarStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let status = ConnectionStatus(model: model)
        Button {
            if model.hidAccess != .granted {
                model.isPermissionSheetPresented = true
            } else {
                model.selection = .status
            }
        } label: {
            HStack(spacing: 8) {
                StatusDot(color: status.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(status.title).font(.callout)
                    if let device = model.device {
                        Text(device.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .help("Show keyboard status")
    }
}
