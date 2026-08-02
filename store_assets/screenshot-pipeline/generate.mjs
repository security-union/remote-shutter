#!/usr/bin/env node
// Generates AI lifestyle scenes for the App Store screenshots via the Gemini API
// (Nano Banana Pro). Requires AI_STUDIO env var (aistudio.google.com API key).
// Prompts mirror docs/marketing/prompt-pack.md.
// Usage:
//   node generate.mjs <sceneId> [count]                 e.g. node generate.mjs slot0_v1 2
//   node generate.mjs edit <inputImg> <outFile> <prompt> [aspect]
//     image-to-image, ad hoc. Anything the manifest ends up using should be
//     recorded in DERIVED instead, so it can be remade.
//   node generate.mjs derive [outFile]
//     re-run a recorded derivation; no argument lists them all
//
// Every file manifest.js references traces back to one of three things: a
// PROMPTS entry (with CHOSEN recording which candidate was kept), a DERIVED
// entry, or a crop. Adding a scene means adding it here too — see README.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(here, "..", "ai-scenes");
const MODEL = "gemini-3-pro-image";
const KEY = process.env.AI_STUDIO;
if (!KEY) { console.error("AI_STUDIO env var not set"); process.exit(1); }

const STYLE = `Commercial photography in the style of an Apple ad, photorealistic,
shallow depth of field, bright and premium, neutral warm palette. All device screens
are dark and off. Subjects framed in the upper two thirds of the image; the lower
third stays simple. No text, no logos, no watermarks. Vertical 9:16.`;

const PROMPTS = {
  // ---- Mac App Store listing scenes (landscape 16:10 canvases) ----
  mac0_studio: `Over-the-shoulder shot from behind and to the right of a
professional female photographer standing at a white product table in a
bright, minimal photo studio. Her head and right shoulder are softly out of
focus at the right edge of the near foreground. With her LEFT hand in a white
glove she reaches down to adjust a luxury watch lying on the product table.
In her RIGHT hand she holds an unbranded modern smartphone upright in portrait
orientation raised at chest height, screen facing back toward the viewer,
completely black and switched off, no reflections, shown large in the upper
half of the frame. Several steps away in the lower-left of the frame, on a
separate light wooden side desk, an unbranded modern aluminum laptop sits
open, its screen facing the viewer, completely black and off, all four corners
of the screen fully visible, nothing overlapping the laptop. Beside the
laptop, a professional compact cinema camera on a small desktop mount aims at
the product table, connected to the laptop by a neat black cable. The
photographer is clearly far from the laptop — she works at the table while
the Mac and camera film from across the room. White cyclorama wall, softbox
visible, soft high-key daylight, 35mm look. ${STYLE}`,
  mac3_direct: `A bright home-studio scene, vertical composition: in the lower
half of the frame, an unbranded modern aluminum laptop sits open on a tidy desk,
screen facing the viewer straight on, completely black and switched off, no
reflections, shown large. Nothing and no one is between the viewer and the
laptop — the desk is empty around it and all four corners of the laptop screen
are fully visible. A person stands off to the far left edge of the frame in
soft focus, watching the dark screen like a director's monitor, not touching
the desk. Behind and above, through a large bright window, a leafy garden: a
rustic wooden bird feeder where a bright red cardinal perches, and an unbranded
modern smartphone mounted on a small flexible mini tripod clamped to the feeder
pole RIGHT NEXT to the cardinal, its lens almost touching the feeder ledge,
screen dark — the phone and the bird close together in the upper third,
both clearly recognizable. Morning light, warm interior, telephoto garden
compression. The laptop screen large and clearly visible. ${STYLE}`,
  // Short prompt per the Veo/Nano Banana five-part formula:
  // [Cinematography] + [Subject] + [Action] + [Context] + [Style & Ambiance]
  mac2_cook: `Over-the-shoulder shot from behind a home cook at a wooden kitchen
counter. She garnishes a colorful charcuterie board while her other hand rests
on the trackpad of an open laptop beside her, its dark screen facing the viewer,
fully visible. A smartphone on an articulated arm under the upper cabinet points
straight down at the board. Bright modern kitchen, soft daylight, photorealistic
commercial photography in the style of an Apple ad. Vertical 9:16.`,
  mac3_window: `A bright home-office scene, vertical composition: in the lower
half of the frame, an unbranded modern aluminum laptop sits open on a tidy desk,
screen facing the viewer straight on, completely black and switched off, no
reflections, shown large, all four corners of the screen fully visible, nothing
overlapping the laptop. Behind the desk, a large bright window onto a leafy
garden. Mounted on the INSIDE of the window glass with a small suction-cup phone
mount, an unbranded modern smartphone in portrait orientation, its camera facing
out through the glass and its dark switched-off screen facing back into the room
toward the viewer, in the upper third. Just outside the glass, inches from the
phone, a rustic wooden bird feeder hangs with a bright red cardinal perched on
its ledge, sharp and clearly visible next to the phone. Morning light, warm
interior, telephoto garden compression. ${STYLE}`,
  slot0_v1: `A professional female photographer in a bright, minimal photo studio
doing a product shoot. In the midground, an unbranded modern smartphone is mounted on
a high-end carbon-fiber tripod with a geared head, aimed at a small product table
where a luxury watch sits under a softbox — the phone's screen is dark and off. The
photographer stands a few steps away in the upper right of the frame, holding a large
unbranded tablet in both hands like a camera monitor, screen dark and off, looking at
it with focused confidence. White cyclorama wall, softbox and reflector visible, soft
high-key daylight balance, 35mm lens look. ${STYLE}`,
  slot0_ots: `Over-the-shoulder shot from directly behind a professional female
photographer in a bright, minimal photo studio. Her head and shoulder are softly out
of focus at the right edge of the near foreground. She holds a large unbranded modern
tablet in portrait orientation with both hands gripping only the side bezels, no
fingers over the screen; the tablet screen faces the viewer, completely black,
switched off, no reflections, shown large in the center of the frame at a slight
angle. A few steps ahead to the left, an unbranded modern smartphone is mounted on a
high-end carbon-fiber tripod, aimed at a small white product table where a luxury
watch sits under a softbox; the phone's screen faces back toward the photographer and
the viewer, completely black and off. White cyclorama wall, soft high-key studio
light, photorealistic, sharp focus on the tablet and phone, 35mm lens look. ${STYLE}`,
  slot1_group: `A warm multi-generation family group photo moment in a leafy
backyard at golden hour: grandparents, parents and two kids clustered together
laughing, arranged for a group photo. The adult at the edge of the group holds an
unbranded modern smartphone casually at waist height, glancing at it — its screen is
dark and off — while still being part of the group. In the near foreground corner,
a second unbranded smartphone stands on a small tripod facing the family, screen
dark and off. String lights and greenery softly blurred behind, warm golden light,
50mm look. ${STYLE}`,
  slot3_wild: `Nature photography scene in a garden: in the sharp foreground, an
unbranded modern smartphone is mounted on a low flexible mini tripod very close to
a rustic wooden bird feeder where a bright red cardinal perches; the phone's screen
faces the viewer, completely black and off. Far in the softly blurred background, a
person stands on a porch holding another phone, watching from a distance. Morning
light, dewy greens, telephoto compression, the feeder and phone in the upper two
thirds. ${STYLE}`,
  slot3_ots: `Over-the-shoulder shot from directly behind a woman standing on a
cozy wooden porch on a bright morning. Her shoulder and hair are softly out of
focus at the right edge of the near foreground. She holds an unbranded modern
smartphone upright in portrait orientation in one hand, screen facing the viewer,
completely black and switched off, no reflections, shown large in the center-left
of the frame. Beyond the porch railing, across the garden a few steps away, a
rustic wooden bird feeder with a bright red cardinal perched on its ledge, and a
second unbranded smartphone mounted on a small flexible tripod clamped right next
to the feeder, its screen dark — both clearly recognizable, gently soft from
distance. Morning light, dewy greens. ${STYLE}`,
  slot3_ipad: `Over-the-shoulder shot from directly behind a woman standing on a
cozy wooden porch on a bright morning. Her shoulder and hair are softly out of
focus at the right edge of the near foreground. She holds an unbranded modern
tablet upright in portrait orientation in one hand, screen facing the viewer,
completely black and switched off, no reflections, shown large in the
center-left of the frame. Beyond the porch railing, across the garden a few
steps away, a rustic wooden bird feeder with a bright red cardinal perched on
its ledge, and an unbranded smartphone mounted in PORTRAIT orientation on a
small flexible tripod clamped right next to the feeder, its screen dark — both
clearly recognizable, gently soft from distance. Morning light, dewy greens.
${STYLE}`,
  slot4_watch: `Night scene, close-up of a raised wrist wearing an unbranded modern
smartwatch with a rectangular rounded screen, completely black and off, facing the
viewer, in the upper half of the frame. In the softly blurred background, an
amateur astronomy setup: a telescope on a tripod with an unbranded smartphone
clamped to its eyepiece, and a deep blue starry night sky with a bright full moon.
Cool blue night palette with warm skin tones, cinematic but clean. ${STYLE}`,
  slot0_v2: `A professional photographer in a modern studio shooting a designer
sneaker on a pedestal lit by a single softbox. An unbranded smartphone on a
professional tripod faces the pedestal, screen dark. The photographer, wearing a
black tee, stands well off to the side holding an unbranded tablet as a wireless
camera monitor, screen dark, one hand hovering over it. Charcoal-gray backdrop, rim
lighting, controlled shadows but overall bright and premium. ${STYLE}`,
  slot0_v3: `A professional photographer directing a seated portrait session in a
bright loft studio. An unbranded smartphone on a heavy-duty tripod with a ring light
faces the model; the photographer stands apart near a large window holding an
unbranded tablet in one hand as her remote camera monitor, gesturing direction with
the other hand. Both device screens dark and off. Airy daylight, white brick and
wood floor. ${STYLE}`,
};

// Which candidate each base scene the manifest uses came from. `node
// generate.mjs <id> N` writes <id>_c1..cN; this records which one was kept, so
// a regenerated set can be compared against the same slot.
const CHOSEN = {
  slot0_ots: "slot0_ots_c1.jpg",
  slot1_group: "slot1_group_c2.jpg",
  slot3_ipad: "slot3_ipad_c1.jpg",
  slot3_ots: "slot3_ots_c1.jpg",
  slot4_watch: "slot4_watch_c1.jpg",
  mac0_studio: "mac0_studio_c2.jpg",
  mac2_cook: "mac2_cook_c1.jpg",
  mac3_direct: "mac3_direct_c1.jpg",
};

// Everything the manifest uses that is NOT a raw candidate: the "what the
// camera sees" previews, and the edits that fixed a scene's staging.
//
// IMPORTANT — these prompts are RECONSTRUCTED by reading the committed images,
// not the verbatim text originally typed. That was passed as an argv string and
// never recorded anywhere. They describe the same transformation and produce an
// equivalent asset; they will NOT reproduce the committed file pixel for pixel,
// because the model is not deterministic. Treat them as the recipe, not the
// receipt. Crop entries, by contrast, are exact: their boxes were recovered by
// matching the committed crop against its parent.
const DERIVED = {
  // ---- Scene edits ----
  "slot3_ots_c1p.jpg": {
    from: ["slot3_ots_c1.jpg"],
    aspect: "9:16",
    prompt: `Keep this photograph exactly as it is, with one change: rotate the
small smartphone clamped to the flexible tripod beside the bird feeder so it
stands in PORTRAIT orientation, taller than it is wide, its screen still facing
the viewer and completely black and switched off. Do not change the woman, the
phone in her hand, the feeder, the cardinal, the railing, the light, or the
background.`,
  },
  "mac3_direct_e1.jpg": {
    from: ["mac3_direct_c1.jpg"],
    aspect: "9:16",
    prompt: `Keep this room, window, laptop, desk and the woman exactly as they
are, with two changes: move the wooden bird feeder and the cardinal perched on
it OUTSIDE the window, into the garden behind the glass, so the window frame
clearly separates them from the room; and rotate the smartphone clamped to the
flexible tripod beside the feeder into PORTRAIT orientation. Every screen stays
completely black and switched off.`,
  },
  "mac0_studio_e2.jpg": {
    from: ["mac0_studio_c2.jpg"],
    aspect: "9:16",
    prompt: `Keep this studio scene exactly as it is and add the subject being
photographed: on the white product table in front of the professional camera, a
luxury wristwatch with a dark leather strap, being adjusted by a hand in a white
cotton glove reaching in from the right. The camera on the tripod points at the
watch. Every device screen stays completely black and switched off.`,
  },

  // ---- "What the camera sees" previews ----
  // Each renders the scene's subject alone, from the camera device's position,
  // at the aspect that device would actually deliver. Crop the subject out of
  // the scene with `tools.py crop` and pass it as a second reference when the
  // pose needs to match exactly.
  "slot0_ots_preview.jpg": {
    from: ["slot0_ots_c1.jpg"],
    aspect: "9:16",
    prompt: `Render only what the tripod-mounted camera phone in this scene is
pointed at, as a clean full-frame product photograph: the luxury wristwatch
standing on its small white plinth against the seamless white studio backdrop,
softbox-lit. No devices, no people, no tripod in frame.`,
  },
  "slot1_preview.jpg": {
    from: ["slot1_group_c2.jpg"],
    aspect: "16:9",
    prompt: `Render only what the tripod-mounted camera phone in this scene is
pointed at, as a clean full-frame photograph: the whole multi-generation family
sitting together on the picnic blanket, everyone looking at the camera, the
picnic basket in front of them. Same warm golden light and string lights and
greenery behind. No devices, no tripod in frame.`,
  },
  "slot3_preview.jpg": {
    from: ["slot3_ots_c1p.jpg"],
    aspect: "9:16",
    prompt: `Render only what the tripod-mounted camera phone in this scene is
pointed at, as a clean full-frame photograph shot on a telephoto lens: the
rustic wooden bird feeder with the bright red cardinal perched on its ledge,
framed TIGHT so the bird and the feeder ledge fill most of the frame and the
bird is large enough to read at a glance. Same morning light, dewy greens,
softly blurred garden behind. No devices, no people, no porch railing in
frame.`,
  },
  "slot4_preview.jpg": {
    from: ["slot4_watch_c1.jpg"],
    aspect: "9:16",
    prompt: `Render only what the phone clamped to the telescope eyepiece in this
scene is pointed at, as a clean full-frame photograph: the bright full moon,
sharp and detailed, filling much of the frame against a black night sky. No
devices, no people, no telescope in frame.`,
  },
  "mac0_preview.jpg": {
    from: ["mac0_studio_e2.jpg"],
    aspect: "16:9",
    prompt: `Render only what the professional camera on the tripod in this scene
is pointed at, as a clean full-frame product photograph: the luxury wristwatch
with the dark leather strap lying on the white product table, a hand in a white
cotton glove adjusting it. Softbox-lit, bright and premium. No devices, no
tripod in frame.`,
  },
  "mac2_preview.jpg": {
    from: ["mac2_cook_c1.jpg"],
    aspect: "16:9",
    prompt: `Render only what the overhead phone on the under-cabinet arm in this
scene is pointed at, as a clean full-frame overhead photograph shot straight
down: the round wooden charcuterie board on the kitchen counter, loaded with
cured meats, cheeses, figs, grapes, nuts, olives and edible flowers, with a hand
reaching in to place a sprig of rosemary. No devices, no arm in frame.`,
  },
  "mac3_preview.jpg": {
    from: ["mac3_direct_e1.jpg"],
    aspect: "16:9",
    prompt: `Render only what the phone clamped beside the feeder in this scene is
pointed at, as a clean full-frame photograph: the rustic wooden bird feeder with
the bright red cardinal perched on its ledge, framed TIGHT so the feeder and the
bird fill most of the frame, softly blurred garden foliage behind. No devices,
no window frame, no people in frame.`,
  },
  "mac3_preview_port.jpg": {
    from: ["mac3_direct_e1.jpg"],
    aspect: "9:16",
    // Committed at 1295x2752 (aspect 0.47) rather than the 1536x2752 the model
    // returns: that near-phone aspect is what makes the frame reach the top and
    // bottom edges of a portrait screen in slots 2 and 2i. The trim was not
    // recorded; a centred crop reproduces the committed framing.
    crop: { from: "mac3_preview_port.jpg", box: [120, 0, 1415, 2752] },
    prompt: `Render a tight close-up of what the phone clamped beside the feeder
in this scene is pointed at, as a clean full-frame photograph: the bright red
cardinal filling most of the frame, perched on the weathered wooden ledge with
seed scattered around it, softly blurred green foliage and a wooden post behind.
No devices, no window frame, no people in frame.`,
  },

  // ---- Deterministic crops (exact; boxes recovered from the committed files) ----
  "mac2_cook_c1_crop.jpg": {
    crop: { from: "mac2_cook_c1.jpg", box: [0, 440, 1536, 2210] },
  },
};

async function callModel(parts, aspectRatio) {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
    {
      method: "POST",
      headers: { "x-goog-api-key": KEY, "content-type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts }],
        generationConfig: {
          responseModalities: ["IMAGE"],
          imageConfig: { aspectRatio, imageSize: "2K" },
        },
      }),
    },
  );
  if (!res.ok) { console.error(`HTTP ${res.status}: ${(await res.text()).slice(0, 500)}`); process.exit(1); }
  const data = await res.json();
  const part = data.candidates?.[0]?.content?.parts?.find((p) => p.inlineData);
  if (!part) { console.error(`no image in response: ${JSON.stringify(data).slice(0, 500)}`); process.exit(1); }
  return part.inlineData;
}

function save(file, inline) {
  writeFileSync(file, Buffer.from(inline.data, "base64"));
  console.log(`saved ${file}`);
}

mkdirSync(OUT_DIR, { recursive: true });

if (process.argv[2] === "derive") {
  const want = process.argv[3];
  if (!want) {
    console.log("recorded derivations:\n");
    for (const [out, d] of Object.entries(DERIVED)) {
      const how = d.prompt ? `edit of ${d.from.join(", ")} @ ${d.aspect}` : "crop";
      console.log(`  ${out.padEnd(26)} ${how}${d.crop && d.prompt ? " + crop" : ""}`);
    }
    console.log("\nbase scenes kept from PROMPTS:\n");
    for (const [id, file] of Object.entries(CHOSEN)) console.log(`  ${file.padEnd(26)} node generate.mjs ${id}`);

    // Coverage: every scene the manifest renders must be remakeable. Without
    // this the gap is invisible until someone tries to change a scene and finds
    // the recipe was never written down.
    const manifest = readFileSync(join(here, "manifest.js"), "utf8");
    const used = [...new Set(manifest.match(/\.\.\/ai-scenes\/[\w.-]+/g) || [])]
      .map((p) => p.replace("../ai-scenes/", ""));
    const known = new Set([...Object.keys(DERIVED), ...Object.values(CHOSEN)]);
    const orphans = used.filter((f) => !known.has(f));
    console.log(`\ncoverage: ${used.length - orphans.length}/${used.length} manifest scenes have a recipe`);
    for (const f of orphans) console.log(`  NO RECIPE: ${f}`);
    process.exit(orphans.length ? 1 : 0);
  }
  const d = DERIVED[want];
  if (!d) { console.error(`no recorded derivation for ${want}; have: ${Object.keys(DERIVED).join(", ")}`); process.exit(1); }
  // `--as <name>` writes somewhere else, so a regeneration can be compared
  // against the committed asset before it replaces it. The model is not
  // deterministic; you always want to look before you overwrite.
  const asIdx = process.argv.indexOf("--as");
  const outName = asIdx > 0 ? process.argv[asIdx + 1] : want;
  if (d.prompt) {
    const parts = d.from.map((f) => ({
      inlineData: { mimeType: "image/jpeg", data: readFileSync(join(OUT_DIR, f)).toString("base64") },
    }));
    parts.push({ text: d.prompt });
    save(join(OUT_DIR, outName), await callModel(parts, d.aspect));
  }
  if (d.crop) {
    const [x0, y0, x1, y1] = d.crop.box;
    // tools.py owns image manipulation; this script stays dependency-free.
    console.log(`then crop:\n  python3 tools.py crop ../ai-scenes/${d.crop.from} ${x0} ${y0} ${x1} ${y1} ../ai-scenes/${want}`);
  }
} else if (process.argv[2] === "edit") {
  // input may be several comma-separated reference image paths
  const [input, outFile, prompt, aspect = "9:16"] = process.argv.slice(3);
  const parts = input.split(",").map((p) => ({
    inlineData: {
      mimeType: p.endsWith(".png") ? "image/png" : "image/jpeg",
      data: readFileSync(p).toString("base64"),
    },
  }));
  parts.push({ text: prompt });
  const inline = await callModel(parts, aspect);
  save(join(OUT_DIR, outFile), inline);
} else {
  const id = process.argv[2];
  const count = Number(process.argv[3] || 1);
  const aspect = process.argv[4] || "9:16";
  if (!PROMPTS[id]) { console.error(`unknown scene id; have: ${Object.keys(PROMPTS)}`); process.exit(1); }
  for (let i = 1; i <= count; i++) {
    const inline = await callModel([{ text: PROMPTS[id] }], aspect);
    const ext = inline.mimeType?.includes("jpeg") ? "jpg" : "png";
    save(join(OUT_DIR, `${id}_c${i}.${ext}`), inline);
  }
}
