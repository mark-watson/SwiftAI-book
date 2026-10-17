import SwiftUI
import CodingAgentKit

// The transcript: every ConsoleEvent the agent produced, rendered by kind.
// Tool chatter, diffs, and raw debug dumps are collapsed by default so the
// assistant's prose stays readable.

extension TranscriptKind {
    var label: String {
        switch self {
        case .user: return "You"
        case .assistant: return "Assistant"
        case .toolCall: return "Tool call"
        case .toolResult: return "Result"
        case .diff: return "Diff"
        case .decision: return "Decision"
        case .intent: return "Intent"
        case .log: return "Agent"
        case .error: return "Error"
        case .debug: return "Debug"
        case .status: return ""
        }
    }

    var color: Color {
        switch self {
        case .user: return .accentColor
        case .assistant: return .primary
        case .toolCall: return .teal
        case .toolResult: return .secondary
        case .diff: return .purple
        case .decision: return .orange
        case .intent: return .secondary
        case .log: return .primary
        case .error: return .red
        case .debug: return .gray
        case .status: return .secondary
        }
    }

    /// Kinds that are usually noise until you need them.
    var collapsible: Bool {
        switch self {
        case .toolCall, .toolResult, .debug, .log: return true
        default: return false
        }
    }

    var systemImage: String {
        switch self {
        case .user: return "person.crop.circle"
        case .assistant: return "sparkles"
        case .toolCall: return "hammer"
        case .toolResult: return "arrow.return.left"
        case .diff: return "doc.text"
        case .decision: return "checkmark.seal"
        case .intent: return "arrow.triangle.branch"
        case .log: return "text.alignleft"
        case .error: return "exclamationmark.triangle"
        case .debug: return "ant"
        case .status: return "info.circle"
        }
    }
}

struct TranscriptView: View {
    @Environment(AgentViewModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if model.transcript.isEmpty {
                        EmptyTranscriptHint()
                            .padding(.top, 60)
                    }
                    ForEach(model.transcript) { item in
                        TranscriptRow(item: item)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Log lines are merged into an existing row, so the count can stay
            // the same while the transcript grows: scroll on the revision.
            .onChange(of: model.transcriptRevision) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: model.pendingApproval?.id) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

private struct EmptyTranscriptHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("No conversation yet", systemImage: "sparkles")
                .font(AppFont.title3)
            Text("""
            Ask for a change in the field below. The agent reads files with \
            read_file, list_dir, and grep, then proposes edits you approve one \
            diff at a time. Every accepted edit runs `make check`.

            Type / for commands, or use the sidebar to switch provider, model, \
            and mode.
            """)
            .font(AppFont.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 520, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct TranscriptRow: View {
    let item: TranscriptItem
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if !item.kind.collapsible || expanded {
                content
            }
        }
        .padding(.vertical, 3)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if !item.kind.label.isEmpty {
                Image(systemName: item.kind.systemImage)
                    .font(AppFont.caption2)
                    .foregroundStyle(item.kind.color)
                Text(item.kind.label)
                    .font(AppFont.captionStrong)
                    .foregroundStyle(item.kind.color)
            }
            // For tool rows the title is the tool name; for diffs, the path.
            if item.kind == .toolCall || item.kind == .toolResult || item.kind == .diff
                || item.kind == .decision {
                Text(item.title)
                    .font(AppFont.monoCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !item.detail.isEmpty {
                Text(item.detail)
                    .font(AppFont.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            Spacer(minLength: 0)
            if item.kind.collapsible {
                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(AppFont.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help(expanded ? "Collapse" : "Expand")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .diff:
            DiffView(diff: item.body)
        case .toolCall, .toolResult, .debug:
            mono(item.body, maxHeight: item.kind == .toolResult ? 240 : 160)
        case .status, .intent:
            Text(item.body)
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        case .error:
            Text(item.body)
                .font(AppFont.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        case .user:
            Text(item.body)
                .font(AppFont.body)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 7))
        case .assistant:
            Text(item.body)
                .font(AppFont.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Text(item.body)
                .font(AppFont.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func mono(_ text: String, maxHeight: CGFloat) -> some View {
        ScrollView {
            Text(text.isEmpty ? "(empty)" : text)
                .font(AppFont.monoCaption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(maxHeight: maxHeight)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary))
    }
}

// ---------------------------------------------------------------------------
// Unified diff rendering. The kit hands over raw `diff -u` output (Settings.color
// is off, so no ANSI), and the view does the colorizing the terminal used to.

struct DiffLine: Equatable {
    enum Kind { case fileHeader, hunk, addition, deletion, context }
    let kind: Kind
    let text: String

    var color: Color {
        switch kind {
        case .fileHeader: return .secondary
        case .hunk: return .cyan
        case .addition: return .green
        case .deletion: return .red
        case .context: return .primary.opacity(0.8)
        }
    }

    var background: Color {
        switch kind {
        case .addition: return .green.opacity(0.12)
        case .deletion: return .red.opacity(0.12)
        case .hunk: return .cyan.opacity(0.08)
        default: return .clear
        }
    }

    static func parse(_ diff: String) -> [DiffLine] {
        diff.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
            let line = String(raw)
            let kind: Kind
            if line.hasPrefix("+++") || line.hasPrefix("---") { kind = .fileHeader }
            else if line.hasPrefix("@@") { kind = .hunk }
            else if line.hasPrefix("+") { kind = .addition }
            else if line.hasPrefix("-") { kind = .deletion }
            else { kind = .context }
            return DiffLine(kind: kind, text: line)
        }
    }
}

struct DiffView: View {
    let diff: String

    var body: some View {
        let lines = DiffLine.parse(diff)
        VStack(alignment: .leading, spacing: 0) {
            if lines.isEmpty || (lines.count == 1 && lines[0].text.isEmpty) {
                Text("No textual difference (the file would be rewritten with identical bytes).")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(AppFont.monoCaption)
                        .foregroundStyle(line.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(line.background)
                        .textSelection(.enabled)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary))
    }
}
