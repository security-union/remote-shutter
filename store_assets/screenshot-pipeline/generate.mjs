#!/usr/bin/env node
// Generates AI lifestyle scenes for the App Store screenshots via the Gemini API
// (Nano Banana Pro). Requires AI_STUDIO env var (aistudio.google.com API key).
// Prompts mirror docs/marketing/prompt-pack.md.
// Usage:
//   node generate.mjs <sceneId> [count]                 e.g. node generate.mjs slot0_v1 2
//   node generate.mjs edit <inputImg> <outFile> <prompt> [aspect]
//     image-to-image, e.g. deriving "what the camera phone sees" from a scene
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

if (process.argv[2] === "edit") {
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
  if (!PROMPTS[id]) { console.error(`unknown scene id; have: ${Object.keys(PROMPTS)}`); process.exit(1); }
  for (let i = 1; i <= count; i++) {
    const inline = await callModel([{ text: PROMPTS[id] }], "9:16");
    const ext = inline.mimeType?.includes("jpeg") ? "jpg" : "png";
    save(join(OUT_DIR, `${id}_c${i}.${ext}`), inline);
  }
}
