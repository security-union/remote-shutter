# Remote Shutter — App Store Marketing Prompt Pack

AI-generated lifestyle scenes for the App Store screenshot set. Scenes are generated
with Imagen / Nano Banana Pro (stills) or Veo (video → frame grab) in Google AI Studio
or Flow. The device screens in the generated scene are **not** used — the pipeline in
`store_assets/screenshot-pipeline/` composites real app UI into a clean device mockup,
so screenshots stay compliant with App Review guideline 2.3.3 (genuine app UI).

## Art direction (applies to every scene)

- Apple advertising style: bright, airy, natural light, believable candid moment.
- Neutral palette (warm whites, soft grays, muted tones), one warm accent max.
- Shallow depth of field, 35–85mm look, photorealistic, high dynamic range.
- **Unbranded modern smartphones** (no Apple logo, no visible UI, screens dark/off).
- No text, no logos, no watermarks anywhere in frame.
- Portrait **9:16**, highest available resolution.
- Subjects framed in the **upper two thirds** — the bottom third gets covered by the
  device mockup overlay, so keep it simple (ground, grass, floor, table surface).

## How to generate & deliver

1. Open Google AI Studio (Imagen / Nano Banana Pro) or Flow.
2. Generate 3–4 candidates per prompt below, aspect ratio 9:16.
3. Reject candidates with: warped hands, phone screens showing content, readable
   text/brands, subjects too low in frame.
4. Save selects as `store_assets/ai-scenes/slot<N>_v<K>.png` (e.g. `slot0_v1.png`).

---

## Slot 0 — Hero: studio product shoot, iPhone on tripod + iPad remote

Scene: a professional photographer shooting product photos in a studio. The camera
is an unbranded smartphone locked on a high-end tripod aimed at the product set; the
photographer stands away from it holding a tablet as her wireless monitor. This is
the strongest "why this app exists" scenario: the camera can't be touched without
ruining the shot, so she controls it remotely.

### Still prompt — V1 · Product tabletop set (primary)

> Commercial photography in the style of an Apple ad: a professional female
> photographer in a bright, minimal photo studio doing a product shoot. In the
> midground, an unbranded modern smartphone is mounted on a high-end carbon-fiber
> tripod with a geared head, aimed at a small product table where a luxury watch sits
> under a softbox — the phone's screen is dark and off. The photographer stands a few
> steps away in the upper right of the frame, holding a large unbranded tablet in both
> hands like a camera monitor, screen dark and off, looking at it with focused
> confidence. White cyclorama wall, softbox and reflector visible, soft high-key
> daylight balance, shallow depth of field, 35mm lens look, photorealistic, neutral
> warm palette. All subjects framed in the upper two thirds; the lower third is clean
> studio floor. No text, no logos, no watermarks. Vertical 9:16.

### Still prompt — V2 · Sneaker shoot, dramatic light

> Commercial photography in the style of an Apple ad: a professional photographer in
> a modern studio shooting a designer sneaker on a pedestal lit by a single softbox.
> An unbranded smartphone on a professional tripod faces the pedestal, screen dark.
> The photographer, wearing a black tee, stands well off to the side holding an
> unbranded tablet as a wireless monitor, screen dark, one hand hovering over it.
> Charcoal-gray backdrop, rim lighting, controlled shadows but overall bright and
> premium, shallow depth of field, photorealistic. Subjects in the upper two thirds;
> lower third is simple dark studio floor. No text, no logos, no watermarks.
> Vertical 9:16.

### Still prompt — V3 · Portrait session behind glass

> Commercial photography in the style of an Apple ad: a professional photographer
> directing a seated portrait session in a bright loft studio. An unbranded smartphone
> on a heavy-duty tripod with a ring light faces the model; the photographer stands
> apart near a large window holding an unbranded tablet in one hand as her remote
> monitor, gesturing direction with the other hand. Both device screens dark and off.
> Airy daylight, white brick and wood floor, shallow depth of field, photorealistic,
> warm neutral palette. Subjects in the upper two thirds; simple floor in the lower
> third. No text, no logos, no watermarks. Vertical 9:16.

### Veo video prompt (website / social follow-up, and frame grabs)

> Cinematic 8-second commercial in the style of an Apple ad, single continuous shot:
> inside a bright minimal photo studio, the camera dollies slowly past a smartphone
> mounted on a high-end tripod aimed at a product table with a luxury watch under a
> softbox, revealing a professional photographer several steps away holding a tablet
> as a wireless monitor. She taps the tablet once and glances up at the set with a
> satisfied nod. Soft high-key light, shallow depth of field, photorealistic, phone
> and tablet screens dark, no on-screen text. 9:16 vertical.

---

## Scene ideas bank (candidates for slots 1–5 and campaigns)

Each scene answers "why can't I just walk over to the camera?" — that's what makes
the remote story land.

| # | Scene | Why it sells | Caption idea |
|---|---|---|---|
| A | Golden-hour park: two friends, one poses, one holds the remote phone, second phone on a bench tripod | Relatable mass-market hero | "One phone is the camera. The other is the remote." |
| B | Multi-generation family group photo in a backyard; the person holding the remote is IN the shot | #1 real use case | "Everyone's in the shot. Including you." |
| C | Wildlife: phone on a low tripod near a bird feeder / squirrel, photographer watches the live view from the porch 40 ft away | Distance is physically required — perfect "why" | "Get close. Without getting close." |
| D | Night sky: phone clamped to a telescope eyepiece mount, stargazer triggers from their wrist (Apple Watch) — ties to the Watch feature | Touching the rig ruins the shot; Watch hero | "NEW — Fire the shutter from your wrist." |
| E | Sleeping newborn in a crib, phone on a small tripod above, parent watches the live preview from the couch | Emotional + silence required | "Never wake the baby." |
| F | Skate park: phone lying at ramp edge for a low wide angle, skater's friend triggers from the fence | Creative angles + phone-in-harm's-way | "Angles you'd never reach." |
| G | Solo creator on set checking their own framing on an iPad while standing in the shot | Growing creator segment | "Direct yourself." |
| H | Overhead flat-lay food/product rig, phone on a boom arm, monitor at eye level | Pro/studio second scenario | "The top-down shot, without the ladder." |
| I | Wedding reception photo-booth: phone on tripod, guests trigger group shots from an iPad on a stand | Event/party use case | "The photo booth you already own." |

Slot plan (after slot 0 sign-off): 1 = B (group photo), 2 = clean UI callout (no
scene), 3 = C or F, 4 = D (Watch), 5 = connection diagram ("No internet. No
account. Just connect.").
