import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = GameViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSolvedCelebration = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 12) {
                    header
                    puzzleCard(availableWidth: geometry.size.width)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .background(
                    LinearGradient(
                        colors: [palette.backgroundTop, palette.backgroundBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
            }
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Star Battle Lite")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.headerText)
                Spacer()
                Text("1 star")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(palette.modeBadge, in: Capsule())
                    .foregroundStyle(palette.headerText)
            }

            Text("Tap once for X, tap twice for a star. Drag to sweep crosses.")
                .font(.footnote)
                .foregroundStyle(palette.headerSubtext)

            HStack {
                Label("Auto X", systemImage: viewModel.autoMarkEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.headerText)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.autoMarkEnabled },
                    set: { viewModel.setAutoMarkEnabled($0) }
                ))
                .labelsHidden()
                .tint(.orange)
            }
        }
        .padding(16)
        .background(palette.headerCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(palette.headerBorder, lineWidth: 1)
        )
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
                SolvedOverlay(durationText: viewModel.lastSolvedDurationText)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onChange(of: viewModel.status) { _, newValue in
            guard newValue == "Solved" else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                showSolvedCelebration = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeOut(duration: 0.25)) {
                    showSolvedCelebration = false
                }
            }
        }
    }

    private var palette: AppPalette {
        AppPalette(colorScheme: colorScheme)
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
            backgroundBottom = Color(red: 0.08, green: 0.09, blue: 0.11)
            headerCard = Color.white.opacity(0.08)
            headerBorder = Color.white.opacity(0.12)
            headerText = .white
            headerSubtext = Color.white.opacity(0.74)
            modeBadge = Color.white.opacity(0.08)
            cardBackground = Color(red: 0.15, green: 0.17, blue: 0.20)
            bodySubtext = Color.white.opacity(0.72)
            cellBackground = Color(red: 0.10, green: 0.11, blue: 0.13)
            gridLine = Color.white.opacity(0.12)
            regionBorder = Color.white.opacity(0.72)
            outerBorder = Color.white.opacity(0.18)
            star = Color.yellow.opacity(0.95)
            mark = Color.white.opacity(0.72)
        } else {
            backgroundTop = Color(red: 0.93, green: 0.94, blue: 0.97)
            backgroundBottom = Color(red: 0.84, green: 0.87, blue: 0.91)
            headerCard = Color.white.opacity(0.68)
            headerBorder = Color.black.opacity(0.08)
            headerText = Color.black.opacity(0.9)
            headerSubtext = Color.black.opacity(0.66)
            modeBadge = Color.black.opacity(0.06)
            cardBackground = Color(red: 0.97, green: 0.97, blue: 0.98)
            bodySubtext = Color.black.opacity(0.62)
            cellBackground = .white
            gridLine = Color.black.opacity(0.12)
            regionBorder = Color.black.opacity(0.62)
            outerBorder = Color.black.opacity(0.22)
            star = Color(red: 0.62, green: 0.25, blue: 0.13)
            mark = Color.black.opacity(0.55)
        }
    }
}

private struct SolvedOverlay: View {
    let durationText: String

    var body: some View {
        VStack(spacing: 8) {
            Text("★")
                .font(.system(size: 44))
            Text("Puzzle Solved")
                .font(.headline.weight(.bold))
            Text(durationText.isEmpty ? "Nice work" : "Finished in \(durationText)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
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
