import SwiftUI
import AuraCore

@MainActor
struct LightingView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedZone = 0
    @State private var isNamingPreset = false
    @State private var presetName = ""

    private var lighting: LightingController { model.lighting }
    private var mode: AuraMode { lighting.state.mode }

    var body: some View {
        Form {
            Section {
                KeyboardPreview(
                    state: lighting.state,
                    zoneCount: lighting.profile.zoneCount,
                    selectedZone: mode.usesIndividualZones ? selectedZone : nil,
                    onSelectZone: mode.usesIndividualZones ? { selectedZone = $0 } : nil
                )
                .frame(height: 200)
                .listRowInsets(EdgeInsets())
            }

            Section("Backlight") {
                Toggle("Backlight", isOn: Binding(get: { lighting.state.isOn }, set: { lighting.setOn($0) }))
                Picker("Brightness", selection: Binding(get: { lighting.state.brightness }, set: { lighting.setLevel($0) })) {
                    Text("Low").tag(1)
                    Text("Medium").tag(2)
                    Text("High").tag(3)
                }
                .pickerStyle(.segmented)
                .disabled(!lighting.state.isOn)
            }

            Section {
                Picker("Effect", selection: Binding(
                    get: { mode.effect ?? .staticColor },
                    set: { lighting.setEffect($0) }
                )) {
                    ForEach(lighting.profile.supportedEffects) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                effectControls

                if let speed = mode.speed {
                    Picker("Speed", selection: Binding(get: { speed }, set: { lighting.setSpeed($0) })) {
                        ForEach(AuraSpeed.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Effect")
            } footer: {
                Text(lighting.profile.isWhiteKeyboard
                     ? "This keyboard has a single-zone white backlight; colors map to brightness."
                     : "Effects run on the keyboard controller, so they keep going with no CPU cost.")
                    .foregroundStyle(.secondary)
            }

            Section {
                PresetGrid()
            } header: {
                HStack {
                    Text("Presets")
                    Spacer()
                    Button("Save Current…") {
                        presetName = ""
                        isNamingPreset = true
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem {
                Button {
                    lighting.resync()
                } label: {
                    Label("Re-sync Keyboard", systemImage: "arrow.clockwise")
                }
                .help("Send the current lighting to the keyboard again")
            }
        }
        .alert("Save Preset", isPresented: $isNamingPreset) {
            TextField("Name", text: $presetName)
            Button("Save") { lighting.saveCurrentAsPreset(named: presetName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current effect, colors and speed.")
        }
    }

    // MARK: - Effect Controls

    @ViewBuilder
    private var effectControls: some View {
        switch mode.effect ?? .staticColor {
        case .staticColor:
            if !lighting.profile.isWhiteKeyboard {
                Toggle("Separate color per zone", isOn: Binding(
                    get: { mode.usesIndividualZones },
                    set: { lighting.setIndividualZones($0) }
                ))
                if mode.usesIndividualZones {
                    Picker("Zone", selection: $selectedZone) {
                        ForEach(AuraZone.allCases) { Text($0.shortName).tag($0.rawValue - 1) }
                    }
                    .pickerStyle(.segmented)
                    colorRow("Zone color", mode.zoneColors[selectedZone]) { lighting.setZone(selectedZone, color: $0) }
                } else {
                    colorRow("Color", mode.primaryColor ?? .white) { lighting.setPrimaryColor($0) }
                }
            } else {
                colorRow("Brightness color", mode.primaryColor ?? .white) { lighting.setPrimaryColor($0) }
            }

        case .breathing:
            colorRow("Color", mode.primaryColor ?? .white) { lighting.setPrimaryColor($0) }
            let fadesToOff = (mode.secondaryColor ?? .black) == .black
            Toggle("Fade to off", isOn: Binding(
                get: { fadesToOff },
                set: { lighting.setSecondaryColor($0 ? .black : .white) }
            ))
            if !fadesToOff, let second = mode.secondaryColor {
                colorRow("Second color", second) { lighting.setSecondaryColor($0) }
            }

        case .strobe:
            colorRow("Color", mode.primaryColor ?? .white) { lighting.setPrimaryColor($0) }

        case .colorCycle:
            Text("All zones move through the spectrum together.").foregroundStyle(.secondary)

        case .rainbow:
            Text("A rainbow wave travels across the four zones.").foregroundStyle(.secondary)
        }
    }

    private func colorRow(_ title: String, _ color: AuraColor, set: @escaping (AuraColor) -> Void) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                ForEach(Self.quickColors, id: \.self) { swatch in
                    Button {
                        set(swatch)
                    } label: {
                        Circle()
                            .fill(Color(swatch))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(.primary.opacity(swatch == color ? 0.9 : 0.15), lineWidth: swatch == color ? 2 : 0.5))
                    }
                    .buttonStyle(.plain)
                    .help("#\(swatch.upperHexString)")
                }
                ColorPicker(title, selection: Binding(get: { Color(color) }, set: { set(AuraColor($0)) }), supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }

    private static let quickColors: [AuraColor] = [.rogRed, .orange, .gold, .lime, .cyan, .blue, .purple, .magenta, .white]
}

// MARK: - Presets

private struct PresetGrid: View {
    @Environment(AppModel.self) private var model
    @State private var renaming: AuraPreset?
    @State private var newName = ""

    var body: some View {
        let lighting = model.lighting
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 12)], spacing: 12) {
            ForEach(lighting.allPresets) { preset in
                PresetTile(preset: preset, isSelected: preset.id == lighting.state.presetID) {
                    lighting.apply(preset)
                }
                .contextMenu {
                    if preset.isCustom {
                        Button("Rename…") {
                            newName = preset.name
                            renaming = preset
                        }
                        Button("Delete", role: .destructive) { lighting.deletePreset(preset) }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .alert("Rename Preset", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { renaming.map { lighting.renamePreset($0, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct PresetTile: View {
    let preset: AuraPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(swatch)
                    .frame(height: 38)
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(5)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : .primary.opacity(0.1), lineWidth: isSelected ? 2 : 0.5)
                    )
                HStack(spacing: 4) {
                    Text(preset.name).font(.callout).lineLimit(1)
                    if preset.isCustom {
                        Image(systemName: "person.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var swatch: AnyShapeStyle {
        switch preset.mode {
        case .colorCycle, .rainbow:
            return AnyShapeStyle(LinearGradient(colors: (0..<6).map { Color(AuraColor.hue(Double($0) / 6)) },
                                                startPoint: .leading, endPoint: .trailing))
        default:
            let colors = preset.previewColors.isEmpty ? [AuraColor.white] : preset.previewColors
            return colors.count == 1
                ? AnyShapeStyle(Color(colors[0]))
                : AnyShapeStyle(LinearGradient(colors: colors.map(Color.init), startPoint: .leading, endPoint: .trailing))
        }
    }
}
