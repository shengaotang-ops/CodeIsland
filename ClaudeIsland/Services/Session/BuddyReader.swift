//
//  BuddyReader.swift
//  CodeIsland
//
//  Reads Claude Code buddy data by running buddy-bones.js with Bun
//  to get exact species, rarity, stats matching Claude Code's computation.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Color hex extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Buddy Types

enum BuddyRarity: String, Sendable {
    case common, uncommon, rare, epic, legendary
    var displayName: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .common: return Color(hex: "9CA3AF")
        case .uncommon: return Color(hex: "4ADE80")
        case .rare: return Color(hex: "60A5FA")
        case .epic: return Color(hex: "A78BFA")
        case .legendary: return Color(hex: "FBBF24")
        }
    }
    var stars: String {
        switch self {
        case .common: return "★"
        case .uncommon: return "★★"
        case .rare: return "★★★"
        case .epic: return "★★★★"
        case .legendary: return "★★★★★"
        }
    }
}

struct BuddyStats: Sendable {
    let debugging: Int
    let patience: Int
    let chaos: Int
    let wisdom: Int
    let snark: Int
}

enum BuddySpecies: String, CaseIterable, Sendable {
    case duck, goose, blob, cat, dragon, octopus, owl, penguin, turtle, snail
    case ghost, axolotl, capybara, cactus, robot, rabbit, mushroom, chonk
    case unknown

    var emoji: String {
        switch self {
        case .duck: return "🦆"
        case .goose: return "🪿"
        case .cat: return "🐱"
        case .rabbit: return "🐰"
        case .owl: return "🦉"
        case .penguin: return "🐧"
        case .turtle: return "🐢"
        case .snail: return "🐌"
        case .dragon: return "🐉"
        case .octopus: return "🐙"
        case .axolotl: return "🦎"
        case .ghost: return "👻"
        case .robot: return "🤖"
        case .blob: return "🫧"
        case .cactus: return "🌵"
        case .mushroom: return "🍄"
        case .chonk: return "🐈"
        case .capybara: return "🦫"
        case .unknown: return "🐾"
        }
    }
}

struct BuddyInfo: Sendable {
    let name: String
    let personality: String
    let species: BuddySpecies
    let rarity: BuddyRarity
    let stats: BuddyStats
    let eye: String
    let hat: String
    let isShiny: Bool
    let hatchedAt: Date?
}

// MARK: - Buddy Reader

class BuddyReader: ObservableObject {
    static let shared = BuddyReader()

    @Published var buddy: BuddyInfo?

    private init() {
        reload()
    }

    func reload() {
        // Try running bun script first for accurate data
        if let info = runBunScript() {
            buddy = info
            return
        }
        // Fallback: read basic info from ~/.claude.json
        buddy = readBasicInfo()
    }

    // MARK: - Bun Script (accurate computation)

    private func runBunScript() -> BuddyInfo? {
        // Find the buddy-bones.js script in the app bundle
        guard let scriptURL = Bundle.main.url(forResource: "buddy-bones", withExtension: "js") else {
            return nil
        }

        // Find bun
        let bunPaths = ["/Users/\(NSUserName())/bin/bun", "/opt/homebrew/bin/bun", "/usr/local/bin/bun"]
        guard let bunPath = bunPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: bunPath)
        process.arguments = [scriptURL.path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            return parseBuddyJSON(json)
        } catch {
            return nil
        }
    }

    // MARK: - Fallback: basic info from config

    private func readBasicInfo() -> BuddyInfo? {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let companion = json["companion"] as? [String: Any],
              let name = companion["name"] as? String,
              let personality = companion["personality"] as? String else {
            return nil
        }

        // Detect species from personality text
        let species = BuddySpecies.allCases.first { s in
            s != .unknown && personality.lowercased().contains(s.rawValue)
        } ?? .unknown

        let hatchedAt: Date? = (companion["hatchedAt"] as? Double).map {
            Date(timeIntervalSince1970: $0 / 1000.0)
        }

        return BuddyInfo(
            name: name, personality: personality,
            species: species, rarity: .common,
            stats: BuddyStats(debugging: 0, patience: 0, chaos: 0, wisdom: 0, snark: 0),
            eye: "·", hat: "none", isShiny: false, hatchedAt: hatchedAt
        )
    }

    // MARK: - Parse JSON

    private func parseBuddyJSON(_ json: [String: Any]) -> BuddyInfo? {
        guard let name = json["name"] as? String else { return nil }

        let personality = json["personality"] as? String ?? ""
        let speciesStr = json["species"] as? String ?? "unknown"
        let species = BuddySpecies(rawValue: speciesStr) ?? .unknown
        let rarityStr = json["rarity"] as? String ?? "common"
        let rarity = BuddyRarity(rawValue: rarityStr) ?? .common
        let eye = json["eye"] as? String ?? "·"
        let hat = json["hat"] as? String ?? "none"
        let shiny = json["shiny"] as? Bool ?? false

        let statsDict = json["stats"] as? [String: Any] ?? [:]
        let stats = BuddyStats(
            debugging: statsDict["DEBUGGING"] as? Int ?? 0,
            patience: statsDict["PATIENCE"] as? Int ?? 0,
            chaos: statsDict["CHAOS"] as? Int ?? 0,
            wisdom: statsDict["WISDOM"] as? Int ?? 0,
            snark: statsDict["SNARK"] as? Int ?? 0
        )

        let hatchedAt: Date? = (json["hatchedAt"] as? Double).map {
            Date(timeIntervalSince1970: $0 / 1000.0)
        }

        return BuddyInfo(
            name: name, personality: personality,
            species: species, rarity: rarity,
            stats: stats, eye: eye, hat: hat,
            isShiny: shiny, hatchedAt: hatchedAt
        )
    }
}
