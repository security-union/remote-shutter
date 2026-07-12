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
// Per-device slot plans: iPad drops the Watch slot and uses iPad-native
// variants for the mockup slots and the cardinal scene.
// iPad drops the Watch slot and the family scene (no iPad in it) and uses
// iPad-native variants for the mockup slots and the cardinal scene.
const PLANS = [
  ["APP_IPHONE_67", 1290, 2796, ["0", "1", "3", "4", "2"]],
  ["APP_IPHONE_65", 1284, 2778, ["0", "1", "3", "4", "2"]],
  ["APP_IPAD_PRO_3GEN_129", 2048, 2732, ["0", "3i", "2i"]],
  ["APP_IPAD_PRO_3GEN_11", 1640, 2360, ["0", "3i", "2i"]],
  // Mac App Store listing (deliver detects the Mac display family by the
  // 2880x1800 16:10 resolution).
  ["APP_DESKTOP", 2880, 1800, ["mac0", "mac3", "mac1", "mac2"]],
];

// Locale: `node render.mjs --locale it [slots...]` — headline/label strings come
// from the static translations.js table; output goes to out/<locale>/.
// Platforms: `--plans iphone,ipad,mac,banner` renders only those device plans
// (default: all). Aliases map to the PLANS device-name prefixes.
const args = process.argv.slice(2);
const locIdx = args.indexOf("--locale");
const LOCALE = locIdx >= 0 ? args.splice(locIdx, 2)[1] : "en-US";
const plansIdx = args.indexOf("--plans");
const PLAN_ALIAS = { iphone: "APP_IPHONE", ipad: "APP_IPAD", mac: "APP_DESKTOP", desktop: "APP_DESKTOP", banner: "banner" };
const PLAN_FILTER = plansIdx >= 0
  ? args.splice(plansIdx, 2)[1].split(",").map((p) => PLAN_ALIAS[p.trim().toLowerCase()] || p.trim())
  : null;
const planOn = (dev) => !PLAN_FILTER || PLAN_FILTER.some((w) => dev.toUpperCase().startsWith(w.toUpperCase()));
const OUT = `out/${LOCALE === "en-US" ? "" : LOCALE + "/"}`;

const RENDERS = PLANS.filter(([dev]) => planOn(dev)).flatMap(([dev, width, height, slots]) =>
  slots.map((slot, i) => ({
    slot, width, height, out: `${OUT}${i}_${dev}_${i}.png`,
  })),
);
// In-App Event card (16:9, min 1920x1080); rendered at 2x for crispness.
if (planOn("banner")) RENDERS.push({ slot: "banner", width: 1920, height: 1080, dsf: 2, out: `${OUT}event_card_3840x2160.png` });

// Headless Chrome on macOS reserves ~87px of the window for chrome even in
// --headless=new, shrinking the viewport. Pad the window and crop afterwards;
// the template gets exact canvas dims via ?w=&h= so layout never depends on
// the viewport.
const PAD = 120;

const only = args;
for (const r of RENDERS) {
  if (only.length && !only.includes(r.slot)) continue;
  const dsf = r.dsf || 1;
  const outPath = resolve(join(here, r.out));
  mkdirSync(dirname(outPath), { recursive: true });
  const url = `file://${join(here, "template.html")}?slot=${r.slot}&w=${r.width}&h=${r.height}&locale=${LOCALE}`;
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
