# SafariF12

Press **F12** in Safari to toggle the Web Inspector — the same muscle memory as
Chrome and Firefox.

A tiny native background app: while Safari is the frontmost application it
listens for F12 and sends ⌥⌘I. It does nothing in any other app, and its
listen-only event tap can never block or delay your keyboard input.

## Prerequisites

Safari → Settings → Advanced → check **"Show features for web developers"**.

## Install

### Homebrew

```bash
brew install --cask rxliuli/tap/safari-f12
```

### Download

Grab the latest `.dmg` from
[Releases](https://github.com/rxliuli/safari-f12/releases), open it, and drag
`SafariF12.app` to your `/Applications` folder.

## First launch

Launch SafariF12 and grant **Accessibility** when prompted — it covers both
observing the F12 key and sending the synthetic ⌥⌘I. (In rare cases macOS
additionally asks for **Input Monitoring**; the status window guides you if
so.)

SafariF12 registers itself to launch at login (macOS notifies you; turn it
off anytime under System Settings → General → Login Items) and then works
silently in the background: no menu bar icon, no Dock icon. To bring the
status window back (status, quit), open SafariF12 from Launchpad or Finder
again while it is running. It also reappears on its own if the permission
ever goes missing.

## Build from source

```bash
./scripts/build-app.sh          # universal binary → bin/SafariF12.app
./scripts/build-app.sh --native # quick single-arch build
```

## The built-in alternative

macOS can do most of this without any extra software: System Settings →
Keyboard → Keyboard Shortcuts → App Shortcuts → add a Safari shortcut for the
menu item "Show Web Inspector" bound to F12. The trade-offs: it depends on the
exact (localized) menu title, and F12 keeps its original meaning elsewhere.
SafariF12 works out of the box and only intercepts F12 while Safari is active.

## License

This project is licensed under the [GPL-3.0 License](./LICENSE).
