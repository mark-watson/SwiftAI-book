import SwiftUI
import AppKit
import CodingAgentKit

// CodingAgentUI -- a SwiftUI front end for the CodingCLI_swift coding agent.
//
// The agent runs in-process as the CodingAgentKit library: same tool loop,
// same six tools, same providers, MCP servers, and skills as the terminal
// REPL. The difference is the front end -- stdout becomes a transcript of
// typed events, and the y/n/s diff prompt becomes an approval card that the
// agent awaits.
//
// Run with `make run` (a bare executable) or `make open` (a real .app bundle).
// Nothing here is sandboxed, so the agent reads and writes the project
// directory you pick, exactly as the CLI does, and every write still goes
// through the approval gate.

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` produces a plain executable, not an .app bundle, so
        // LaunchServices starts it as an accessory process: the window opens
        // but never becomes key, and keystrokes keep going to the terminal
        // that launched it. Claiming the regular policy and activating puts
        // the app in the Dock and gives the window keyboard focus.
        // `make open` builds a bundle, where this is already the default.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Without a bundle there is no Dock icon to relaunch from, so closing the
    // window should end the process rather than leave it running invisibly.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct CodingAgentUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AgentViewModel()

    var body: some Scene {
        WindowGroup("Coding Agent") {
            ContentView()
                .environment(model)
                .frame(minWidth: 940, minHeight: 620)
        }
        .commands {
            CommandMenu("Agent") {
                Button("Reset Conversation") { model.resetConversation() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Divider()
                Button("Show Context (/context)") { model.runCommand("/context") }
                Button("Compact Context (/compact)") { model.runCommand("/compact") }
                Button("Summarize Project (/summary)") { model.runCommand("/summary") }
                Button("Token Usage (/tokens)") { model.runCommand("/tokens") }
                Button("MCP Servers (/mcp)") { model.runCommand("/mcp") }
                Button("Skills (/skills)") { model.runCommand("/skills") }
                Divider()
                Button("Stop Turn") { model.cancel() }
                    .keyboardShortcut(".", modifiers: [.command])
                    .disabled(!model.isBusy)
            }
        }
    }
}
