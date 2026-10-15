// Cards.swift -- players, cards, deck, and hand evaluation for contract bridge.
//
// Suits are integers 0..3 (clubs, diamonds, hearts, spades) so suit comparisons
// match standard bridge ranking. Ranks are 2..14 (14 = Ace).

import Foundation

public enum Player: String, CaseIterable, Codable, Hashable, CustomStringConvertible {
    case north = "North"
    case east = "East"
    case south = "South"
    case west = "West"

    public var description: String { rawValue }

    public var partner: Player {
        switch self {
        case .north: return .south
        case .south: return .north
        case .east: return .west
        case .west: return .east
        }
    }

    public var next: Player {
        switch self {
        case .north: return .east
        case .east: return .south
        case .south: return .west
        case .west: return .north
        }
    }

    /// Side 0 is North-South, side 1 is East-West
    public var side: Int {
        (self == .north || self == .south) ? 0 : 1
    }
}

public enum Suit: Int, CaseIterable, Comparable, Codable, Hashable, CustomStringConvertible {
    case clubs = 0
    case diamonds = 1
    case hearts = 2
    case spades = 3

    public static func < (lhs: Suit, rhs: Suit) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var letter: Character {
        switch self {
        case .clubs: return "C"
        case .diamonds: return "D"
        case .hearts: return "H"
        case .spades: return "S"
        }
    }

    public var name: String {
        switch self {
        case .clubs: return "Clubs"
        case .diamonds: return "Diamonds"
        case .hearts: return "Hearts"
        case .spades: return "Spades"
        }
    }

    public var description: String { name }

    public init?(letter: Character) {
        switch letter {
        case "C", "c": self = .clubs
        case "D", "d": self = .diamonds
        case "H", "h": self = .hearts
        case "S", "s": self = .spades
        default: return nil
        }
    }
}

public struct Card: Hashable, Codable, CustomStringConvertible {
    public static let jack = 11
    public static let queen = 12
    public static let king = 13
    public static let ace = 14

    public let suit: Suit
    public let rank: Int // 2..14

    public init(suit: Suit, rank: Int) {
        self.suit = suit
        self.rank = rank
    }

    public var rankString: String {
        switch rank {
        case 14: return "A"
        case 13: return "K"
        case 12: return "Q"
        case 11: return "J"
        default: return String(rank)
        }
    }

    /// Card codes used by the UI: "AS", "10D", "7C", etc.
    public var code: String {
        "\(rankString)\(suit.letter)"
    }

    public var description: String { code }

    public init?(code: String) {
        let s = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard s.count >= 2 else { return nil }
        guard let lastChar = s.last, let suit = Suit(letter: lastChar) else { return nil }
        let rankStr = String(s.dropLast())
        let rank: Int
        switch rankStr {
        case "A": rank = Card.ace
        case "K": rank = Card.king
        case "Q": rank = Card.queen
        case "J": rank = Card.jack
        default:
            guard let val = Int(rankStr), val >= 2, val <= 10 else { return nil }
            rank = val
        }
        self.suit = suit
        self.rank = rank
    }

    public var hcp: Int {
        switch rank {
        case Card.ace: return 4
        case Card.king: return 3
        case Card.queen: return 2
        case Card.jack: return 1
        default: return 0
        }
    }
}

// ---------------------------------------------------------------------------
// Deck and Dealing
// ---------------------------------------------------------------------------

public enum Deck {
    public static func makeDeck() -> [Card] {
        var deck = [Card]()
        for suit in Suit.allCases {
            for rank in 2...14 {
                deck.append(Card(suit: suit, rank: rank))
            }
        }
        return deck
    }

    /// Sort for display: spades first (descending suit), high cards first within suit
    public static func sortHand(_ cards: [Card]) -> [Card] {
        cards.sorted { a, b in
            if a.suit.rawValue != b.suit.rawValue {
                return a.suit.rawValue > b.suit.rawValue
            }
            return a.rank > b.rank
        }
    }

    /// Deal a 52-card deck round robin to North, East, South, West.
    public static func dealHands(deck: [Card]) -> [Player: [Card]] {
        var hands: [Player: [Card]] = [
            .north: [],
            .east: [],
            .south: [],
            .west: []
        ]
        let players = Player.allCases
        for (index, card) in deck.enumerated() {
            let p = players[index % 4]
            hands[p]?.append(card)
        }
        for p in players {
            if let h = hands[p] {
                hands[p] = sortHand(h)
            }
        }
        return hands
    }
}

// ---------------------------------------------------------------------------
// Hand Evaluation
// ---------------------------------------------------------------------------

public enum HandEvaluator {
    public static func handHCP(_ cards: [Card]) -> Int {
        cards.reduce(0) { $0 + $1.hcp }
    }

    public static func suitCards(in hand: [Card], suit: Suit) -> [Card] {
        hand.filter { $0.suit == suit }
    }

    public static func suitLength(in hand: [Card], suit: Suit) -> Int {
        suitCards(in: hand, suit: suit).count
    }

    /// Suit lengths sorted longest first, e.g. [5, 3, 3, 2]
    public static func handShapeSorted(_ hand: [Card]) -> [Int] {
        Suit.allCases.map { suitLength(in: hand, suit: $0) }.sorted(by: >)
    }

    public static func isBalanced(_ hand: [Card]) -> Bool {
        let shape = handShapeSorted(hand)
        return shape == [4, 3, 3, 3] || shape == [4, 4, 3, 2] || shape == [5, 3, 3, 2]
    }

    public static func hasMajor(_ hand: [Card], minLen: Int) -> Bool {
        suitLength(in: hand, suit: .hearts) >= minLen || suitLength(in: hand, suit: .spades) >= minLen
    }

    /// Longest suit among given suits; ties broken by the higher-ranking suit
    public static func longestSuit(in hand: [Card], from suits: [Suit] = Suit.allCases) -> Suit {
        let sortedCandidates = suits.sorted(by: >) // e.g. Spades down to Clubs
        var best = sortedCandidates.first ?? .spades
        for s in sortedCandidates {
            if suitLength(in: hand, suit: s) > suitLength(in: hand, suit: best) {
                best = s
            }
        }
        return best
    }

    /// Number of cards ten or higher in a suit
    public static func suitHonorCount(in hand: [Card], suit: Suit) -> Int {
        suitCards(in: hand, suit: suit).filter { $0.rank >= 10 }.count
    }
}
