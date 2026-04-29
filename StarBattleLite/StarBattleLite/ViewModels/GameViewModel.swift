import Foundation

@MainActor
final class GameViewModel: ObservableObject {
    private enum StorageKeys {
        static let autoMarkEnabled = "starbattle.autoMarkEnabled"
        static let colorRegionsEnabled = "starbattle.colorRegionsEnabled"
        static let leaderboard = "starbattle.leaderboard"
        static let solvedPuzzleIDs = "starbattle.solvedPuzzleIDs"
        static let activeSession = "starbattle.activeSession"
        static let puzzleOrder = "starbattle.puzzleOrder"
    }

    private struct ActiveSessionSnapshot: Codable {
        let boardSize: Int
        let starsPerUnit: Int
        let difficulty: String
        let puzzleID: String
        let boardState: [[CellState]]
        let startedAt: Date

        private enum CodingKeys: String, CodingKey {
            case boardSize
            case starsPerUnit
            case difficulty
            case puzzleID
            case boardState
            case startedAt
        }

        init(boardSize: Int, starsPerUnit: Int, difficulty: String, puzzleID: String, boardState: [[CellState]], startedAt: Date) {
            self.boardSize = boardSize
            self.starsPerUnit = starsPerUnit
            self.difficulty = difficulty
            self.puzzleID = puzzleID
            self.boardState = boardState
            self.startedAt = startedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            boardSize = try container.decode(Int.self, forKey: .boardSize)
            starsPerUnit = try container.decodeIfPresent(Int.self, forKey: .starsPerUnit) ?? 1
            difficulty = try container.decode(String.self, forKey: .difficulty)
            puzzleID = try container.decode(String.self, forKey: .puzzleID)
            boardState = try container.decode([[CellState]].self, forKey: .boardState)
            startedAt = try container.decode(Date.self, forKey: .startedAt)
        }
    }

    @Published private(set) var config: GameConfig
    @Published private(set) var puzzles: [Puzzle]
    @Published private(set) var puzzleIndex: Int = 0
    @Published private(set) var currentBoardSize: PuzzleBoardSize = .six
    @Published private(set) var currentDifficulty: PuzzleDifficulty = .easy
    @Published private(set) var boardState: [[CellState]]
    @Published var message: String = ""
    @Published var status: String = ""
    @Published var autoMarkEnabled: Bool
    @Published var colorRegionsEnabled: Bool
    @Published private(set) var invalidCells: Set<CellPosition> = []
    @Published private(set) var hintCells: Set<CellPosition> = []
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var lastSolvedDurationText: String = ""
    @Published private(set) var leaderboard: [GameStyle: [LeaderboardEntry]]
    @Published private(set) var solvedPuzzleIDs: [GameStyle: Set<String>]

    private var history: [[[CellState]]] = []
    private var lastTapPosition: CellPosition?
    private var lastTapTime = Date.distantPast
    private var puzzleStartTime = Date()
    private let userDefaults: UserDefaults

    init(
        config: GameConfig = .oneStar,
        puzzles: [Puzzle] = PuzzleLibrary.puzzles(for: .easy, boardSize: .six, starsPerUnit: 1),
        userDefaults: UserDefaults = .standard
    ) {
        self.userDefaults = userDefaults
        self.config = config
        self.puzzles = puzzles
        self.autoMarkEnabled = userDefaults.bool(forKey: StorageKeys.autoMarkEnabled)
        self.colorRegionsEnabled = userDefaults.bool(forKey: StorageKeys.colorRegionsEnabled)
        self.leaderboard = Self.loadLeaderboard(from: userDefaults)
        self.solvedPuzzleIDs = Self.loadSolvedPuzzleIDs(from: userDefaults)
        let initialPuzzles = Self.orderedPuzzles(
            from: puzzles,
            for: GameStyle(boardSize: .six, starsPerUnit: config.starsPerUnit),
            difficulty: .easy,
            userDefaults: userDefaults
        )
        self.puzzles = initialPuzzles
        self.boardState = Array(
            repeating: Array(repeating: .empty, count: config.boardSize),
            count: config.boardSize
        )
        if !restoreActiveSessionIfPossible() {
            loadPuzzle(at: preferredStartIndex(for: .six))
        }
    }

    var currentPuzzle: Puzzle {
        puzzles[puzzleIndex]
    }

    var availableDifficultyCounts: [PuzzleDifficulty: Int] {
        Dictionary(uniqueKeysWithValues: PuzzleDifficulty.allCases.map { difficulty in
            (difficulty, PuzzleLibrary.puzzleCount(for: difficulty, boardSize: currentBoardSize, starsPerUnit: config.starsPerUnit))
        })
    }

    func availableBoardCounts(for starsPerUnit: Int) -> [PuzzleBoardSize: Int] {
        Dictionary(uniqueKeysWithValues: PuzzleBoardSize.allCases.map { boardSize in
            (boardSize, PuzzleLibrary.puzzleCount(for: boardSize, starsPerUnit: starsPerUnit))
        })
    }

    func leaderboardEntries(for style: GameStyle) -> [LeaderboardEntry] {
        leaderboard[style] ?? []
    }

    func bestTimeText(for boardSize: PuzzleBoardSize, starsPerUnit: Int) -> String? {
        let style = GameStyle(boardSize: boardSize, starsPerUnit: starsPerUnit)
        guard let duration = leaderboard[style]?.first?.duration else { return nil }
        return Self.formatDuration(duration)
    }

    func solvedCount(for boardSize: PuzzleBoardSize, starsPerUnit: Int) -> Int {
        let style = GameStyle(boardSize: boardSize, starsPerUnit: starsPerUnit)
        return solvedPuzzleIDs[style]?.count ?? 0
    }

    func completionRatio(for boardSize: PuzzleBoardSize, starsPerUnit: Int) -> Double {
        let total = max(PuzzleLibrary.puzzleCount(for: boardSize, starsPerUnit: starsPerUnit), 1)
        return min(Double(solvedCount(for: boardSize, starsPerUnit: starsPerUnit)) / Double(total), 1)
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

    var isCurrentPuzzleSolved: Bool {
        status == "Solved"
    }

    var hasActiveSession: Bool {
        loadActiveSession() != nil
    }

    var activeSessionStyle: GameStyle? {
        guard let snapshot = loadActiveSession(),
              let boardSize = PuzzleBoardSize(rawValue: snapshot.boardSize) else {
            return nil
        }
        return GameStyle(boardSize: boardSize, starsPerUnit: snapshot.starsPerUnit)
    }

    func discardActiveSession() {
        clearActiveSession()
    }

    func toggleStar(at position: CellPosition) {
        saveHistory()
        let current = boardState[position.row][position.column]
        boardState[position.row][position.column] = current == .star ? .empty : .star

        invalidCells.removeAll()
        hintCells.removeAll()
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
        hintCells.removeAll()
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
        hintCells.removeAll()
        updateSolvedState()
        lastTapPosition = position
        lastTapTime = now
    }

    func applyDraggedMark(at position: CellPosition) {
        guard boardState[position.row][position.column] == .empty else { return }
        boardState[position.row][position.column] = .marked
        invalidCells.removeAll()
        hintCells.removeAll()
        persistSessionIfNeeded()
    }

    func setAutoMarkEnabled(_ enabled: Bool) {
        autoMarkEnabled = enabled
        userDefaults.set(enabled, forKey: StorageKeys.autoMarkEnabled)
        if enabled {
            saveHistory()
            applyAutoMarks()
            updateSolvedState()
        }
    }

    func setColorRegionsEnabled(_ enabled: Bool) {
        colorRegionsEnabled = enabled
        userDefaults.set(enabled, forKey: StorageKeys.colorRegionsEnabled)
    }

    func resetBoard() {
        history.removeAll()
        boardState = Self.emptyBoard(size: currentPuzzle.size)
        invalidCells.removeAll()
        hintCells.removeAll()
        status = ""
        canUndo = false
        lastSolvedDurationText = ""
        lastTapPosition = nil
        puzzleStartTime = Date()
        message = ""
        clearActiveSession()
    }

    func loadNextPuzzle() {
        guard isCurrentPuzzleSolved else { return }
        let nextIndex = nextPuzzleIndex(after: puzzleIndex)
        loadPuzzle(at: nextIndex)
    }

    func startNewSession(boardSize: PuzzleBoardSize, difficulty: PuzzleDifficulty, starsPerUnit: Int) {
        if let snapshot = loadActiveSession(),
           let snapshotSize = PuzzleBoardSize(rawValue: snapshot.boardSize),
           snapshotSize == boardSize,
           snapshot.starsPerUnit == starsPerUnit,
           restore(snapshot: snapshot, difficulty: difficulty) {
            return
        }

        if loadActiveSession() != nil {
            clearActiveSession()
        }

        currentBoardSize = boardSize
        currentDifficulty = difficulty
        config = GameConfig(starsPerUnit: starsPerUnit, boardSize: boardSize.rawValue)
        puzzles = Self.orderedPuzzles(
            from: PuzzleLibrary.puzzles(for: difficulty, boardSize: boardSize, starsPerUnit: starsPerUnit),
            for: GameStyle(boardSize: boardSize, starsPerUnit: starsPerUnit),
            difficulty: difficulty,
            userDefaults: userDefaults
        )
        loadPuzzle(at: preferredStartIndex(for: boardSize))
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
            message = "No direct conflicts yet. Keep narrowing rows, columns, and regions."
        }
    }

    func useHint() {
        invalidCells.removeAll()
        hintCells.removeAll()

        if let hint = nextHint() {
            hintCells = hint.cells
            message = hint.message
            return
        }

        message = "No clear deduction right now. Try checking rows and regions with the fewest open cells."
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        boardState = previous
        invalidCells.removeAll()
        hintCells.removeAll()
        canUndo = !history.isEmpty
        lastTapPosition = nil
        let validation = validateBoard()
        status = validation.solved ? "Solved" : ""
        message = ""
        persistSessionIfNeeded()
    }

    private func loadPuzzle(at index: Int) {
        guard !puzzles.isEmpty else { return }
        puzzleIndex = index
        boardState = Self.emptyBoard(size: puzzles[index].size)
        history.removeAll()
        invalidCells.removeAll()
        hintCells.removeAll()
        canUndo = false
        status = ""
        lastSolvedDurationText = ""
        lastTapPosition = nil
        puzzleStartTime = Date()
        message = ""
        clearActiveSession()
    }

    private var boardHasProgress: Bool {
        boardState.flatMap { $0 }.contains { $0 != .empty }
    }

    private var currentStyle: GameStyle {
        GameStyle(boardSize: currentBoardSize, starsPerUnit: config.starsPerUnit)
    }

    private func preferredStartIndex(for boardSize: PuzzleBoardSize) -> Int {
        guard !puzzles.isEmpty else { return 0 }

        let solvedIDs = solvedPuzzleIDs[currentStyle] ?? []
        if let unsolvedIndex = puzzles.firstIndex(where: { !solvedIDs.contains($0.id) }) {
            return unsolvedIndex
        }

        return 0
    }

    private func nextPuzzleIndex(after index: Int) -> Int {
        guard !puzzles.isEmpty else { return 0 }

        let solvedIDs = solvedPuzzleIDs[currentStyle] ?? []
        for offset in 1...puzzles.count {
            let nextIndex = (index + offset) % puzzles.count
            if !solvedIDs.contains(puzzles[nextIndex].id) {
                return nextIndex
            }
        }

        return (index + 1) % puzzles.count
    }

    private func updateSolvedState() {
        let validation = validateBoard()
        if validation.solved {
            let wasSolved = status == "Solved"
            status = "Solved"
            let elapsed = Date().timeIntervalSince(puzzleStartTime)
            lastSolvedDurationText = Self.formatDuration(elapsed)
            message = ""
            invalidCells.removeAll()
            hintCells.removeAll()
            if !wasSolved {
                recordSolvedTime(elapsed)
                recordSolvedPuzzle()
            }
            clearActiveSession()
        } else {
            status = ""
            persistSessionIfNeeded()
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
        hintCells.removeAll()
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

    private func recordSolvedTime(_ duration: TimeInterval) {
        let entry = LeaderboardEntry(duration: duration)
        var entries = leaderboard[currentStyle] ?? []
        entries.append(entry)
        entries.sort { $0.duration < $1.duration }
        leaderboard[currentStyle] = Array(entries.prefix(5))
        saveLeaderboard()
    }

    private func recordSolvedPuzzle() {
        var ids = solvedPuzzleIDs[currentStyle] ?? []
        ids.insert(currentPuzzle.id)
        solvedPuzzleIDs[currentStyle] = ids
        saveSolvedPuzzleIDs()
    }

    private func persistSessionIfNeeded() {
        guard boardHasProgress, !isCurrentPuzzleSolved else {
            clearActiveSession()
            return
        }

        let snapshot = ActiveSessionSnapshot(
            boardSize: currentBoardSize.rawValue,
            starsPerUnit: config.starsPerUnit,
            difficulty: currentDifficulty.rawValue,
            puzzleID: currentPuzzle.id,
            boardState: boardState,
            startedAt: puzzleStartTime
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(data, forKey: StorageKeys.activeSession)
    }

    private func clearActiveSession() {
        userDefaults.removeObject(forKey: StorageKeys.activeSession)
    }

    private func loadActiveSession() -> ActiveSessionSnapshot? {
        guard
            let data = userDefaults.data(forKey: StorageKeys.activeSession),
            let snapshot = try? JSONDecoder().decode(ActiveSessionSnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot
    }

    private func restoreActiveSessionIfPossible() -> Bool {
        guard let snapshot = loadActiveSession(),
              let boardSize = PuzzleBoardSize(rawValue: snapshot.boardSize),
              let difficulty = PuzzleDifficulty(rawValue: snapshot.difficulty) else {
            return false
        }

        return restore(snapshot: snapshot, difficulty: difficulty, fallbackBoardSize: boardSize)
    }

    private func restore(
        snapshot: ActiveSessionSnapshot,
        difficulty: PuzzleDifficulty,
        fallbackBoardSize: PuzzleBoardSize? = nil
    ) -> Bool {
        let boardSize = fallbackBoardSize ?? PuzzleBoardSize(rawValue: snapshot.boardSize) ?? currentBoardSize
        let style = GameStyle(boardSize: boardSize, starsPerUnit: snapshot.starsPerUnit)
        let ordered = Self.orderedPuzzles(
            from: PuzzleLibrary.puzzles(for: difficulty, boardSize: boardSize, starsPerUnit: snapshot.starsPerUnit),
            for: style,
            difficulty: difficulty,
            userDefaults: userDefaults
        )
        guard let index = ordered.firstIndex(where: { $0.id == snapshot.puzzleID }) else {
            clearActiveSession()
            return false
        }

        currentBoardSize = boardSize
        currentDifficulty = difficulty
        config = GameConfig(starsPerUnit: snapshot.starsPerUnit, boardSize: boardSize.rawValue)
        puzzles = ordered
        puzzleIndex = index
        boardState = snapshot.boardState
        history.removeAll()
        invalidCells.removeAll()
        hintCells.removeAll()
        canUndo = false
        status = validateBoard().solved ? "Solved" : ""
        lastSolvedDurationText = ""
        lastTapPosition = nil
        puzzleStartTime = snapshot.startedAt
        message = ""
        return true
    }

    private static func orderedPuzzles(
        from puzzles: [Puzzle],
        for style: GameStyle,
        difficulty: PuzzleDifficulty,
        userDefaults: UserDefaults
    ) -> [Puzzle] {
        guard !puzzles.isEmpty else { return [] }

        // Keep the first copy of each ID so stale duplicate entries in the
        // generated bank don't crash startup when we build the lookup table.
        var uniquePuzzles: [Puzzle] = []
        var seenIDs = Set<String>()
        for puzzle in puzzles where seenIDs.insert(puzzle.id).inserted {
            uniquePuzzles.append(puzzle)
        }

        let orderKey = "\(style.storageKey)-\(difficulty.rawValue)"
        let savedOrders = loadPuzzleOrders(from: userDefaults)
        let currentIDs = Set(uniquePuzzles.map(\.id))
        let legacyKey = style.starsPerUnit == 1 && difficulty == .easy ? String(style.boardSize.rawValue) : nil
        let savedOrder = (savedOrders[orderKey] ?? legacyKey.flatMap { savedOrders[$0] } ?? []).filter { currentIDs.contains($0) }
        let missingIDs = currentIDs.subtracting(savedOrder).shuffled()
        let finalOrder = savedOrder + missingIDs
        savePuzzleOrder(finalOrder, for: orderKey, in: userDefaults)

        let lookup = Dictionary(uniqueKeysWithValues: uniquePuzzles.map { ($0.id, $0) })
        return finalOrder.compactMap { lookup[$0] }
    }

    private static func loadPuzzleOrders(from userDefaults: UserDefaults) -> [String: [String]] {
        guard
            let data = userDefaults.data(forKey: StorageKeys.puzzleOrder),
            let payload = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return [:]
        }
        return payload
    }

    private static func savePuzzleOrder(_ order: [String], for key: String, in userDefaults: UserDefaults) {
        var payload = loadPuzzleOrders(from: userDefaults)
        payload[key] = order
        guard let data = try? JSONEncoder().encode(payload) else { return }
        userDefaults.set(data, forKey: StorageKeys.puzzleOrder)
    }

    private struct HintSuggestion {
        let cells: Set<CellPosition>
        let message: String
    }

    private func nextHint() -> HintSuggestion? {
        let candidates = candidateMap()

        let regionIDs = Array(Set(currentPuzzle.regions.flatMap { $0 })).sorted()
        for regionID in regionIDs where !regionHasQuota(regionID) {
            let regionCandidates = candidates
                .filter { currentPuzzle.regions[$0.key.row][$0.key.column] == regionID }
                .map(\.key)
            if regionCandidates.count == 1, let cell = regionCandidates.first {
                return HintSuggestion(
                    cells: [cell],
                    message: "This region has only one possible star left."
                )
            }
        }

        for row in 0..<currentPuzzle.size where !rowHasQuota(row) {
            let rowCandidates = candidates.keys.filter { $0.row == row }
            if rowCandidates.count == 1, let cell = rowCandidates.first {
                return HintSuggestion(
                    cells: [cell],
                    message: "Row \(row + 1) has only one legal place for its star."
                )
            }
        }

        for column in 0..<currentPuzzle.size where !columnHasQuota(column) {
            let columnCandidates = candidates.keys.filter { $0.column == column }
            if columnCandidates.count == 1, let cell = columnCandidates.first {
                return HintSuggestion(
                    cells: [cell],
                    message: "Column \(column + 1) has only one legal place for its star."
                )
            }
        }

        for row in 0..<currentPuzzle.size {
            for column in 0..<currentPuzzle.size {
                let position = CellPosition(row: row, column: column)
                guard boardState[row][column] == .empty else { continue }
                if !isLegalStarPosition(position) {
                    return HintSuggestion(
                        cells: [position],
                        message: "This cell can't hold a star. Mark it with an X."
                    )
                }
            }
        }

        return nil
    }

    private func candidateMap() -> [CellPosition: Bool] {
        var candidates: [CellPosition: Bool] = [:]
        for row in 0..<currentPuzzle.size {
            for column in 0..<currentPuzzle.size {
                let position = CellPosition(row: row, column: column)
                guard boardState[row][column] != .star else { continue }
                if isLegalStarPosition(position) {
                    candidates[position] = true
                }
            }
        }
        return candidates
    }

    private func isLegalStarPosition(_ position: CellPosition) -> Bool {
        if boardState[position.row][position.column] == .star {
            return true
        }

        if rowHasQuota(position.row) || columnHasQuota(position.column) {
            return false
        }

        let regionID = currentPuzzle.regions[position.row][position.column]
        if regionHasQuota(regionID) {
            return false
        }

        for star in starPositions {
            if abs(star.row - position.row) <= 1 && abs(star.column - position.column) <= 1 {
                return false
            }
        }

        return true
    }

    private func saveLeaderboard() {
        let payload = Dictionary(
            uniqueKeysWithValues: leaderboard.map { key, value in
                (key.storageKey, value)
            }
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        userDefaults.set(data, forKey: StorageKeys.leaderboard)
    }

    private func saveSolvedPuzzleIDs() {
        let payload = Dictionary(
            uniqueKeysWithValues: solvedPuzzleIDs.map { key, value in
                (key.storageKey, Array(value).sorted())
            }
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        userDefaults.set(data, forKey: StorageKeys.solvedPuzzleIDs)
    }

    private static func loadLeaderboard(from userDefaults: UserDefaults) -> [GameStyle: [LeaderboardEntry]] {
        guard
            let data = userDefaults.data(forKey: StorageKeys.leaderboard),
            let payload = try? JSONDecoder().decode([String: [LeaderboardEntry]].self, from: data)
        else {
            return [:]
        }

        var result: [GameStyle: [LeaderboardEntry]] = [:]
        for (rawKey, entries) in payload {
            if let style = GameStyle.fromStorageKey(rawKey) {
                result[style] = entries.sorted { $0.duration < $1.duration }
                continue
            }

            guard let sizeValue = Int(rawKey), let boardSize = PuzzleBoardSize(rawValue: sizeValue) else {
                continue
            }

            let style = GameStyle(boardSize: boardSize, starsPerUnit: 1)
            result[style] = entries.sorted { $0.duration < $1.duration }
        }
        return result
    }

    private static func loadSolvedPuzzleIDs(from userDefaults: UserDefaults) -> [GameStyle: Set<String>] {
        guard
            let data = userDefaults.data(forKey: StorageKeys.solvedPuzzleIDs),
            let payload = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return [:]
        }

        var result: [GameStyle: Set<String>] = [:]
        for (rawKey, ids) in payload {
            if let style = GameStyle.fromStorageKey(rawKey) {
                result[style] = Set(ids)
                continue
            }

            guard let sizeValue = Int(rawKey), let boardSize = PuzzleBoardSize(rawValue: sizeValue) else {
                continue
            }

            let style = GameStyle(boardSize: boardSize, starsPerUnit: 1)
            result[style] = Set(ids)
        }
        return result
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
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
