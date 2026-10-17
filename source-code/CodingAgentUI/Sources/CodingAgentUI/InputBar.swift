import SwiftUI
import CodingAgentKit

// The prompt field. Return sends, Option+Return inserts a newline, and typing
// "/" offers the same commands and skills the REPL's Tab completion did.

struct InputBar: View {
    @Environment(AgentViewModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 6) {
            if !model.slashSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.slashSuggestions, id: \.self) { suggestion in
                            Button {
                                model.draft = suggestion + " "
                                focused = true
                            } label: {
                                Text(suggestion)
                                    .font(.caption.monospaced())
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(promptPlaceholder, text: $model.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...6)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    .focused($focused)
                    .onSubmit { model.send() }

                Button {
                    if model.isBusy { model.cancel() } else { model.send() }
                } label: {
                    Image(systemName: model.isBusy ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(model.isBusy ? Color.red : Color.accentColor)
                        .symbolEffect(.pulse, isActive: model.isBusy)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .help(model.isBusy ? "Stop this turn (⌘.)" : "Send (⌘↩)")
                .disabled(!model.isBusy
                          && model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            statusBar
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .onAppear { focused = true }
    }

    private var promptPlaceholder: String {
        model.isBusy
            ? "Agent is working — Stop to interrupt"
            : "Ask for a change, or type / for a command"
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if model.isBusy {
                ProgressView().controlSize(.small)
                Text("Working…").font(.caption).foregroundStyle(.secondary)
            } else if let outcome = model.lastOutcome, outcome != .ok {
                Label(AgentViewModel.describe(outcome), systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(outcome == .interrupted ? Color.secondary : Color.orange)
            } else {
                Label("\(model.activeProvider) · \(model.currentModel)", systemImage: "cpu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if model.options.dryRun {
                Text("dry run").font(.caption2).padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            if model.options.autoApprove {
                Text("auto-approve").font(.caption2).padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.orange.opacity(0.2), in: Capsule())
            }
            Text("\(model.context.messages) msgs · ≈\(model.context.estimatedTokens) tok")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
