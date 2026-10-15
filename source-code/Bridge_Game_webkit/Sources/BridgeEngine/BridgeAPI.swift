// BridgeAPI.swift -- session state, command handlers, and JSON marshalling.

import Foundation

public struct Session {
    public var game: Game
    public var rubber: Rubber
    public var lastTrick: [PlayedCard] // Last completed trick in play order
    public var rubberTricksNs: Int // Tricks won in finished deals of this rubber
    public var rubberTricksEw: Int

    public init(
        game: Game,
        rubber: Rubber,
        lastTrick: [PlayedCard] = [],
        rubberTricksNs: Int = 0,
        rubberTricksEw: Int = 0
    ) {
        self.game = game
        self.rubber = rubber
        self.lastTrick = lastTrick
        self.rubberTricksNs = rubberTricksNs
        self.rubberTricksEw = rubberTricksEw
    }

    public static func vulnerability(for rubber: Rubber) -> String {
        switch (rubber.nsVul, rubber.ewVul) {
        case (true, true): return "Both"
        case (true, false): return "NsOnly"
        case (false, true): return "EwOnly"
        case (false, false): return "None"
        }
    }

    public static func deal(for rubber: Rubber) -> Game {
        var g = Game(
            dealer: rubber.dealer,
            vulnerability: vulnerability(for: rubber),
            human: .south
        )
        g.runAIBidding()
        return g
    }

    public static func freshSession() -> Session {
        let rs = Rubber.newRubber()
        return Session(game: deal(for: rs), rubber: rs)
    }

    public mutating func nextDeal() {
        let finishedDealsNs = rubberTricksNs + game.tricksNs
        let finishedDealsEw = rubberTricksEw + game.tricksEw
        self.rubberTricksNs = finishedDealsNs
        self.rubberTricksEw = finishedDealsEw
        self.lastTrick = []
        self.game = Session.deal(for: rubber)
    }

    public mutating func playAndScore(card: Card) {
        guard let actor = game.currentActor else { return }
        var currentTrickWithCard = game.currentTrick
        currentTrickWithCard.append(PlayedCard(player: actor, card: card))

        game.applyCardPlay(card)

        let completedTrick = (currentTrickWithCard.count == 4) ? currentTrickWithCard : []
        self.lastTrick = completedTrick

        if game.phase == .scoring {
            guard let contract = game.contract,
                  case let .bid(level, strain) = contract,
                  let declarer = game.declarer else { return }

            let tricksWon = (declarer.side == 0) ? game.tricksNs : game.tricksEw
            let (rs1, _) = Scoring.scoreDeal(
                level: level,
                strain: strain,
                tricksWon: tricksWon,
                declarer: declarer,
                doubled: game.doubled,
                rubber: rubber
            )

            var rs2 = rs1
            rs2.dealsPlayed += 1
            rs2.dealer = rubber.dealer.next
            self.rubber = rs2
        }
    }
}

public class BridgeEngineService {
    public private(set) var session: Session

    public init(session: Session? = nil) {
        self.session = session ?? Session.freshSession()
    }

    public func resetSession() {
        self.session = Session.freshSession()
    }

    // -----------------------------------------------------------------------
    // Command Handlers
    // -----------------------------------------------------------------------

    public func handleCommand(command: String, payload: [String: Any]) -> [String: Any] {
        switch command {
        case "get-state":
            return stateDictionary()
        case "bid":
            return doBid(payload: payload)
        case "play-card":
            return doPlayCard(payload: payload)
        case "ai-play-single":
            return doAIPlaySingle()
        case "next-deal":
            session.nextDeal()
            return stateDictionary()
        case "reset-game":
            resetSession()
            return stateDictionary()
        default:
            return ["error": "Unknown command: \(command)"]
        }
    }

    public func handleCommandJSON(command: String, payloadJSON: String) -> String {
        let payloadDict: [String: Any]
        if let data = payloadJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data, options: []),
           let dict = obj as? [String: Any] {
            payloadDict = dict
        } else {
            payloadDict = [:]
        }

        let responseDict = handleCommand(command: command, payload: payloadDict)
        if let data = try? JSONSerialization.data(withJSONObject: responseDict, options: []),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{\"error\": \"JSON serialization failed\"}"
    }

    private func doBid(payload: [String: Any]) -> [String: Any] {
        let g = session.game
        guard g.phase == .bidding else {
            return ["error": "The auction is over."]
        }
        guard g.currentActor == .south else {
            return ["error": "It is not your turn to bid."]
        }

        guard let bidStr = payload["bid"] as? String else {
            return ["error": "Missing bid parameter"]
        }
        guard let call = Call(string: bidStr) else {
            return ["error": "Failed to parse bid: \(bidStr)"]
        }
        guard AuctionRules.isLegalCall(call, for: .south, in: g.bidHistory) else {
            return ["error": "Bid \(bidStr) is not legal."]
        }

        var newGame = g
        newGame.applyBid(call)
        newGame.runAIBidding()

        if newGame.phase == .done {
            // Passed out: the deal moves to the next dealer
            var rs = session.rubber
            rs.dealer = rs.dealer.next
            session.rubber = rs
            session.game = Session.deal(for: rs)
            session.lastTrick = []
        } else {
            session.game = newGame
            session.lastTrick = []
        }

        return stateDictionary()
    }

    private func doPlayCard(payload: [String: Any]) -> [String: Any] {
        let g = session.game
        guard g.phase == .playing else {
            return ["error": "No card play is in progress."]
        }
        guard let actor = g.currentActor else {
            return ["error": "No active player."]
        }
        guard g.humanControls(player: actor) else {
            return ["error": "It is \(actor)'s turn, not yours."]
        }

        guard let cardStr = payload["card"] as? String else {
            return ["error": "Missing card parameter"]
        }
        guard let card = Card(code: cardStr) else {
            return ["error": "Failed to parse card: \(cardStr)"]
        }
        let legal = g.legalCards(for: actor)
        guard legal.contains(card) else {
            return ["error": "Card \(cardStr) is not a legal play."]
        }

        session.playAndScore(card: card)
        return stateDictionary()
    }

    private func doAIPlaySingle() -> [String: Any] {
        let g = session.game
        guard g.phase == .playing else {
            return ["error": "No card play is in progress."]
        }
        guard let actor = g.currentActor else {
            return ["error": "No active player."]
        }
        guard !g.humanControls(player: actor) else {
            return ["error": "It is your turn to play, not the computer's."]
        }

        let card = g.aiCard()
        session.playAndScore(card: card)
        return stateDictionary()
    }

    // -----------------------------------------------------------------------
    // State Dictionary Marshalling (matches index.html expectations)
    // -----------------------------------------------------------------------

    public func stateDictionary() -> [String: Any] {
        let g = session.game
        let rs = session.rubber
        let actor = g.currentActor
        let phase = g.phase
        let humanTurn = (actor != nil && phase == .playing && g.humanControls(player: actor!))

        let reportedPhase: String
        if phase == .scoring && rs.isComplete {
            reportedPhase = "Done"
        } else {
            reportedPhase = phase.rawValue
        }

        func handsDict(_ hands: [Player: [Card]]) -> [String: [String]] {
            [
                "hlNorth": (hands[.north] ?? []).map { $0.code },
                "hlEast": (hands[.east] ?? []).map { $0.code },
                "hlSouth": (hands[.south] ?? []).map { $0.code },
                "hlWest": (hands[.west] ?? []).map { $0.code }
            ]
        }

        func playedList(_ pcs: [PlayedCard]) -> [[String: String]] {
            pcs.map {
                ["pcPlayer": $0.player.rawValue, "pcCard": $0.card.code]
            }
        }

        let bidHistoryList: [[String: String]] = g.bidHistory.map {
            ["bePlayer": $0.player.rawValue, "beBid": $0.call.description]
        }

        let rubberDict: [String: Any] = [
            "nsBelow": rs.nsBelow,
            "ewBelow": rs.ewBelow,
            "nsAbove": rs.nsAbove,
            "ewAbove": rs.ewAbove,
            "nsGames": rs.nsGames,
            "ewGames": rs.ewGames,
            "nsVulnerable": rs.nsVul,
            "ewVulnerable": rs.ewVul,
            "currentDealer": rs.dealer.rawValue,
            "dealsPlayed": rs.dealsPlayed
        ]

        let dummyVisible = (phase == .playing) && (
            g.tricksPlayed > 0 ||
            !g.currentTrick.isEmpty ||
            humanTurn
        )

        var dict: [String: Any] = [
            "phase": reportedPhase,
            "dealer": g.dealer.rawValue,
            "vulnerability": g.vulnerability,
            "humanPlayer": g.human.rawValue,
            "hands": handsDict(g.hands),
            "originalHands": handsDict(g.originalHands),
            "bidHistory": bidHistoryList,
            "doubled": g.doubled,
            "dummyVisible": dummyVisible,
            "currentTrick": playedList(g.currentTrick),
            "lastCompletedTrick": playedList(session.lastTrick),
            "trickLead": g.trickLead.rawValue,
            "tricksNs": g.tricksNs,
            "tricksEw": g.tricksEw,
            "tricksPlayed": g.tricksPlayed,
            "rubberState": rubberDict,
            "legalCards": humanTurn ? g.legalCards(for: actor!).map { $0.code } : [],
            "dealNum": rs.dealsPlayed + (phase == .scoring ? 0 : 1),
            "totalTricksNs": session.rubberTricksNs + g.tricksNs,
            "totalTricksEw": session.rubberTricksEw + g.tricksEw
        ]

        if let a = actor {
            dict["activeActor"] = a.rawValue
        } else {
            dict["activeActor"] = NSNull()
        }

        if let c = g.contract {
            dict["contract"] = c.description
        } else {
            dict["contract"] = NSNull()
        }

        if let decl = g.declarer {
            dict["declarer"] = decl.rawValue
        } else {
            dict["declarer"] = NSNull()
        }

        if let dum = g.dummy {
            dict["dummy"] = dum.rawValue
        } else {
            dict["dummy"] = NSNull()
        }

        if let trump = g.trump {
            dict["trumpSuit"] = trump.name
        } else {
            dict["trumpSuit"] = NSNull()
        }

        return dict
    }
}
