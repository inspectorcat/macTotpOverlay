# macTotpOverlay

Always-on-top macOS overlay showing a real-time TOTP code with countdown.

## Build & Run

```bash
# compile
swiftc -O -o totpoverlay TOTPOverlay.swift -framework Cocoa

# run (reads secret from env)
export TOTP_SECRET='YOUR_BASE32_SECRET'
./totpoverlay
```

Requires macOS and Xcode Command Line Tools (`xcode-select --install`).

## Features

- SHA-256 HMAC-TOTP, 6 digits, 30s period
- Borderless transparent overlay, always on top across all Spaces
- Countdown bar (green -> red when <5s remain)
- Draggable window, no dock icon
