# IP JOKER

Android proxy/VPN client. The active Android application is in `mobile/`.

## Current implementation
- Preserves the supplied Persian RTL interface in `mobile/assets/index.html`.
- Uses Flutter WebView to host the interface.
- Uses the `sing_box` Flutter plugin (official sing-box core via libbox) for Android `VpnService` / TUN operation.
- The web UI sends connect/disconnect requests through a JavaScript channel to the Flutter host.
- Supported plain proxy URI types for the current IP:port form: HTTP (`http://`), HTTPS proxy (`https://`) and SOCKS5 (`socks5://`). The sing-box core validates the proxy and reports its actual startup errors.
- VPN permission is requested by Android on first connection.

## Build APK
GitHub Actions builds an ARM64 release APK on pushes affecting `mobile/**`, or manually:
1. Open **Actions**.
2. Select **Build IP JOKER Android APK**.
3. Press **Run workflow**.
4. Download artifact **IP-JOKER-android-arm64** after the run completes.

## Important
The APK has not yet been built and tested on a physical device in this development session. A successful CI build is not the same as a successful connection to a reachable proxy; test with a valid proxy endpoint. The current UI has no username/password fields, so authenticated HTTP/SOCKS proxies are not yet supported by its simple host/port form.

## Licensing
The sing-box core and `sing_box` plugin are GPL-3.0-or-later. This project must be distributed with the corresponding source and required license notices under a GPL-compatible license. See upstream notices before redistribution.
