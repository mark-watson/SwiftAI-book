// Bidding.swift -- auction rules and heuristic Standard American bidder.
//
// A bid is either a contract bid (level 1..7 + strain) or Pass, Double, Redouble.
// Strains are suits 0..3 or NT (4).

import Foundation

public enum Strain: Int, CaseIterable, Comparable, Codable, Hashable, CustomStringConvertible {
    case clubs = 0
    case diamonds = 1
    case hearts = 2
    case spades = 3
    case notrump = 4

    public static func < (lhs: Strain, rhs: Strain) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var letter: String {
        switch self {
        case .clubs: return "C"
        case .diamonds: return "D"
        case .hearts: return "H"
        case .spades: return "S"
        case .notrump: return "NT"
        }
    }

    public var description: String { letter }

    public var asSuit: Suit? {
        switch self {
        case .clubs: return .clubs
        case .diamonds: return .diamonds
        case .hearts: return .hearts
        case .spades: return .spades
        case .notrump: return nil
        }
    }

    public init(suit: Suit) {
        switch suit {
        case .clubs: self = .clubs
        case .diamonds: self = .diamonds
        case .hearts: self = .hearts
        case .spades: self = .spades
        }
    }

    public init?(string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch s {
        case "C", "CLUBS": self = .clubs
        case "D", "DIAMONDS": self = .diamonds
        case "H", "HEARTS": self = .hearts
        case "S", "SPADES": self = .spades
        case "N", "NT", "NOTRUMP", "NO TRUMP": self = .notrump
        default: return nil
        }
    }
}

public enum Call: Hashable, Codable, CustomStringConvertible {
    case bid(level: Int, strain: Strain)
    case pass
    case double
    case redouble

    public var description: String {
        switch self {
        case let .bid(level, strain):
            return "\(level)\(strain.letter)"
        case .pass:
            return "Pass"
        case .double:
            return "Dbl"
        case .redouble:
            return "Rdbl"
        }
    }

    public var bidIndex: Int? {
        guard case let .bid(level, strain) = self else { return nil }
        return 5 * (level - 1) + strain.rawValue
    }

    public func isHigher(than other: Call) -> Bool {
        guard let myIdx = self.bidIndex, let otherIdx = other.bidIndex else {
            return false
        }
        return myIdx > otherIdx
    }

    public init?(string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch s {
        case "PASS", "P":
            self = .pass
        case "DOUBLE", "DBL", "X":
            self = .double
        case "REDOUBLE", "RDBL", "XX":
            self = .redouble
        default:
            guard s.count >= 2, let firstChar = s.first,
                  let level = Int(String(firstChar)), level >= 1, level <= 7 else {
                return nil
            }
            let strainStr = String(s.dropFirst())
            guard let strain = Strain(string: strainStr) else { return nil }
            self = .bid(level: level, strain: strain)
        }
    }
}

public struct BidEntry: Hashable, Codable {
    public let player: Player
    public let call: Call

    public init(player: Player, call: Call) {
        self.player = player
        self.call = call
    }
}

// ---------------------------------------------------------------------------
// Auction Rules
// ---------------------------------------------------------------------------

public enum AuctionRules {
    /// 1C = 0, 1D = 1, ..., 7NT = 34
    public static func bidIndex(level: Int, strain: Strain) -> Int {
        5 * (level - 1) + strain.rawValue
    }

    public static func lastSuitBid(in history: [BidEntry]) -> Call? {
        history.last(where: {
            if case .bid = $0.call { return true }
            return false
        })?.call
    }

    public static func isPassedOut(_ history: [BidEntry]) -> Bool {
        history.count == 4 && history.allSatisfy { $0.call == .pass }
    }

    /// Auction ends after four opening passes, or three passes following any bid
    public static func isBiddingComplete(_ history: [BidEntry]) -> Bool {
        if isPassedOut(history) { return true }
        guard history.count >= 4 else { return false }
        let lastThree = history.suffix(3)
        let hasAnyBid = history.contains(where: {
            if case .bid = $0.call { return true }
            return false
        })
        return lastThree.allSatisfy { $0.call == .pass } && hasAnyBid
    }

    /// Is a call legal for player right now given the chronological history?
    public static func isLegalCall(_ call: Call, for player: Player, in history: [BidEntry]) -> Bool {
        let lastNonPass = history.last(where: { $0.call != .pass })
        switch call {
        case .pass:
            return true
        case .bid:
            if let hi = lastSuitBid(in: history) {
                return call.isHigher(than: hi)
            }
            return true
        case .double:
            guard let last = lastNonPass else { return false }
            if case .bid = last.call, last.player.side != player.side {
                return true
            }
            return false
        case .redouble:
            guard let last = lastNonPass else { return false }
            if last.call == .double, last.player.side != player.side {
                return true
            }
            return false
        }
    }

    /// Returns (contract, declarer, doubled) where doubled is 0 (none), 1 (doubled), 2 (redoubled)
    /// Returns nil for a passed-out deal.
    public static func extractContract(from history: [BidEntry]) -> (contract: Call, declarer: Player, doubled: Int)? {
        guard let lastBidIndex = history.lastIndex(where: {
            if case .bid = $0.call { return true }
            return false
        }) else {
            return nil
        }

        let winningBidEntry = history[lastBidIndex]
        let contract = winningBidEntry.call
        guard case let .bid(_, strain) = contract else { return nil }
        let declSide = winningBidEntry.player.side

        // Declarer: first player of winning side to name the strain in chronological order
        let declarer = history.first(where: { entry in
            if case let .bid(_, s) = entry.call, s == strain, entry.player.side == declSide {
                return true
            }
            return false
        })?.player ?? winningBidEntry.player

        // Doubled: the most recent double or redouble after the final contract bid
        var doubled = 0
        for entry in history[(lastBidIndex + 1)...].reversed() {
            if entry.call == .double {
                doubled = 1
                break
            } else if entry.call == .redouble {
                doubled = 2
                break
            }
        }

        return (contract, declarer, doubled)
    }

    /// First contract bid made by a given player in auction order
    public static func firstSuitBid(by player: Player, in history: [BidEntry]) -> Call? {
        history.first(where: {
            if $0.player == player, case .bid = $0.call { return true }
            return false
        })?.call
    }
}

// ---------------------------------------------------------------------------
// AI Bidding: Standard American Heuristic Bidder
// ---------------------------------------------------------------------------

public enum AIBidder {
    public static func openingBid(for hand: [Card]) -> Call? {
        let hcp = HandEvaluator.handHCP(hand)
        let bal = HandEvaluator.isBalanced(hand)

        let openingSuit: Suit
        if HandEvaluator.suitLength(in: hand, suit: .spades) >= 5 {
            openingSuit = .spades
        } else if HandEvaluator.suitLength(in: hand, suit: .hearts) >= 5 {
            openingSuit = .hearts
        } else if HandEvaluator.suitLength(in: hand, suit: .diamonds) > HandEvaluator.suitLength(in: hand, suit: .clubs) {
            openingSuit = .diamonds
        } else {
            openingSuit = .clubs
        }

        let sevenCardSuits = Suit.allCases.filter {
            HandEvaluator.suitLength(in: hand, suit: $0) >= 7 && HandEvaluator.suitHonorCount(in: hand, suit: $0) >= 2
        }
        let weakTwoSuits: [Suit] = [.diamonds, .hearts, .spades].filter {
            HandEvaluator.suitLength(in: hand, suit: $0) >= 6
        }

        if hcp >= 22 {
            return .bid(level: 2, strain: .clubs)
        } else if bal && (20...21).contains(hcp) {
            return .bid(level: 2, strain: .notrump)
        } else if bal && (15...17).contains(hcp) {
            return .bid(level: 1, strain: .notrump)
        } else if (13...21).contains(hcp) {
            return .bid(level: 1, strain: Strain(suit: openingSuit))
        } else if hcp < 13 && !sevenCardSuits.isEmpty {
            return .bid(level: 3, strain: Strain(suit: sevenCardSuits[0]))
        } else if (5...12).contains(hcp) && !weakTwoSuits.isEmpty {
            return .bid(level: 2, strain: Strain(suit: weakTwoSuits[0]))
        }
        return nil
    }

    public static func respondingBid(for hand: [Card], partnerBid: Call) -> Call? {
        guard case let .bid(pLevel, pStrain) = partnerBid else { return nil }
        let hcp = HandEvaluator.handHCP(hand)
        func len(_ s: Suit) -> Int { HandEvaluator.suitLength(in: hand, suit: s) }

        // Partner opened 1NT (15-17)
        if pStrain == .notrump && pLevel == 1 {
            if hcp <= 7 {
                if len(.spades) >= 5 { return .bid(level: 2, strain: .spades) }
                if len(.hearts) >= 5 { return .bid(level: 2, strain: .hearts) }
                if len(.diamonds) >= 5 { return .bid(level: 2, strain: .diamonds) }
                return nil
            } else if len(.hearts) >= 4 || len(.spades) >= 4 {
                return .bid(level: 2, strain: .clubs) // Stayman
            } else if hcp <= 9 {
                return .bid(level: 2, strain: .notrump)
            } else if hcp <= 15 {
                if len(.spades) >= 6 { return .bid(level: 4, strain: .spades) }
                if len(.hearts) >= 6 { return .bid(level: 4, strain: .hearts) }
                if len(.spades) >= 5 { return .bid(level: 3, strain: .spades) }
                if len(.hearts) >= 5 { return .bid(level: 3, strain: .hearts) }
                return .bid(level: 3, strain: .notrump)
            } else {
                return .bid(level: 4, strain: .notrump)
            }
        }

        // Partner opened 2NT (20-21)
        if pStrain == .notrump {
            if hcp <= 4 && Suit.allCases.allSatisfy({ len($0) < 5 }) {
                return nil
            }
            if hcp >= 4 && (len(.hearts) >= 4 || len(.spades) >= 4) {
                return .bid(level: 3, strain: .clubs) // Stayman
            }
            if hcp >= 5 {
                return .bid(level: 3, strain: .notrump)
            }
            return nil
        }

        // Partner opened one of a major
        if pLevel == 1, let major = pStrain.asSuit, major == .hearts || major == .spades {
            if hcp <= 5 { return nil }
            if hcp <= 10 {
                if len(major) >= 3 { return .bid(level: 2, strain: pStrain) }
                if major == .hearts && len(.spades) >= 4 { return .bid(level: 1, strain: .spades) }
                return .bid(level: 1, strain: .notrump)
            }
            if hcp <= 12 {
                if len(major) >= 3 { return .bid(level: 3, strain: pStrain) }
                let longest = HandEvaluator.longestSuit(in: hand)
                if longest > major {
                    return .bid(level: 2, strain: Strain(suit: longest))
                }
                return .bid(level: 2, strain: .notrump)
            }
            if len(major) >= 3 { return .bid(level: 4, strain: pStrain) }
            return .bid(level: 3, strain: .notrump)
        }

        // Partner opened one of a minor
        if pLevel == 1 {
            if hcp < 6 { return nil }
            if len(.hearts) >= 4 || len(.spades) >= 4 {
                if (len(.hearts) >= 5 && len(.spades) >= 5) || len(.hearts) < 4 {
                    return .bid(level: 1, strain: .spades)
                }
                return .bid(level: 1, strain: .hearts)
            }
            if hcp <= 10 { return .bid(level: 1, strain: .notrump) }
            if hcp <= 12 {
                if let minor = pStrain.asSuit, len(minor) >= 4 {
                    return .bid(level: 3, strain: pStrain)
                }
                return .bid(level: 2, strain: .notrump)
            }
            if hcp <= 15 {
                if let minor = pStrain.asSuit, len(minor) >= 4 {
                    return .bid(level: 5, strain: pStrain)
                }
                return .bid(level: 3, strain: .notrump)
            }
            return .bid(level: 4, strain: .notrump)
        }

        // Partner opened strong 2C
        if pStrain == .clubs && pLevel == 2 {
            let bal = HandEvaluator.isBalanced(hand)
            if hcp < 8 { return .bid(level: 2, strain: .diamonds) }
            if !bal && len(.spades) >= 5 { return .bid(level: 2, strain: .spades) }
            if !bal && len(.hearts) >= 5 { return .bid(level: 2, strain: .hearts) }
            if !bal && len(.diamonds) >= 5 { return .bid(level: 3, strain: .diamonds) }
            if !bal && len(.clubs) >= 5 { return .bid(level: 3, strain: .clubs) }
            return .bid(level: 2, strain: .notrump)
        }

        // Partner opened weak two
        if pLevel == 2 {
            if let s = pStrain.asSuit, len(s) >= 3 && hcp >= 14 {
                return .bid(level: 4, strain: pStrain)
            }
            if let s = pStrain.asSuit, len(s) >= 3 && hcp >= 10 {
                return .bid(level: 3, strain: pStrain)
            }
            return nil
        }

        // Partner opened three-level preempt
        if pLevel == 3 {
            if let s = pStrain.asSuit, len(s) >= 3 && hcp >= 14 {
                let lvl = (s == .hearts || s == .spades) ? 4 : 5
                return .bid(level: lvl, strain: pStrain)
            }
            return nil
        }

        return nil
    }

    public static func openerRebid(for hand: [Card], myOpening: Call, partnerResponse: Call) -> Call? {
        guard case let .bid(myLevel, myStrain) = myOpening,
              case let .bid(pLevel, pStrain) = partnerResponse else {
            return nil
        }
        let hcp = HandEvaluator.handHCP(hand)
        func len(_ s: Suit) -> Int { HandEvaluator.suitLength(in: hand, suit: s) }
        func countRank(_ rank: Int) -> Int { hand.filter { $0.rank == rank }.count }

        func gerberReply(level: Int, n: Int) -> Call {
            switch n {
            case 0: return .bid(level: level, strain: .diamonds)
            case 1: return .bid(level: level, strain: .hearts)
            case 2: return .bid(level: level, strain: .spades)
            case 3: return .bid(level: level, strain: .notrump)
            default: return .bid(level: level + 1, strain: .clubs)
            }
        }

        // Stayman: 2C over 1NT or 3C over 2NT asks for a four-card major
        if myStrain == .notrump && pStrain == .clubs && pLevel == (myLevel + 1) && myLevel <= 2 {
            if len(.hearts) >= 4 { return .bid(level: pLevel, strain: .hearts) }
            if len(.spades) >= 4 { return .bid(level: pLevel, strain: .spades) }
            return .bid(level: pLevel, strain: .diamonds)
        }

        // Blackwood 4NT asks for aces, 5NT for kings (step responses)
        if partnerResponse == .bid(level: 4, strain: .notrump) {
            let aces = countRank(Card.ace)
            return .bid(level: 5, strain: Strain(rawValue: aces % 5)!)
        }
        if partnerResponse == .bid(level: 5, strain: .notrump) {
            let kings = countRank(Card.king)
            return .bid(level: 6, strain: Strain(rawValue: kings % 5)!)
        }

        // Gerber 4C over notrump asks for aces, 5C for kings
        if partnerResponse == .bid(level: 4, strain: .clubs) && myStrain == .notrump {
            return gerberReply(level: 4, n: countRank(Card.ace))
        }
        if partnerResponse == .bid(level: 5, strain: .clubs) {
            return gerberReply(level: 5, n: countRank(Card.king))
        }

        // Partner responded in notrump
        if pStrain == .notrump {
            if let mySuit = myStrain.asSuit, len(mySuit) >= 6 {
                return .bid(level: pLevel + 1, strain: myStrain)
            }
            if hcp <= 15 { return nil }
            if hcp <= 17 { return .bid(level: pLevel + 1, strain: .notrump) }
            return .bid(level: pLevel + 2, strain: .notrump)
        }

        // Partner raised my suit
        if myStrain != .notrump && pStrain == myStrain {
            guard let mySuit = myStrain.asSuit else { return nil }
            if hcp <= 15 { return nil }
            if hcp >= 19 && (mySuit == .hearts || mySuit == .spades) {
                return .bid(level: 4, strain: .notrump) // Blackwood
            }
            let targetLevel = (mySuit == .hearts || mySuit == .spades) ? 4 : 5
            return .bid(level: targetLevel, strain: myStrain)
        }

        // Partner bid a new suit
        if let pSuit = pStrain.asSuit, len(pSuit) >= 4 {
            return .bid(level: pLevel + 1, strain: pStrain)
        }
        if let mySuit = myStrain.asSuit, len(mySuit) >= 6 {
            return .bid(level: 2, strain: myStrain)
        }
        if hcp <= 15 && HandEvaluator.isBalanced(hand) {
            return .bid(level: max(pLevel, 1), strain: .notrump)
        }
        if let mySuit = myStrain.asSuit, len(mySuit) >= 5 {
            return .bid(level: 2, strain: myStrain)
        }
        return .bid(level: 1, strain: .notrump)
    }

    public static func overcall(for hand: [Card]) -> Call? {
        let hcp = HandEvaluator.handHCP(hand)
        if hcp >= 13 && HandEvaluator.hasMajor(hand, minLen: 5) {
            let major: Strain = HandEvaluator.suitLength(in: hand, suit: .spades) >= 5 ? .spades : .hearts
            return .bid(level: 1, strain: major)
        }
        if (15...18).contains(hcp) && HandEvaluator.isBalanced(hand) {
            return .bid(level: 1, strain: .notrump)
        }
        return nil
    }

    /// Select a bid for player me. Any insufficient or illegal bid becomes Pass.
    public static func selectBid(for hand: [Card], in history: [BidEntry], me: Player) -> Call {
        let highest = AuctionRules.lastSuitBid(in: history)
        let partnerBid = AuctionRules.firstSuitBid(by: me.partner, in: history)
        let myBid = AuctionRules.firstSuitBid(by: me, in: history)

        let raw: Call?
        if let m = myBid, let p = partnerBid {
            raw = openerRebid(for: hand, myOpening: m, partnerResponse: p)
        } else if let p = partnerBid {
            raw = respondingBid(for: hand, partnerBid: p)
        } else if highest == nil {
            raw = openingBid(for: hand)
        } else {
            raw = overcall(for: hand)
        }

        if let raw = raw {
            if highest == nil || raw.isHigher(than: highest!) {
                return raw
            }
        }
        return .pass
    }
}
