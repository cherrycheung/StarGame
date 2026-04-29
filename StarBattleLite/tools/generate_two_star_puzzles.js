#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const DEFAULT_OUTPUT = path.resolve(__dirname, "../StarBattleLite/Resources/generated_puzzles.json");
const DEFAULT_TARGETS = { 8: 16, 10: 16 };
const REGION_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const TRANSFORMS = [
  "identity",
  "rotate90",
  "rotate180",
  "rotate270",
  "flipH",
  "flipV",
  "transpose",
  "antiTranspose",
];

function parseArgs(argv) {
  const options = {
    output: DEFAULT_OUTPUT,
    targets: { ...DEFAULT_TARGETS },
    maxAttemptsPerSeed: 500,
    maxSeedsPerSize: 4,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--output") {
      options.output = path.resolve(process.cwd(), argv[index + 1]);
      index += 1;
    } else if (arg === "--eight") {
      options.targets[8] = Number(argv[index + 1]);
      index += 1;
    } else if (arg === "--ten") {
      options.targets[10] = Number(argv[index + 1]);
      index += 1;
    } else if (arg === "--max-attempts") {
      options.maxAttemptsPerSeed = Number(argv[index + 1]);
      index += 1;
    } else if (arg === "--max-seeds") {
      options.maxSeedsPerSize = Number(argv[index + 1]);
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

function regionLabel(index) {
  if (index < REGION_LETTERS.length) {
    return REGION_LETTERS[index];
  }

  return `R${index}`;
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

function nonTouchingRowCombos(size, starsPerUnit) {
  const results = [];

  function search(startColumn, chosen) {
    if (chosen.length === starsPerUnit) {
      results.push(chosen.slice());
      return;
    }

    for (let column = startColumn; column < size; column += 1) {
      const previous = chosen[chosen.length - 1];
      if (previous !== undefined && Math.abs(previous - column) <= 1) {
        continue;
      }
      chosen.push(column);
      search(column + 1, chosen);
      chosen.pop();
    }
  }

  search(0, []);
  return results;
}

function generateTwoStarSolution(size) {
  const starsPerUnit = 2;
  const rowCombos = nonTouchingRowCombos(size, starsPerUnit);
  const columnCounts = Array(size).fill(0);
  const chosenByRow = [];

  function isCompatibleWithPreviousRow(columns, previousColumns) {
    if (!previousColumns) {
      return true;
    }

    return columns.every((column) => previousColumns.every((previous) => Math.abs(previous - column) > 1));
  }

  function hasReachableColumnQuotas(row) {
    const remainingRows = size - row;
    return columnCounts.every((count) => count <= starsPerUnit && count + remainingRows >= starsPerUnit);
  }

  function search(row) {
    if (row === size) {
      return columnCounts.every((count) => count === starsPerUnit);
    }

    const previousColumns = chosenByRow[row - 1];
    for (const columns of shuffle(rowCombos)) {
      if (!isCompatibleWithPreviousRow(columns, previousColumns)) {
        continue;
      }
      if (columns.some((column) => columnCounts[column] >= starsPerUnit)) {
        continue;
      }

      columns.forEach((column) => {
        columnCounts[column] += 1;
      });
      chosenByRow[row] = columns;

      if (hasReachableColumnQuotas(row + 1) && search(row + 1)) {
        return true;
      }

      chosenByRow[row] = undefined;
      columns.forEach((column) => {
        columnCounts[column] -= 1;
      });
    }

    return false;
  }

  if (!search(0)) {
    return null;
  }

  return chosenByRow.flatMap((columns, row) => columns.map((column) => ({ row, column })));
}

function pairStars(solution) {
  const remaining = shuffle(solution);
  const pairs = [];

  while (remaining.length > 1) {
    const star = remaining.shift();
    let bestIndex = 0;
    let bestScore = Number.POSITIVE_INFINITY;

    for (let index = 0; index < remaining.length; index += 1) {
      const candidate = remaining[index];
      const score =
        Math.abs(candidate.row - star.row) +
        Math.abs(candidate.column - star.column) +
        (candidate.row === star.row ? 3 : 0) +
        (candidate.column === star.column ? 2 : 0);
      if (score < bestScore) {
        bestScore = score;
        bestIndex = index;
      }
    }

    const partner = remaining.splice(bestIndex, 1)[0];
    pairs.push([star, partner]);
  }

  return pairs;
}

function generateRegionsFromPairs(pairs, size) {
  const targetRegionSize = size;
  const board = Array.from({ length: size }, () => Array(size).fill(-1));
  const regionSeeds = pairs.map((pair) => pair.slice());
  const cellsByRegion = regionSeeds.map((pair) => pair.slice());

  pairs.forEach((pair, index) => {
    for (const star of pair) {
      board[star.row][star.column] = index;
    }
  });

  let assignedCount = pairs.length * 2;
  const totalCells = size * size;

  while (assignedCount < totalCells) {
    let progress = false;

    for (const regionIndex of shuffle([...Array(pairs.length).keys()])) {
      if (cellsByRegion[regionIndex].length >= targetRegionSize) {
        continue;
      }

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

          const seedDistance = Math.min(
            ...regionSeeds[regionIndex].map(
              (seed) => Math.abs(seed.row - neighbor.row) + Math.abs(seed.column - neighbor.column)
            )
          );
          let connectedEdges = 0;
          for (const adjacent of orthogonalNeighbors(neighbor, size)) {
            if (board[adjacent.row][adjacent.column] === regionIndex) {
              connectedEdges += 1;
            }
          }
          frontier.push({
            cell: neighbor,
            score: seedDistance + (connectedEdges >= 2 ? 0 : 2) + Math.random() * 1.1,
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

  if (cellsByRegion.some((cells) => cells.length !== targetRegionSize || !isConnected(cells, size))) {
    return null;
  }

  return board.map((row) => row.map((region) => regionLabel(region)));
}

function randomMutationTwoStar(regions, solution, starsPerUnit) {
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

  for (const move of shuffle(moves).slice(0, 120)) {
    const next = cloneRegions(regions);
    next[move.cell.row][move.cell.column] = move.targetRegion;

    const cells = buildRegionCells(next);
    if (cells.size !== size) {
      continue;
    }

    let valid = true;
    for (const regionCells of cells.values()) {
      if (regionCells.length !== size || !isConnected(regionCells, size)) {
        valid = false;
        break;
      }
      const starCount = regionCells.filter((position) => starKeys.has(key(position))).length;
      if (starCount !== starsPerUnit) {
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

function enumerateRegionOptions(regionCells) {
  const options = [];
  for (let left = 0; left < regionCells.length; left += 1) {
    for (let right = left + 1; right < regionCells.length; right += 1) {
      const first = regionCells[left];
      const second = regionCells[right];
      if (Math.abs(first.row - second.row) <= 1 && Math.abs(first.column - second.column) <= 1) {
        continue;
      }
      options.push([first, second]);
    }
  }
  return options;
}

function analyzeTwoStarPuzzle(regions, maxSolutions = 2) {
  const size = regions.length;
  const starsPerUnit = 2;
  const touchingNeighbors = buildNeighborMap(size);
  const regionCells = buildRegionCells(regions);
  const regionIds = [...regionCells.keys()];
  const rowCounts = Array(size).fill(0);
  const columnCounts = Array(size).fill(0);
  const blocked = Array.from({ length: size }, () => Array(size).fill(false));
  const placements = [];
  let solutionCount = 0;
  let branchScore = 0;
  let forcedChoices = 0;

  for (const cells of regionCells.values()) {
    if (cells.length !== size || !isConnected(cells, size)) {
      return { solutionCount: maxSolutions + 1, branchScore: 999, forcedChoices: 0 };
    }
  }

  const optionsByRegion = new Map(
    regionIds.map((regionId) => [regionId, enumerateRegionOptions(regionCells.get(regionId))])
  );

  function optionFits(option) {
    const rowAdds = new Map();
    const columnAdds = new Map();

    for (const cell of option) {
      if (blocked[cell.row][cell.column]) {
        return false;
      }
      rowAdds.set(cell.row, (rowAdds.get(cell.row) ?? 0) + 1);
      columnAdds.set(cell.column, (columnAdds.get(cell.column) ?? 0) + 1);
    }

    for (const [row, added] of rowAdds) {
      if (rowCounts[row] + added > starsPerUnit) {
        return false;
      }
    }
    for (const [column, added] of columnAdds) {
      if (columnCounts[column] + added > starsPerUnit) {
        return false;
      }
    }

    return true;
  }

  function search() {
    if (solutionCount > maxSolutions) {
      return;
    }

    const remaining = regionIds
      .filter((regionId) => !placements.some((placement) => placement.regionId === regionId))
      .map((regionId) => ({
        regionId,
        options: optionsByRegion.get(regionId).filter(optionFits),
      }));

    if (remaining.length === 0) {
      if (rowCounts.every((count) => count === starsPerUnit) && columnCounts.every((count) => count === starsPerUnit)) {
        solutionCount += 1;
      }
      return;
    }

    remaining.sort((left, right) => left.options.length - right.options.length);
    const next = remaining[0];

    if (next.options.length === 0) {
      return;
    }

    if (next.options.length === 1) {
      forcedChoices += 1;
    } else {
      branchScore += next.options.length - 1;
    }

    for (const option of shuffle(next.options)) {
      placements.push({ regionId: next.regionId, option });
      const changed = [];

      for (const cell of option) {
        rowCounts[cell.row] += 1;
        columnCounts[cell.column] += 1;

        for (const neighbor of touchingNeighbors.get(key(cell)).concat([cell])) {
          if (!blocked[neighbor.row][neighbor.column]) {
            blocked[neighbor.row][neighbor.column] = true;
            changed.push(neighbor);
          }
        }
      }

      search();

      for (const cell of option) {
        rowCounts[cell.row] -= 1;
        columnCounts[cell.column] -= 1;
      }
      for (const neighbor of changed) {
        blocked[neighbor.row][neighbor.column] = false;
      }
      placements.pop();

      if (solutionCount > maxSolutions) {
        return;
      }
    }
  }

  search();
  return { solutionCount, branchScore, forcedChoices };
}

function puzzleSignature(regions) {
  return regions.map((row) => row.join("")).join("|");
}

function chooseName(index, size) {
  const nouns = [
    "Orbit",
    "Lattice",
    "Vector",
    "Signal",
    "Halo",
    "Beacon",
    "Pulsar",
    "Anchor",
  ];
  return `Twin ${nouns[index % nouns.length]} ${size}-${index + 1}`;
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
    size: seed.size,
    difficulty: "easy",
    starsPerUnit: 2,
    regions: nextRegions,
    solution: nextSolution,
  };
}

function searchUniqueTwoStarPuzzle(size, maxAttempts) {
  let best = null;

  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    const solution = generateTwoStarSolution(size);
    if (!solution) {
      continue;
    }

    for (let pairAttempt = 0; pairAttempt < 12; pairAttempt += 1) {
      const pairs = pairStars(solution);
      let regions = generateRegionsFromPairs(pairs, size);
      if (!regions) {
        continue;
      }

      let analysis = analyzeTwoStarPuzzle(regions);
      if (analysis.solutionCount === 1) {
        return { regions, solution, analysis };
      }

      let currentRegions = regions;
      let currentScore = analysis.solutionCount;

      for (let mutation = 0; mutation < size * 220; mutation += 1) {
        const nextRegions = randomMutationTwoStar(currentRegions, solution, 2);
        if (!nextRegions) {
          continue;
        }

        const nextAnalysis = analyzeTwoStarPuzzle(nextRegions);
        const shouldAccept =
          nextAnalysis.solutionCount < currentScore ||
          (nextAnalysis.solutionCount === currentScore && Math.random() < 0.12);
        if (!shouldAccept) {
          continue;
        }

        currentRegions = nextRegions;
        currentScore = nextAnalysis.solutionCount;
        analysis = nextAnalysis;

        if (!best || nextAnalysis.solutionCount < best.analysis.solutionCount) {
          best = { regions: nextRegions, solution, analysis: nextAnalysis };
        }

        if (nextAnalysis.solutionCount === 1) {
          return { regions: nextRegions, solution, analysis: nextAnalysis };
        }
      }
    }
  }

  return best;
}

function nextIndexForSize(existing, size) {
  return existing.filter((puzzle) => puzzle.size === size && puzzle.starsPerUnit === 2).length;
}

function injectTwoStarPuzzles(payload, options) {
  const easy = (payload.puzzles?.easy ?? []).filter((puzzle) => puzzle.starsPerUnit !== 2);
  const medium = payload.puzzles?.medium ?? [];
  const hard = payload.puzzles?.hard ?? [];
  const seen = new Set(easy.map((puzzle) => `2:${puzzle.starsPerUnit}:${puzzle.size}:${puzzleSignature(puzzle.regions)}`));

  for (const size of Object.keys(options.targets).map(Number)) {
    let addedForSize = 0;
    let seedCount = 0;
    while (nextIndexForSize(easy, size) < options.targets[size] && seedCount < options.maxSeedsPerSize) {
      seedCount += 1;
      const candidate = searchUniqueTwoStarPuzzle(size, options.maxAttemptsPerSeed);
      if (!candidate || candidate.analysis.solutionCount !== 1) {
        continue;
      }

      for (const transform of TRANSFORMS) {
        if (nextIndexForSize(easy, size) >= options.targets[size]) {
          break;
        }

        const transformed = transformPuzzle({
          size,
          regions: candidate.regions,
          solution: candidate.solution,
        }, transform);
        const signature = `2:2:${size}:${puzzleSignature(transformed.regions)}`;
        if (seen.has(signature)) {
          continue;
        }
        seen.add(signature);

        const index = nextIndexForSize(easy, size);
        easy.push({
          id: `2s-${size}-easy-${String(index + 1).padStart(3, "0")}`,
          name: chooseName(index, size),
          size,
          starsPerUnit: 2,
          difficulty: "easy",
          regions: transformed.regions,
          solution: transformed.solution,
        });
        addedForSize += 1;
      }
    }
  }

  payload.generatedAt = new Date().toISOString();
  payload.modeCounts = {
    oneStar: {
      6: easy.filter((puzzle) => puzzle.size === 6 && puzzle.starsPerUnit === 1).length,
      8: easy.filter((puzzle) => puzzle.size === 8 && puzzle.starsPerUnit === 1).length,
      10: easy.filter((puzzle) => puzzle.size === 10 && puzzle.starsPerUnit === 1).length,
    },
    twoStar: {
      8: easy.filter((puzzle) => puzzle.size === 8 && puzzle.starsPerUnit === 2).length,
      10: easy.filter((puzzle) => puzzle.size === 10 && puzzle.starsPerUnit === 2).length,
    },
  };
  payload.puzzles = { easy, medium, hard };
  return payload;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const payload = JSON.parse(fs.readFileSync(options.output, "utf8"));
  const updated = injectTwoStarPuzzles(payload, options);
  fs.writeFileSync(options.output, JSON.stringify(updated, null, 2));

  const easy = updated.puzzles.easy;
  console.log("Two-star puzzle counts:");
  console.log(
    JSON.stringify(
      {
        8: easy.filter((puzzle) => puzzle.size === 8 && puzzle.starsPerUnit === 2).length,
        10: easy.filter((puzzle) => puzzle.size === 10 && puzzle.starsPerUnit === 2).length,
      },
      null,
      2
    )
  );
}

if (require.main === module) {
  main();
}

module.exports = {
  analyzeTwoStarPuzzle,
  generateRegionsFromPairs,
  generateTwoStarSolution,
  pairStars,
  searchUniqueTwoStarPuzzle,
  transformPuzzle,
};
