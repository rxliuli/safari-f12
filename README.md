# SafariF12

Press **F12** in Safari to toggle the Web Inspector — the same muscle memory as
Chrome and Firefox.

A tiny native menu bar app: while Safari is the frontmost application it
swallows F12 and sends ⌥⌘I. It does nothing in any other app.

## Prerequisites

Safari → Settings → Advanced → check **"Show features for web developers"**.

## Install

Download the latest `.dmg` from Releases (or
`brew install --cask rxliuli/tap/safari-f12`), drag `SafariF12.app` to your
`/Applications` folder, and launch it. Grant Accessibility permission when
prompted (required for the global keyboard event tap).

SafariF12 registers itself to launch at login — macOS notifies you and lists
it under System Settings → General → Login Items, and the menu bar toggle
turns it off anytime. Prefer total silence? Pick **Hide Menu Bar Icon** from
the menu; the app keeps working in the background. To bring the icon back,
open SafariF12 from Finder or Launchpad again while it is running.

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
