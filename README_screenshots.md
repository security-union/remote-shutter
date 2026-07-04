# App Store Screenshots

The screenshot system lives in
[`store_assets/screenshot-pipeline/`](store_assets/screenshot-pipeline/README.md)
— AI-generated lifestyle scenes with the real app UI composited in, rendered
deterministically for all 10 App Store locales (no AI calls at render time).

```bash
cd store_assets/screenshot-pipeline
./ship-locales.sh        # regenerate everything -> fastlane/screenshots/
```

- Localized strings: edit `store_assets/screenshot-pipeline/translations.js`, re-run the script.
- New screenshots / scene changes: see the "Adding a new screenshot" section of
  the pipeline README — it documents the Claude Code prompts and the manual steps.
- Marketing scene prompts and art direction: [`docs/marketing/prompt-pack.md`](docs/marketing/prompt-pack.md).
