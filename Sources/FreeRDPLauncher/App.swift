import SwiftUI
import AppKit

@main
struct FreeRDPLauncherApp: App {
    @State private var store = ConnectionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 760, minHeight: 480)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct ContentView: View {
    @Environment(ConnectionStore.self) private var store

    @State private var selection: UUID?
    @State private var editing: Connection?          // non-nil = showing the edit form
    @State private var isNew = false
    @State private var freerdpInstalled = FreeRDPLocator.find() != nil

    // password prompt
    @State private var askPassword = false
    @State private var pendingConnection: Connection?
    @State private var promptPassword = ""
    @State private var promptSave = false

    @State private var errorText: String?

    private var selectedConnection: Connection? {
        store.connections.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $askPassword) { passwordSheet }
        .alert("FreeRDP error", isPresented: .constant(errorText != nil)) {
            Button("OK") { errorText = nil }
        } message: { Text(errorText ?? "") }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Connections") {
                    ForEach(store.connections) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name.isEmpty ? "Untitled" : c.name)
                                .font(.body)
                            Text("\(c.host)\(c.port == 3389 ? "" : ":\(c.port)")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(c.id)
                        .contextMenu {
                            Button("Connect") { connect(c) }
                            Button("Edit") { beginEdit(c) }
                            Button("Delete", role: .destructive) { store.delete(c) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            if !freerdpInstalled { notInstalledBanner }
        }
        .frame(minWidth: 220)
    }

    private var notInstalledBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("FreeRDP isn’t installed", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
            Text("Connections won’t launch. Install it:")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("brew install freerdp")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install freerdp", forType: .string)
                }
                Button("Re-check") { freerdpInstalled = FreeRDPLocator.find() != nil }
            }
        }
        .padding(10)
        .background(.quaternary)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let editing {
            ConnectionEditView(
                connection: editing,
                isNew: isNew,
                onSave: { saved in
                    if isNew { store.add(saved); selection = saved.id }
                    else { store.update(saved) }
                    self.editing = nil
                },
                onCancel: { self.editing = nil }
            )
            .id(editing.id)
        } else if let c = selectedConnection {
            DetailReadView(connection: c, onConnect: { connect(c) }, onEdit: { beginEdit(c) })
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "display").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No connection selected").font(.title3)
            Text("Add a remote desktop to get started.").foregroundStyle(.secondary)
            Button { beginAdd() } label: { Label("Add Connection", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button { beginAdd() } label: { Image(systemName: "plus") }
                .help("Add connection")
            Button { if let c = selectedConnection { beginEdit(c) } } label: { Image(systemName: "pencil") }
                .disabled(selectedConnection == nil)
                .help("Edit")
            Button { if let c = selectedConnection { store.delete(c); selection = nil } } label: { Image(systemName: "trash") }
                .disabled(selectedConnection == nil)
                .help("Delete")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { if let c = selectedConnection { connect(c) } } label: {
                Label("Connect", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedConnection == nil || !freerdpInstalled)
        }
    }

    // MARK: Actions

    private func beginAdd() {
        isNew = true
        editing = Connection()
    }

    private func beginEdit(_ c: Connection) {
        isNew = false
        selection = c.id
        editing = c
    }

    private func connect(_ c: Connection) {
        guard freerdpInstalled else { return }
        if let pw = Keychain.password(for: c.id) {
            doLaunch(c, password: pw)
        } else {
            pendingConnection = c
            promptPassword = ""
            promptSave = c.savePassword
            askPassword = true
        }
    }

    private func doLaunch(_ c: Connection, password: String) {
        do {
            try SessionLauncher.launch(c, password: password) { msg in
                errorText = msg
            }
            store.markUsed(c.id)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private var passwordSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Password for \(pendingConnection?.username ?? "")@\(pendingConnection?.host ?? "")")
                .font(.headline)
            SecureField("Password", text: $promptPassword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            Toggle("Save to Keychain", isOn: $promptSave)
            HStack {
                Spacer()
                Button("Cancel") { askPassword = false }
                Button("Connect") {
                    if let c = pendingConnection {
                        if promptSave { Keychain.save(password: promptPassword, for: c.id) }
                        doLaunch(c, password: promptPassword)
                    }
                    askPassword = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(promptPassword.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

// MARK: - Read-only detail

struct DetailReadView: View {
    let connection: Connection
    var onConnect: () -> Void
    var onEdit: () -> Void

    private var displaySummary: String {
        switch connection.display {
        case .dynamic: return "Dynamic" + (connection.scale != 100 ? " · \(connection.scale)%" : "")
        case .fullscreen: return "Fullscreen" + (connection.scale != 100 ? " · \(connection.scale)%" : "")
        case .fixed: return "\(connection.width)×\(connection.height)" + (connection.scale != 100 ? " · \(connection.scale)%" : "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(connection.name.isEmpty ? "Untitled" : connection.name)
                    .font(.largeTitle).bold()
                Spacer()
            }
            .padding(.bottom, 12)

            Form {
                LabeledContent("Host", value: "\(connection.host):\(connection.port)")
                LabeledContent("Username", value: connection.username.isEmpty ? "—" : connection.username)
                LabeledContent("Password", value: Keychain.hasPassword(for: connection.id) ? "Saved in Keychain" : "Ask on connect")
                LabeledContent("Display", value: displaySummary)
                LabeledContent("Clipboard", value: connection.clipboard ? "On" : "Off")
                LabeledContent("Audio", value: connection.audio.label)
                if let used = connection.lastUsed {
                    LabeledContent("Last connected", value: used.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .formStyle(.grouped)

            Spacer()
            HStack {
                Spacer()
                Button("Edit", action: onEdit)
                Button { onConnect() } label: { Label("Connect", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.top, 8)
        }
        .padding(20)
    }
}
