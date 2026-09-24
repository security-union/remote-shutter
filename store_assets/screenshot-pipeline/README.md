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
| `tools.py` | Quad helpers: `detect` (find a screen's corners), `overlay` (draw a quad to verify), `zoom`, `crop`; plus `find-logo`/`strip-logos` (below), `chrome` (chrome overlays, below) and `grid` (multicam wall: composite N camera previews, aspect-fit, under a real window capture's keyed chrome — see `mac2_multicam_grid.png`'s recipe below) |
| `logo-patches.json` | The brand marks to clone out of a generated scene, and where to take clean pixels from — the `strip-logos` table |
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

## The multicam grid screen

`assets/raw/monitor-mac-multicam.png` is a real Catalyst window capture over a
black viewfinder (Cmd-Shift-4 + Space). The composed 4-cam monitor is fully
deterministic from it and the four scene-derived tile previews:

```bash
python3 tools.py grid assets/raw/monitor-mac-multicam.png ../ai-scenes/mac2_multicam_grid.png \
  --tiles ../ai-scenes/mac2_multicam_preview_wide.jpg ../ai-scenes/mac2_multicam_preview_side.jpg \
          ../ai-scenes/mac2_preview.jpg ../ai-scenes/mac2_multicam_preview_pan.jpg \
  --disc 730,850,180,150 --titlebar 34
```

Tiles are aspect-fit (the app's own letterboxing — a portrait camera
pillarboxes honestly); the chrome is value-keyed off the black capture and
re-laid on top, same physics as the `chrome` command.

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

## Changing a scene

Every image `manifest.js` renders traces back to a recorded recipe in
`generate.mjs`, so a scene can be changed rather than reverse-engineered:

```bash
node generate.mjs derive            # list every recipe + coverage check
node generate.mjs derive slot3_preview.jpg --as try.jpg   # remake, don't clobber
```

Three kinds of recipe:

- **`PROMPTS`** — the base scenes. `CHOSEN` records which candidate the manifest
  kept, since `node generate.mjs <id> N` writes `<id>_c1..cN`.
- **`DERIVED`** — the "what the camera sees" previews and the edits that fixed a
  scene's staging (a phone rotated to portrait, a feeder moved outside a window).
- **crops** — exact boxes, recovered by matching each committed crop against its
  parent.

`node generate.mjs derive` with no argument also checks that every manifest
reference has a recipe, and exits non-zero if one doesn't. Add a scene, add its
recipe — otherwise the gap stays invisible until someone tries to change it.

**The `DERIVED` prompts are reconstructions.** The originals were typed as argv
strings and never recorded; these were rebuilt by reading the committed images.
They produce an equivalent asset, not the same pixels — the model is not
deterministic. Always `--as` and compare before overwriting.

Worked example — swapping the cardinal for another animal:

1. Edit the `slot3_ots`, `slot3_ipad` and `mac3_direct` prompts in `PROMPTS`.
2. `node generate.mjs slot3_ots 3`, pick a candidate, update `CHOSEN`.
3. Re-run the staging edits that sit on top (`slot3_ots_c1p`, `mac3_direct_e1`).
4. Re-measure the quads — the phone lands somewhere new. `tools.py detect`, then
   ALWAYS `tools.py overlay` to check.
5. Re-run the previews (`slot3_preview`, `mac3_preview`, `mac3_preview_port`)
   so the remote screens show the same animal the in-scene camera is pointed at.
6. `./ship-locales.sh`.

## Rendering a UI capture from the app itself

`assets/raw/*.png` do not have to be hand-captured on a device. `SnapshotTestCase`
hosts any SwiftUI screen in a real window at any size, so a test can seed a view
model and write a PNG of the true app UI at true device pixels — which is more
2.3.3-correct than reusing another platform's capture, and unblocks device sizes
nobody has captured. `MulticamGridSnapshotTests` (in
`RemoteCamTests/MulticamViewModelTests.swift`) renders the 4-lane director grid
and the camera standby screen:

```bash
mkdir -p /tmp/rs-tiles && cp <four tile jpgs> /tmp/rs-tiles/{1,2,3,4}.jpg
xcodebuild test -workspace RemoteShutter.xcworkspace -scheme RemoteCam \
  -destination 'platform=iOS Simulator,OS=18.5,name=iPad (A16)' \
  -configuration Release -only-testing:RemoteShutterTests/MulticamGridSnapshotTests \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  SWIFT_ENABLE_TESTABILITY=YES ENABLE_TESTABILITY=YES
# -> /tmp/rs-out/*.png
```

Three things that are not obvious:

- **Release, not Debug.** `MulticamView` draws `SessionDebugOverlay()` under
  `#if DEBUG` and it renders as a yellow bug badge on the screenshot. Release
  strips `-enable-testing`, hence the two testability flags.
- **Environment variables never reach a hosted unit test** — not plain, not
  `TEST_RUNNER_`-prefixed (that is for UI-test runners). The paths are fixed and
  the test skips when `/tmp/rs-tiles` is absent, so CI ignores it.
- **Set published fields directly**, not through `updateStatus`: that hops to
  main and the render beats it, so the screen comes out with the defaults.

## Stripping brand marks (the last stage of a scene's chain)

Nano Banana paints an Apple logo on a phone back every few generations. There is
no way to prompt it away — the Gemini family has no negative prompt, so "no
logo" mostly injects one — and re-rolling gambles away a scene that is otherwise
right. So the mark comes off in post, from a table, and the generated original
is never edited in place:

```bash
python3 tools.py find-logo ../ai-scenes/SCENE.jpg X0 Y0 X1 Y1   # measure the box
python3 tools.py strip-logos --preview                          # apply the table
```

`find-logo` takes a window over the surface, reports the darkest blob's
bounding box and prints a ready-made `logo-patches.json` fragment. Each entry
maps an `in` scene to an `out` scene and lists patches; a patch clones the
rectangle at `from` (an offset into the *same* surface, so grain and lighting
already match) over `box`, feathered, with the source's exposure scaled to the
ring around the destination.

Three things to hold on to:

- **Size the box generously.** The feather ring blends the original back in at
  the box edge, so a box that only just contains the mark leaves a ghost of it.
  Leave more margin than `feather` on every side.
- **`find-logo` is a locator, not a pass/fail detector.** On a surface that is
  already flat it just returns the window's noise. Confirm removal by looking at
  the `--preview` before/after sheet.
- **Set `SCRATCHPAD`** before using `--preview`; `tools.py`'s built-in default
  points at an old session directory.

Turning a phone around usually removes the problem for free: a camera correctly
aimed at the subject shows the viewer its *screen*, and a screen carries no
logo. See the aim rule under Gotchas.

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
   `node generate.mjs <sceneId> 2`, then record the candidate you keep in
   `CHOSEN`. Scenes must show device screens *black/off*, subjects in the upper
   two thirds, no logos (reject candidates with Apple logos). Requires a Google
   AI Studio key in `AI_STUDIO`.
2. **Derive the preview** — what the camera device sees, seeded from the scene
   itself for consistency. Add a `DERIVED` entry and run
   `node generate.mjs derive <out.jpg>`; use `edit` only while you are still
   iterating on the wording. Crop the subject with `python3 tools.py crop` and
   pass it as a second reference so pose/orientation match exactly.
3. **Find the screen quads** — `python3 tools.py detect <scene> X0 Y0 X1 Y1`,
   then ALWAYS verify with `python3 tools.py overlay <scene> TLx TLy ... --out q.png`.
   AI-image device edges bow slightly: trust locally-measured corners over global
   line fits, and check that rendered UI rows sit parallel to the device's bottom edge.
4. **Add the slot to `manifest.js`** (scene, quads, UI capture, preview, callouts)
   and to the `PLANS` slot lists in `render.mjs` (iPhone and/or iPad variants).
5. **Add strings to `translations.js`** for all 15 locales.
6. `./ship-locales.sh` and review the output.

## Gotchas (learned the hard way)

**Edit hops cost detail everywhere, not just where you edited.** Each
`generate.mjs edit` re-encodes the whole frame. Measured on a wall region no edit
ever touched, a four-hop chain kept 64% of the original high-frequency detail;
collapsing the same changes into one hop off the sharp seed kept 115%. When a
scene needs several changes, make them in ONE edit from the sharpest ancestor
rather than a change per hop, and measure before you accept:

```python
a = np.asarray(Image.open(f).convert("L").crop(untouched_box), dtype=float)
detail = (np.diff(a, axis=1)**2).mean() + (np.diff(a, axis=0)**2).mean()
```

**A surface has no occlusion mask.** The template warps the UI onto the quad and
paints it, so anything crossing the glass in the photo — a clamp arm, a thumb —
gets painted out. Either pick a quad whose screen is unobstructed, or leave that
screen alone.

**Which way a camera faces.** The lenses look out of the phone's back, and the
viewer's eye sits about where the director sits — *behind* the camera phones,
further from the subject than they are. So a phone correctly aimed at the
subject shows the viewer its **pure black switched-off screen**. If you can see
the lens array, that camera is filming the viewer. Only a phone placed past the
subject, aiming back toward the director's side, correctly shows its lenses.
Write the edit prompt as the viewer-visible outcome and get the side right;
never ask to see the back *and* the lens bump on a camera meant to aim away.


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
