// main.swift -- Rubber bridge in a native macOS WebKit window.
//
// You play South against three computer players. Run with:
//     swift run bridge
// Or headless simulation:
//     swift run bridge --simulate

import Cocoa
import BridgeEngine

let args = CommandLine.arguments

if args.contains("--help") || args.contains("-h") {
    print("""
    Rubber Bridge — Swift WebKit

    Usage:
      swift run bridge             Launch native macOS WebKit game
      swift run bridge --simulate  Run 20 automated headless rubbers
      swift run bridge --help      Show this help message
    """)
    exit(0)
}

if args.contains("--simulate") || args.contains("--headless") {
    print("Starting headless simulation of 20 rubbers...")
    let service = BridgeEngineService()

    func randomLegalBid(state: [String: Any]) -> String {
        let history = (state["bidHistory"] as? [[String: String]]) ?? []
        var highestBid: Call? = nil
        for entry in history {
            if let bidStr = entry["beBid"], let call = Call(string: bidStr), case .bid = call {
                highestBid = call
            }
        }

        var options = ["Pass"]
        for level in 1...7 {
            for strain in Strain.allCases {
                let candidate = Call.bid(level: level, strain: strain)
                if highestBid == nil || candidate.isHigher(than: highestBid!) {
                    options.append(candidate.description)
                }
            }
        }

        if Double.random(in: 0..<1.0) < 0.7 {
            return "Pass"
        }
        let pickIdx = min(3, options.count - 1)
        return options[pickIdx]
    }

    for i in 1...20 {
        service.resetSession()
        var state = service.handleCommand(command: "get-state", payload: [:])
        var steps = 0

        while steps < 5000 {
            steps += 1
            if let err = state["error"] {
                print("Rubber \(i) error at step \(steps): \(err)")
                exit(1)
            }

            guard let phase = state["phase"] as? String else {
                print("Rubber \(i): missing phase")
                exit(1)
            }

            if phase == "Done" {
                break
            } else if phase == "Scoring" {
                state = service.handleCommand(command: "next-deal", payload: [:])
            } else if phase == "Bidding" {
                let bid = randomLegalBid(state: state)
                state = service.handleCommand(command: "bid", payload: ["bid": bid])
            } else if phase == "Playing" {
                let legal = (state["legalCards"] as? [String]) ?? []
                if legal.isEmpty {
                    state = service.handleCommand(command: "ai-play-single", payload: [:])
                } else {
                    let chosen = legal.randomElement()!
                    state = service.handleCommand(command: "play-card", payload: ["card": chosen])
                }
            }
        }

        guard let rs = state["rubberState"] as? [String: Any],
              let nsGames = rs["nsGames"] as? Int,
              let ewGames = rs["ewGames"] as? Int else {
            print("Rubber \(i): missing rubberState")
            exit(1)
        }

        let deals = rs["dealsPlayed"] as? Int ?? 0
        let winner = nsGames >= 2 ? "North-South" : "East-West"
        print("  Rubber \(String(format: "%2d", i)): Won by \(winner) in \(deals) deals (Games: NS \(nsGames) - EW \(ewGames))")
    }

    print("All 20 rubbers completed successfully!")
    exit(0)
}

// GUI Mode
let app = NSApplication.shared
app.setActivationPolicy(.regular)

let delegate = AppDelegate()
app.delegate = delegate

print("Starting Swift Rubber Bridge WebKit application...")
app.run()
