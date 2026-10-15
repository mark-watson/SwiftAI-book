// Engine.swift -- deal state machine: dealing, auction, and card play.

import Foundation

public enum Phase: String, Codable {
    case bidding = "Bidding"
    case playing = "Playing"
    case scoring = "Scoring"
    case done = "Done"
}

public struct Game: Codable {
    public var hands: [Player: [Card]]
    public var originalHands: [Player: [Card]]
    public var dealer: Player
    public var vulnerability: String // "None", "NsOnly", "EwOnly", "Both"
    public var human: Player // Seat person plays, always South
    public var bidHistory: [BidEntry] // Chronological order: first to last
    public var contract: Call? // .bid(level, strain) or nil
    public var declarer: Player?
    public var doubled: Int // 0, 1 or 2
    public var dummy: Player?
    public var currentTrick: [PlayedCard] // Cards in play order
    public var trickLead: Player // Who led (or will lead) the current trick
    public var tricksNs: Int
    public var tricksEw: Int
    public var tricksPlayed: Int
    public var trump: Suit?
    public var phase: Phase

    public init(
        dealer: Player,
        vulnerability: String,
        human: Player = .south,
        deck: [Card]? = nil
    ) {
        let deckToDeal = deck ?? Deck.makeDeck().shuffled()
        let dealtHands = Deck.dealHands(deck: deckToDeal)

        self.hands = dealtHands
        self.originalHands = dealtHands
        self.dealer = dealer
        self.vulnerability = vulnerability
        self.human = human
        self.bidHistory = []
        self.contract = nil
        self.declarer = nil
        self.doubled = 0
        self.dummy = nil
        self.currentTrick = []
        self.trickLead = dealer
        self.tricksNs = 0
        self.tricksEw = 0
        self.tricksPlayed = 0
        self.trump = nil
        self.phase = .bidding
    }

    public func hand(of player: Player) -> [Card] {
        hands[player] ?? []
    }

    /// Whose turn is it? nil once the deal or bidding is over.
    public var currentActor: Player? {
        switch phase {
        case .bidding:
            if bidHistory.isEmpty {
                return dealer
            }
            return bidHistory.last?.player.next
        case .playing:
            if currentTrick.isEmpty {
                return trickLead
            }
            return currentTrick.last?.player.next
        case .scoring, .done:
            return nil
        }
    }

    public var trickCards: [Card] {
        currentTrick.map { $0.card }
    }

    public var leadSuit: Suit? {
        currentTrick.first?.card.suit
    }

    /// The human controls South, and also North when North is dummy for N-S
    public func humanControls(player: Player) -> Bool {
        if player == human { return true }
        if player == dummy, let decl = declarer, decl.side == human.side {
            return true
        }
        return false
    }

    public func legalCards(for player: Player) -> [Card] {
        TrickRules.legalPlays(hand: hand(of: player), leadSuit: leadSuit)
    }

    // -----------------------------------------------------------------------
    // Bidding
    // -----------------------------------------------------------------------

    public mutating func applyBid(_ bid: Call) {
        guard let actor = currentActor else { return }
        bidHistory.append(BidEntry(player: actor, call: bid))

        if !AuctionRules.isBiddingComplete(bidHistory) {
            return
        }

        if let (contractCall, rawDeclarer, doubledState) = AuctionRules.extractContract(from: bidHistory) {
            // When partner North declares, swap North and South hands so person plays
            // as declarer from South and North becomes dummy.
            let swap = (rawDeclarer == human.partner && human == .south)
            if swap {
                let southCards = hands[.south] ?? []
                let northCards = hands[.north] ?? []
                hands[.north] = southCards
                hands[.south] = northCards
            }

            let effDeclarer = swap ? .south : rawDeclarer
            guard case let .bid(_, strain) = contractCall else { return }

            self.contract = contractCall
            self.declarer = effDeclarer
            self.doubled = doubledState
            self.dummy = effDeclarer.partner
            self.trump = strain.asSuit
            self.trickLead = effDeclarer.next
            self.phase = .playing
        } else {
            // Passed out
            self.phase = .done
        }
    }

    /// Let the computer bid for every seat until it is the human's turn or auction finishes
    public mutating func runAIBidding() {
        while phase == .bidding, let actor = currentActor, actor != human {
            let aiBid = AIBidder.selectBid(for: hand(of: actor), in: bidHistory, me: actor)
            applyBid(aiBid)
        }
    }

    // -----------------------------------------------------------------------
    // Card Play
    // -----------------------------------------------------------------------

    public mutating func applyCardPlay(_ card: Card) {
        guard let actor = currentActor else { return }
        if var h = hands[actor], let idx = h.firstIndex(of: card) {
            h.remove(at: idx)
            hands[actor] = h
        }

        currentTrick.append(PlayedCard(player: actor, card: card))

        if currentTrick.count < 4 {
            // Trick still in progress
            return
        }

        let winner = TrickRules.trickWinner(trick: currentTrick, trump: trump)
        let nsWon = (winner.side == 0)
        let played = tricksPlayed + 1

        self.currentTrick = []
        self.trickLead = winner
        self.tricksNs += nsWon ? 1 : 0
        self.tricksEw += nsWon ? 0 : 1
        self.tricksPlayed = played
        self.phase = (played == 13) ? .scoring : .playing
    }

    /// The computer's choice of card for the seat whose turn it is
    public func aiCard() -> Card {
        guard let actor = currentActor, let decl = declarer else {
            return hand(of: dealer).first!
        }
        return AICardPlayer.selectCard(
            hand: hand(of: actor),
            trick: currentTrick,
            leader: trickLead,
            trump: trump,
            me: actor,
            declarer: decl
        )
    }
}
