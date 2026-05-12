#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const {
  analyzeTwoStarPuzzle,
  generateRegionsFromPairs,
  pairStars,
  randomMutationTwoStar,
  transformPuzzle,
} = require("./generate_two_star_puzzles");

const OUTPUT_PATH = path.resolve(__dirname, "../StarBattleLite/Resources/generated_puzzles.json");
const targetCount = Number(process.argv[2] ?? 100);
const maxCycles = Number(process.argv[3] ?? 150);
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

function puzzleSignature(regions) {
  return regions.map((row) => row.join("")).join("|");
}

function count8x8(puzzles) {
  return puzzles.filter((p) => p.size === 8 && p.starsPerUnit === 2).length;
}

function updateMetadata(payload) {
  const easy = payload.puzzles.easy;
  payload.generatedAt = new Date().toISOString();
  payload.modeCounts = {
    oneStar: {
      6: easy.filter((p) => p.size === 6 && p.starsPerUnit === 1).length,
      8: easy.filter((p) => p.size === 8 && p.starsPerUnit === 1).length,
      10: easy.filter((p) => p.size === 10 && p.starsPerUnit === 1).length,
      12: easy.filter((p) => p.size === 12 && p.starsPerUnit === 1).length,
    },
    twoStar: {
      8: easy.filter((p) => p.size === 8 && p.starsPerUnit === 2).length,
      10: easy.filter((p) => p.size === 10 && p.starsPerUnit === 2).length,
      12: easy.filter((p) => p.size === 12 && p.starsPerUnit === 2).length,
    },
  };
}

function tryAddPuzzle(easy, seen, candidate, namePrefix = "Twin Orbit 8") {
  if (!candidate?.regions || !candidate?.solution) {
    return 0;
  }

  let added = 0;
  for (const transform of TRANSFORMS) {
    if (count8x8(easy) >= targetCount) {
      break;
    }

    const transformed = transformPuzzle(
      {
        size: 8,
        regions: candidate.regions,
        solution: candidate.solution,
      },
      transform
    );
    const signature = puzzleSignature(transformed.regions);
    if (seen.has(signature)) {
      continue;
    }
    const analysis = analyzeTwoStarPuzzle(transformed.regions, 2);
    if (analysis.solutionCount !== 1 || !analysis.firstSolution) {
      continue;
    }

    seen.add(signature);
    const index = count8x8(easy) + 1;
    easy.push({
      id: `2s-8-easy-${String(index).padStart(3, "0")}`,
      name: `${namePrefix}-${index}`,
      size: 8,
      starsPerUnit: 2,
      difficulty: "easy",
      regions: transformed.regions,
      solution: analysis.firstSolution,
    });
    added += 1;
  }

  return added;
}

function main() {
  const payload = JSON.parse(fs.readFileSync(OUTPUT_PATH, "utf8"));
  const easy = payload.puzzles.easy;
  const seedPuzzles = easy.filter((p) => p.size === 8 && p.starsPerUnit === 2);
  const seen = new Set(seedPuzzles.map((p) => puzzleSignature(p.regions)));

  let cycle = 0;
  while (count8x8(easy) < targetCount && cycle < maxCycles) {
    cycle += 1;
    let addedThisCycle = 0;

    const currentSeeds = easy
      .filter((p) => p.size === 8 && p.starsPerUnit === 2)
      .sort(() => Math.random() - 0.5)
      .slice(0, 12);

    for (const seed of currentSeeds) {
      if (count8x8(easy) >= targetCount) {
        break;
      }

      const freshRegions = generateRegionsFromPairs(pairStars(seed.solution), 8);
      if (freshRegions) {
        addedThisCycle += tryAddPuzzle(
          easy,
          seen,
          { regions: freshRegions, solution: seed.solution },
          "Twin Forge 8"
        );
      }

      let working = seed.regions;
      for (let mutation = 0; mutation < 80 && count8x8(easy) < targetCount; mutation += 1) {
        const next = randomMutationTwoStar(working, seed.solution, 2);
        if (!next) {
          continue;
        }
        working = next;
        addedThisCycle += tryAddPuzzle(
          easy,
          seen,
          { regions: next, solution: seed.solution },
          "Twin Orbit 8"
        );
      }
    }

    console.log(`cycle ${cycle}: added ${addedThisCycle}, total ${count8x8(easy)}/${targetCount}`);
    if (addedThisCycle === 0 && cycle > 20) {
      break;
    }
  }

  updateMetadata(payload);
  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(payload, null, 2));
  console.log(JSON.stringify({ total8x8TwoStar: count8x8(easy), cycles: cycle }, null, 2));
}

main();
