import SwiftUI
import LogiCore

// MARK: - Shared grouped-list parts

struct ProSection<Content: View, Trailing: View>: View {
    var title: String
    var trailing: Trailing
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title; self.trailing = trailing(); self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                trailing.font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 12)
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.cardBackground))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
        }
    }
}
extension ProSection where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) { self.init(title, trailing: { EmptyView() }, content: content) }
}

struct ProRow<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    var divider = true
    var height: CGFloat = 40
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: subtitle == nil ? height : 56)
            if divider { Rectangle().fill(Color.hairline).frame(height: 1) }
        }
    }
}

private struct StatusText: View {
    let ok: Bool
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(ok ? Color.green : Color.orange).frame(width: 6, height: 6)
            Text(ok ? "Granted" : "Not granted").foregroundStyle(.secondary)
        }
    }
}

private struct Note: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 12)
    }
}

// MARK: - General (unchanged)

struct GeneralView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Panel(title: "Appearance") {
                Picker("Appearance", selection: $model.draft.theme) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 320)
                Text("Applied after Save.").font(.caption).foregroundStyle(.secondary)
                Toggle("Launch at Login", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
                Text("May need approval in System Settings and can be rejected for an ad-hoc development build. Actual status and errors are shown.").font(.caption).foregroundStyle(.secondary)
            }
            Panel(title: "Permissions & recovery") {
                LabeledContent("Input Monitoring", value: model.inputAllowed ? "Granted" : "Not granted")
                LabeledContent("Accessibility", value: model.accessibilityAllowed ? "Granted" : "Not granted")
                Text("Grant Input Monitoring to access BLE vendor reports. Accessibility is needed only for mapped actions. After granting access, quit and reopen the app or Retry Devices.")
                HStack {
                    Button("Input Monitoring") { model.requestPermission(false) }
                    Button("Accessibility") { model.requestPermission(true) }
                    Button("Retry Devices") { Task { await model.retry() } }
                    Button("Relaunch LogiMXLite") { model.relaunch() }
                }.buttonStyle(.pill)
                Text("Bluetooth permission is not requested: this app uses IOHID for already-paired BLE devices and does not scan with CoreBluetooth.").font(.caption).foregroundStyle(.secondary)
                if !model.conflicts.isEmpty { Label("Suspected conflicts: \(model.conflicts.joined(separator: ", ")). Quit them manually before enabling mappings.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            Panel(title: "Input mappings") {
                Text("Temporary diversion is enabled only for enumerated controls. Primary clicks and standard typing are never intercepted. Leftover diversion from another tool is taken over and released on quit, so Back and Forward always return to native behavior. Scroll speed, direction and smoothing run through macOS and stop the moment the app quits.")
                Button(model.mappingEnabled ? "Disable mappings & restore native controls" : "Enable verified mappings for this session") {
                    Task { if model.mappingEnabled { await model.disableMappings() } else { await model.enableMappings() } }
                }.buttonStyle(.pillProminent)
                Toggle("Enable mappings automatically when devices are ready", isOn: $model.autoEnableMappings)
                Text("Applies only when Input Monitoring and Accessibility are granted, no conflicting app is running, and the controls were enumerated. Otherwise mappings stay off. Unsupported source actions retain native behavior.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Profiles

struct ProfilesView: View {
    @ObservedObject var model: AppModel

    private static let mouseNames = ["c82": "Wheel button", "c196": "Top button", "c83": "Back button", "c86": "Forward button", "thumbWheel": "Thumb wheel"]
    private func controlName(_ group: String, _ key: String) -> (String, String) {
        switch group {
        case "mouse": return (Self.mouseNames[key] ?? key, "Mouse")
        case "gestures": return (key == "click" ? "Gesture click" : "Gesture \(key)", "Mouse")
        default: return (KeyboardView.keys.first { $0.id == key }?.name ?? key, "Keyboard")
        }
    }
    private func overrideCount(_ p: Profile) -> Int { p.mouse.count + p.keyboard.count + p.gestures.count }

    var body: some View {
        HStack(spacing: 0) {
            profileList
            ScrollView {
                detail
                    .frame(maxWidth: 820, alignment: .leading)
                    .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 110)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .background(Lite.page.ignoresSafeArea(edges: []))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private var profileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(model.draft.profiles.count) profiles").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)
            VStack(spacing: 2) {
                ForEach(model.draft.profiles) { p in
                    let on = p.id == model.selectedProfile
                    Button { model.selectedProfile = p.id } label: {
                        HStack(spacing: 9) {
                            Text(String(p.name.prefix(1))).font(.system(size: 10, weight: .bold))
                                .frame(width: 22, height: 22)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Color.white.opacity(0.22) : Color.trackBackground))
                            Text(p.name).lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 4)
                            Text(p.isDefault ? "Default" : "\(overrideCount(p))").font(.system(size: 11))
                                .foregroundStyle(on ? Color.white.opacity(0.8) : Color.secondary)
                        }
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .padding(.horizontal, 8).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? Lite.accent : Color.clear))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 12)
            Spacer(minLength: 12)
            HStack(spacing: 0) {
                Button { model.chooseApplication(associate: false) } label: { Image(systemName: "plus").frame(width: 28, height: 26) }
                    .help("Add application profile")
                Rectangle().fill(Color.hairline).frame(width: 1, height: 26)
                Button(action: model.deleteProfile) { Image(systemName: "minus").frame(width: 28, height: 26) }
                    .disabled(model.selected.isDefault).help("Delete profile")
                Rectangle().fill(Color.hairline).frame(width: 1, height: 26)
                Spacer()
            }
            .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
        }
        .frame(width: 240).frame(maxHeight: .infinity)
        .background(Lite.content.ignoresSafeArea(edges: []))
        .overlay(alignment: .trailing) { Rectangle().fill(Color.hairline).frame(width: 1) }
    }

    @ViewBuilder private var detail: some View {
        let p = model.selected
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Text(String(p.name.prefix(1))).font(.system(size: 17, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.trackBackground))
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Profile name", text: Binding(get: { model.selected.name }, set: { v in model.editProfile { $0.name = v } }))
                        .textFieldStyle(.plain).font(.system(size: 17, weight: .semibold))
                    Text(p.isDefault ? "Default profile · used when no app profile matches" : "Application profile")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    if !p.isDefault { Button("Associate App…") { model.chooseApplication(associate: true) } }
                    Button("Duplicate", action: model.duplicate)
                    Button("Delete", role: .destructive, action: model.deleteProfile).disabled(p.isDefault)
                }.buttonStyle(.pill)
            }

            ProSection("Profile") {
                ProRow(title: "Bundle ID") {
                    Text(p.isDefault ? "Desktop fallback" : p.bundleID ?? "Unresolved: select the installed .app").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                ProRow(title: "Active now") {
                    HStack(spacing: 6) { Circle().fill(Color.green).frame(width: 6, height: 6); Text(model.activeName).foregroundStyle(.secondary) }
                }
                ProRow(title: "Switch hardware settings with apps",
                       subtitle: "When off, Desktop hardware settings apply. When on, saved app hardware overrides apply; identical readback values are skipped. Backlight and Fn settings may persist on the device.",
                       divider: false) {
                    Toggle("", isOn: $model.draft.switchHardwareWithApps).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Lite.green)
                }
            }

            ProSection("Assignments", trailing: { Text("Missing settings inherit Desktop") }) {
                let rows: [(String, String)] = p.mouse.keys.sorted().map { ("mouse", $0) } + p.gestures.keys.sorted().map { ("gestures", $0) } + p.keyboard.keys.sorted().map { ("keyboard", $0) }
                if rows.isEmpty {
                    ProRow(title: "No overrides", divider: false) { EmptyView() }.foregroundStyle(.secondary)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        let name = controlName(r.0, r.1)
                        VStack(spacing: 0) {
                            ProAssignmentRow(model: model, group: r.0, key: r.1, name: name.0, device: name.1)
                            if i < rows.count - 1 { Rectangle().fill(Color.hairline).frame(height: 1) }
                        }
                    }
                }
            }
            if !p.isDefault {
                Button("Reset All Overrides to Desktop") {
                    model.editProfile { $0.mouse = [:]; $0.keyboard = [:]; $0.gestures = [:]; $0.dpiPreset = nil; $0.scroll = nil; $0.keyboardSettings = nil; $0.wheelMode = nil; $0.smartShiftThreshold = nil }
                }.buttonStyle(.pill).padding(.leading, 4)
            }
            Note(text: "Excel and PowerPoint require association through their installed app bundles; no bundle ID is guessed.")
        }
    }
}

/// Assignment row matching the Profiles design: name, device in tertiary, 190pt popup.
private struct ProAssignmentRow: View {
    @ObservedObject var model: AppModel
    let group: String
    let key: String
    let name: String
    let device: String
    @State private var shortcut = false
    private var effective: Action? { group == "mouse" ? model.resolvedSelected.mouse[key] : group == "keyboard" ? model.resolvedSelected.keyboard[key] : model.resolvedSelected.gestures[key] }
    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                Text(device).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Menu {
                if !model.selected.isDefault { Button("Inherit Desktop") { model.setAction(group, key: key, action: nil) } }
                if key == "thumbWheel" { Button("Horizontal scroll (native)") { model.setAction(group, key: key, action: Action(.nativeHorizontalScroll)) } }
                else { Button("Keyboard shortcut…") { shortcut = true } }
                ForEach(ActionKind.allCases.filter { kind in
                    kind != .shortcut && kind != .requiresConfirmation && kind != .nativeHorizontalScroll && (key == "thumbWheel" ? kind.isThumbMode || kind == .none : !kind.isThumbMode)
                }, id: \.self) { kind in
                    Button(Action(kind).label) { model.setAction(group, key: key, action: Action(kind)) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(effective?.displayLabel ?? "Native").lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .font(.system(size: 12))
                .padding(.leading, 10).padding(.trailing, 8).frame(width: 190, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Lite.control))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 0.5, y: 0.5)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("\(name) action")
        }
        .padding(.leading, 14).padding(.trailing, 8).frame(height: 40)
        .sheet(isPresented: $shortcut) { ShortcutEditor { action in model.setAction(group, key: key, action: action); shortcut = false } cancel: { shortcut = false } }
    }
}

// MARK: - Export / Import

struct BackupView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ProSection("Transfer") {
                ProRow(title: "Export current settings", subtitle: "Save your mouse and keyboard configuration to a file.") {
                    Button("Export…") { model.exportSettings() }.buttonStyle(.pillProminent)
                }
                ProRow(title: "Import settings", subtitle: "Import a previously exported LogiMXLite configuration file.") {
                    Button("Import…") { model.importSettings() }.buttonStyle(.pill)
                }
                ProRow(title: "Import from Logi Options+", subtitle: "Read mappings from an Options+ settings.db file.", divider: false) {
                    Button("Choose File…") { model.importOptionsPlus() }.buttonStyle(.pill)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ProSection("Export file") {
                    info("Format", "LogiMXLite Settings (JSON)")
                    info("Includes", "Mouse + Keyboard settings, \(model.configuration.profiles.count) profiles")
                    info("Schema", "\(model.configuration.schemaVersion)")
                    info("File name", "LogiMXLite-settings.json", divider: false)
                }
                Note(text: "Exports contain saved settings, symbolic Downloads actions and bundle identifiers. They contain no Bluetooth keys, serial numbers, tokens, private paths or account data. Imports are limited to 1 MiB, validated before preview, and require confirmation. Preview never runs actions.")
                Note(text: "Imports automatically keep one local recovery copy before replacing settings. Options+ settings.db is read only.")
            }
        }
        .frame(maxWidth: 720).frame(maxWidth: .infinity)
    }
    private func info(_ name: String, _ value: String, divider: Bool = true) -> some View {
        ProRow(title: name, divider: divider, height: 36) { Text(value).textSelection(.enabled) }
            .foregroundStyle(.primary)
    }
}

// MARK: - Import review (unchanged)

struct ImportReview: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review settings replacement").font(.title2.bold())
            Text("No imported action has been executed. Confirming replaces saved settings and the editing draft. A backup of current saved settings is created first.")
            ScrollView { VStack(alignment: .leading, spacing: 8) { ForEach(Array((model.preview?.changes ?? []).enumerated()), id: \.offset) { _, line in Text(line).font(.callout).frame(maxWidth: .infinity, alignment: .leading) } }.textSelection(.enabled) }.frame(maxHeight: 380)
            HStack { Button("Cancel") { model.preview = nil }; Spacer(); Button("Confirm Import", action: model.applyImport).buttonStyle(.borderedProminent).disabled(model.busy) }
        }.padding(24).frame(width: 680)
    }
}

// MARK: - About

struct AboutView: View {
    @ObservedObject var model: AppModel
    @State private var open: Set<String> = []
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                LiteImage(names: ["lite-appicon"]).frame(width: 64, height: 64).padding(-4)
                VStack(alignment: .leading, spacing: 3) {
                    Text("LogiMXLite").font(.system(size: 20, weight: .semibold))
                    Text("Version \(version) · macOS 15+ · Apple Silicon").font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("Developed by Harith Dilshan ·").foregroundStyle(.secondary)
                        Link("h4rithd.com", destination: URL(string: "https://h4rithd.com")!).foregroundStyle(.primary)
                    }.font(.system(size: 12))
                }
            }.padding(.horizontal, 4)

            ProSection("Privacy") {
                Text("Local-only. No network runtime, accounts, telemetry, background cloud sync, private APIs or updater. MIT licensed; protocol research references and license notices are included in the app Resources and repository docs.")
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                ProSection("Diagnostics") {
                    ProRow(title: "Input Monitoring") { StatusText(ok: model.inputAllowed) }
                    ProRow(title: "Accessibility") { StatusText(ok: model.accessibilityAllowed) }
                    ForEach(Model.allCases) { device in
                        disclosure(device.name, divider: true) { deviceDetails(device) }
                    }
                    disclosure("Recent diagnostics", divider: false) {
                        ForEach(Array(model.diagnostics.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 11)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button("Refresh Permissions", action: model.checkPermissions)
                    Button("Retry Transport") { Task { await model.retry() } }
                    Button("Export Redacted Diagnostics…", action: model.exportDiagnostics)
                }.buttonStyle(.pill).padding(.horizontal, 4).padding(.top, 4)
                Note(text: "System Settings → Privacy & Security → Input Monitoring / Accessibility. Enable LogiMXLite, then quit and reopen it. Ad-hoc rebuilds may require regranting access. Performance and hardware checks are recorded in docs/TEST_RESULTS.md and docs/HARDWARE_MATRIX.md.")
            }
        }
        .frame(maxWidth: 720).frame(maxWidth: .infinity)
    }

    private func disclosure<C: View>(_ title: String, divider: Bool, @ViewBuilder _ content: () -> C) -> some View {
        let isOpen = open.contains(title)
        return VStack(spacing: 0) {
            Button {
                withAnimation(.smooth(duration: 0.2)) { if isOpen { open.remove(title) } else { open.insert(title) } }
            } label: {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 14).frame(height: 40).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if isOpen {
                VStack(alignment: .leading, spacing: 4) { content() }
                    .padding(.horizontal, 14).padding(.bottom, 12).frame(maxWidth: .infinity, alignment: .leading)
            }
            if divider { Rectangle().fill(Color.hairline).frame(height: 1) }
        }
    }

    @ViewBuilder private func deviceDetails(_ device: Model) -> some View {
        let d = model.devices[device]
        Text(d?.status ?? "Unknown").font(.system(size: 12)).foregroundStyle(.secondary)
        Text("Firmware: \((d?.snapshot.firmware ?? []).isEmpty ? "Unknown" : d!.snapshot.firmware.joined(separator: "; "))").font(.system(size: 11))
        ForEach(d?.snapshot.features.values.sorted { $0.id < $1.id } ?? []) { f in
            Text(String(format: "0x%04X · index %d · version %d", f.id, f.index, f.version)).font(.system(size: 11, design: .monospaced))
        }
        ForEach(d?.snapshot.controls ?? []) { c in
            Text("CID \(c.id), task \(c.task), flags \(c.flags); divertible: \(c.divertible ? "yes" : "no")").font(.system(size: 11))
        }
    }
}
