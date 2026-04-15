#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const BOARD_SIZE = 6;
const DEFAULT_COUNTS = { easy: 10, medium: 10, hard: 10 };
const REGION_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const SEED_PUZZLES = [
  {
    name: "Morning Drift",
    regions: [
      ["A", "A", "C", "C", "B", "B"],
      ["C", "C", "C", "C", "B", "B"],
      ["C", "C", "C", "C", "C", "D"],
      ["C", "C", "C", "C", "C", "D"],
      ["E", "F", "F", "C", "F", "D"],
      ["E", "F", "F", "F", "F", "D"],
    ],
    solution: [
      { row: 0, column: 1 },
      { row: 1, column: 4 },
      { row: 2, column: 2 },
      { row: 3, column: 5 },
      { row: 4, column: 0 },
      { row: 5, column: 3 },
    ],
  },
  {
    name: "Quiet Orbit",
    regions: [
      ["B", "B", "C", "A", "A", "A"],
      ["B", "B", "C", "A", "E", "A"],
      ["D", "C", "C", "C", "E", "E"],
      ["D", "C", "F", "E", "E", "E"],
      ["F", "F", "F", "F", "F", "E"],
      ["F", "F", "F", "F", "F", "F"],
    ],
    solution: [
      { row: 0, column: 4 },
      { row: 1, column: 1 },
      { row: 2, column: 3 },
      { row: 3, column: 0 },
      { row: 4, column: 5 },
      { row: 5, column: 2 },
    ],
  },
];

function parseArgs(argv) {
  const options = {
    output: path.resolve(__dirname, "../StarBattleLite/Resources/generated_puzzles.json"),
    counts: { ...DEFAULT_COUNTS },
    maxAttempts: 200000,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--output") {
      options.output = path.resolve(process.cwd(), argv[index + 1]);
      index += 1;
    } else if (arg === "--easy") {
      options.counts.easy = Number(argv[index + 1]);
      index += 1;
    } else if (arg === "--medium") {
      options.counts.medium = Number(argv[index + 1]);
      index += 1;
    } else if (arg === "--hard") {
      options.counts.hard = Number(argv[index + 1]);
      index += 1;
    } else if (arg === "--max-attempts") {
      options.maxAttempts = Number(argv[index + 1]);
      index += 1;
    }
  }

  return options;
}

function shuffle(values) {
  const copy = values.slice();
  for (let i = copy.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

function key(position) {
  return `${position.row},${position.column}`;
}

function buildNeighborMap(size) {
  const map = new Map();
  for (let row = 0; row < size; row += 1) {
    for (let column = 0; column < size; column += 1) {
      const neighbors = [];
      for (let rowOffset = -1; rowOffset <= 1; rowOffset += 1) {
        for (let columnOffset = -1; columnOffset <= 1; columnOffset += 1) {
          if (rowOffset === 0 && columnOffset === 0) {
            continue;
          }
          const nextRow = row + rowOffset;
          const nextColumn = column + columnOffset;
          if (nextRow >= 0 && nextRow < size && nextColumn >= 0 && nextColumn < size) {
            neighbors.push({ row: nextRow, column: nextColumn });
          }
        }
      }
      map.set(key({ row, column }), neighbors);
    }
  }
  return map;
}

const TOUCHING_NEIGHBORS = buildNeighborMap(BOARD_SIZE);

function generateSolution(size) {
  const columns = new Set();
  const chosen = [];

  function search(row) {
    if (row === size) {
      return true;
    }

    for (const column of shuffle([...Array(size).keys()])) {
      if (columns.has(column)) {
        continue;
      }

      const candidate = { row, column };
      let touches = false;
      for (const existing of chosen) {
        if (
          Math.abs(existing.row - candidate.row) <= 1 &&
          Math.abs(existing.column - candidate.column) <= 1
        ) {
          touches = true;
          break;
        }
      }
      if (touches) {
        continue;
      }

      columns.add(column);
      chosen.push(candidate);
      if (search(row + 1)) {
        return true;
      }
      chosen.pop();
      columns.delete(column);
    }

    return false;
  }

  return search(0) ? chosen.slice() : null;
}

function orthogonalNeighbors(position, size) {
  const results = [];
  const offsets = [
    [-1, 0],
    [1, 0],
    [0, -1],
    [0, 1],
  ];
  for (const [rowOffset, columnOffset] of offsets) {
    const row = position.row + rowOffset;
    const column = position.column + columnOffset;
    if (row >= 0 && row < size && column >= 0 && column < size) {
      results.push({ row, column });
    }
  }
  return results;
}

function generateRegions(solution, size) {
  const board = Array.from({ length: size }, () => Array(size).fill(-1));
  const starByCell = new Map(solution.map((position, index) => [key(position), index]));
  const cellsByRegion = solution.map((position) => [position]);

  solution.forEach((position, index) => {
    board[position.row][position.column] = index;
  });

  let assignedCount = solution.length;
  const totalCells = size * size;

  while (assignedCount < totalCells) {
    const candidateMoves = [];

    for (let region = 0; region < solution.length; region += 1) {
      const seen = new Set();
      for (const cell of cellsByRegion[region]) {
        for (const neighbor of orthogonalNeighbors(cell, size)) {
          if (board[neighbor.row][neighbor.column] !== -1) {
            continue;
          }
          const neighborKey = key(neighbor);
          if (seen.has(neighborKey)) {
            continue;
          }
          seen.add(neighborKey);
          const star = solution[region];
          const distance = Math.abs(star.row - neighbor.row) + Math.abs(star.column - neighbor.column);
          const penalty = star.row === neighbor.row || star.column === neighbor.column ? 0.3 : 0;
          candidateMoves.push({
            region,
            cell: neighbor,
            score: distance + penalty + Math.random() * 0.6,
          });
        }
      }
    }

    if (candidateMoves.length === 0) {
      return null;
    }

    candidateMoves.sort((left, right) => left.score - right.score);
    const selected = candidateMoves[0];
    board[selected.cell.row][selected.cell.column] = selected.region;
    cellsByRegion[selected.region].push(selected.cell);
    assignedCount += 1;
  }

  for (let region = 0; region < size; region += 1) {
    const cells = cellsByRegion[region];
    if (!isConnected(cells, size)) {
      return null;
    }
    const starCount = cells.filter((cell) => starByCell.has(key(cell))).length;
    if (starCount !== 1) {
      return null;
    }
  }

  return board.map((row) => row.map((region) => REGION_LETTERS[region]));
}

function isConnected(cells, size) {
  if (cells.length === 0) {
    return false;
  }
  const wanted = new Set(cells.map(key));
  const queue = [cells[0]];
  const seen = new Set([key(cells[0])]);

  while (queue.length > 0) {
    const current = queue.shift();
    for (const neighbor of orthogonalNeighbors(current, size)) {
      const neighborKey = key(neighbor);
      if (!wanted.has(neighborKey) || seen.has(neighborKey)) {
        continue;
      }
      seen.add(neighborKey);
      queue.push(neighbor);
    }
  }

  return seen.size === wanted.size;
}

function buildRegionCells(regions) {
  const map = new Map();
  for (let row = 0; row < regions.length; row += 1) {
    for (let column = 0; column < regions.length; column += 1) {
      const region = regions[row][column];
      if (!map.has(region)) {
        map.set(region, []);
      }
      map.get(region).push({ row, column });
    }
  }
  return map;
}

function cloneRegions(regions) {
  return regions.map((row) => row.slice());
}

function transformPuzzle(seed, transform) {
  const size = seed.regions.length;
  const nextRegions = Array.from({ length: size }, () => Array(size).fill(""));
  const nextSolution = [];

  function mapPosition(position) {
    const row = position.row;
    const column = position.column;
    switch (transform) {
      case "identity":
        return { row, column };
      case "rotate90":
        return { row: column, column: size - 1 - row };
      case "rotate180":
        return { row: size - 1 - row, column: size - 1 - column };
      case "rotate270":
        return { row: size - 1 - column, column: row };
      case "flipH":
        return { row, column: size - 1 - column };
      case "flipV":
        return { row: size - 1 - row, column };
      case "transpose":
        return { row: column, column: row };
      case "antiTranspose":
        return { row: size - 1 - column, column: size - 1 - row };
      default:
        return { row, column };
    }
  }

  for (let row = 0; row < size; row += 1) {
    for (let column = 0; column < size; column += 1) {
      const mapped = mapPosition({ row, column });
      nextRegions[mapped.row][mapped.column] = seed.regions[row][column];
    }
  }

  for (const star of seed.solution) {
    nextSolution.push(mapPosition(star));
  }

  return { regions: nextRegions, solution: nextSolution };
}

function singleMutation(regions, starKeys) {
  const size = regions.length;
  const moves = [];

  for (let row = 0; row < size; row += 1) {
    for (let column = 0; column < size; column += 1) {
      const cell = { row, column };
      if (starKeys.has(key(cell))) {
        continue;
      }
      const sourceRegion = regions[row][column];
      for (const neighbor of orthogonalNeighbors(cell, size)) {
        const targetRegion = regions[neighbor.row][neighbor.column];
        if (targetRegion !== sourceRegion) {
          moves.push({ cell, sourceRegion, targetRegion });
        }
      }
    }
  }

  for (const move of shuffle(moves)) {
    const next = cloneRegions(regions);
    next[move.cell.row][move.cell.column] = move.targetRegion;

    const cells = buildRegionCells(next);
    if (cells.size !== size) {
      continue;
    }

    let valid = true;
    for (const regionCells of cells.values()) {
      if (!isConnected(regionCells, size)) {
        valid = false;
        break;
      }
    }

    if (!valid) {
      continue;
    }

    for (const [regionId, regionCells] of cells.entries()) {
      const starCount = regionCells.filter((position) => starKeys.has(key(position))).length;
      if (starCount !== 1) {
        valid = false;
        break;
      }
      if (!REGION_LETTERS.includes(regionId)) {
        valid = false;
        break;
      }
    }

    if (valid) {
      return {
        regions: next,
      };
    }
  }

  return null;
}

function mutatePuzzle(seed) {
  let regions = cloneRegions(seed.regions);
  const starKeys = new Set(seed.solution.map(key));
  const steps = 1 + Math.floor(Math.random() * 3);

  for (let index = 0; index < steps; index += 1) {
    const next = singleMutation(regions, starKeys);
    if (!next) {
      break;
    }
    regions = next.regions;
  }

  if (puzzleSignature(regions) === puzzleSignature(seed.regions)) {
    return null;
  }

  return {
    name: seed.name,
    regions,
    solution: seed.solution.slice(),
  };
}

function analyzePuzzle(regions) {
  const size = regions.length;
  const regionCells = buildRegionCells(regions);
  const regionIds = [...regionCells.keys()];
  const rowUsage = Array(size).fill(false);
  const columnUsage = Array(size).fill(false);
  const blocked = Array.from({ length: size }, () => Array(size).fill(false));
  const placements = [];
  let solutionCount = 0;
  let branchScore = 0;
  let forcedChoices = 0;

  function availableCells(regionId) {
    const cells = regionCells.get(regionId).filter((cell) => {
      if (rowUsage[cell.row] || columnUsage[cell.column] || blocked[cell.row][cell.column]) {
        return false;
      }
      for (const placed of placements) {
        if (
          Math.abs(placed.row - cell.row) <= 1 &&
          Math.abs(placed.column - cell.column) <= 1
        ) {
          return false;
        }
      }
      return true;
    });
    return cells;
  }

  function search() {
    if (solutionCount > 1) {
      return;
    }

    const remaining = regionIds
      .filter((regionId) => !placements.some((placed) => regions[placed.row][placed.column] === regionId))
      .map((regionId) => ({ regionId, cells: availableCells(regionId) }));

    if (remaining.length === 0) {
      solutionCount += 1;
      return;
    }

    remaining.sort((left, right) => left.cells.length - right.cells.length);
    const next = remaining[0];
    if (next.cells.length === 0) {
      return;
    }

    if (next.cells.length === 1) {
      forcedChoices += 1;
    } else {
      branchScore += next.cells.length - 1;
    }

    for (const cell of shuffle(next.cells)) {
      placements.push(cell);
      rowUsage[cell.row] = true;
      columnUsage[cell.column] = true;

      const newlyBlocked = [];
      for (const neighbor of TOUCHING_NEIGHBORS.get(key(cell))) {
        if (!blocked[neighbor.row][neighbor.column]) {
          blocked[neighbor.row][neighbor.column] = true;
          newlyBlocked.push(neighbor);
        }
      }
      if (!blocked[cell.row][cell.column]) {
        blocked[cell.row][cell.column] = true;
        newlyBlocked.push(cell);
      }

      search();

      for (const neighbor of newlyBlocked) {
        blocked[neighbor.row][neighbor.column] = false;
      }
      rowUsage[cell.row] = false;
      columnUsage[cell.column] = false;
      placements.pop();
      if (solutionCount > 1) {
        return;
      }
    }
  }

  search();

  return { solutionCount, branchScore, forcedChoices };
}

function classifyDifficulty(analysis) {
  const score = analysis.branchScore - analysis.forcedChoices * 0.35;
  if (score <= 3.25) {
    return { tier: "easy", score };
  }
  if (score <= 6.75) {
    return { tier: "medium", score };
  }
  return { tier: "hard", score };
}

function puzzleSignature(regions) {
  return regions.map((row) => row.join("")).join("|");
}

function chooseName(tier, number) {
  const prefixes = {
    easy: "Soft",
    medium: "Quiet",
    hard: "Deep",
  };
  const nouns = [
    "Orbit",
    "Nova",
    "Drift",
    "Signal",
    "Arc",
    "Vector",
    "Skylight",
    "Comet",
    "Halo",
    "Lattice",
  ];
  return `${prefixes[tier]} ${nouns[number % nouns.length]} ${number + 1}`;
}

function generatePuzzleBank({ counts, maxAttempts }) {
  const bank = { easy: [], medium: [], hard: [] };
  const seen = new Set();
  let attempts = 0;
  const transforms = [
    "identity",
    "rotate90",
    "rotate180",
    "rotate270",
    "flipH",
    "flipV",
    "transpose",
    "antiTranspose",
  ];
  const seedQueue = [];

  for (const seed of SEED_PUZZLES) {
    for (const transform of transforms) {
      const transformed = transformPuzzle(seed, transform);
      seedQueue.push({
        name: seed.name,
        regions: transformed.regions,
        solution: transformed.solution,
      });
    }
  }

  while (
    attempts < maxAttempts &&
    (bank.easy.length < counts.easy || bank.medium.length < counts.medium || bank.hard.length < counts.hard)
  ) {
    attempts += 1;
    const seed = seedQueue.length > 0 ? seedQueue.shift() : null;

    if (!seed || !seed.regions || !seed.solution) {
      continue;
    }

    const candidate = mutatePuzzle(seed) ?? seed;
    const regions = candidate.regions;
    const solution = candidate.solution;

    const signature = puzzleSignature(regions);
    if (seen.has(signature)) {
      continue;
    }

    const analysis = analyzePuzzle(regions);
    if (analysis.solutionCount !== 1) {
      continue;
    }

    const difficulty = classifyDifficulty(analysis);
    if (bank[difficulty.tier].length >= counts[difficulty.tier]) {
      continue;
    }

    seen.add(signature);
    seedQueue.push(candidate);
    bank[difficulty.tier].push({
      id: `${difficulty.tier}-${String(bank[difficulty.tier].length + 1).padStart(3, "0")}`,
      name: chooseName(difficulty.tier, bank[difficulty.tier].length),
      size: BOARD_SIZE,
      starsPerUnit: 1,
      difficulty: difficulty.tier,
      regions,
      solution,
      metrics: {
        branchScore: Number(analysis.branchScore.toFixed(2)),
        forcedChoices: analysis.forcedChoices,
        ratingScore: Number(difficulty.score.toFixed(2)),
      },
    });
  }

  return { bank, attempts };
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const { bank, attempts } = generatePuzzleBank(options);
  const payload = {
    generatedAt: new Date().toISOString(),
    boardSize: BOARD_SIZE,
    starsPerUnit: 1,
    attempts,
    counts: {
      easy: bank.easy.length,
      medium: bank.medium.length,
      hard: bank.hard.length,
    },
    puzzles: bank,
  };

  fs.mkdirSync(path.dirname(options.output), { recursive: true });
  fs.writeFileSync(options.output, JSON.stringify(payload, null, 2));

  const bytes = fs.statSync(options.output).size;
  console.log(`Generated puzzles after ${attempts} attempts.`);
  console.log(`Easy: ${bank.easy.length}, Medium: ${bank.medium.length}, Hard: ${bank.hard.length}`);
  console.log(`Output: ${options.output}`);
  console.log(`Size: ${bytes} bytes (${(bytes / 1024).toFixed(2)} KB)`);

  if (
    bank.easy.length < options.counts.easy ||
    bank.medium.length < options.counts.medium ||
    bank.hard.length < options.counts.hard
  ) {
    process.exitCode = 2;
  }
}

if (require.main === module) {
  main();
}

module.exports = {
  analyzePuzzle,
  classifyDifficulty,
  generatePuzzleBank,
  generateRegions,
  generateSolution,
};
