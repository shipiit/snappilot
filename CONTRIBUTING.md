# Contributing to Snappilot

Thanks for your interest in improving Snappilot! 🎉 Contributions of all kinds are
welcome — bug reports, feature ideas, docs, and code.

## Ground rules

- **No direct pushes to `main`.** `main` is protected — all changes land via **pull
  request** with at least one approving review.
- Keep changes focused. One PR = one logical change.
- Be kind and constructive in issues and reviews.

## Getting set up

Requires **macOS 14+**, **Xcode 16+**, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/shipiit/snappilot.git
cd snappilot
xcodegen generate         # creates Snappilot.xcodeproj
open Snappilot.xcodeproj   # then Run (⌘R)
```

## Architecture (where things live)

- **`Sources/SnapCore/`** — pure, UI-free logic (geometry, OCR wrapper, image ops,
  annotation model, library index). This is where unit-testable code goes.
- **`App/`** — SwiftUI + AppKit UI (capture overlay, editor, recorder, player, dashboard).

Put logic in `SnapCore` so it can be tested without a UI; the app layer consumes it
through clean value types.

## Before you open a PR

1. **Add/keep tests passing** for logic changes:
   ```bash
   swift run snapverify      # framework-free SnapCore checks
   ```
2. **Build the app cleanly:**
   ```bash
   xcodebuild -project Snappilot.xcodeproj -scheme Snappilot -destination 'platform=macOS' build
   ```
3. Match the surrounding code style (naming, spacing, doc comments).

## Pull request flow

1. Fork (or branch, if you have write access): `git checkout -b feature/my-change`
2. Commit with clear messages.
3. Open a PR against `main`, fill in the template, and link any related issue.
4. A maintainer reviews; address feedback; once approved it's merged.

## Reporting bugs & requesting features

Use the [issue templates](https://github.com/shipiit/snappilot/issues/new/choose):
**Bug report** or **Feature request**. The more detail (macOS version, steps, screenshots),
the faster we can help.

## License

By contributing, you agree that your contributions are licensed under the **MIT License**.
