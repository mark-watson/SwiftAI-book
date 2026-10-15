// Play.swift -- trick taking rules and heuristic card play for AI players.
//
// A trick is an ordered list of played cards (leader's card first).
// Trump is a Suit or nil for notrump.

import Foundation

public struct PlayedCard: Hashable, Codable {
    public let player: Player
    public let card: Card

    public init(player: Player, card: Card) {
        self.player = player
        self.card = card
    }
}

public enum TrickRules {
    /// Must follow the led suit when possible
    public static func legalPlays(hand: [Card], leadSuit: Suit?) -> [Card] {
        guard let lead = leadSuit else { return hand }
        let inSuit = HandEvaluator.suitCards(in: hand, suit: lead)
        return inSuit.isEmpty ? hand : inSuit
    }

    /// Trumps beat the led suit, which beats everything else
    public static func cardScore(card: Card, leadSuit: Suit, trump: Suit?) -> Int {
        if let t = trump, card.suit == t {
            return 100 + card.rank
        }
        if card.suit == leadSuit {
            return 50 + card.rank
        }
        return card.rank
    }

    public static func bestScore(trick: [Card], trump: Suit?) -> Int {
        guard let lead = trick.first else { return 0 }
        return trick.map { cardScore(card: $0, leadSuit: lead.suit, trump: trump) }.max() ?? 0
    }

    public static func trickWinner(trick: [PlayedCard], trump: Suit?) -> Player {
        precondition(!trick.isEmpty, "Cannot determine winner of an empty trick")
        let leadSuit = trick[0].card.suit
        var bestPlayer = trick[0].player
        var bestVal = cardScore(card: trick[0].card, leadSuit: leadSuit, trump: trump)

        for pc in trick.dropFirst() {
            let score = cardScore(card: pc.card, leadSuit: leadSuit, trump: trump)
            if score > bestVal {
                bestVal = score
                bestPlayer = pc.player
            }
        }
        return bestPlayer
    }

    public static func lowestCard(_ cards: [Card]) -> Card {
        precondition(!cards.isEmpty, "cards must not be empty")
        return cards.min(by: { $0.rank < $1.rank })!
    }

    public static func highestCard(_ cards: [Card]) -> Card {
        precondition(!cards.isEmpty, "cards must not be empty")
        return cards.max(by: { $0.rank < $1.rank })!
    }

    public static func isPartnerWinning(trick: [PlayedCard], leader: Player, trump: Suit?, me: Player) -> Bool {
        guard !trick.isEmpty else { return false }
        let winner = trickWinner(trick: trick, trump: trump)
        return winner.side == me.side
    }

    /// Cards from inSuit that would currently win the trick
    public static func winningCards(in inSuit: [Card], trick: [PlayedCard], trump: Suit?) -> [Card] {
        guard !trick.isEmpty else { return inSuit }
        let leadSuit = trick[0].card.suit
        let toBeat = bestScore(trick: trick.map { $0.card }, trump: trump)
        return inSuit.filter { cardScore(card: $0, leadSuit: leadSuit, trump: trump) > toBeat }
    }

    /// Play the cheapest card that wins, otherwise the lowest card
    public static func cheapestWinner(in inSuit: [Card], trick: [PlayedCard], trump: Suit?) -> Card {
        let winners = winningCards(in: inSuit, trick: trick, trump: trump)
        return lowestCard(winners.isEmpty ? inSuit : winners)
    }

    public static func longestNonTrump(hand: [Card], trump: Suit?) -> Suit {
        let candidates = (trump != nil) ? Suit.allCases.filter { $0 != trump! } : Suit.allCases
        return HandEvaluator.longestSuit(in: hand, from: candidates)
    }

    /// Discard the lowest card of the longest side suit
    public static func bestDiscard(cards: [Card], trump: Suit?) -> Card {
        let longest = longestNonTrump(hand: cards, trump: trump)
        let inLongest = HandEvaluator.suitCards(in: cards, suit: longest)
        return lowestCard(inLongest.isEmpty ? cards : inLongest)
    }
}

// ---------------------------------------------------------------------------
// AI Card Play: Leads and Following
// ---------------------------------------------------------------------------

public enum AICardPlayer {
    private static func highToLow(_ cards: [Card]) -> [Card] {
        cards.sorted { $0.rank > $1.rank }
    }

    /// Top of a three card sequence headed by the jack or better (e.g. KQJ)
    public static func leadTopOfSequence(hand: [Card], trump: Suit?) -> Card? {
        let candidates = (trump != nil) ? Suit.allCases.filter { $0 != trump! } : Suit.allCases
        for s in candidates {
            let sorted = highToLow(HandEvaluator.suitCards(in: hand, suit: s))
            if sorted.count >= 3 {
                let c1 = sorted[0], c2 = sorted[1], c3 = sorted[2]
                if c1.rank >= Card.jack && c1.rank == (c2.rank + 1) && c2.rank == (c3.rank + 1) {
                    return c1
                }
            }
        }
        return nil
    }

    /// Fourth highest card of the longest side suit
    public static func leadFourthBest(hand: [Card], trump: Suit?) -> Card? {
        let suit = TrickRules.longestNonTrump(hand: hand, trump: trump)
        let cards = highToLow(HandEvaluator.suitCards(in: hand, suit: suit))
        return cards.count >= 4 ? cards[3] : nil
    }

    /// Top card of the shortest side suit, hoping for a ruff later
    public static func leadShortSuit(hand: [Card], trump: Suit?) -> Card? {
        guard let t = trump else { return nil }
        let sideSuits = Suit.allCases.filter { $0 != t && HandEvaluator.suitLength(in: hand, suit: $0) > 0 }
        guard !sideSuits.isEmpty else { return nil }
        let shortest = sideSuits.min(by: {
            HandEvaluator.suitLength(in: hand, suit: $0) < HandEvaluator.suitLength(in: hand, suit: $1)
        })!
        return TrickRules.highestCard(HandEvaluator.suitCards(in: hand, suit: shortest))
    }

    public static func selectLead(hand: [Card], trump: Suit?, me: Player, declarer: Player) -> Card {
        let defending = (me.side != declarer.side)
        let trumps = trump != nil ? HandEvaluator.suitCards(in: hand, suit: trump!) : []

        if defending {
            return leadTopOfSequence(hand: hand, trump: trump)
                ?? leadFourthBest(hand: hand, trump: trump)
                ?? leadShortSuit(hand: hand, trump: trump)
                ?? TrickRules.bestDiscard(cards: hand, trump: trump)
        } else {
            // Declarer side: draw trumps when holding three or more including the queen+
            if trumps.count >= 3 && trumps.contains(where: { $0.rank >= Card.queen }) {
                return TrickRules.highestCard(trumps)
            }
            return leadTopOfSequence(hand: hand, trump: trump)
                ?? leadFourthBest(hand: hand, trump: trump)
                ?? hand.first!
        }
    }

    public static func selectFollow(hand: [Card], trick: [PlayedCard], leader: Player, trump: Suit?, me: Player) -> Card {
        guard let first = trick.first else { return hand.first! }
        let leadSuit = first.card.suit
        let legal = TrickRules.legalPlays(hand: hand, leadSuit: leadSuit)
        let partnerWins = TrickRules.isPartnerWinning(trick: trick, leader: leader, trump: trump, me: me)

        if legal.count == 1 { return legal[0] }

        if legal[0].suit == leadSuit {
            // Fourth hand ducks when partner already has the trick won
            if trick.count == 3 && partnerWins {
                return TrickRules.lowestCard(legal)
            }
            return TrickRules.cheapestWinner(in: legal, trick: trick, trump: trump)
        } else {
            // Void in the led suit: ruff if partner isn't winning, else discard
            let trumps = trump != nil ? HandEvaluator.suitCards(in: legal, suit: trump!) : []
            let others = trump != nil ? legal.filter { $0.suit != trump! } : legal
            if !partnerWins && !trumps.isEmpty {
                let ruffs = TrickRules.winningCards(in: trumps, trick: trick, trump: trump)
                if !ruffs.isEmpty {
                    return TrickRules.lowestCard(ruffs)
                } else {
                    return TrickRules.bestDiscard(cards: !others.isEmpty ? others : legal, trump: trump)
                }
            } else {
                return TrickRules.bestDiscard(cards: !others.isEmpty ? others : legal, trump: trump)
            }
        }
    }

    public static func selectCard(hand: [Card], trick: [PlayedCard], leader: Player, trump: Suit?, me: Player, declarer: Player) -> Card {
        let choice = trick.isEmpty
            ? selectLead(hand: hand, trump: trump, me: me, declarer: declarer)
            : selectFollow(hand: hand, trick: trick, leader: leader, trump: trump, me: me)

        let leadSuit = trick.first?.card.suit
        let legal = TrickRules.legalPlays(hand: hand, leadSuit: leadSuit)
        return legal.contains(choice) ? choice : legal.first!
    }
}
