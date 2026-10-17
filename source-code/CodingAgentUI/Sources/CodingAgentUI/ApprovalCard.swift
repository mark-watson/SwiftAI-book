import SwiftUI
import CodingAgentKit

// The diff gate. The agent's propose_edit tool is suspended inside
// ApprovalGate.decide until one of these buttons resumes it, so this card is
// pinned between the transcript and the input bar rather than floating: there
// is a turn waiting on it, and nothing else can proceed until it is answered.

struct ApprovalCard: View {
    @Environment(AgentViewModel.self) private var model
    @FocusState private var reasonFocused: Bool

    var body: some View {
        if let request = model.pendingApproval {
            VStack(alignment: .leading, spacing: 10) {
                header(request)
                ScrollView {
                    DiffView(diff: request.unifiedDiff)
                }
                .frame(maxHeight: 240)
                controls
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.5)))
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
    }

    private func header(_ request: ApprovalRequest) -> some View {
        HStack(spacing: 8) {
            Image(systemName: request.isNewFile ? "doc.badge.plus" : "pencil.line")
                .foregroundStyle(.orange)
            Text(request.isNewFile ? "Create file" : "Proposed edit")
                .font(AppFont.headline)
            Text(request.path)
                .font(AppFont.monoCallout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(request.path)
            Spacer()
            Label("Agent is waiting", systemImage: "hourglass")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Why? Sent back to the model with Skip", text: $model.skipReason)
                    .textFieldStyle(.roundedBorder)
                    .focused($reasonFocused)
                    .onSubmit { model.skip() }
                Button("Skip") { model.skip() }
                    .help("Refuse this edit and tell the model why, so it can take a different approach")
            }
            HStack(spacing: 10) {
                if model.options.dryRun {
                    Label("Dry run — nothing will be written", systemImage: "eye")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                } else if model.options.autoApprove {
                    Label("Auto-approve is on — edits apply without asking", systemImage: "bolt")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reject") { model.reject() }
                    .keyboardShortcut(.cancelAction)
                    .help("Refuse this edit (Esc)")
                Button("Approve") { model.approve() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .help("Write the file, then run `make check` (⌘↩)")
            }
        }
    }
}
