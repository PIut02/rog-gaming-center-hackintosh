import SwiftUI
import AppKit
import AuraCore
import AuraHID

// MARK: - Theme

extension Color {
    init(_ aura: AuraColor) {
        self.init(.sRGB, red: Double(aura.red) / 255, green: Double(aura.green) / 255, blue: Double(aura.blue) / 255)
    }
}

extension AuraColor {
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(
            red: UInt8((ns.redComponent * 255).rounded().clamped(to: 0...255)),
            green: UInt8((ns.greenComponent * 255).rounded().clamped(to: 0...255)),
            blue: UInt8((ns.blueComponent * 255).rounded().clamped(to: 0...255))
        )
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

// MARK: - Brand Assets

enum BrandImage {
    /// Loads from the app bundle, or from ./Resources when run with `swift run`.
    static func load(_ name: String, _ ext: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext), let image = NSImage(contentsOf: url) {
            return image
        }
        let local = URL(fileURLWithPath: "Resources/\(name).\(ext)")
        return NSImage(contentsOf: local)
    }

    static let emblem: NSImage? = {
        let image = load("emblem", "png")
        image?.isTemplate = true
        return image
    }()

    static let menuBarIcon: NSImage? = {
        guard let image = load("menubar_icon", "png") ?? emblem?.copy() as? NSImage else { return nil }
        let aspect = image.size.width / max(image.size.height, 1)
        image.size = NSSize(width: 13 * aspect, height: 13)
        image.isTemplate = true
        return image
    }()
}

/// The ROG emblem, white in dark mode and adapting to the label color in light mode.
struct ROGEmblem: View {
    var height: CGFloat = 20

    var body: some View {
        Group {
            if let image = BrandImage.emblem {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
            } else {
                Text("ROG").font(.system(size: height * 0.8, weight: .heavy)).italic()
            }
        }
        .frame(height: height)
        .foregroundStyle(.primary)
        .accessibilityLabel("Republic of Gamers")
    }
}

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let icon = BrandImage.menuBarIcon {
                Image(nsImage: icon)
            } else {
                Text("ROG")
            }
        }
        // The label is created at launch, so it is a reliable place to hand the
        // model a way to reopen the main window from outside SwiftUI.
        .onAppear {
            model.openMainWindowAction = { openWindow(id: "main") }
        }
    }
}

// MARK: - Window Bridge

/// Reports the hosting NSWindow so the model can show/hide it and react to closing.
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    var onClose: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            onWindow(window)
            context.coordinator.observe(window, onClose: onClose)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var token: NSObjectProtocol?

        func observe(_ window: NSWindow, onClose: @escaping () -> Void) {
            token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                onClose()
            }
        }

        deinit { token.map(NotificationCenter.default.removeObserver) }
    }
}

// MARK: - Status

struct ConnectionStatus {
    enum Level { case good, warning, error, inactive }
    let level: Level
    let title: String

    @MainActor
    init(model: AppModel) {
        if model.hidAccess != .granted {
            self.init(level: .warning, title: "Keyboard access needed")
        } else if model.device == nil {
            self.init(level: .inactive, title: "Keyboard not found")
        } else if let result = model.lighting.lastResult, !result.isSuccess {
            self.init(level: .error, title: "Keyboard not responding")
        } else {
            self.init(level: .good, title: "Keyboard connected")
        }
    }

    init(level: Level, title: String) {
        self.level = level
        self.title = title
    }

    var color: Color {
        switch level {
        case .good: return .green
        case .warning: return .orange
        case .error: return .red
        case .inactive: return .secondary
        }
    }
}

struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }
}

// MARK: - Formatting

enum Format {
    static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    static func duration(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 86_400 ? [.day, .hour] : [.hour, .minute]
        f.unitsStyle = .abbreviated
        return f.string(from: seconds) ?? "—"
    }

    static func minutes(_ minutes: Int) -> String { duration(TimeInterval(minutes * 60)) }

    static func gb(_ value: Double) -> String { String(format: "%.1f GB", value) }
}

// MARK: - Dashboard Card

struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

/// Label on the left, value right-aligned, for use outside of Forms.
struct StatRow: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

struct BigValue: View {
    let value: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let caption {
                Text(caption).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
