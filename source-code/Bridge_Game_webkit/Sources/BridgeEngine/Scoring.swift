// Scoring.swift -- rubber bridge scoring.

import Foundation

public struct Rubber: Hashable, Codable {
    public var nsBelow: Int
    public var ewBelow: Int
    public var nsAbove: Int
    public var ewAbove: Int
    public var nsGames: Int
    public var ewGames: Int
    public var nsVul: Bool
    public var ewVul: Bool
    public var dealer: Player
    public var dealsPlayed: Int

    public init(
        nsBelow: Int = 0,
        ewBelow: Int = 0,
        nsAbove: Int = 0,
        ewAbove: Int = 0,
        nsGames: Int = 0,
        ewGames: Int = 0,
        nsVul: Bool = false,
        ewVul: Bool = false,
        dealer: Player = .north,
        dealsPlayed: Int = 0
    ) {
        self.nsBelow = nsBelow
        self.ewBelow = ewBelow
        self.nsAbove = nsAbove
        self.ewAbove = ewAbove
        self.nsGames = nsGames
        self.ewGames = ewGames
        self.nsVul = nsVul
        self.ewVul = ewVul
        self.dealer = dealer
        self.dealsPlayed = dealsPlayed
    }

    public static func newRubber() -> Rubber {
        Rubber()
    }

    public var isComplete: Bool {
        nsGames >= 2 || ewGames >= 2
    }

    public var bonus: (points: Int, winner: String?) {
        if nsGames >= 2 {
            return (ewGames == 0 ? 700 : 500, "N-S")
        } else if ewGames >= 2 {
            return (nsGames == 0 ? 700 : 500, "E-W")
        } else {
            return (0, nil)
        }
    }
}

public enum Scoring {
    /// Points per trick bid and made
    public static func trickValue(strain: Strain, doubled: Int) -> Int {
        let base = (strain.rawValue < Strain.hearts.rawValue) ? 20 : 30
        let mult = (doubled == 1) ? 2 : ((doubled == 2) ? 4 : 1)
        return base * mult
    }

    public static func contractTrickScore(level: Int, strain: Strain, doubled: Int) -> Int {
        let base = level * trickValue(strain: strain, doubled: doubled)
        let bonus: Int
        if strain == .notrump {
            bonus = (doubled == 1) ? 20 : ((doubled == 2) ? 40 : 10)
        } else {
            bonus = 0
        }
        return base + bonus
    }

    public static func undertrickPenalty(down: Int, doubled: Int, vul: Bool) -> Int {
        let doubledPenalty: Int
        if vul {
            doubledPenalty = 200 + 300 * (down - 1)
        } else {
            switch down {
            case 1: doubledPenalty = 100
            case 2: doubledPenalty = 300
            case 3: doubledPenalty = 500
            default: doubledPenalty = 500 + 300 * (down - 3)
            }
        }

        switch doubled {
        case 0:
            return down * (vul ? 100 : 50)
        case 1:
            return doubledPenalty
        default:
            return 2 * doubledPenalty
        }
    }

    /// Score one deal. Returns (newRubberState, scoreForDeclarer).
    public static func scoreDeal(
        level: Int,
        strain: Strain,
        tricksWon: Int,
        declarer: Player,
        doubled: Int,
        rubber: Rubber
    ) -> (rubber: Rubber, score: Int) {
        let ns = (declarer.side == 0)
        let vul = ns ? rubber.nsVul : rubber.ewVul
        let overtricks = tricksWon - (level + 6)
        var rs = rubber

        if overtricks >= 0 {
            let below = contractTrickScore(level: level, strain: strain, doubled: doubled)
            let overtrickValue: Int
            switch doubled {
            case 0:
                overtrickValue = trickValue(strain: strain, doubled: 0)
            case 1:
                overtrickValue = vul ? 200 : 100
            default:
                overtrickValue = vul ? 400 : 200
            }

            let insult = (doubled == 1) ? 50 : ((doubled == 2) ? 100 : 0)
            let slam: Int
            switch level {
            case 6: slam = vul ? 750 : 500
            case 7: slam = vul ? 1500 : 1000
            default: slam = 0
            }

            let above = overtricks * overtrickValue + insult + slam

            if ns {
                rs.nsBelow += below
                rs.nsAbove += above
            } else {
                rs.ewBelow += below
                rs.ewAbove += above
            }

            // 100 points below the line wins a game; part scores are wiped out.
            // Below-the-line points are also carried above the line when game ends.
            let game = ns ? (rs.nsBelow >= 100) : (rs.ewBelow >= 100)
            if game {
                rs.nsAbove += rs.nsBelow
                rs.ewAbove += rs.ewBelow
                rs.nsBelow = 0
                rs.ewBelow = 0
                if ns {
                    rs.nsGames += 1
                    rs.nsVul = true
                } else {
                    rs.ewGames += 1
                    rs.ewVul = true
                }
            }

            return (rs, below + above)
        } else {
            let down = -overtricks
            let penalty = undertrickPenalty(down: down, doubled: doubled, vul: vul)
            if ns {
                rs.ewAbove += penalty
            } else {
                rs.nsAbove += penalty
            }
            return (rs, -penalty)
        }
    }
}
