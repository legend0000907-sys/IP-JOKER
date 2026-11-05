# IP JOKER Android

This repository contains the original Persian web interface and an Android WebView host project.

## Current status
- The original UI is in `web/index.html`.
- The Android Gradle project and GitHub Actions APK build workflow are scaffolding.
- **A working proxy-to-TUN engine is NOT integrated yet.** The current native bridge deliberately reports that connection is unavailable; it does not pretend to establish a VPN.
- A real implementation must integrate a compatible Android VPN engine (for example sing-box/libbox), handle its configuration and lifecycle, and be tested on a physical Android device.

## Build
Push to GitHub, then open **Actions → Build Android APK → Run workflow**. The workflow also runs on pushes to main. The debug APK is uploaded as an Actions artifact.

## License note
The web interface is the supplied project file. Any future libbox integration must comply with the upstream project's GPL-3.0-or-later license and notices.
