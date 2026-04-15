import Foundation

@MainActor
final class GameViewModel: ObservableObject {
    @Published private(set) var config: GameConfig
    @Published private(set) var puzzles: [Puzzle]
    @Published private(set) var puzzleIndex: Int = 0
    @Published private(set) var currentDifficulty: PuzzleDifficulty = .easy
    @Published private(set) var boardState: [[CellState]]
    @Published var message: String = ""
    @Published var status: String = ""
    @Published var autoMarkEnabled: Bool = false
    @Published private(set) var invalidCells: Set<CellPosition> = []
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var lastSolvedDurationText: String = ""

    private var history: [[[CellState]]] = []
    private var lastTapPosition: CellPosition?
    private var lastTapTime = Date.distantPast
    private var puzzleStartTime = Date()

    init(config: GameConfig = .oneStar, puzzles: [Puzzle] = PuzzleLibrary.puzzles(for: .easy)) {
        self.config = config
        self.puzzles = puzzles
        self.boardState = Array(
            repeating: Array(repeating: .empty, count: config.boardSize),
            count: config.boardSize
        )
        loadPuzzle(at: 0)
    }

    var currentPuzzle: Puzzle {
        puzzles[puzzleIndex]
    }

    var availableDifficultyCounts: [PuzzleDifficulty: Int] {
        Dictionary(uniqueKeysWithValues: PuzzleDifficulty.allCases.map { difficulty in
            (difficulty, PuzzleLibrary.puzzleCount(for: difficulty))
        })
    }

    var starCount: Int {
        starPositions.count
    }

    var markCount: Int {
        boardState.flatMap { $0 }.filter { $0 == .marked }.count
    }

    var targetCount: Int {
        currentPuzzle.size * config.starsPerUnit
    }

    func toggleStar(at position: CellPosition) {
        saveHistory()
        let current = boardState[position.row][position.column]
        boardState[position.row][position.column] = current == .star ? .empty : .star

        invalidCells.removeAll()
        lastTapPosition = nil
        if autoMarkEnabled {
            applyAutoMarks()
        }
        updateSolvedState()
    }

    func toggleMark(at position: CellPosition) {
        saveHistory()
        let current = boardState[position.row][position.column]
        boardState[position.row][position.column] = current == .marked ? .empty : .marked

        invalidCells.removeAll()
        lastTapPosition = nil
        updateSolvedState()
    }

    func beginPrimaryInteraction(at position: CellPosition) {
        saveHistory()

        let now = Date()
        if lastTapPosition == position, now.timeIntervalSince(lastTapTime) < 0.3 {
            promoteLastMarkToStar(at: position)
            lastTapPosition = nil
            lastTapTime = .distantPast
            return
        }

        let current = boardState[position.row][position.column]
        boardState[position.row][position.column] = current == .marked ? .empty : .marked
        invalidCells.removeAll()
        updateSolvedState()
        lastTapPosition = position
        lastTapTime = now
    }

    func applyDraggedMark(at position: CellPosition) {
        guard boardState[position.row][position.column] == .empty else { return }
        boardState[position.row][position.column] = .marked
        invalidCells.removeAll()
    }

    func setAutoMarkEnabled(_ enabled: Bool) {
        autoMarkEnabled = enabled
        if enabled {
            saveHistory()
            applyAutoMarks()
            updateSolvedState()
        }
    }

    func resetBoard() {
        history.removeAll()
        boardState = Self.emptyBoard(size: currentPuzzle.size)
        invalidCells.removeAll()
        status = ""
        canUndo = false
        lastSolvedDurationText = ""
        lastTapPosition = nil
        puzzleStartTime = Date()
        message = ""
    }

    func loadNextPuzzle() {
        let nextIndex = (puzzleIndex + 1) % puzzles.count
        loadPuzzle(at: nextIndex)
    }

    func startNewSession(difficulty: PuzzleDifficulty) {
        currentDifficulty = difficulty
        puzzles = PuzzleLibrary.puzzles(for: difficulty)
        loadPuzzle(at: 0)
    }

    func checkProgress() {
        let validation = validateBoard()
        invalidCells = validation.invalidCells

        if validation.solved {
            status = "Solved"
            message = "Everything checks out. Puzzle solved!"
        } else if !validation.invalidCells.isEmpty {
            status = "Conflicts"
            message = "Highlighted stars break the rules. Adjust those placements first."
        } else {
            status = ""
            message = "No direct conflicts yet. Try the single-cell regions first."
        }
    }

    func useHint() {
        guard let hintPosition = currentPuzzle.solution.first(where: { boardState[$0.row][$0.column] != .star }) else {
            message = "All solution stars are already placed."
            return
        }

        saveHistory()
        boardState[hintPosition.row][hintPosition.column] = .star
        invalidCells.removeAll()
        if autoMarkEnabled {
            applyAutoMarks()
        }
        updateSolvedState()
        if status != "Solved" {
            message = ""
        }
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        boardState = previous
        invalidCells.removeAll()
        canUndo = !history.isEmpty
        lastTapPosition = nil
        let validation = validateBoard()
        status = validation.solved ? "Solved" : ""
        message = ""
    }

    private func loadPuzzle(at index: Int) {
        guard !puzzles.isEmpty else { return }
        puzzleIndex = index
        boardState = Self.emptyBoard(size: puzzles[index].size)
        history.removeAll()
        invalidCells.removeAll()
        canUndo = false
        status = ""
        lastSolvedDurationText = ""
        lastTapPosition = nil
        puzzleStartTime = Date()
        message = ""
    }

    private func updateSolvedState() {
        let validation = validateBoard()
        if validation.solved {
            status = "Solved"
            lastSolvedDurationText = formattedElapsedTime(since: puzzleStartTime)
            message = ""
            invalidCells.removeAll()
        } else {
            status = ""
        }
    }

    private func saveHistory() {
        history.append(boardState)
        canUndo = true
    }

    private func promoteLastMarkToStar(at position: CellPosition) {
        if boardState[position.row][position.column] == .marked {
            boardState[position.row][position.column] = .star
        } else {
            boardState[position.row][position.column] = .star
        }
        invalidCells.removeAll()
        if autoMarkEnabled {
            applyAutoMarks()
        }
        updateSolvedState()
    }

    private func applyAutoMarks() {
        for star in starPositions {
            for rowOffset in -1...1 {
                for columnOffset in -1...1 {
                    let row = star.row + rowOffset
                    let column = star.column + columnOffset
                    guard row >= 0, row < currentPuzzle.size, column >= 0, column < currentPuzzle.size else {
                        continue
                    }
                    if boardState[row][column] == .empty {
                        boardState[row][column] = .marked
                    }
                }
            }
        }

        for row in 0..<currentPuzzle.size where rowHasQuota(row) {
            for column in 0..<currentPuzzle.size where boardState[row][column] == .empty {
                boardState[row][column] = .marked
            }
        }

        for column in 0..<currentPuzzle.size where columnHasQuota(column) {
            for row in 0..<currentPuzzle.size where boardState[row][column] == .empty {
                boardState[row][column] = .marked
            }
        }

        let regionIDs = Set(currentPuzzle.regions.flatMap { $0 })
        for regionID in regionIDs where regionHasQuota(regionID) {
            for row in 0..<currentPuzzle.size {
                for column in 0..<currentPuzzle.size
                where currentPuzzle.regions[row][column] == regionID && boardState[row][column] == .empty {
                    boardState[row][column] = .marked
                }
            }
        }
    }

    private func rowHasQuota(_ row: Int) -> Bool {
        boardState[row].filter { $0 == .star }.count >= config.starsPerUnit
    }

    private func columnHasQuota(_ column: Int) -> Bool {
        (0..<currentPuzzle.size).filter { boardState[$0][column] == .star }.count >= config.starsPerUnit
    }

    private func regionHasQuota(_ regionID: String) -> Bool {
        var count = 0
        for row in 0..<currentPuzzle.size {
            for column in 0..<currentPuzzle.size
            where currentPuzzle.regions[row][column] == regionID && boardState[row][column] == .star {
                count += 1
            }
        }
        return count >= config.starsPerUnit
    }

    private func formattedElapsedTime(since start: Date) -> String {
        let interval = max(0, Int(Date().timeIntervalSince(start)))
        let minutes = interval / 60
        let seconds = interval % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }

    private func validateBoard() -> ValidationResult {
        let stars = starPositions
        var invalid = Set<CellPosition>()
        var rowCounts = Array(repeating: 0, count: currentPuzzle.size)
        var columnCounts = Array(repeating: 0, count: currentPuzzle.size)
        var regionCounts: [String: Int] = [:]

        for star in stars {
            rowCounts[star.row] += 1
            columnCounts[star.column] += 1
            let region = currentPuzzle.regions[star.row][star.column]
            regionCounts[region, default: 0] += 1
        }

        for (index, star) in stars.enumerated() {
            let region = currentPuzzle.regions[star.row][star.column]
            if rowCounts[star.row] > config.starsPerUnit ||
                columnCounts[star.column] > config.starsPerUnit ||
                regionCounts[region, default: 0] > config.starsPerUnit {
                invalid.insert(star)
            }

            if index + 1 >= stars.count {
                continue
            }

            for other in stars[(index + 1)...] {
                let rowDistance = abs(star.row - other.row)
                let columnDistance = abs(star.column - other.column)
                if rowDistance <= 1 && columnDistance <= 1 {
                    invalid.insert(star)
                    invalid.insert(other)
                }
            }
        }

        let regionTotal = Set(currentPuzzle.regions.flatMap { $0 }).count
        let solved = invalid.isEmpty &&
            rowCounts.allSatisfy { $0 == config.starsPerUnit } &&
            columnCounts.allSatisfy { $0 == config.starsPerUnit } &&
            regionCounts.count == regionTotal &&
            regionCounts.values.allSatisfy { $0 == config.starsPerUnit }

        return ValidationResult(invalidCells: invalid, solved: solved)
    }

    private var starPositions: [CellPosition] {
        var positions: [CellPosition] = []
        for row in 0..<boardState.count {
            for column in 0..<boardState[row].count where boardState[row][column] == .star {
                positions.append(CellPosition(row: row, column: column))
            }
        }
        return positions
    }

    private static func emptyBoard(size: Int) -> [[CellState]] {
        Array(repeating: Array(repeating: .empty, count: size), count: size)
    }
}
