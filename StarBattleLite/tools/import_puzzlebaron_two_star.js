#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { analyzeTwoStarPuzzle, transformPuzzle } = require("./generate_two_star_puzzles");

const OUTPUT_PATH = path.resolve(__dirname, "../StarBattleLite/Resources/generated_puzzles.json");
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

const SELECTOR_BY_SIZE = {
  8: 1,
  10: 2,
  12: 3,
};

const size = Number(process.argv[2] ?? 8);
const targetCount = Number(process.argv[3] ?? 100);
const maxFetches = Number(process.argv[4] ?? 20);

function fetchUrl(url, extraArgs = []) {
  return execFileSync("curl", ["-sL", "--max-time", "20", ...extraArgs, url], {
    encoding: "utf8",
  });
}

function fetchPlayHtml(boardSize) {
  const selector = SELECTOR_BY_SIZE[boardSize];
  if (!selector) {
    return null;
  }

  const initHtml = fetchUrl(`https://starbattle.puzzlebaron.com/init2.php?sg=${selector}`);
  const tokenMatch = initHtml.match(/name="u"\s+value="([a-f0-9]+)"/i);
  if (!tokenMatch) {
    return null;
  }

  return fetchUrl("https://starbattle.puzzlebaron.com/play.php", [
    "-X",
    "POST",
    "-d",
    `u=${tokenMatch[1]}`,
  ]);
}

function extractRegions(playHtml, boardSize) {
  const matches = [...playHtml.matchAll(/in_shape\[(\d+)\]\s*=\s*'([^']+)'/g)];
  const cellCount = boardSize * boardSize;
  if (matches.length !== cellCount) {
    return null;
  }

  const flat = Array(cellCount).fill("");
  for (const match of matches) {
    flat[Number(match[1])] = match[2];
  }

  return Array.from({ length: boardSize }, (_, row) =>
    flat.slice(row * boardSize, row * boardSize + boardSize)
  );
}

function puzzleSignature(regions) {
  return regions.map((row) => row.join("")).join("|");
}

function countForSize(puzzles, boardSize) {
  return puzzles.filter((puzzle) => puzzle.size === boardSize && puzzle.starsPerUnit === 2).length;
}

function updateMetadata(payload) {
  const easy = payload.puzzles.easy;
  payload.generatedAt = new Date().toISOString();
  payload.modeCounts = {
    oneStar: {
      6: easy.filter((puzzle) => puzzle.size === 6 && puzzle.starsPerUnit === 1).length,
      8: easy.filter((puzzle) => puzzle.size === 8 && puzzle.starsPerUnit === 1).length,
      10: easy.filter((puzzle) => puzzle.size === 10 && puzzle.starsPerUnit === 1).length,
      12: easy.filter((puzzle) => puzzle.size === 12 && puzzle.starsPerUnit === 1).length,
    },
    twoStar: {
      8: easy.filter((puzzle) => puzzle.size === 8 && puzzle.starsPerUnit === 2).length,
      10: easy.filter((puzzle) => puzzle.size === 10 && puzzle.starsPerUnit === 2).length,
      12: easy.filter((puzzle) => puzzle.size === 12 && puzzle.starsPerUnit === 2).length,
    },
  };
}

function main() {
  const payload = JSON.parse(fs.readFileSync(OUTPUT_PATH, "utf8"));
  const easy = payload.puzzles.easy;
  const seen = new Set(
    easy
      .filter((puzzle) => puzzle.starsPerUnit === 2 && puzzle.size === size)
      .map((puzzle) => puzzleSignature(puzzle.regions))
  );

  let fetchCount = 0;
  while (countForSize(easy, size) < targetCount && fetchCount < maxFetches) {
    fetchCount += 1;
    const playHtml = fetchPlayHtml(size);
    const regions = playHtml ? extractRegions(playHtml, size) : null;
    if (!regions) {
      console.log(`fetch ${fetchCount}: could not parse regions`);
      continue;
    }

    const analysis = analyzeTwoStarPuzzle(regions);
    if (analysis.solutionCount !== 1 || !analysis.firstSolution) {
      console.log(`fetch ${fetchCount}: not uniquely solvable`);
      continue;
    }

    let added = 0;
    for (const transform of TRANSFORMS) {
      if (countForSize(easy, size) >= targetCount) {
        break;
      }

      const transformed = transformPuzzle(
        {
          size,
          regions,
          solution: analysis.firstSolution,
        },
        transform
      );
      const signature = puzzleSignature(transformed.regions);
      if (seen.has(signature)) {
        continue;
      }

      seen.add(signature);
      const index = countForSize(easy, size) + 1;
      easy.push({
        id: `2s-${size}-easy-${String(index).padStart(3, "0")}`,
        name: `Twin Orbit ${size}-${index}`,
        size,
        starsPerUnit: 2,
        difficulty: "easy",
        regions: transformed.regions,
        solution: transformed.solution,
      });
      added += 1;
    }

    console.log(`fetch ${fetchCount}: added ${added}, total ${countForSize(easy, size)}/${targetCount}`);
  }

  updateMetadata(payload);
  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(payload, null, 2));
  console.log(JSON.stringify({ size, total: countForSize(easy, size), fetches: fetchCount }, null, 2));
}

main();
