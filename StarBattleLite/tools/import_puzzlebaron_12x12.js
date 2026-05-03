#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { analyzeTwoStarPuzzle, transformPuzzle } = require("./generate_two_star_puzzles");

const OUTPUT_PATH = path.resolve(__dirname, "../StarBattleLite/Resources/generated_puzzles.json");
const TARGET_COUNT = Number(process.argv[2] ?? 16);
const MAX_FETCHES = Number(process.argv[3] ?? 6);
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

function fetchUrl(url, extraArgs = []) {
  return execFileSync("curl", ["-sL", "--max-time", "20", ...extraArgs, url], {
    encoding: "utf8",
  });
}

function fetchPlayHtml() {
  const initHtml = fetchUrl("https://starbattle.puzzlebaron.com/init2.php?sg=3");
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

function extractRegions(playHtml) {
  const matches = [...playHtml.matchAll(/in_shape\[(\d+)\]\s*=\s*'([^']+)'/g)];
  if (matches.length !== 144) {
    return null;
  }

  const flat = Array(144).fill("");
  for (const match of matches) {
    flat[Number(match[1])] = match[2];
  }

  return Array.from({ length: 12 }, (_, row) => flat.slice(row * 12, row * 12 + 12));
}

function puzzleSignature(regions) {
  return regions.map((row) => row.join("")).join("|");
}

function nextIndexForTwelve(puzzles) {
  return puzzles.filter((puzzle) => puzzle.size === 12 && puzzle.starsPerUnit === 2).length;
}

function updateMetadata(payload) {
  const easy = payload.puzzles.easy;
  payload.generatedAt = new Date().toISOString();

  const sizes = new Set(payload.sizes ?? []);
  sizes.add(12);
  payload.sizes = [...sizes].sort((left, right) => left - right);

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
      .filter((puzzle) => puzzle.starsPerUnit === 2 && puzzle.size === 12)
      .map((puzzle) => puzzleSignature(puzzle.regions))
  );

  let fetchCount = 0;
  while (nextIndexForTwelve(easy) < TARGET_COUNT && fetchCount < MAX_FETCHES) {
    fetchCount += 1;
    const playHtml = fetchPlayHtml();
    const regions = playHtml ? extractRegions(playHtml) : null;
    if (!regions) {
      console.log(`fetch ${fetchCount}: could not parse regions`);
      continue;
    }

    const analysis = analyzeTwoStarPuzzle(regions);
    if (analysis.solutionCount !== 1 || !analysis.firstSolution) {
      console.log(`fetch ${fetchCount}: not uniquely solvable`);
      continue;
    }

    let addedFromSeed = 0;
    for (const transform of TRANSFORMS) {
      if (nextIndexForTwelve(easy) >= TARGET_COUNT) {
        break;
      }

      const transformed = transformPuzzle(
        {
          size: 12,
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
      const index = nextIndexForTwelve(easy) + 1;
      easy.push({
        id: `2s-12-easy-${String(index).padStart(3, "0")}`,
        name: `Twin Orbit 12-${index}`,
        size: 12,
        starsPerUnit: 2,
        difficulty: "easy",
        regions: transformed.regions,
        solution: transformed.solution,
      });
      addedFromSeed += 1;
    }

    console.log(`fetch ${fetchCount}: added ${addedFromSeed}, total ${nextIndexForTwelve(easy)}/${TARGET_COUNT}`);
  }

  updateMetadata(payload);
  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(payload, null, 2));
  console.log(
    JSON.stringify(
      {
        twelveTwoStar: nextIndexForTwelve(easy),
        fetches: fetchCount,
      },
      null,
      2
    )
  );
}

main();
