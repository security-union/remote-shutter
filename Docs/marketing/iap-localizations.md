# In-App Purchase Localizations

IAP display names and descriptions for all 10 App Store locales live in
[`fastlane/iap_localizations.json`](../../fastlane/iap_localizations.json)
(display name ≤30 chars, description ≤45 chars).

To sync App Store Connect to that file, run the **Sync IAP Localizations**
workflow (GitHub → Actions → workflow_dispatch), or locally with ASC key env
vars set:

```bash
bundle exec fastlane ios sync_iap
```

The lane creates missing locales and updates changed ones (idempotent — it
skips entries that already match). Metadata changes to approved IAPs go into
review with the next app submission.

Products: `05` Remove Ads · `06` Pro: All Features · `07` Torch Control · `08` Video Recording
