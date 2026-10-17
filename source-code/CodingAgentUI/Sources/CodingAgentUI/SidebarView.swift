import SwiftUI
import CodingAgentKit

// The sidebar: workspace and provider selection, the modes the CLI set from
// flags, session figures, and the MCP servers and skills the agent picked up
// from the harness config.

struct SidebarView: View {
    @Environment(AgentViewModel.self) private var model
    @State private var modelDraft = ""

    var body: some View {
        List {
            workspaceSection
            providerSection
            modeSection
            sessionSection
            if !model.mcpServers.isEmpty { mcpSection }
            if !model.skills.isEmpty { skillsSection }
            commandsSection
        }
        .listStyle(.sidebar)
        .onChange(of: model.currentModel) { modelDraft = model.currentModel }
        .onAppear { modelDraft = model.currentModel }
    }

    // ---- Workspace ----

    private var workspaceSection: some View {
        @Bindable var model = model
        return Section("Workspace") {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text((model.workspace?.directory ?? model.directory)
                    .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(model.workspace?.directory ?? model.directory)
            }
            Button("Change Directory…") { model.directoryPickerPresented = true }
                .disabled(model.isBusy)

            if let w = model.workspace {
                configRow("Global config", path: w.globalConfigPath, exists: w.globalConfigExists)
                configRow("Project config", path: w.localConfigPath, exists: w.localConfigExists)
                LabeledContent("make check") {
                    statusTag(w.hasMakefile ? "Makefile found" : "no Makefile",
                              ok: w.hasMakefile)
                }
            }
        }
    }

    private func configRow(_ label: String, path: String, exists: Bool) -> some View {
        LabeledContent(label) {
            statusTag(exists ? "loaded" : "absent", ok: exists)
                .help(path)
        }
    }

    private func statusTag(_ text: String, ok: Bool) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(ok ? Color.secondary : Color.orange)
    }

    // ---- Provider and model ----

    private var providerSection: some View {
        Section("Provider") {
            Picker("Profile", selection: providerBinding) {
                ForEach(model.providers) { p in
                    Text(p.isReady ? p.name : "\(p.name) ⚠︎").tag(p.name)
                }
            }
            if let info = model.providers.first(where: { $0.name == model.activeProvider }) {
                LabeledContent("Type") { Text(info.kind.rawValue).font(.caption) }
                if !info.isReady, let env = info.apiKeyEnv {
                    Text("Set \(env) in the environment, then relaunch.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if info.kind == .apple, let warning = model.appleWarning {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
            }

            TextField("Model", text: $modelDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onSubmit { model.setModel(modelDraft) }
            if !model.configuredModels.isEmpty {
                DisclosureGroup("Configured models") {
                    ForEach(model.configuredModels, id: \.self) { id in
                        Button {
                            modelDraft = id
                            model.setModel(id)
                        } label: {
                            Text(id).font(.caption.monospaced()).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(id == model.currentModel ? Color.accentColor : Color.primary)
                    }
                }
                .font(.caption)
            }
            Button("Apply Model") { model.setModel(modelDraft) }
                .disabled(modelDraft.trimmingCharacters(in: .whitespaces).isEmpty
                          || modelDraft == model.currentModel)
        }
    }

    private var providerBinding: Binding<String> {
        Binding(get: { model.activeProvider }, set: { model.selectProvider($0) })
    }

    // ---- Modes (the CLI's flags) ----

    private var modeSection: some View {
        Section("Mode") {
            boolToggle("Dry run (never write)", \.dryRun)
            boolToggle("Auto-approve edits", \.autoApprove)
            boolToggle("Web search", \.webSearch)
            if model.options.webSearch {
                Picker("Engine", selection: engineBinding) {
                    ForEach(SearchEngine.allCases, id: \.self) { engine in
                        Text(engine.rawValue.capitalized).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                Text("Needs \(model.options.searchEngine == .brave ? "BRAVE" : "EXA")_SEARCH_API_KEY.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            boolToggle("Show tool calls", \.showToolChatter)
            boolToggle("Debug raw traffic", \.debug)
        }
    }

    private func boolToggle(_ title: String, _ keyPath: WritableKeyPath<AgentOptions, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { model.options[keyPath: keyPath] },
            set: { newValue in model.update { $0[keyPath: keyPath] = newValue } }))
            .font(.callout)
    }

    private var engineBinding: Binding<SearchEngine> {
        Binding(get: { model.options.searchEngine },
                set: { engine in model.update { $0.searchEngine = engine } })
    }

    // ---- Session figures ----

    private var sessionSection: some View {
        Section("Session") {
            let t = model.tokens
            LabeledContent("Messages") { Text("\(model.context.messages)").font(.caption) }
            LabeledContent("Context") {
                Text("\(model.context.chars) chars ≈ \(model.context.estimatedTokens) tok")
                    .font(.caption)
            }
            if t.totalTokens > 0 || t.promptTokens > 0 {
                LabeledContent("Prompt") { Text("\(t.promptTokens)").font(.caption) }
                LabeledContent("Completion") { Text("\(t.completionTokens)").font(.caption) }
                if t.cachedTokens > 0 {
                    LabeledContent("Cached") { Text("\(t.cachedTokens)").font(.caption) }
                }
                if let cost = t.estimatedCostUSD {
                    LabeledContent("Est. cost") {
                        Text(String(format: "$%.6f", cost)).font(.caption)
                    }
                }
            }
            if !t.note.isEmpty {
                Text(t.note).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Reset") { model.resetConversation() }
                    .help("Clear conversation history (/reset)")
                Button("Compact") { model.runCommand("/compact") }
                    .disabled(model.isBusy)
                    .help("Summarize history to save tokens (/compact)")
                Button("Summarize") { model.runCommand("/summary") }
                    .disabled(model.isBusy)
                    .help("Summarize the source files in this directory (/summary)")
            }
            .font(.caption)
        }
    }

    // ---- MCP servers ----

    private var mcpSection: some View {
        Section("MCP Servers") {
            ForEach(model.mcpServers) { server in
                DisclosureGroup {
                    ForEach(server.tools, id: \.self) { tool in
                        Text(tool)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(server.running ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(server.name).font(.callout)
                        Spacer()
                        Text("\(server.tools.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
        }
    }

    // ---- Skills ----

    private var skillsSection: some View {
        Section("Skills") {
            ForEach(model.skills) { skill in
                Button {
                    model.runCommand("/\(skill.name)")
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("/\(skill.name)").font(.caption.monospaced())
                        if let summary = skill.summary {
                            Text(summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)
            }
        }
    }

    // ---- Commands (REPL parity) ----

    private var commandsSection: some View {
        Section("Commands") {
            ForEach(commandHelp, id: \.0) { command, help in
                Button {
                    model.runCommand(command)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(command).font(.caption.monospaced())
                        Text(help).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)
            }
        }
    }

    private let commandHelp: [(String, String)] = [
        ("/context", "context breakdown"),
        ("/history", "dump message log"),
        ("/tokens", "usage and cost"),
        ("/mcp", "MCP servers and tools"),
        ("/skills", "list skills"),
        ("/search", "toggle web search"),
        ("/debug", "toggle raw logging"),
        ("/help", "command help"),
    ]
}
