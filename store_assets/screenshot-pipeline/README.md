# App Store Screenshot Pipeline

Generates every App Store screenshot (10 locales × iPhone/iPad) plus the In-App
Event banner from AI-generated lifestyle scenes with the **real app UI**
composited onto the in-scene device screens. Rendering is fully deterministic —
no AI calls, no manual image editing.

## TL;DR — rerun everything

```bash
cd store_assets/screenshot-pipeline
./ship-locales.sh              # render all 10 locales -> fastlane/screenshots/<locale>/
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
| `translations.js` | **All localized strings** (headlines, sublines, callout labels) for the 10 locales |
| `template.html` | Renders one slot in headless Chrome: caption + scene + perspective-mapped screens + callouts |
| `render.mjs` | Drives Chrome over the slot × device matrix (`PLANS`), crops to exact pixels |
| `ship-locales.sh` | Renders every locale and syncs `fastlane/screenshots/<locale>/` (cleans stale files, keeps Watch captures) |
| `generate.mjs` | Nano Banana (Gemini) scene generation/editing — needs `AI_STUDIO` env var; only used when creating **new** scenes |
| `tools.py` | Quad helpers: `detect` (find a screen's corners), `overlay` (draw a quad to verify), `zoom`, `crop` |
| `assets/` | Real app UI captures composited onto screens (monitor iPhone/iPad, etc.) |
| `../ai-scenes/` | Generated scene photos + "what the camera sees" preview shots |

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
5. **Add strings to `translations.js`** for all 10 locales.
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
