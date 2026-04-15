import Foundation

enum CellState: String {
    case empty
    case star
    case marked
}

struct GameConfig {
    let starsPerUnit: Int
    let boardSize: Int

    static let oneStar = GameConfig(starsPerUnit: 1, boardSize: 6)
}

enum PuzzleDifficulty: String, CaseIterable, Codable, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

struct Puzzle: Identifiable {
    let id: String
    let name: String
    let size: Int
    let difficulty: PuzzleDifficulty
    let regions: [[String]]
    let solution: [CellPosition]
}

struct CellPosition: Hashable, Codable {
    let row: Int
    let column: Int
}

struct ValidationResult {
    let invalidCells: Set<CellPosition>
    let solved: Bool
}

private struct GeneratedPuzzleBank: Codable {
    let puzzles: GeneratedDifficultyBuckets
}

private struct GeneratedDifficultyBuckets: Codable {
    let easy: [GeneratedPuzzle]
    let medium: [GeneratedPuzzle]
    let hard: [GeneratedPuzzle]
}

private struct GeneratedPuzzle: Codable {
    let id: String
    let name: String
    let size: Int
    let starsPerUnit: Int
    let difficulty: PuzzleDifficulty
    let regions: [[String]]
    let solution: [CellPosition]
}

enum PuzzleLibrary {
    static let puzzleBank: [PuzzleDifficulty: [Puzzle]] = loadPuzzleBank()

    static func puzzles(for difficulty: PuzzleDifficulty) -> [Puzzle] {
        let bank = puzzleBank[difficulty] ?? []
        if !bank.isEmpty {
            return bank
        }
        if difficulty == .easy {
            return fallbackPuzzles
        }
        return []
    }

    static func puzzleCount(for difficulty: PuzzleDifficulty) -> Int {
        puzzles(for: difficulty).count
    }

    private static func loadPuzzleBank() -> [PuzzleDifficulty: [Puzzle]] {
        guard
            let url = Bundle.main.url(forResource: "generated_puzzles", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(GeneratedPuzzleBank.self, from: data)
        else {
            return [.easy: fallbackPuzzles, .medium: [], .hard: []]
        }

        let easy = decoded.puzzles.easy.map(makePuzzle)
        let medium = decoded.puzzles.medium.map(makePuzzle)
        let hard = decoded.puzzles.hard.map(makePuzzle)
        return [
            .easy: easy.isEmpty ? fallbackPuzzles : easy,
            .medium: medium,
            .hard: hard
        ]
    }

    private static func makePuzzle(from generated: GeneratedPuzzle) -> Puzzle {
        Puzzle(
            id: generated.id,
            name: generated.name,
            size: generated.size,
            difficulty: generated.difficulty,
            regions: generated.regions,
            solution: generated.solution
        )
    }

    private static let fallbackPuzzles: [Puzzle] = [
        Puzzle(
            id: "fallback-001",
            name: "Morning Drift",
            size: 6,
            difficulty: .easy,
            regions: [
                ["A", "A", "C", "C", "B", "B"],
                ["C", "C", "C", "C", "B", "B"],
                ["C", "C", "C", "C", "C", "D"],
                ["C", "C", "C", "C", "C", "D"],
                ["E", "F", "F", "C", "F", "D"],
                ["E", "F", "F", "F", "F", "D"]
            ],
            solution: [
                CellPosition(row: 0, column: 1),
                CellPosition(row: 1, column: 4),
                CellPosition(row: 2, column: 2),
                CellPosition(row: 3, column: 5),
                CellPosition(row: 4, column: 0),
                CellPosition(row: 5, column: 3)
            ]
        ),
        Puzzle(
            id: "fallback-002",
            name: "Quiet Orbit",
            size: 6,
            difficulty: .easy,
            regions: [
                ["B", "B", "C", "A", "A", "A"],
                ["B", "B", "C", "A", "E", "A"],
                ["D", "C", "C", "C", "E", "E"],
                ["D", "C", "F", "E", "E", "E"],
                ["F", "F", "F", "F", "F", "E"],
                ["F", "F", "F", "F", "F", "F"]
            ],
            solution: [
                CellPosition(row: 0, column: 4),
                CellPosition(row: 1, column: 1),
                CellPosition(row: 2, column: 3),
                CellPosition(row: 3, column: 0),
                CellPosition(row: 4, column: 5),
                CellPosition(row: 5, column: 2)
            ]
        )
    ]
}
