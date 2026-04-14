const GAME_CONFIG = {
  starsPerUnit: 1,
  boardSize: 6,
};

const PUZZLES = [
  {
    name: "Morning Drift",
    size: 6,
    regions: [
      ["A", "A", "A", "B", "B", "B"],
      ["A", "A", "C", "B", "B", "B"],
      ["E", "C", "C", "C", "B", "D"],
      ["E", "E", "C", "F", "D", "D"],
      ["E", "E", "F", "F", "D", "D"],
      ["E", "F", "F", "F", "F", "D"],
    ],
    solution: [
      [0, 1],
      [1, 4],
      [2, 2],
      [3, 5],
      [4, 0],
      [5, 3],
    ],
  },
  {
    name: "Quiet Orbit",
    size: 6,
    regions: [
      ["A", "A", "A", "B", "C", "C"],
      ["A", "A", "B", "B", "C", "C"],
      ["D", "A", "B", "B", "E", "E"],
      ["D", "D", "D", "E", "E", "E"],
      ["D", "F", "F", "F", "E", "E"],
      ["D", "F", "F", "F", "F", "E"],
    ],
    solution: [
      [0, 4],
      [1, 1],
      [2, 3],
      [3, 0],
      [4, 5],
      [5, 2],
    ],
  },
];

const boardElement = document.getElementById("board");
const messageElement = document.getElementById("message");
const modeLabel = document.getElementById("modeLabel");
const puzzleName = document.getElementById("puzzleName");
const statusPill = document.getElementById("statusPill");
const starCount = document.getElementById("starCount");
const targetCount = document.getElementById("targetCount");
const markCount = document.getElementById("markCount");
const markModeButton = document.getElementById("markModeButton");
const resetButton = document.getElementById("resetButton");
const checkButton = document.getElementById("checkButton");
const newGameButton = document.getElementById("newGameButton");

let currentPuzzleIndex = 0;
let currentPuzzle = null;
let boardState = [];
let inputMode = "star";

function buildEmptyBoard(size) {
  return Array.from({ length: size }, () => Array(size).fill("empty"));
}

function loadPuzzle(index) {
  currentPuzzleIndex = index % PUZZLES.length;
  currentPuzzle = PUZZLES[currentPuzzleIndex];
  boardState = buildEmptyBoard(currentPuzzle.size);
  GAME_CONFIG.boardSize = currentPuzzle.size;

  puzzleName.textContent = currentPuzzle.name;
  modeLabel.textContent = `${GAME_CONFIG.starsPerUnit} star per row/column/region`;
  targetCount.textContent = currentPuzzle.size * GAME_CONFIG.starsPerUnit;
  statusPill.textContent = "In progress";
  messageElement.textContent =
    "Tap cells to place stars. Switch mode to add X marks for notes.";

  renderBoard();
  updateStats();
}

function renderBoard() {
  const { size, regions } = currentPuzzle;
  boardElement.innerHTML = "";
  boardElement.style.gridTemplateColumns = `repeat(${size}, 1fr)`;
  boardElement.style.gridTemplateRows = `repeat(${size}, 1fr)`;

  regions.forEach((row, rowIndex) => {
    row.forEach((regionId, columnIndex) => {
      const cell = document.createElement("button");
      cell.type = "button";
      cell.className = `cell ${getRegionClass(regionId)}`;
      cell.dataset.row = String(rowIndex);
      cell.dataset.column = String(columnIndex);
      cell.dataset.state = boardState[rowIndex][columnIndex];
      cell.setAttribute("role", "gridcell");
      cell.setAttribute("aria-label", `Row ${rowIndex + 1}, column ${columnIndex + 1}`);
      cell.addEventListener("click", handleCellClick);
      boardElement.appendChild(cell);
    });
  });
}

function getRegionClass(regionId) {
  const paletteIndex = regionId.charCodeAt(0) % 5;
  return ["region-a", "region-b", "region-c", "region-d", "region-e"][paletteIndex];
}

function handleCellClick(event) {
  const button = event.currentTarget;
  const row = Number(button.dataset.row);
  const column = Number(button.dataset.column);
  const currentState = boardState[row][column];

  if (inputMode === "star") {
    boardState[row][column] = currentState === "star" ? "empty" : "star";
  } else {
    boardState[row][column] = currentState === "marked" ? "empty" : "marked";
  }

  if (inputMode === "star" && currentState === "marked") {
    boardState[row][column] = "star";
  }

  if (inputMode === "mark" && currentState === "star") {
    boardState[row][column] = "marked";
  }

  syncBoardState();
  clearValidationHighlights();
  updateStats();
  evaluateSolvedState();
}

function syncBoardState() {
  for (const cell of boardElement.children) {
    const row = Number(cell.dataset.row);
    const column = Number(cell.dataset.column);
    cell.dataset.state = boardState[row][column];
  }
}

function toggleInputMode() {
  inputMode = inputMode === "star" ? "mark" : "star";
  markModeButton.textContent = `Mode: ${inputMode === "star" ? "Star" : "Mark"}`;
}

function resetBoard() {
  boardState = buildEmptyBoard(currentPuzzle.size);
  syncBoardState();
  clearValidationHighlights();
  updateStats();
  statusPill.textContent = "In progress";
  messageElement.textContent = "Board cleared. Ready for another attempt.";
}

function getStarPositions() {
  const positions = [];

  boardState.forEach((row, rowIndex) => {
    row.forEach((cellState, columnIndex) => {
      if (cellState === "star") {
        positions.push([rowIndex, columnIndex]);
      }
    });
  });

  return positions;
}

function getValidation() {
  const starPositions = getStarPositions();
  const invalidCells = new Set();
  const rowCounts = Array(currentPuzzle.size).fill(0);
  const columnCounts = Array(currentPuzzle.size).fill(0);
  const regionCounts = new Map();

  starPositions.forEach(([row, column]) => {
    rowCounts[row] += 1;
    columnCounts[column] += 1;

    const regionKey = currentPuzzle.regions[row][column];
    regionCounts.set(regionKey, (regionCounts.get(regionKey) || 0) + 1);
  });

  starPositions.forEach(([row, column], index) => {
    if (
      rowCounts[row] > GAME_CONFIG.starsPerUnit ||
      columnCounts[column] > GAME_CONFIG.starsPerUnit ||
      (regionCounts.get(currentPuzzle.regions[row][column]) || 0) > GAME_CONFIG.starsPerUnit
    ) {
      invalidCells.add(`${row},${column}`);
    }

    for (let otherIndex = index + 1; otherIndex < starPositions.length; otherIndex += 1) {
      const [otherRow, otherColumn] = starPositions[otherIndex];
      const rowDistance = Math.abs(row - otherRow);
      const columnDistance = Math.abs(column - otherColumn);

      if (rowDistance <= 1 && columnDistance <= 1) {
        invalidCells.add(`${row},${column}`);
        invalidCells.add(`${otherRow},${otherColumn}`);
      }
    }
  });

  const expectedPerLine = GAME_CONFIG.starsPerUnit;
  const solved =
    invalidCells.size === 0 &&
    rowCounts.every((count) => count === expectedPerLine) &&
    columnCounts.every((count) => count === expectedPerLine) &&
    new Set(currentPuzzle.regions.flat()).size === regionCounts.size &&
    Array.from(regionCounts.values()).every((count) => count === expectedPerLine);

  return { invalidCells, solved };
}

function showValidation(invalidCells) {
  for (const cell of boardElement.children) {
    const key = `${cell.dataset.row},${cell.dataset.column}`;
    cell.classList.toggle("invalid", invalidCells.has(key));
  }
}

function clearValidationHighlights() {
  for (const cell of boardElement.children) {
    cell.classList.remove("invalid");
  }
}

function updateStats() {
  const stars = getStarPositions().length;
  const marks = boardState.flat().filter((cell) => cell === "marked").length;

  starCount.textContent = String(stars);
  markCount.textContent = String(marks);
}

function evaluateSolvedState() {
  const validation = getValidation();

  if (validation.solved) {
    statusPill.textContent = "Solved";
    showValidation(new Set());
    messageElement.textContent = "Puzzle solved. Nice work!";
  }
}

function checkProgress() {
  const { invalidCells, solved } = getValidation();
  showValidation(invalidCells);

  if (solved) {
    statusPill.textContent = "Solved";
    messageElement.textContent = "Everything checks out. Puzzle solved!";
    return;
  }

  statusPill.textContent = invalidCells.size > 0 ? "Conflicts found" : "Keep going";
  messageElement.textContent =
    invalidCells.size > 0
      ? "Highlighted stars break the rules. Adjust those placements first."
      : "No direct conflicts yet. Keep filling rows, columns, and regions.";
}

function loadNextPuzzle() {
  loadPuzzle(currentPuzzleIndex + 1);
}

markModeButton.addEventListener("click", toggleInputMode);
resetButton.addEventListener("click", resetBoard);
checkButton.addEventListener("click", checkProgress);
newGameButton.addEventListener("click", loadNextPuzzle);

loadPuzzle(0);
