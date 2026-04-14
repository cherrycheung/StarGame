import Foundation

enum CellState: String {
    case empty
    case star
    case marked
}

enum InputMode: String {
    case star = "Star"
    case mark = "Mark"
}

struct GameConfig {
    let starsPerUnit: Int
    let boardSize: Int

    static let oneStar = GameConfig(starsPerUnit: 1, boardSize: 6)
}

struct Puzzle: Identifiable {
    let id = UUID()
    let name: String
    let size: Int
    let regions: [[String]]
    let solution: [CellPosition]
}

struct CellPosition: Hashable {
    let row: Int
    let column: Int
}

struct ValidationResult {
    let invalidCells: Set<CellPosition>
    let solved: Bool
}

enum PuzzleLibrary {
    static let starterPuzzles: [Puzzle] = [
        Puzzle(
            name: "Morning Drift",
            size: 6,
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
            name: "Quiet Orbit",
            size: 6,
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
