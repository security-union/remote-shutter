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
  const aspect = process.argv[4] || "9:16";
  if (!PROMPTS[id]) { console.error(`unknown scene id; have: ${Object.keys(PROMPTS)}`); process.exit(1); }
  for (let i = 1; i <= count; i++) {
    const inline = await callModel([{ text: PROMPTS[id] }], aspect);
    const ext = inline.mimeType?.includes("jpeg") ? "jpg" : "png";
    save(join(OUT_DIR, `${id}_c${i}.${ext}`), inline);
  }
}
