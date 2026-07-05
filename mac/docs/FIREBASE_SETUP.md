# Firebase Remote Config & Sparkle Setup

## Remote Config

Import the parameter definitions from [`remote_config_template.json`](remote_config_template.json) into Firebase Console → Remote Config, or create each parameter manually.

### Example promo campaign

| Parameter | Value |
|-----------|-------|
| `promo_enabled` | `true` |
| `promo_id` | `v1.1-instant-search` |
| `promo_text` | `Instant Search is here — search the web without leaving Echo` |
| `promo_link_text` | `See what's new` |
| `promo_link_url` | `https://your-website.com/changelog` |
| `promo_background_color` | `#2563EB33` |

Change `promo_id` to show the banner again after users dismiss it.

### Force update test

Set `min_required_version` to `99.0` to verify the blocking update screen. Reset to `1.0` when done.

## Sparkle auto-updates

1. Generate EdDSA keys:
   ```bash
   # From Sparkle release bundle or repo
   ./bin/generate_keys
   ```
2. Put the **public** key in `mac/Info.plist` → `SUPublicEDKey` (replace `REPLACE_WITH_SPARKLE_PUBLIC_KEY`).
3. Host [`appcast.xml`](appcast.xml) at the URL in `SUFeedURL`.
4. For each release:
   ```bash
   ./bin/sign_update Echo-1.0.dmg -f private_key_file
   ```
   Add the signature to the `<enclosure sparkle:edSignature="...">` attribute.
5. Upload the `.dmg` and updated `appcast.xml` to GitHub Releases (or your CDN).

## Analytics DebugView

Launch Echo from Xcode with argument `-FIRAnalyticsDebugEnabled` to see events in Firebase Console → Analytics → DebugView.
