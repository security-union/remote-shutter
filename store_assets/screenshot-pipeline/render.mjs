#!/usr/bin/env node
// Renders App Store screenshots from template.html using headless Chrome.
// Zero npm dependencies. Usage: node render.mjs [slot ...]
import { execFileSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

// Milestone 1: slot 0 at iPhone 6.7" only. Milestone 2 adds the full
// slot x device-class matrix and writes into fastlane/screenshots/<locale>/.
// dsf: device scale factor — output pixels = width*dsf x height*dsf. Keeps the
// logical window small (huge windows get clamped by Chrome on macOS).
const DEVICES = [
  ["APP_IPHONE_67", 1290, 2796],
  ["APP_IPHONE_65", 1284, 2778],
  ["APP_IPAD_PRO_3GEN_129", 2048, 2732],
  ["APP_IPAD_PRO_3GEN_11", 1640, 2360],
];
const SLOTS = ["0", "1", "2", "3", "4", "5"];
const RENDERS = SLOTS.flatMap((slot) =>
  DEVICES.map(([dev, width, height]) => ({
    slot, width, height, out: `out/${slot}_${dev}_${slot}.png`,
  })),
);
// In-App Event card (16:9, min 1920x1080); rendered at 2x for crispness.
RENDERS.push({ slot: "banner", width: 1920, height: 1080, dsf: 2, out: "out/event_card_3840x2160.png" });

// Headless Chrome on macOS reserves ~87px of the window for chrome even in
// --headless=new, shrinking the viewport. Pad the window and crop afterwards;
// the template gets exact canvas dims via ?w=&h= so layout never depends on
// the viewport.
const PAD = 120;

const only = process.argv.slice(2);
for (const r of RENDERS) {
  if (only.length && !only.includes(r.slot)) continue;
  const dsf = r.dsf || 1;
  const outPath = resolve(join(here, r.out));
  mkdirSync(dirname(outPath), { recursive: true });
  const url = `file://${join(here, "template.html")}?slot=${r.slot}&w=${r.width}&h=${r.height}`;
  execFileSync(CHROME, [
    "--headless=new",
    "--disable-gpu",
    "--hide-scrollbars",
    `--force-device-scale-factor=${dsf}`,
    `--window-size=${r.width},${r.height + PAD}`,
    "--virtual-time-budget=3000",
    `--screenshot=${outPath}`,
    url,
  ], { stdio: "pipe" });
  execFileSync("python3", ["-c", `
from PIL import Image
im = Image.open(${JSON.stringify(outPath)})
im.crop((0, 0, ${r.width * dsf}, ${r.height * dsf})).save(${JSON.stringify(outPath)})
`]);
  console.log(`rendered slot ${r.slot} -> ${r.out} (${r.width * dsf}x${r.height * dsf})`);
}
