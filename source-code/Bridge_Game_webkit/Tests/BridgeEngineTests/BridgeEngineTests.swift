// BridgeEngineTests.swift -- unit tests and headless simulation.

import XCTest
@testable import BridgeEngine

final class BridgeEngineTests: XCTestCase {

    private func cards(_ codes: String...) -> [Card] {
        codes.compactMap { Card(code: $0) }
    }

    // -----------------------------------------------------------------------
    // Cards & Deck Tests
    // -----------------------------------------------------------------------

    func testCardsAndHands() {
        XCTAssertEqual(Card(suit: .hearts, rank: 10).code, "10H")
        XCTAssertEqual(Card(code: "as"), Card(suit: .spades, rank: Card.ace))
        XCTAssertNil(Card(code: "1S"))

        let testHand = cards("AS", "KH", "QD", "JC", "2C")
        XCTAssertEqual(HandEvaluator.handHCP(testHand), 10)

        let hands = Deck.dealHands(deck: Deck.makeDeck())
        var total = 0
        for p in Player.allCases {
            let h = hands[p] ?? []
            XCTAssertEqual(h.count, 13)
            total += h.count
        }
        XCTAssertEqual(total, 52)
    }

    // -----------------------------------------------------------------------
    // Bidding Tests
    // -----------------------------------------------------------------------

    func testBidsAndAuction() {
        XCTAssertEqual(Call(string: "3nt"), .bid(level: 3, strain: .notrump))
        XCTAssertEqual(Call(string: "XX"), .redouble)
        XCTAssertTrue(Call.bid(level: 2, strain: .clubs).isHigher(than: .bid(level: 1, strain: .notrump)))
        XCTAssertEqual(Call.bid(level: 4, strain: .spades).description, "4S")

        // Chronological history: North bids 1H, then East, South, West pass
        let h1: [BidEntry] = [
            BidEntry(player: .north, call: .bid(level: 1, strain: .hearts)),
            BidEntry(player: .east, call: .pass),
            BidEntry(player: .south, call: .pass),
            BidEntry(player: .west, call: .pass)
        ]
        XCTAssertTrue(AuctionRules.isBiddingComplete(h1))
        let extracted1 = AuctionRules.extractContract(from: h1)
        XCTAssertNotNil(extracted1)
        XCTAssertEqual(extracted1?.contract, .bid(level: 1, strain: .hearts))
        XCTAssertEqual(extracted1?.declarer, .north)
        XCTAssertEqual(extracted1?.doubled, 0)

        // Redouble auction
        let h2: [BidEntry] = [
            BidEntry(player: .north, call: .bid(level: 1, strain: .hearts)),
            BidEntry(player: .east, call: .double),
            BidEntry(player: .south, call: .redouble),
            BidEntry(player: .west, call: .pass),
            BidEntry(player: .north, call: .pass),
            BidEntry(player: .east, call: .pass)
        ]
        XCTAssertTrue(AuctionRules.isBiddingComplete(h2))
        let extracted2 = AuctionRules.extractContract(from: h2)
        XCTAssertNotNil(extracted2)
        XCTAssertEqual(extracted2?.doubled, 2)

        let oneH = [BidEntry(player: .north, call: .bid(level: 1, strain: .hearts))]
        XCTAssertTrue(AuctionRules.isLegalCall(.double, for: .east, in: oneH))
        XCTAssertFalse(AuctionRules.isLegalCall(.double, for: .south, in: oneH))
    }

    func testAIBidding() {
        let bigHand = cards("AS", "KS", "QS", "AH", "KH", "QH", "AD", "KD", "QD", "AC", "2C", "3C", "4C")
        XCTAssertEqual(AIBidder.openingBid(for: bigHand), .bid(level: 2, strain: .clubs))

        let ntHand = cards("AS", "KS", "5S", "AH", "4H", "3H", "KD", "QD", "2D", "JC", "4C", "3C", "2C")
        XCTAssertEqual(AIBidder.openingBid(for: ntHand), .bid(level: 1, strain: .notrump))
    }

    // -----------------------------------------------------------------------
    // Trick Taking Tests
    // -----------------------------------------------------------------------

    func testTrickTaking() {
        let trick1: [PlayedCard] = [
            PlayedCard(player: .north, card: Card(code: "2H")!),
            PlayedCard(player: .east, card: Card(code: "AH")!),
            PlayedCard(player: .south, card: Card(code: "3S")!),
            PlayedCard(player: .west, card: Card(code: "KH")!)
        ]
        XCTAssertEqual(TrickRules.trickWinner(trick: trick1, trump: .spades), .south)
        XCTAssertEqual(TrickRules.trickWinner(trick: trick1, trump: nil), .east)

        let hand = cards("AS", "2H", "3H")
        let legal = TrickRules.legalPlays(hand: hand, leadSuit: .hearts)
        XCTAssertEqual(legal, cards("2H", "3H"))
    }

    // -----------------------------------------------------------------------
    // Scoring Tests
    // -----------------------------------------------------------------------

    func testScoring() {
        // 4S made exactly (10 tricks), not vulnerable -> wins a game
        let res1 = Scoring.scoreDeal(
            level: 4,
            strain: .spades,
            tricksWon: 10,
            declarer: .south,
            doubled: 0,
            rubber: Rubber.newRubber()
        )
        XCTAssertEqual(res1.score, 120)
        XCTAssertEqual(res1.rubber.nsGames, 1)
        XCTAssertTrue(res1.rubber.nsVul)

        // 3NT doubled, vulnerable, down two
        var vulRubber = Rubber.newRubber()
        vulRubber.ewVul = true
        let res2 = Scoring.scoreDeal(
            level: 3,
            strain: .notrump,
            tricksWon: 7,
            declarer: .east,
            doubled: 1,
            rubber: vulRubber
        )
        XCTAssertEqual(res2.score, -500)
        XCTAssertEqual(res2.rubber.nsAbove, 500)
    }

    // -----------------------------------------------------------------------
    // Headless Simulation (Port of tests.rkt play-rubber)
    // -----------------------------------------------------------------------

    private func randomLegalBid(state: [String: Any]) -> String {
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

        // Mostly pass so auctions terminate quickly, occasionally bid low
        if Double.random(in: 0..<1.0) < 0.7 {
            return "Pass"
        }
        let pickIdx = min(3, options.count - 1)
        return options[pickIdx]
    }

    private func playRubberSimulation(service: BridgeEngineService) -> [String: Any] {
        service.resetSession()
        var state = service.handleCommand(command: "get-state", payload: [:])
        var steps = 0

        while steps < 5000 {
            steps += 1
            XCTAssertNil(state["error"], "Unexpected error state: \(state)")

            guard let phase = state["phase"] as? String else {
                XCTFail("Missing phase in state")
                return state
            }

            switch phase {
            case "Done":
                return state
            case "Scoring":
                state = service.handleCommand(command: "next-deal", payload: [:])
            case "Bidding":
                XCTAssertEqual(state["activeActor"] as? String, "South")
                let bid = randomLegalBid(state: state)
                state = service.handleCommand(command: "bid", payload: ["bid": bid])
            case "Playing":
                let legal = (state["legalCards"] as? [String]) ?? []
                if legal.isEmpty {
                    state = service.handleCommand(command: "ai-play-single", payload: [:])
                } else {
                    let chosen = legal.randomElement()!
                    state = service.handleCommand(command: "play-card", payload: ["card": chosen])
                }
            default:
                XCTFail("Unknown phase: \(phase)")
                return state
            }
        }

        XCTFail("Simulation did not terminate within 5000 steps")
        return state
    }

    func testHeadlessRubbersSimulation() {
        let service = BridgeEngineService()
        for _ in 1...20 {
            let finalState = playRubberSimulation(service: service)
            guard let rs = finalState["rubberState"] as? [String: Any],
                  let nsGames = rs["nsGames"] as? Int,
                  let ewGames = rs["ewGames"] as? Int else {
                XCTFail("Invalid rubberState in final state")
                continue
            }
            XCTAssertTrue(nsGames >= 2 || ewGames >= 2, "Rubber must conclude with 2 games won by either side")
        }
    }

    func testIllegalRequestsAreRejected() {
        let service = BridgeEngineService()
        service.resetSession()

        // Card play during bidding
        let r1 = service.handleCommand(command: "play-card", payload: ["card": "AS"])
        XCTAssertNotNil(r1["error"])

        // Malformed bid
        let r2 = service.handleCommand(command: "bid", payload: ["bid": "9Z"])
        XCTAssertNotNil(r2["error"])

        // Unknown command
        let r3 = service.handleCommand(command: "nonsense", payload: [:])
        XCTAssertNotNil(r3["error"])
    }
}
