#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const DEFAULT_COUNTS = { easy: 12, medium: 0, hard: 0 };
const DEFAULT_SIZES = [6, 8, 10];
const REGION_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const SEED_PUZZLES = [
  {
    name: "Morning Drift",
    size: 6,
    difficulty: "easy",
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
    size: 6,
    difficulty: "easy",
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
    maxAttemptsPerSize: 3000,
    sizes: DEFAULT_SIZES.slice(),
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
      options.maxAttemptsPerSize = Number(argv[index + 1]);
      index += 1;
    } else if (arg === "--sizes") {
      options.sizes = argv[index + 1]
        .split(",")
        .map((value) => Number(value.trim()))
        .filter((value) => !Number.isNaN(value));
      index += 1;
    }
  }

  return options;
}

function shuffle(values) {
  const copy = values.slice();
  for (let index = copy.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(Math.random() * (index + 1));
    [copy[index], copy[swapIndex]] = [copy[swapIndex], copy[index]];
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

function orthogonalNeighbors(position, size) {
  const results = [];
  for (const [rowOffset, columnOffset] of [
    [-1, 0],
    [1, 0],
    [0, -1],
    [0, 1],
  ]) {
    const row = position.row + rowOffset;
    const column = position.column + columnOffset;
    if (row >= 0 && row < size && column >= 0 && column < size) {
      results.push({ row, column });
    }
  }
  return results;
}

function regionLabel(index) {
  if (index < REGION_LETTERS.length) {
    return REGION_LETTERS[index];
  }
  return `R${index}`;
}

function generateSolution(size) {
  const occupiedColumns = new Set();
  const chosen = [];

  function search(row) {
    if (row === size) {
      return true;
    }

    for (const column of shuffle([...Array(size).keys()])) {
      if (occupiedColumns.has(column)) {
        continue;
      }

      const candidate = { row, column };
      const touches = chosen.some(
        (existing) =>
          Math.abs(existing.row - candidate.row) <= 1 &&
          Math.abs(existing.column - candidate.column) <= 1
      );
      if (touches) {
        continue;
      }

      occupiedColumns.add(column);
      chosen.push(candidate);
      if (search(row + 1)) {
        return true;
      }
      chosen.pop();
      occupiedColumns.delete(column);
    }

    return false;
  }

  return search(0) ? chosen.slice() : null;
}

function generateRegions(solution, size) {
  const board = Array.from({ length: size }, () => Array(size).fill(-1));
  const cellsByRegion = solution.map((position) => [position]);

  solution.forEach((position, index) => {
    board[position.row][position.column] = index;
  });

  let assignedCount = solution.length;
  const totalCells = size * size;

  while (assignedCount < totalCells) {
    let progress = false;

    for (const regionIndex of shuffle([...Array(size).keys()])) {
      const frontier = [];
      const seen = new Set();
      for (const cell of cellsByRegion[regionIndex]) {
        for (const neighbor of orthogonalNeighbors(cell, size)) {
          if (board[neighbor.row][neighbor.column] !== -1) {
            continue;
          }
          const neighborKey = key(neighbor);
          if (seen.has(neighborKey)) {
            continue;
          }
          seen.add(neighborKey);
          const star = solution[regionIndex];
          const distance = Math.abs(star.row - neighbor.row) + Math.abs(star.column - neighbor.column);
          let connectedEdges = 0;
          for (const adjacent of orthogonalNeighbors(neighbor, size)) {
            if (board[adjacent.row][adjacent.column] === regionIndex) {
              connectedEdges += 1;
            }
          }
          frontier.push({
            cell: neighbor,
            score: distance + (connectedEdges >= 2 ? 0 : 2.5) + Math.random() * 1.2,
          });
        }
      }

      if (frontier.length === 0) {
        continue;
      }

      frontier.sort((left, right) => left.score - right.score);
      const selected = frontier[0].cell;
      board[selected.row][selected.column] = regionIndex;
      cellsByRegion[regionIndex].push(selected);
      assignedCount += 1;
      progress = true;
      if (assignedCount === totalCells) {
        break;
      }
    }

    if (!progress) {
      return null;
    }
  }

  return board.map((row) => row.map((region) => regionLabel(region)));
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

function cloneRegions(regions) {
  return regions.map((row) => row.slice());
}

function randomMutation(regions, solution) {
  const size = regions.length;
  const starKeys = new Set(solution.map(key));
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
          moves.push({ cell, targetRegion });
        }
      }
    }
  }

  for (const move of shuffle(moves).slice(0, 80)) {
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

    for (const regionCells of cells.values()) {
      const starCount = regionCells.filter((position) => starKeys.has(key(position))).length;
      if (starCount !== 1) {
        valid = false;
        break;
      }
    }

    if (valid) {
      return next;
    }
  }

  return null;
}

function analyzePuzzle(regions, maxSolutions = 6) {
  const size = regions.length;
  const touchingNeighbors = buildNeighborMap(size);
  const regionCells = buildRegionCells(regions);
  const regionIds = [...regionCells.keys()];
  const rowUsage = Array(size).fill(false);
  const columnUsage = Array(size).fill(false);
  const blocked = Array.from({ length: size }, () => Array(size).fill(false));
  const placements = [];
  let solutionCount = 0;
  let branchScore = 0;
  let forcedChoices = 0;

  for (const cells of regionCells.values()) {
    if (!isConnected(cells, size)) {
      return { solutionCount: maxSolutions + 1, branchScore: 999, forcedChoices: 0 };
    }
  }

  function availableCells(regionId) {
    return regionCells.get(regionId).filter((cell) => {
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
  }

  function search() {
    if (solutionCount > maxSolutions) {
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

      const changed = [];
      for (const neighbor of touchingNeighbors.get(key(cell))) {
        if (!blocked[neighbor.row][neighbor.column]) {
          blocked[neighbor.row][neighbor.column] = true;
          changed.push(neighbor);
        }
      }
      if (!blocked[cell.row][cell.column]) {
        blocked[cell.row][cell.column] = true;
        changed.push(cell);
      }

      search();

      for (const neighbor of changed) {
        blocked[neighbor.row][neighbor.column] = false;
      }
      rowUsage[cell.row] = false;
      columnUsage[cell.column] = false;
      placements.pop();

      if (solutionCount > maxSolutions) {
        return;
      }
    }
  }

  search();
  return { solutionCount, branchScore, forcedChoices };
}

function classifyDifficulty(analysis, size) {
  const score = analysis.branchScore - analysis.forcedChoices * 0.35 + (size - 6) * 0.4;
  if (score <= 4.5) {
    return { tier: "easy", score };
  }
  if (score <= 8.5) {
    return { tier: "medium", score };
  }
  return { tier: "hard", score };
}

function puzzleSignature(regions) {
  return regions.map((row) => row.join("")).join("|");
}

function chooseName(tier, number, size) {
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
  return `${prefixes[tier]} ${nouns[number % nouns.length]} ${size}-${number + 1}`;
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

  return {
    name: seed.name,
    size: seed.size,
    difficulty: seed.difficulty,
    regions: nextRegions,
    solution: nextSolution,
  };
}

function searchUniquePuzzle(size, maxAttempts) {
  let best = null;

  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    const solution = generateSolution(size);
    if (!solution) {
      continue;
    }

    let regions = generateRegions(solution, size);
    if (!regions) {
      continue;
    }

    let analysis = analyzePuzzle(regions);
    if (analysis.solutionCount === 1) {
      return { regions, solution, analysis };
    }

    let currentScore = analysis.solutionCount;
    let currentRegions = regions;

    for (let iteration = 0; iteration < size * 180; iteration += 1) {
      const mutated = randomMutation(currentRegions, solution);
      if (!mutated) {
        continue;
      }

      const mutatedAnalysis = analyzePuzzle(mutated);
      const mutatedScore = mutatedAnalysis.solutionCount;
      const shouldAccept =
        mutatedScore < currentScore || (mutatedScore === currentScore && Math.random() < 0.12);

      if (!shouldAccept) {
        continue;
      }

      currentRegions = mutated;
      currentScore = mutatedScore;
      analysis = mutatedAnalysis;

      if (!best || mutatedScore < best.analysis.solutionCount) {
        best = { regions: mutated, solution, analysis: mutatedAnalysis };
      }

      if (mutatedScore === 1) {
        return { regions: mutated, solution, analysis: mutatedAnalysis };
      }
    }
  }

  return best;
}

function makeBankEntry(size, tier, index, candidate, analysis) {
  return {
    id: `${size}-${tier}-${String(index + 1).padStart(3, "0")}`,
    name: chooseName(tier, index, size),
    size,
    starsPerUnit: 1,
    difficulty: tier,
    regions: candidate.regions,
    solution: candidate.solution,
    metrics: {
      branchScore: Number(analysis.branchScore.toFixed(2)),
      forcedChoices: analysis.forcedChoices,
      ratingScore: Number(classifyDifficulty(analysis, size).score.toFixed(2)),
    },
  };
}

function generatePuzzleBank({ counts, sizes, maxAttemptsPerSize }) {
  const bank = { easy: [], medium: [], hard: [] };
  const seen = new Set();
  const attemptsBySize = {};
  const sizeCounts = {};
  let totalAttempts = 0;

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

  for (const seed of SEED_PUZZLES) {
    for (const transform of transforms) {
      const transformed = transformPuzzle(seed, transform);
      const signature = puzzleSignature(transformed.regions);
      if (seen.has(signature)) {
        continue;
      }
      seen.add(signature);
      bank[seed.difficulty].push({
        id: `${seed.size}-${seed.difficulty}-${String(bank[seed.difficulty].length + 1).padStart(3, "0")}`,
        name: chooseName(seed.difficulty, bank[seed.difficulty].length, seed.size),
        size: seed.size,
        starsPerUnit: 1,
        difficulty: seed.difficulty,
        regions: transformed.regions,
        solution: transformed.solution,
        metrics: {
          branchScore: 0,
          forcedChoices: 0,
          ratingScore: 0,
        },
      });
    }
  }

  for (const size of sizes) {
    attemptsBySize[size] = 0;
    sizeCounts[size] = { easy: 0, medium: 0, hard: 0 };

    for (const tier of Object.keys(bank)) {
      sizeCounts[size][tier] = bank[tier].filter((puzzle) => puzzle.size === size).length;
    }

    while (
      attemptsBySize[size] < maxAttemptsPerSize &&
      (sizeCounts[size].easy < counts.easy ||
        sizeCounts[size].medium < counts.medium ||
        sizeCounts[size].hard < counts.hard)
    ) {
      attemptsBySize[size] += 1;
      totalAttempts += 1;

      const candidate = searchUniquePuzzle(size, 1);
      if (!candidate || candidate.analysis.solutionCount !== 1) {
        continue;
      }

      const signature = puzzleSignature(candidate.regions);
      if (seen.has(signature)) {
        continue;
      }

      const classification = classifyDifficulty(candidate.analysis, size);
      if (sizeCounts[size][classification.tier] >= counts[classification.tier]) {
        continue;
      }

      seen.add(signature);
      bank[classification.tier].push(
        makeBankEntry(size, classification.tier, sizeCounts[size][classification.tier], candidate, candidate.analysis)
      );
      sizeCounts[size][classification.tier] += 1;
    }
  }

  return { bank, attemptsBySize, totalAttempts, sizeCounts };
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const { bank, attemptsBySize, totalAttempts, sizeCounts } = generatePuzzleBank(options);

  const payload = {
    generatedAt: new Date().toISOString(),
    starsPerUnit: 1,
    sizes: options.sizes,
    attempts: totalAttempts,
    attemptsBySize,
    counts: sizeCounts,
    puzzles: bank,
  };

  fs.mkdirSync(path.dirname(options.output), { recursive: true });
  fs.writeFileSync(options.output, JSON.stringify(payload, null, 2));

  const bytes = fs.statSync(options.output).size;
  console.log(`Generated multi-size puzzle bank.`);
  console.log(JSON.stringify(sizeCounts, null, 2));
  console.log(`Output: ${options.output}`);
  console.log(`Size: ${bytes} bytes (${(bytes / 1024).toFixed(2)} KB)`);
}

if (require.main === module) {
  main();
}

module.exports = {
  analyzePuzzle,
  buildNeighborMap,
  classifyDifficulty,
  generateRegions,
  generateSolution,
  randomMutation,
  searchUniquePuzzle,
};
