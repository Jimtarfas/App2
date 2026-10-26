# Phone Cleaner: Clean Up Photos

An iPhone app (SwiftUI, iOS 17+) that frees up photo and video storage. It finds duplicate and similar photos with Vision feature prints, lists screenshots and large videos, and has a swipe screen to keep or delete photos one at a time. It only claims photo and video storage; it makes no "speed up" claims.

- **App Store name:** Phone Cleaner: Clean Up Photos (Apple ID 6826949859)
- **Bundle ID:** `com.cleanupphotos.app`
- **Team:** ZUCC9R4PP4
- **Minimum iOS:** 17.0 (iPhone only)

## How it works

| Piece | Where |
|---|---|
| Scan, grouping, deleting, storage-freed total, free-plan allowance | `PhoneCleaner/Model/Cleaner.swift` |
| Vision feature prints (revision 2), dHash, duplicate and similar grouping, fingerprint cache | `PhoneCleaner/Model/SimilarityScanner.swift` |
| StoreKit 2: weekly and yearly (3-day free trial) plans, entitlements, restore | `PhoneCleaner/Store/Store.swift` |
| Paywall with pricing, trial terms, Restore, Terms and Privacy links | `PhoneCleaner/Views/PaywallView.swift` |
| Swipe to keep or delete, review sheet, undo | `PhoneCleaner/Views/SwipeView.swift` |

- **Duplicates:** photos with the same 64-bit difference hash, or neighbours in time, whose feature-print distance is at most 0.17 and whose aspect ratios match.
- **Similar photos:** runs of photos taken within 15 minutes of each other with a feature-print distance of at most 0.45.
- The suggested keeper in each group is a favorite, then the highest resolution, then the largest file.
- Fingerprints are cached in `Caches/fingerprints-v2.plist`, so a rescan only analyzes new or edited photos.
- Deletions go through `PHAssetChangeRequest.deleteAssets`, so iOS asks to confirm and items land in Recently Deleted.
- The free plan deletes 20 items a day. Premium removes the limit.
- In the simulator Vision can't run its model, so the scanner compares 16×16 colour thumbnails instead (`#if targetEnvironment(simulator)` only).

## Build

```bash
xcodegen generate
open PhoneCleaner.xcodeproj
```

Keep build output outside `~/Desktop`, because codesign fails there. Archives go to `~/Builds/APP2`.

`PhoneCleaner/Store/Products.storekit` mirrors the App Store Connect products for local StoreKit testing from Xcode.

### Debug launch arguments

Debug builds accept `-route duplicates|similar|screenshots|videos|swipe|settings|paywall` to open a screen at launch, and `-swipeDemo YES` to leave the swipe screen mid-swipe for screenshots. Any `@AppStorage` key can be overridden the same way, for example `-introPaywallShown YES -freeDeletesUsed 0`.

## Scripts

- `swift scripts/make-icon.swift PhoneCleaner/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` draws the app icon.
- `swift scripts/make-test-media.swift <photos-dir> <out-dir>` builds a test library (similar bursts, duplicates, large videos) from a few photos.
- `swift scripts/make-store-screenshots.swift marketing/screenshots/raw marketing/screenshots` frames the store screenshots at 6.9" and 6.5".

## Store listing

`marketing/listing.json` holds the name, subtitle, keywords, description, promotional text and review notes. The name is keyword-first, chosen from DataForSEO `keywords_for_app` data for the top three competitors (Cleanup, Cleaner Kit, Phone Storage Cleaner); see `marketing/aso.md`.

## Website

`docs/` holds the landing page, privacy policy and support page. Because this repo is private, the pages are published from the public repo `Jimtarfas/phone-cleaner-site` to https://jimtarfas.github.io/phone-cleaner-site/. Copy `docs/` there to update it.
