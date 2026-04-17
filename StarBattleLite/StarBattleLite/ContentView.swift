import SwiftUI

private enum AppScreen {
    case home
    case game
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
            return "Classic 6x6 starter board"
        case .two:
            return "Coming soon"
        }
    }

    var isAvailable: Bool {
        self == .one
    }
}

struct ContentView: View {
    @StateObject private var viewModel = GameViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentScreen: AppScreen = .home
    @State private var selectedMode: StarMode = .one
    @State private var selectedBoardSize: PuzzleBoardSize = .six
    @State private var showSettings = false
    @State private var showSolvedCelebration = false

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

                    switch currentScreen {
                    case .home:
                        homeScreen
                    case .game:
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
                    )
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var homeScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Text("Star Battle")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.headerText)
                Text("Choose a mode and board size to start.")
                    .font(.footnote)
                    .foregroundStyle(palette.headerSubtext)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 14) {
                ForEach([StarMode.one, StarMode.two], id: \.rawValue) { mode in
                    Button {
                        guard mode.isAvailable else { return }
                        selectedMode = mode
                    } label: {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(mode.title)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(palette.headerText)
                                Text(mode.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(palette.bodySubtext)
                            }

                            Spacer()

                            Image(systemName: mode.isAvailable ? "play.fill" : "clock")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(mode.isAvailable ? palette.star : palette.bodySubtext)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(palette.headerBorder, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!mode.isAvailable)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Board Size")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.headerText)

                HStack(spacing: 10) {
                    ForEach(PuzzleBoardSize.allCases) { boardSize in
                        let count = viewModel.availableBoardCounts[boardSize, default: 0]
                        DifficultyCard(
                            title: boardSize.title,
                            isSelected: selectedBoardSize == boardSize,
                            isEnabled: count > 0 && selectedMode.isAvailable
                        ) {
                            guard count > 0 else { return }
                            selectedBoardSize = boardSize
                        }
                    }
                }
            }

            Button {
                viewModel.startNewSession(
                    boardSize: selectedBoardSize,
                    difficulty: .easy
                )
                currentScreen = .game
            } label: {
                Label("Start Game", systemImage: "play.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.headerText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive())
            .disabled(
                PuzzleLibrary.puzzleCount(for: .easy, boardSize: selectedBoardSize) == 0 ||
                !selectedMode.isAvailable
            )

            leaderboardSection

            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.headerText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive())

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
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
                currentScreen = .home
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
                        currentScreen = .home
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

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Best Times")
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.headerText)

            VStack(spacing: 10) {
                ForEach(PuzzleBoardSize.allCases) { boardSize in
                    LeaderboardRow(
                        title: boardSize.title,
                        entries: viewModel.leaderboardEntries(for: boardSize)
                    )
                }
            }
        }
    }
}

private struct SettingsSheet: View {
    @Binding var autoMarkEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Game") {
                    Toggle("Auto X", isOn: $autoMarkEnabled)
                }

                Section("How To Play") {
                    Text("Tap once for X.")
                    Text("Tap the same cell again quickly for a star.")
                    Text("Drag across the board to sweep crosses.")
                    Text("Place one star in every row, column, and region.")
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
                        .fill(palette.cellBackground)

                    if viewModel.boardState[position.row][position.column] == .star {
                        Text("★")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
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
                    .stroke(palette.regionBorder, lineWidth: 3)
                }
                .overlay {
                    if viewModel.invalidCells.contains(position) {
                        Rectangle()
                            .stroke(Color.red.opacity(0.8), lineWidth: 3)
                            .padding(1)
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
    let headerSubtext: Color
    let modeBadge: Color
    let cardBackground: Color
    let bodySubtext: Color
    let cellBackground: Color
    let gridLine: Color
    let regionBorder: Color
    let outerBorder: Color
    let star: Color
    let mark: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            backgroundTop = Color(red: 0.14, green: 0.16, blue: 0.19)
            backgroundBottom = Color(red: 0.09, green: 0.10, blue: 0.12)
            headerCard = Color.white.opacity(0.08)
            headerBorder = Color.white.opacity(0.12)
            headerText = Color.white.opacity(0.96)
            headerSubtext = Color.white.opacity(0.72)
            modeBadge = Color.white.opacity(0.10)
            cardBackground = Color.white.opacity(0.08)
            bodySubtext = Color.white.opacity(0.70)
            cellBackground = Color.white.opacity(0.03)
            gridLine = Color.white.opacity(0.10)
            regionBorder = Color.white.opacity(0.78)
            outerBorder = Color.white.opacity(0.22)
            star = Color(red: 0.98, green: 0.82, blue: 0.22)
            mark = Color.white.opacity(0.75)
        } else {
            backgroundTop = Color(red: 0.94, green: 0.96, blue: 0.99)
            backgroundBottom = Color(red: 0.86, green: 0.90, blue: 0.96)
            headerCard = Color.white.opacity(0.82)
            headerBorder = Color.black.opacity(0.06)
            headerText = Color(red: 0.10, green: 0.13, blue: 0.18)
            headerSubtext = Color.black.opacity(0.60)
            modeBadge = Color.black.opacity(0.06)
            cardBackground = Color.white.opacity(0.84)
            bodySubtext = Color.black.opacity(0.62)
            cellBackground = Color.white.opacity(0.72)
            gridLine = Color.black.opacity(0.10)
            regionBorder = Color.black.opacity(0.72)
            outerBorder = Color.black.opacity(0.12)
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
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Group {
                    if prominent {
                        Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.82 : 0.94))
                    } else {
                        Capsule().stroke(Color.white.opacity(configuration.isPressed ? 0.55 : 0.80), lineWidth: 1)
                    }
                }
            )
    }
}

private struct DifficultyCard: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected && isEnabled ? Color.white.opacity(0.18) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected && isEnabled ? Color.white.opacity(0.75) : Color.white.opacity(0.18),
                        lineWidth: 1
                    )
            }
            .opacity(isEnabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct LeaderboardRow: View {
    let title: String
    let entries: [LeaderboardEntry]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(width: 56, alignment: .leading)

            if entries.isEmpty {
                Text("No times yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    ForEach(Array(entries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                        Text("\(index + 1). \(GameViewModel.formatDuration(entry.duration))")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ActionIconButton: View {
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
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive())
    }
}
