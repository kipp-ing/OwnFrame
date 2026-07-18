# Contributing

Thanks for your interest. This is a small, spec-driven project with one maintainer; issues and
pull requests are welcome, but please read this page first — especially the licensing section,
which is short and non-negotiable.

## Licensing of contributions

The project is licensed under [FSL-1.1-MIT](LICENSE) (Fair Source: the code is public, competing
products are not permitted, and each release becomes plain MIT two years after publication).

By submitting a contribution (a pull request, patch, or code suggestion) you agree that:

1. The contribution is your own work and you have the right to submit it.
2. Your contribution is licensed under the project's license (FSL-1.1-MIT), including its Grant
   of Future License — like the rest of the code, it becomes MIT two years after release.
3. You additionally grant the maintainer (Jan Kipping) a perpetual, worldwide, non-exclusive,
   royalty-free, irrevocable license to use, reproduce, modify, distribute, sublicense, and
   **relicense** your contribution as part of this project. This is what allows the maintainer
   to ship the App Store binary (which is distributed under Apple's standard terms) and to
   adjust the project license in the future without tracking down every past contributor.
4. You retain the copyright to your contribution.

No separate CLA paperwork — submitting the pull request constitutes agreement. If you can't
agree to the above, please open an issue describing the change instead of a PR.

## Before you write code

- **Open an issue first** for anything non-trivial. The project is spec-driven: features exist
  as specs under `specs/` before they exist as code (see
  [docs/spec-overview.md](docs/spec-overview.md) for the map). A PR that lands out of nowhere
  against an unspecced area will usually be redirected to an issue discussion first.
- Bug fixes with a failing test attached can skip the discussion — the test is the discussion.

## Working method

- **Swift 6, SwiftUI, Swift Package Manager.** App logic lives in the packages under
  `Packages/`; the app target is thin.
- **Test-first.** Red test before implementation. Unit tests use Swift Testing (`@Test`);
  UI tests use XCTest. [docs/testing.md](docs/testing.md) explains the layers and how to run
  each one; `swift test` inside a package runs its unit tests on the host.
- **English only** for all code comments, docs, and user-facing strings (localization happens
  via the xcstrings catalogs; don't hand-add localizations).
- **Security ground rules:** no secrets in code, UserDefaults, or logs — credentials belong in
  the Keychain; never disable TLS validation; the app talks only to user-configured endpoints.
- [docs/engineering-notes.md](docs/engineering-notes.md) collects gotchas and conventions worth
  reading before your first PR.

## Pull requests

- Keep them small and focused — one concern per PR.
- Include the tests that prove the change; if the red-first step is visible in your commit
  history, even better.
- Run the affected package's `swift test` before pushing; for SwiftUI changes, note in the PR
  what you verified in the simulator.
- Don't touch `specs/`, `.specify/`, or the Xcode project file unless the change is explicitly
  about them.
