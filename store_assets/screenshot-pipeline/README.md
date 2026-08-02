# App Store Screenshot Pipeline

Generates every App Store screenshot (15 locales × iPhone/iPad/Mac) plus the
In-App Event banner from AI-generated lifestyle scenes with the **real app UI**
composited onto the in-scene device screens. Rendering is fully deterministic —
no AI calls, no manual image editing.

## TL;DR — rerun everything

```bash
cd store_assets/screenshot-pipeline
./ship-locales.sh              # render all 15 locales -> fastlane/screenshots/<locale>/
./ship-locales.sh it ja        # or just specific locales
./ship-locales.sh -p mac       # only one platform (iphone,ipad,mac,banner); others untouched
./ship-locales.sh -p mac it ja # combine: platform subset x locale subset
node render.mjs                # render en-US only, into out/ (no fastlane copy)
node render.mjs --locale de-DE # render one locale into out/de-DE/
node render.mjs --plans mac    # render only one device plan
node render.mjs 0 banner       # re-render only specific slots
```

Merging the PR ships them: CI's `fastlane release` uploads `fastlane/screenshots/`
and `fastlane/metadata/` to App Store Connect.

## Files

| File | Purpose |
|---|---|
| `manifest.js` | The layout source of truth: per-slot scene image, screen quads, UI captures, callouts, mockup config |
| `translations.js` | **All localized strings** (headlines, sublines, callout labels) for the 15 locales |
| `template.html` | Renders one slot in headless Chrome: caption + scene + perspective-mapped screens + callouts |
| `render.mjs` | Drives Chrome over the slot × device matrix (`PLANS`), crops to exact pixels |
| `ship-locales.sh` | Renders every locale and syncs `fastlane/screenshots/<locale>/` (cleans stale files, keeps Watch captures) |
| `generate.mjs` | Nano Banana (Gemini) scene generation/editing — needs `AI_STUDIO` env var; only used when creating **new** scenes |
| `tools.py` | Quad helpers: `detect` (find a screen's corners), `overlay` (draw a quad to verify), `zoom`, `crop`; plus `chrome` (chrome overlays, below) |
| `assets/` | Chrome overlays composited onto device screens |
| `assets/raw/` | The unmodified device captures each overlay is derived from |
| `../ai-scenes/` | Generated scene photos + "what the camera sees" preview shots |

## The viewfinder: how a remote screen is composited

The remote is a full-bleed preview under floating glass chrome, so the chrome
overlaps the picture and cannot be a flat capture pasted behind a preview
rectangle. Each remote screen is instead built in three layers — black, the
frame aspect-fit (`object-fit: contain`, the app's own letterboxing), then a
**chrome overlay**: a straight-alpha RGBA layer keyed from a real capture.

A capture taken over a **black** viewfinder is exactly the chrome premultiplied
over black, so the value channel recovers it: `alpha = max(R,G,B)`,
`color = pixel/alpha`. That is exact over black, and over a bright frame it
produces the same washed-out light glass the real app shows — dark-mode
`.ultraThinMaterial` is additive light over its backdrop. The value channel is
used rather than luma so the gold accent and the red record disc keep their hue.

`tools.py chrome` does the keying. Two regions need help: `--blank` zeroes the
device status bar (the template redraws a clean 9:41 one) and anything else that
must not ship, and `--disc` finds the shutter — a white disc with a *black* ring
drawn inside it, which would otherwise key to a hole — and forces it opaque.
`--opaque` does the same for a region known to be solid, like a Mac title bar.

```bash
# Regenerate the overlays from assets/raw/ (what produced the committed ones)
python3 tools.py chrome assets/raw/monitor-iphone.png assets/ui-monitor-iphone.png \
  --blank 0,0,1170,125 --blank 283,155,425,150 --disc 0,1700,1170,832
python3 tools.py chrome assets/raw/monitor-ipad.png assets/ui-monitor-ipad.png \
  --blank 0,0,1640,72 --disc 0,1600,1640,760
python3 tools.py chrome assets/raw/monitor-mac.png /tmp/mac_keyed.png \
  --opaque 55,37,1891,54 --disc 800,880,400,200
python3 tools.py crop /tmp/mac_keyed.png 55 37 1946 1089 assets/ui-monitor-mac.png
```

A slot opts in with `viewfinder: "<preview image>"` alongside its `ui:` overlay,
on either a perspective surface or a flat mockup. `viewfinderTop` (percent)
holds the frame below opaque chrome the app never draws under — on the Mac, the
window's title bar. One Mac overlay serves every Mac slot, because the preview is
composited rather than baked in.

**Taking a new capture**: run the remote with a peer connected and the camera
pointed at something black (a lens cap works), so the viewfinder is empty and
only the chrome is lit. Anything visible in the frame has to be blanked, so a
black frame is the whole job.

## Updating translations

Edit `translations.js` (plain text, keyed per locale), then re-ship the locale:

```bash
vim translations.js            # fix the string
./ship-locales.sh fr-FR        # re-render + sync that locale
```

Headlines are arrays of lines (`accentLine` marks the blue one), `sublines` are
the small gray lines under a headline (keyed by slot base id), `labels` map the
English callout text (CAMERA, REMOTE, …) to the localized pill text.

## Design system (keep it consistent)

- Light `#F5F5F7` caption band, SF Pro, black headline + one blue accent line.
- Every scene answers *"why can't I just walk to the camera?"*.
- CAMERA/REMOTE pill callouts with hairline leaders anchor the two-device story.
- Device screens show **genuine app UI** (App Review guideline 2.3.3): AI generates
  the scene with device screens black/off; the pipeline composites real captures.
- Whatever the camera device sees must match the remote's live preview
  (same subject, same orientation, same aspect: portrait camera ⇒ portrait preview).
- iPad screenshots must feature iPads, iPhone screenshots iPhones.
- The feature-callout slots (2, 2i, mac1) need a preview whose edges have
  contrast. Glass chrome over a bright, flat frame is legitimately near-invisible
  — accurate, and useless for a screenshot whose job is labelling the controls.
- No third-party brand names on a device screen. The camera-name chip carries
  whatever `AVCaptureDevice.localizedName` returns, so a capture made against a
  USB webcam has to have that chip blanked.

## Adding a new screenshot (the Claude workflow)

This pipeline was built with Claude Code and is easiest to extend the same way.
Example prompts that work well:

> *"Add a new App Store screenshot: [scenario, e.g. a skateboarder filming a low
> angle at a ramp]. Generate the scene with Nano Banana, composite the real UI,
> caption it '[headline]', add it as slot N for iPhone, and translate it for all
> locales."*

> *"Regenerate the scene for slot 3 but set it at a wedding reception."*

> *"Change slot 1's subline to [text] in all languages and re-ship."*

What Claude does under the hood (or do it manually):

1. **Generate the scene** — add a prompt to `generate.mjs` (`PROMPTS`), run
   `node generate.mjs <sceneId> 2`. Scenes must show device screens *black/off*,
   subjects in the upper two thirds, no logos (reject candidates with Apple logos).
   Requires a Google AI Studio key in `AI_STUDIO`.
2. **Derive the preview** — what the camera device sees, seeded from the scene
   itself for consistency: `node generate.mjs edit "<scene>,<crop>" out.jpg "<prompt>"`.
   Crop the subject with `python3 tools.py crop` and pass it as the second
   reference so pose/orientation match exactly.
3. **Find the screen quads** — `python3 tools.py detect <scene> X0 Y0 X1 Y1`,
   then ALWAYS verify with `python3 tools.py overlay <scene> TLx TLy ... --out q.png`.
   AI-image device edges bow slightly: trust locally-measured corners over global
   line fits, and check that rendered UI rows sit parallel to the device's bottom edge.
4. **Add the slot to `manifest.js`** (scene, quads, UI capture, preview, callouts)
   and to the `PLANS` slot lists in `render.mjs` (iPhone and/or iPad variants).
5. **Add strings to `translations.js`** for all 15 locales.
6. `./ship-locales.sh` and review the output.

## Gotchas (learned the hard way)

- Headless Chrome on macOS steals ~87px of window height even in `--headless=new`;
  `render.mjs` pads the window and crops — don't remove the `PAD`/crop step.
- The template is fully synchronous (canvas size + scene size come from query
  params/manifest); async image decodes race Chrome's load-event screenshot.
- Repo PNGs are in git-lfs; `git show HEAD:file | git lfs smudge` can silently
  return the wrong content — don't trust it for recovering committed images.
- Event banners (`out/<locale>/event_card_3840x2160.png`) are **not** fastlane
  assets — upload manually in App Store Connect when scheduling an In-App Event.
- Keyword/subtitle limits: keywords ≤100 chars, subtitle ≤30, promo ≤170 — check
  with `wc -c` before committing metadata.
