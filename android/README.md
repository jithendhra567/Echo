# Echo Android companion

Pairs with the Mac Echo app over local Wi‑Fi for clipboard sync and per-app streaming/control.

## Features

- **QR pairing** — scan the code from Echo → Dashboard → Phone
- **Clipboard sync** — history + live push both directions on the LAN
- **App streaming** — open a running Mac app window on the phone (not full desktop) and tap / scroll / type

## Build

```bash
cd android
./gradlew :app:assembleDebug
```

Open in Android Studio, or install:

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Pairing

1. On Mac: Echo → Dashboard → **Phone** → enable **Allow phone connections**
2. Allow **Screen Recording** when macOS prompts (needed for app windows)
3. On Android: scan the QR (same Wi‑Fi), or paste the `echo://pair?…` link

## Protocol

WebSocket on port `8742`. Pairing URL:

```
echo://pair?v=1&host=<lan-ip>&port=8742&token=<token>&name=<mac-name>
```
