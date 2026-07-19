# SafariF12

Press **F12** in Safari to toggle the Web Inspector — the same muscle memory as
Chrome and Firefox.

A tiny native background app: while Safari is the frontmost application it
listens for F12 and sends ⌥⌘I. It does nothing in any other app, and its
listen-only event tap can never block or delay your keyboard input.

## Prerequisites

Safari → Settings → Advanced → check **"Show features for web developers"**.

## Install

Download the latest `.dmg` from Releases (or
`brew install --cask rxliuli/tap/safari-f12`), drag `SafariF12.app` to your
`/Applications` folder, and launch it. Grant Accessibility permission when
prompted (required for the global keyboard event tap).

On first launch a status window walks you through granting the permission and
shows a launch-at-login toggle (on by default — macOS notifies you and lists
it under System Settings → General → Login Items). Close the window and
SafariF12 keeps working silently in the background: no menu bar icon, no Dock
icon. To bring the window back (status, settings, quit), open SafariF12 from
Launchpad or Finder again while it is running. It also reappears on its own
if the permission ever goes missing.

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
