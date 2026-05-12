#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { analyzeTwoStarPuzzle } = require("./generate_two_star_puzzles");

const OUTPUT_PATH = path.resolve(__dirname, "../StarBattleLite/Resources/generated_puzzles.json");
const targetCount = Number(process.argv[2] ?? 100);
const maxFetches = Number(process.argv[3] ?? 24);
const sourceSizes = [5, 6];

function fetchPrintPage(sourceSize) {
  return execFileSync(
    "curl",
    [
      "-sL",
      "--max-time",
      "20",
      "-X",
      "POST",
      "-d",
      `goprint=1&size=${sourceSize}`,
      "https://www.puzzle-star-battle.com/print.php",
    ],
    { encoding: "utf8" }
  );
}

function parseTasks(html) {
  const entries = [];
  const regex = /task:\s*'([^']+)'.*?puzzleWidth:\s*(\d+).*?Puzzle&nbsp;ID:&nbsp;([\d,]+)/gs;
  for (const match of html.matchAll(regex)) {
    entries.push({
      task: match[1],
      width: Number(match[2]),
      id: match[3].replace(/,/g, ""),
    });
  }
  return entries;
}

function taskToRegions(task, width) {
  const values = task.split(",");
  if (values.length !== width * width) {
    return null;
  }
  return Array.from({ length: width }, (_, row) =>
    values.slice(row * width, row * width + width)
  );
}

function puzzleSignature(regions) {
  return regions.map((row) => row.join("")).join("|");
}

function count10x10(puzzles) {
  return puzzles.filter((p) => p.size === 10 && p.starsPerUnit === 2).length;
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

function main() {
  const payload = JSON.parse(fs.readFileSync(OUTPUT_PATH, "utf8"));
  const easy = payload.puzzles.easy;
  const seen = new Set(
    easy
      .filter((p) => p.size === 10 && p.starsPerUnit === 2)
      .map((p) => puzzleSignature(p.regions))
  );

  let fetchCount = 0;
  while (count10x10(easy) < targetCount && fetchCount < maxFetches) {
    const sourceSize = sourceSizes[fetchCount % sourceSizes.length];
    fetchCount += 1;
    const html = fetchPrintPage(sourceSize);
    const entries = parseTasks(html);
    let added = 0;

    for (const entry of entries) {
      if (count10x10(easy) >= targetCount) {
        break;
      }
      if (entry.width !== 10) {
        continue;
      }
      const regions = taskToRegions(entry.task, entry.width);
      if (!regions) {
        continue;
      }
      const signature = puzzleSignature(regions);
      if (seen.has(signature)) {
        continue;
      }
      const analysis = analyzeTwoStarPuzzle(regions, 2);
      if (analysis.solutionCount !== 1 || !analysis.firstSolution) {
        continue;
      }

      seen.add(signature);
      const index = count10x10(easy) + 1;
      easy.push({
        id: `2s-10-easy-${String(index).padStart(3, "0")}`,
        name: `Twin Print 10-${index}`,
        size: 10,
        starsPerUnit: 2,
        difficulty: "easy",
        regions,
        solution: analysis.firstSolution,
      });
      added += 1;
    }

    console.log(`fetch ${fetchCount}: added ${added}, total ${count10x10(easy)}/${targetCount}`);
  }

  updateMetadata(payload);
  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(payload, null, 2));
  console.log(JSON.stringify({ total10x10TwoStar: count10x10(easy), fetches: fetchCount }, null, 2));
}

main();
