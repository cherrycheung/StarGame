import SwiftUI

private enum AppRootTab: Hashable {
    case play
    case challenge
}

private enum StarMode: Int {
    case one = 1
    case two = 2

    var title: String {
        "\(rawValue) Star"
    }

    var subtitle: String {
        switch self {
        case .one:
            return "Classic single-star puzzles"
        case .two:
            return "Denser two-star boards"
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = GameViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: AppRootTab = .play
    @State private var showingGame = false
    @State private var selectedMode: StarMode = .one
    @State private var selectedBoardSize: PuzzleBoardSize = .eight
    @State private var showSettings = false
    @State private var showRecords = false
    @State private var showSolvedCelebration = false
    @State private var pendingStartStyle: GameStyle?
    @State private var showSessionChoice = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    LinearGradient(
                        colors: [palette.backgroundTop, palette.backgroundBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()

                    VStack(spacing: 0) {
                        topTabHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 18)
                            .padding(.bottom, 8)

                        TabView(selection: $selectedTab) {
                            homeScreen
                                .tag(AppRootTab.play)
                                .tabItem {
                                    Label("Solo", systemImage: "person.fill")
                                }

                            challengeScreen
                                .tag(AppRootTab.challenge)
                                .tabItem {
                                    Label("Challenge", systemImage: "person.2.fill")
                                }
                        }
                    }
                    .opacity(showingGame ? 0 : 1)
                    .allowsHitTesting(!showingGame)

                    if showingGame {
                        gameScreen(availableSize: geometry.size)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSettings) {
                SettingsSheet(
                    autoMarkEnabled: Binding(
                        get: { viewModel.autoMarkEnabled },
                        set: { viewModel.setAutoMarkEnabled($0) }
                    ),
                    colorRegionsEnabled: Binding(
                        get: { viewModel.colorRegionsEnabled },
                        set: { viewModel.setColorRegionsEnabled($0) }
                    )
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showRecords) {
                BestTimesSheet(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                sessionChoiceTitle,
                isPresented: $showSessionChoice,
                titleVisibility: .visible
            ) {
                if let activeStyle = viewModel.activeSessionStyle {
                    Button("Resume \(activeStyle.title)") {
                        startActiveSession(activeStyle)
                    }
                }

                Button(startNewChoiceTitle, role: .destructive) {
                    startSelectedGameDiscardingActiveSession()
                }

                Button("Cancel", role: .cancel) {
                    pendingStartStyle = nil
                }
            } message: {
                Text(sessionChoiceMessage)
            }
        }
        .onChange(of: selectedMode) { _, _ in
            normalizeSelectedBoardSize()
        }
    }

    private var homeScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Star Mode")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(palette.headerSubtext)

                    HStack(spacing: 12) {
                        ForEach([StarMode.one, StarMode.two], id: \.rawValue) { mode in
                            SelectionChipButton(
                                title: mode.title,
                                subtitle: modeInstruction(mode),
                                isSelected: selectedMode == mode,
                                action: {
                                    guard modeIsAvailable(mode) else { return }
                                    selectedMode = mode
                                }
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Board Size")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(palette.headerSubtext)

                    HStack(spacing: 12) {
                        ForEach(visibleBoardSizes) { boardSize in
                            CompactSelectionChipButton(
                                title: boardSize.title,
                                subtitle: boardSizeSummary(boardSize),
                                isSelected: selectedBoardSize == boardSize,
                                action: {
                                    selectedBoardSize = boardSize
                                }
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }

            Button {
                handleStartButton()
            } label: {
                Label("Start Game", systemImage: homeActionSymbol)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(startButtonForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(startButtonBackground).interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: startButtonShadow, radius: 16, y: 9)
            .disabled(
                PuzzleLibrary.puzzleCount(for: .easy, boardSize: selectedBoardSize, starsPerUnit: selectedMode.rawValue) == 0 ||
                !modeIsAvailable(selectedMode)
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var challengeScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            HomeSectionCard(title: "Coming Soon") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Async 1v1 is the next step for this app.")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(palette.headerText)

                    Text("You’ll be able to send the same puzzle to a friend, each solve on your own time, and let the app compare the finish times.")
                        .font(.subheadline)
                        .foregroundStyle(palette.bodySubtext)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        ChallengeFeatureRow(symbol: "paperplane.fill", text: "Send a challenge link")
                        ChallengeFeatureRow(symbol: "square.grid.2x2.fill", text: "Play the exact same puzzle")
                        ChallengeFeatureRow(symbol: "timer", text: "Compare finish times automatically")
                    }
                }
            }

            HomeSectionCard(title: "Preview") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Challenge Mode")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(palette.headerText)

                    Text("We’ll give this its own setup flow so it feels distinct from solo play.")
                        .font(.subheadline)
                        .foregroundStyle(palette.bodySubtext)

                    HStack(spacing: 10) {
                        ChallengePill(title: "Same Puzzle")
                        ChallengePill(title: "Best Time Wins")
                    }
                }
            }

            Button {
            } label: {
                Label("Challenge Coming Soon", systemImage: "person.2.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(startButtonForeground.opacity(0.92))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(startButtonBackground.opacity(0.82)).interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: startButtonShadow, radius: 14, y: 8)
            .opacity(0.78)
            .disabled(true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func gameScreen(availableSize: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            gameHeader
            puzzleCard(availableWidth: availableSize.width)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: availableSize.width, height: availableSize.height, alignment: .top)
    }

    private var gameHeader: some View {
        HStack(spacing: 12) {
            Button {
                showingGame = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(palette.headerText)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive())

            VStack(alignment: .leading, spacing: 4) {
                Text("Star Battle")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.headerText)
                Text("\(selectedMode.title) • \(viewModel.currentBoardSize.title)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.headerSubtext)
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(palette.headerText)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive())
        }
        .padding(12)
        .background(palette.headerCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(palette.headerBorder, lineWidth: 1)
        }
    }

    private func puzzleCard(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ActionIconButton(symbol: "shuffle", title: "New") {
                    viewModel.loadNextPuzzle()
                }
                .disabled(!viewModel.isCurrentPuzzleSolved)

                ActionIconButton(symbol: "lightbulb", title: "Hint") {
                    viewModel.useHint()
                }

                ActionIconButton(symbol: "arrow.uturn.backward", title: "Undo") {
                    viewModel.undo()
                }
                .disabled(!viewModel.canUndo)

                ActionIconButton(symbol: "trash", title: "Clear") {
                    viewModel.resetBoard()
                }

                ActionIconButton(symbol: "checkmark.circle", title: "Check") {
                    viewModel.checkProgress()
                }
            }
            .font(.subheadline.weight(.medium))

            BoardView(viewModel: viewModel, availableWidth: availableWidth - 64)

            if !viewModel.message.isEmpty {
                Text(viewModel.message)
                    .font(.footnote)
                    .foregroundStyle(palette.bodySubtext)
            }
        }
        .padding(16)
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .center) {
            if showSolvedCelebration {
                SolvedOverlay(
                    durationText: viewModel.lastSolvedDurationText,
                    onNewGame: {
                        showSolvedCelebration = false
                        viewModel.loadNextPuzzle()
                    },
                    onHome: {
                        showSolvedCelebration = false
                        showingGame = false
                        selectedTab = .play
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onChange(of: viewModel.status) { _, newValue in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                showSolvedCelebration = newValue == "Solved"
            }
        }
    }

    private var palette: AppPalette {
        AppPalette(colorScheme: colorScheme)
    }

    private var homeActionTitle: String {
        "Start Game"
    }

    private var homeActionSymbol: String {
        "play.fill"
    }

    private var selectedStyle: GameStyle {
        GameStyle(boardSize: selectedBoardSize, starsPerUnit: selectedMode.rawValue)
    }

    private var visiblePickerBoardSizes: [PuzzleBoardSize] {
        [.eight, .ten]
    }

    private var visibleBoardSizes: [PuzzleBoardSize] {
        visiblePickerBoardSizes.filter {
            viewModel.availableBoardCounts(for: selectedMode.rawValue)[$0, default: 0] > 0
        }
    }

    private var startButtonBackground: Color {
        palette.star
    }

    private var startButtonForeground: Color {
        colorScheme == .dark ? Color.black.opacity(0.86) : Color.white
    }

    private var startButtonShadow: Color {
        palette.star.opacity(colorScheme == .dark ? 0.22 : 0.28)
    }

    private var topTabHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Star Battle")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(palette.headerAccent)

            Spacer()

            HStack(spacing: 10) {
                if selectedTab == .play {
                    HomeIconButton(symbol: "list.number") {
                        showRecords = true
                    }
                }

                HomeIconButton(symbol: "gearshape.fill") {
                    showSettings = true
                }
            }
        }
        .frame(height: 60, alignment: .top)
    }


    private func modeIsAvailable(_ mode: StarMode) -> Bool {
        viewModel.availableBoardCounts(for: mode.rawValue).values.contains { $0 > 0 }
    }

    private func modeSubtitle(_ mode: StarMode) -> String {
        let counts = viewModel.availableBoardCounts(for: mode.rawValue)
        let availableSizes = visiblePickerBoardSizes.filter { counts[$0, default: 0] > 0 }.map(\.title)
        if availableSizes.isEmpty {
            return mode.subtitle
        }
        return availableSizes.joined(separator: " • ")
    }

    private func modeInstruction(_ mode: StarMode) -> String {
        switch mode {
        case .one:
            return "1 in each row, column, region"
        case .two:
            return "2 in each row, column, region"
        }
    }

    private func boardSizeSummary(_ boardSize: PuzzleBoardSize) -> String {
        "\(viewModel.solvedCount(for: boardSize, starsPerUnit: selectedMode.rawValue))/\(PuzzleLibrary.puzzleCount(for: .easy, boardSize: boardSize, starsPerUnit: selectedMode.rawValue)) solved"
    }

    private func normalizeSelectedBoardSize() {
        let counts = viewModel.availableBoardCounts(for: selectedMode.rawValue)
        guard counts[selectedBoardSize, default: 0] == 0 else { return }
        if let firstAvailable = visiblePickerBoardSizes.first(where: { counts[$0, default: 0] > 0 }) {
            selectedBoardSize = firstAvailable
        }
    }

    private var sessionChoiceTitle: String {
        guard let activeStyle = viewModel.activeSessionStyle else {
            return "Unfinished Game"
        }
        return activeStyle == selectedStyle ? "Continue This Game?" : "Unfinished Game Found"
    }

    private var sessionChoiceMessage: String {
        guard let activeStyle = viewModel.activeSessionStyle else {
            return ""
        }
        if activeStyle == selectedStyle {
            return "You already have an unfinished \(activeStyle.title) puzzle."
        }
        return "You already have an unfinished \(activeStyle.title) puzzle. Starting \(selectedStyle.title) will forfeit it."
    }

    private var startNewChoiceTitle: String {
        guard let activeStyle = viewModel.activeSessionStyle, activeStyle == selectedStyle else {
            return "Start \(selectedStyle.title)"
        }
        return "Start New \(selectedStyle.title)"
    }

    private func handleStartButton() {
        pendingStartStyle = selectedStyle
        guard viewModel.activeSessionStyle != nil else {
            startSelectedGame()
            return
        }
        showSessionChoice = true
    }

    private func startSelectedGame() {
        viewModel.startNewSession(
            boardSize: selectedBoardSize,
            difficulty: .easy,
            starsPerUnit: selectedMode.rawValue
        )
        showingGame = true
        pendingStartStyle = nil
    }

    private func startSelectedGameDiscardingActiveSession() {
        viewModel.discardActiveSession()
        startSelectedGame()
    }

    private func startActiveSession(_ style: GameStyle) {
        selectedMode = style.starsPerUnit == 2 ? .two : .one
        selectedBoardSize = style.boardSize
        selectedTab = .play
        viewModel.startNewSession(
            boardSize: style.boardSize,
            difficulty: .easy,
            starsPerUnit: style.starsPerUnit
        )
        showingGame = true
        pendingStartStyle = nil
    }

}

private struct SettingsSheet: View {
    @Binding var autoMarkEnabled: Bool
    @Binding var colorRegionsEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Game") {
                    Toggle("Auto X", isOn: $autoMarkEnabled)
                    Toggle("Color Regions", isOn: $colorRegionsEnabled)
                }

                Section("How To Play") {
                    Text("Tap once for X.")
                    Text("Tap the same cell again quickly for a star.")
                    Text("Drag across the board to sweep crosses.")
                    Text("Place the required number of stars in every row, column, and region.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct BestTimesSheet: View {
    @ObservedObject var viewModel: GameViewModel
    @Environment(\.dismiss) private var dismiss

    private var styles: [GameStyle] {
        [PuzzleBoardSize.eight, .ten].flatMap { boardSize in
            [1, 2].map { GameStyle(boardSize: boardSize, starsPerUnit: $0) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(styles) { style in
                    if PuzzleLibrary.puzzleCount(for: .easy, boardSize: style.boardSize, starsPerUnit: style.starsPerUnit) > 0 {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(style.title)
                                    .font(.headline)
                                Text("Easy")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(viewModel.bestTimeText(for: style.boardSize, starsPerUnit: style.starsPerUnit) ?? "No time")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Best Times")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct BoardView: View {
    @ObservedObject var viewModel: GameViewModel
    let availableWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDragMarking = false
    @State private var draggedPositions = Set<CellPosition>()

    var body: some View {
        let size = viewModel.currentPuzzle.size
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: size)
        let boardSide = min(max(availableWidth, 0), 370)
        let positions = (0..<size).flatMap { row in
            (0..<size).map { column in
                CellPosition(row: row, column: column)
            }
        }

        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(positions, id: \.self) { position in
                ZStack {
                    Rectangle()
                        .fill(cellFill(for: position))

                    if viewModel.boardState[position.row][position.column] == .star {
                        Text("★")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.star)
                    } else if viewModel.boardState[position.row][position.column] == .marked {
                        Text("✕")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.mark)
                    }
                }
                .overlay {
                    Rectangle()
                        .strokeBorder(palette.gridLine, lineWidth: 0.5)
                }
                .overlay {
                    RegionEdgesShape(
                        top: needsTopBorder(position),
                        bottom: needsBottomBorder(position),
                        leading: needsLeadingBorder(position),
                        trailing: needsTrailingBorder(position)
                    )
                    .stroke(
                        viewModel.colorRegionsEnabled ? palette.regionBorder.opacity(0.8) : palette.regionBorder,
                        lineWidth: viewModel.colorRegionsEnabled ? 1.8 : 3
                    )
                }
                .overlay {
                    if viewModel.invalidCells.contains(position) {
                        Rectangle()
                            .stroke(Color.red.opacity(0.8), lineWidth: 3)
                            .padding(1)
                    }
                }
                .overlay {
                    if viewModel.hintCells.contains(position) {
                        Rectangle()
                            .stroke(Color(red: 0.44, green: 0.82, blue: 0.98), lineWidth: 3)
                            .padding(2)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .contentShape(Rectangle())
            }
        }
        .overlay(
            Rectangle()
                .stroke(palette.outerBorder, lineWidth: 1.5)
        )
        .frame(width: boardSide, height: boardSide)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard let position = position(for: value.location, boardSide: boardSide, size: size) else {
                        return
                    }

                    if !isDragMarking {
                        isDragMarking = true
                        draggedPositions.removeAll()
                        draggedPositions.insert(position)
                        viewModel.beginPrimaryInteraction(at: position)
                        return
                    }

                    if draggedPositions.insert(position).inserted {
                        viewModel.applyDraggedMark(at: position)
                    }
                }
                .onEnded { _ in
                    isDragMarking = false
                    draggedPositions.removeAll()
                }
        )
    }

    private func needsTopBorder(_ position: CellPosition) -> Bool {
        if position.row == 0 { return true }
        return regionID(position) != viewModel.currentPuzzle.regions[position.row - 1][position.column]
    }

    private func needsBottomBorder(_ position: CellPosition) -> Bool {
        if position.row == viewModel.currentPuzzle.size - 1 { return true }
        return regionID(position) != viewModel.currentPuzzle.regions[position.row + 1][position.column]
    }

    private func needsLeadingBorder(_ position: CellPosition) -> Bool {
        if position.column == 0 { return true }
        return regionID(position) != viewModel.currentPuzzle.regions[position.row][position.column - 1]
    }

    private func needsTrailingBorder(_ position: CellPosition) -> Bool {
        if position.column == viewModel.currentPuzzle.size - 1 { return true }
        return regionID(position) != viewModel.currentPuzzle.regions[position.row][position.column + 1]
    }

    private func regionID(_ position: CellPosition) -> String {
        viewModel.currentPuzzle.regions[position.row][position.column]
    }

    private func cellFill(for position: CellPosition) -> some ShapeStyle {
        if viewModel.colorRegionsEnabled {
            return AnyShapeStyle(regionColor(for: regionID(position)))
        }
        return AnyShapeStyle(palette.cellBackground)
    }

    private func regionColor(for regionID: String) -> Color {
        let colorsByRegion = regionColorsByID()
        if let color = colorsByRegion[regionID] {
            return color
        }
        return palette.cellBackground
    }

    private func regionColorsByID() -> [String: Color] {
        let regions = viewModel.currentPuzzle.regions
        var adjacency = [String: Set<String>]()

        for row in 0..<regions.count {
            for column in 0..<regions[row].count {
                let current = regions[row][column]
                adjacency[current, default: []] = adjacency[current, default: []]

                if row + 1 < regions.count {
                    let below = regions[row + 1][column]
                    if below != current {
                        adjacency[current, default: []].insert(below)
                        adjacency[below, default: []].insert(current)
                    }
                }

                if column + 1 < regions[row].count {
                    let trailing = regions[row][column + 1]
                    if trailing != current {
                        adjacency[current, default: []].insert(trailing)
                        adjacency[trailing, default: []].insert(current)
                    }
                }
            }
        }

        let orderedRegions = adjacency.keys.sorted {
            let lhsDegree = adjacency[$0]?.count ?? 0
            let rhsDegree = adjacency[$1]?.count ?? 0
            if lhsDegree != rhsDegree {
                return lhsDegree > rhsDegree
            }
            return $0 < $1
        }

        let uniqueColors = generatedUniqueRegionColors(count: orderedRegions.count)
        var assignments = [String: Int]()
        var remainingIndices = Set(uniqueColors.indices)

        for region in orderedRegions {
            let usedNeighborIndices = Set((adjacency[region] ?? []).compactMap { neighbor in
                assignments[neighbor]
            })

            let selectedIndex = remainingIndices
                .sorted()
                .first { !usedNeighborIndices.contains($0) } ?? remainingIndices.sorted().first ?? 0

            assignments[region] = selectedIndex
            remainingIndices.remove(selectedIndex)
        }

        return assignments.reduce(into: [String: Color]()) { partialResult, entry in
            partialResult[entry.key] = uniqueColors[entry.value]
        }
    }

    private func generatedUniqueRegionColors(count: Int) -> [Color] {
        guard count > 0 else { return [] }

        let hueOffset = 0.08
        let saturation = colorScheme == .dark ? 0.58 : 0.34
        let brightness = colorScheme == .dark ? 0.66 : 0.96
        let opacity = colorScheme == .dark ? 0.88 : 1.0

        return (0..<count).map { index in
            let hue = (Double(index) / Double(count) + hueOffset).truncatingRemainder(dividingBy: 1)
            return Color(hue: hue, saturation: saturation, brightness: brightness, opacity: opacity)
        }
    }

    private func position(for location: CGPoint, boardSide: CGFloat, size: Int) -> CellPosition? {
        guard boardSide > 0, size > 0 else { return nil }
        let cellSize = boardSide / CGFloat(size)
        let column = min(max(Int(location.x / cellSize), 0), size - 1)
        let row = min(max(Int(location.y / cellSize), 0), size - 1)
        return CellPosition(row: row, column: column)
    }

    private var palette: AppPalette {
        AppPalette(colorScheme: colorScheme)
    }
}

private struct AppPalette {
    let backgroundTop: Color
    let backgroundBottom: Color
    let headerCard: Color
    let headerBorder: Color
    let headerText: Color
    let headerAccent: Color
    let headerSubtext: Color
    let modeBadge: Color
    let cardBackground: Color
    let bodySubtext: Color
    let cellBackground: Color
    let gridLine: Color
    let regionBorder: Color
    let outerBorder: Color
    let regionPalette: [Color]
    let star: Color
    let mark: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            backgroundTop = Color(red: 0.14, green: 0.16, blue: 0.19)
            backgroundBottom = Color(red: 0.09, green: 0.10, blue: 0.12)
            headerCard = Color.white.opacity(0.08)
            headerBorder = Color.white.opacity(0.12)
            headerText = Color.white.opacity(0.96)
            headerAccent = Color(red: 0.80, green: 0.72, blue: 0.40)
            headerSubtext = Color.white.opacity(0.72)
            modeBadge = Color.white.opacity(0.10)
            cardBackground = Color.white.opacity(0.08)
            bodySubtext = Color.white.opacity(0.70)
            cellBackground = Color.white.opacity(0.03)
            gridLine = Color.white.opacity(0.16)
            regionBorder = Color.white.opacity(0.92)
            outerBorder = Color.white.opacity(0.28)
            regionPalette = [
                Color(red: 0.24, green: 0.33, blue: 0.44),
                Color(red: 0.37, green: 0.25, blue: 0.43),
                Color(red: 0.20, green: 0.38, blue: 0.31),
                Color(red: 0.43, green: 0.29, blue: 0.23),
                Color(red: 0.25, green: 0.30, blue: 0.48),
                Color(red: 0.44, green: 0.36, blue: 0.20),
                Color(red: 0.19, green: 0.39, blue: 0.44),
                Color(red: 0.43, green: 0.22, blue: 0.31)
            ].map { $0.opacity(0.88) }
            star = Color(red: 0.98, green: 0.82, blue: 0.22)
            mark = Color.white.opacity(0.75)
        } else {
            backgroundTop = Color(red: 0.94, green: 0.96, blue: 0.99)
            backgroundBottom = Color(red: 0.86, green: 0.90, blue: 0.96)
            headerCard = Color.white.opacity(0.82)
            headerBorder = Color.black.opacity(0.06)
            headerText = Color(red: 0.10, green: 0.13, blue: 0.18)
            headerAccent = Color(red: 0.40, green: 0.28, blue: 0.04)
            headerSubtext = Color.black.opacity(0.60)
            modeBadge = Color.black.opacity(0.06)
            cardBackground = Color.white.opacity(0.84)
            bodySubtext = Color.black.opacity(0.62)
            cellBackground = Color.white.opacity(0.72)
            gridLine = Color.black.opacity(0.10)
            regionBorder = Color.black.opacity(0.72)
            outerBorder = Color.black.opacity(0.12)
            regionPalette = [
                Color(red: 0.89, green: 0.93, blue: 0.98),
                Color(red: 0.94, green: 0.90, blue: 0.98),
                Color(red: 0.89, green: 0.96, blue: 0.92),
                Color(red: 0.98, green: 0.92, blue: 0.89),
                Color(red: 0.91, green: 0.92, blue: 0.99),
                Color(red: 0.98, green: 0.95, blue: 0.88),
                Color(red: 0.89, green: 0.96, blue: 0.97),
                Color(red: 0.97, green: 0.90, blue: 0.93)
            ]
            star = Color(red: 0.88, green: 0.67, blue: 0.10)
            mark = Color.black.opacity(0.55)
        }
    }
}

private struct RegionEdgesShape: Shape {
    let top: Bool
    let bottom: Bool
    let leading: Bool
    let trailing: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if top {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        if bottom {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        if leading {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        if trailing {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        return path
    }
}

private struct SolvedOverlay: View {
    let durationText: String
    let onNewGame: () -> Void
    let onHome: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color(red: 0.98, green: 0.82, blue: 0.22))

            Text("Puzzle solved")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            if !durationText.isEmpty {
                Text("Finished in \(durationText)")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.78))
            }

            HStack(spacing: 10) {
                Button("Home", action: onHome)
                    .buttonStyle(SolvedActionButtonStyle())

                Button("New Game", action: onNewGame)
                    .buttonStyle(SolvedActionButtonStyle(prominent: true))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }
}

private struct SolvedActionButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Color.black.opacity(0.88) : Color.white)
            .frame(minWidth: 136)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(prominent ? Color.white.opacity(configuration.isPressed ? 0.88 : 0.96) : Color.white.opacity(configuration.isPressed ? 0.14 : 0.10))
            )
            .glassEffect(.regular.interactive(), in: Capsule())
    }
}

private struct HomeSectionCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(palette.headerSubtext)

            content
        }
        .padding(16)
        .background(palette.headerCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(palette.headerBorder, lineWidth: 1)
        }
    }

    private var palette: AppPalette {
        AppPalette(colorScheme: colorScheme)
    }
}

private struct HomeIconButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(palette.headerText)
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var palette: AppPalette {
        AppPalette(colorScheme: colorScheme)
    }
}

private struct SelectionChipButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text(starSymbols)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.star)

                    Text(title)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark" : "circle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isSelected ? selectionBadgeForeground : palette.headerSubtext)
                    .frame(width: 22, height: 22)
                    .background(selectionBadgeBackground, in: Circle())
            }

            if let subtitle {
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.bodySubtext)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: subtitle == nil ? 64 : 74)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(palette.headerText)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(selectionFill)
        )
    }

    private var palette: AppPalette {
        AppPalette(colorScheme: colorScheme)
    }

    private var selectionFill: Color {
        if !isSelected {
            return .clear
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.06)
    }
    private var selectionBadgeBackground: Color {
        isSelected ? palette.star : Color.clear
    }

    private var selectionBadgeForeground: Color {
        colorScheme == .dark ? Color.black.opacity(0.86) : Color.white
    }

    private var starSymbols: String {
        let count = Int(title.prefix(1)) ?? 1
        return String(repeating: "★", count: max(count, 1))
    }
}

private struct CompactSelectionChipButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark" : "circle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isSelected ? selectionBadgeForeground : palette.headerSubtext)
                    .frame(width: 22, height: 22)
                    .background(selectionBadgeBackground, in: Circle())
            }

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(palette.bodySubtext)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 68)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .foregroundStyle(palette.headerText)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(selectionFill)
        )
    }

    private var palette: AppPalette {
        AppPalette(colorScheme: colorScheme)
    }

    private var selectionFill: Color {
        if !isSelected {
            return .clear
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.06)
    }

    private var selectionBadgeBackground: Color {
        isSelected ? palette.star : Color.clear
    }

    private var selectionBadgeForeground: Color {
        colorScheme == .dark ? Color.black.opacity(0.86) : Color.white
    }
}

private struct ChallengeFeatureRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.star)
                .frame(width: 22)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(palette.headerText)
        }
    }

    private var palette: AppPalette {
        AppPalette(colorScheme: colorScheme)
    }
}

private struct ChallengePill: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.headerText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: Capsule())
    }

    private var palette: AppPalette {
        AppPalette(colorScheme: colorScheme)
    }
}

private struct DifficultyCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let solvedCount: Int
    let totalCount: Int
    let progress: Double
    let isSelected: Bool
    let isEnabled: Bool
    let unavailableLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    if solvedCount > 0 {
                        Text("\(solvedCount)/\(totalCount)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(cardMetaColor)
                    }
                }

                if let unavailableLabel, !isEnabled {
                    Text(unavailableLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(cardMetaColor)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(trackColor)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        progressLeadingColor,
                                        progressTrailingColor
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(proxy.size.width * progress, progress > 0 ? 8 : 0))
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .foregroundStyle(cardTitleColor)
            .opacity(isEnabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(selectedFillColor)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    borderColor,
                    lineWidth: 1
                )
        }
        .disabled(!isEnabled)
    }

    private var palette: AppPalette {
        AppPalette(colorScheme: colorScheme)
    }

    private var cardTitleColor: Color {
        palette.headerText
    }

    private var cardMetaColor: Color {
        colorScheme == .dark ? Color.white.opacity(isEnabled ? 0.62 : 0.38) : Color.black.opacity(isEnabled ? 0.52 : 0.30)
    }

    private var selectedFillColor: Color {
        colorScheme == .dark
            ? (isSelected && isEnabled ? Color.white.opacity(0.18) : Color.clear)
            : (isSelected && isEnabled ? Color.black.opacity(0.08) : Color.clear)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? (isSelected && isEnabled ? Color.white.opacity(0.75) : Color.white.opacity(0.18))
            : (isSelected && isEnabled ? Color.black.opacity(0.30) : Color.black.opacity(0.10))
    }

    private var trackColor: Color {
        colorScheme == .dark ? Color.white.opacity(isEnabled ? 0.10 : 0.05) : Color.black.opacity(isEnabled ? 0.08 : 0.04)
    }

    private var progressLeadingColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(isSelected ? 0.90 : 0.70)
            : Color.black.opacity(isSelected ? 0.58 : 0.38)
    }

    private var progressTrailingColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(isSelected ? 0.55 : 0.36)
            : Color.black.opacity(isSelected ? 0.34 : 0.22)
    }
}

private struct ActionIconButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(AppPalette(colorScheme: colorScheme).headerText)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive())
    }
}
