import Foundation

// Skills: ~/.agents/skills/<name>/SKILL.md, listed by /skills and loaded by
// /<skill-name>.

extension Agent {
    static var skillsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agents/skills")
    }

    static func skillFile(_ name: String) -> URL {
        skillsDir.appendingPathComponent(name).appendingPathComponent("SKILL.md")
    }

    static func listSkills() -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: skillsDir.path)) ?? []
        return entries.filter { FileManager.default.fileExists(atPath: skillFile($0).path) }.sorted()
    }

    // The YAML frontmatter `description:` field, if any.
    static func skillDescription(_ name: String) -> String? {
        guard let text = try? String(contentsOf: skillFile(name), encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { return nil }
            if line.hasPrefix("description:") {
                return line.dropFirst("description:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    func showSkills() {
        let skills = Self.listSkills()
        guard !skills.isEmpty else {
            Console.print("No skills found in \(Self.skillsDir.path)")
            return
        }
        Console.print("Available skills (from \(Self.skillsDir.path)):")
        for s in skills {
            if let d = Self.skillDescription(s) { Console.print("  /\(s) — \(d)") } else { Console.print("  /\(s)") }
        }
        Console.print("\nType /<skill-name> to load a skill into the conversation.")
    }

    func loadSkill(_ name: String) async {
        guard !name.contains("/"), !name.hasPrefix("."),
              let content = try? String(contentsOf: Self.skillFile(name), encoding: .utf8) else {
            Console.print("Unknown command or skill: /\(name)  (try /skills)")
            return
        }
        messages.append(["role": "system",
                         "content": .string("The user has loaded the following skill: '\(name)'. Use it as authoritative reference and guidance for subsequent responses in this conversation.\n\n" + content)])
        Console.print("Loaded skill: \(name)  (\(content.count) chars)")
        if let d = Self.skillDescription(name) { Console.print("  \(d)") }
        Console.print("\nAsking the model to load the skill into context...")
        let reply: String
        do {
            reply = try await llmChat(messages)
        } catch {
            reply = "(model call failed: \(error))"
        }
        Console.print("\n\(reply.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
}
