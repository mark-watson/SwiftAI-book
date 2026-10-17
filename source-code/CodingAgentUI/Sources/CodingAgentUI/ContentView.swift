import SwiftUI
import UniformTypeIdentifiers
import CodingAgentKit

struct ContentView: View {
    @Environment(AgentViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        return NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 270, ideal: 320, max: 420)
        } detail: {
            VStack(spacing: 0) {
                TranscriptView()
                if model.pendingApproval != nil {
                    ApprovalCard()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                InputBar()
            }
            .animation(.easeOut(duration: 0.18), value: model.pendingApproval?.id)
        }
        .navigationTitle("Coding Agent")
        // Default for controls and labels that do not set a font of their own
        // (buttons, pickers, list rows): the app-wide bump in Typography.swift.
        .font(AppFont.body)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.cancel()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
                .disabled(!model.isBusy)
                .help("Cancel the current turn (⌘.)")
            }
        }
        .task { model.start() }
        .fileImporter(isPresented: $model.directoryPickerPresented,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await model.open(url.path) }
        }
    }
}
