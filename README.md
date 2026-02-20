# 🛡️ SimpleProxyMenuBar

A lightweight native macOS menu bar app that shows your **current proxy IP address** at a glance.

> ⚠️ **Disclaimer:** This software is provided "as is", without warranty of any kind. The author(s) are not liable for any damages or issues arising from the use of this software. Use at your own risk. See [LICENSE](LICENSE) for full details.

> 🤖 **AI Disclosure:** This project was created with assistance from [Claude](https://claude.ai) by Anthropic.

---

## Features

- **Native Swift** — no dependencies, no Python, no Electron
- Detects proxies using `networksetup` — the same tool macOS uses internally
- Checks all network services for HTTP, HTTPS, SOCKS, and PAC proxies
- Icons: **🛡️** proxy active · **🌐** no proxy
- Click the IP item to **copy to clipboard**
- Auto-refreshes every 30 seconds (toggle on/off)
- Manual refresh with ⌘R
- Reverse DNS hostname lookup
- **Preferences** → Open at Login toggle
- **Help** → link to GitHub
- Hides from Dock (`LSUIElement`) — lives only in the menu bar

## Requirements

- macOS 12.0+
- Xcode 15+

## Setup

```bash
git clone https://github.com/baldwinsung/SimpleProxyMenuBar.git
cd SimpleProxyMenuBar
open SimpleProxyMenuBar.xcodeproj
```

1. In Xcode, go to the **SimpleProxyMenuBar** target → **Signing & Capabilities**
2. Set your **Team**
3. Press **⌘R** to build and run

## Build & Install to /Applications

```bash
./build.sh
```

Builds a Release binary with `xcodebuild` and installs it to `/Applications` using `ditto`.

## Project Structure

```
SimpleProxyMenuBar/
├── SimpleProxyMenuBar.xcodeproj/
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/
│       └── SimpleProxyMenuBar.xcscheme
├── AppDelegate.swift       # Menu bar UI, preferences, help
├── ProxyChecker.swift      # Proxy detection + IP fetching
├── main.swift              # Entry point
├── Assets.xcassets/        # App icon and accent color
├── build.sh                # Build and install to /Applications
├── LICENSE
└── README.md
```

## How Proxy Detection Works

Iterates every network service from `networksetup -listallnetworkservices` and checks:

```bash
networksetup -getautoproxyurl       "$svc"   # PAC
networksetup -getwebproxy           "$svc"   # HTTP
networksetup -getsecurewebproxy     "$svc"   # HTTPS
networksetup -getsocksfirewallproxy "$svc"   # SOCKS
```

If any service reports `Enabled: Yes`, the proxy is shown as active with its host, port, and service name — e.g. `HTTPS [Wi-Fi]: 127.0.0.1:7890`.

## Set up your proxy

Manage your proxy via pac ( proxy auto config ) file. Use scripts at https://github.com/baldwinsung/scripts_apple_mac/tree/main/proxy to get setup.

## License

MIT — see [LICENSE](LICENSE). Free to use, modify, and distribute.

## Disclaimer

This software is provided without warranty. The author(s) accept no liability for any damages, data loss, security issues, or other problems arising from the use of this software. It is your responsibility to ensure it is suitable for your use case.
