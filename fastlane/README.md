fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios load_asc_api_key

```sh
[bundle exec] fastlane ios load_asc_api_key
```

Load ASC API Key information to use in subsequent lanes

### ios sync_iap

```sh
[bundle exec] fastlane ios sync_iap
```

Sync in-app purchase & subscription localizations on ASC from fastlane/iap_localizations.json

### ios sync_product_page

```sh
[bundle exec] fastlane ios sync_product_page
```

Upload the product page header + search results art from fastlane/product_page/

to the iOS version being prepared (iOS 27 creative assets).

Options:

  locales — comma-separated subset, e.g. locales:en-US,ja (default: all)

  overwrite — when true, replace art already placed on a locale. Apple has

    no update call, so replacing means deleting the old placement first.

    Default false: the run stops before uploading if any target is taken.

### ios release

```sh
[bundle exec] fastlane ios release
```

Build and upload to App Store Connect

Options:

  overwrite_screenshots — when true (default) delete ALL screenshots on

    ASC and re-upload fastlane/screenshots/; when false, leave ASC

    screenshots untouched (skip them entirely). e.g.

    fastlane release overwrite_screenshots:false

### ios release_mac

```sh
[bundle exec] fastlane ios release_mac
```

Build the Mac Catalyst app and upload to App Store Connect (macOS platform)

Options:

  overwrite_screenshots — when true (default) delete ALL Mac screenshots

    on ASC and re-upload fastlane/screenshots_mac/; when false, leave ASC

    screenshots untouched (skip them entirely). e.g.

    fastlane release_mac overwrite_screenshots:false

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
