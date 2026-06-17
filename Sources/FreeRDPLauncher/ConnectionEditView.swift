import SwiftUI

/// Inline add/edit form shown in the detail pane (never a separate window).
struct ConnectionEditView: View {
    @State var connection: Connection
    let isNew: Bool
    var onSave: (Connection) -> Void
    var onCancel: () -> Void

    @State private var password = ""

    private var canSave: Bool {
        !connection.name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !connection.host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isNew ? "New Connection" : "Edit Connection")
                    .font(.title2).bold()
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.bottom, 8)

            Form {
                Section {
                    TextField("Name", text: $connection.name)
                    TextField("Host (IP or hostname)", text: $connection.host)
                    TextField("Port", value: $connection.port, format: .number.grouping(.never))
                    TextField("Username", text: $connection.username)
                    SecureField(isNew ? "Password" : "Password (leave blank to keep)", text: $password)
                    Toggle("Save password to Keychain", isOn: $connection.savePassword)
                }

                Section("Display") {
                    Picker("Resolution", selection: $connection.display) {
                        ForEach(DisplayMode.allCases) { Text($0.label).tag($0) }
                    }
                    if connection.display == .fixed {
                        Picker("Size", selection: sizeBinding) {
                            ForEach(SizePreset.presets) { Text($0.label).tag($0.id) }
                        }
                    }
                    Picker("Make text bigger (scaling)", selection: $connection.scale) {
                        ForEach(Connection.scaleOptions, id: \.self) { Text("\($0)%").tag($0) }
                    }
                    Picker("Graphics codec", selection: $connection.graphics) {
                        ForEach(GraphicsMode.allCases) { Text($0.label).tag($0) }
                    }
                    Text("Tips: Dynamic is smoothest — press Ctrl+Alt+Enter (or the green window button) to go fullscreen. Keep the codec on Automatic if a session crashes after the login screen. For bigger, sharp text, scale on the GNOME side rather than with client scaling (see README).")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Shared clipboard", isOn: $connection.clipboard)
                    Picker("Audio", selection: $connection.audio) {
                        ForEach(AudioMode.allCases) { Text($0.label).tag($0) }
                    }
                    if connection.audio == .local {
                        Picker("Audio buffer", selection: $connection.audioLatency) {
                            ForEach(AudioLatency.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    Toggle("Forward microphone", isOn: $connection.microphone)
                    Toggle("Ignore server certificate (LAN)", isOn: $connection.ignoreCert)
                }

                Section("Advanced") {
                    TextField("Extra FreeRDP flags",
                              text: $connection.extraFlags,
                              prompt: Text("e.g. /gfx:RFX +fonts /drive:home,/Users/me"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.leading)
                    Text("Passed verbatim to FreeRDP, space-separated.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .multilineTextAlignment(.leading)
        }
        .padding(20)
    }

    private var sizeBinding: Binding<String> {
        Binding(
            get: { "\(connection.width)x\(connection.height)" },
            set: { newID in
                if let p = SizePreset.presets.first(where: { $0.id == newID }) {
                    connection.width = p.width
                    connection.height = p.height
                }
            }
        )
    }

    private func save() {
        var c = connection
        c.name = c.name.trimmingCharacters(in: .whitespaces)
        c.host = c.host.trimmingCharacters(in: .whitespaces)
        if !password.isEmpty && c.savePassword {
            Keychain.save(password: password, for: c.id)
        }
        onSave(c)
    }
}
