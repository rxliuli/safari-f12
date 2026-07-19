# SafariF12

Press **F12** in Safari to toggle the Web Inspector — the same muscle memory as
Chrome and Firefox.

A tiny native menu bar app: while Safari is the frontmost application it
swallows F12 and sends ⌥⌘I. It does nothing in any other app.

## Prerequisites

Safari → Settings → Advanced → check **"Show features for web developers"**.

## Install

Download the latest `.dmg` from Releases, open it, and drag `SafariF12.app`
to your `/Applications` folder. Launch it and grant Accessibility permission
when prompted (required for the global keyboard event tap). Use the menu bar
icon to enable **Launch at Login**.

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
