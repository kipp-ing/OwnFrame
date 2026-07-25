# Engineering Notes

Hard-won learnings and gotchas for working in this codebase. These are the things
that cost time once and shouldn't cost it again. For testing specifics see
[testing.md](testing.md); for the project rules see [CLAUDE.md](../CLAUDE.md).

## Swift / SwiftUI

### Cross-module re-export needs an explicit import
`OnboardingViewModel.albums` is `[Album]`, but `Album` is defined in `ImmichClient`,
not `OnboardingKit`. A SwiftUI view that only `import OnboardingKit` and touches
`album.id` / `album.name` fails to compile:

> property not available due to missing import of defining module 'ImmichClient'

Fix: add `import ImmichClient` to any view that uses `Album` members
(`AlbumStepView.swift` does). Swift does **not** auto-re-export a transitive
module's members.

### Pre-link SourceKit noise is not a real error
While editing files in the app target, the editor may show
`No such module 'OnboardingKit' / 'ImmichClient' / 'XCTest'`. These are transient
SourceKit diagnostics that clear once a simulator build runs and resolves the
package/target linkage. The `build_sim` / `test_sim` result is the real signal —
not the live editor diagnostics.

## Test seam pattern

The onboarding UI is tested hermetically via a `--uitest` launch-argument seam
(`UITestSupport` in `OwnFrameApp.swift`) that injects a stub API + in-memory
stores. This is the project's standard way to make a SwiftUI flow deterministically
testable — reuse it for future flows. Full details in
[testing.md](testing.md#layer-3--ui-tests-hermetic-xcuitest).

## SPM test targets vs. the simulator
SwiftPM **test** targets can't run on the simulator through the app `.xcodeproj`
(only library *products* surface as schemes). Consequence:

- Package **logic** → host `swift test`.
- Anything needing the real simulator runtime (real Keychain, real-target
  integration) → the **app-hosted** `OwnFrameTests` bundle, which links the
  packages.

## Xcode project file (`project.pbxproj`)

Editing `project.pbxproj` by hand is brittle — **prefer to avoid it.**

- **Adding source files to an *existing* target:** you can often sidestep pbxproj
  entirely by putting code in a file the target already compiles. The UI-test seam,
  for example, was inlined into `OwnFrameApp.swift` and the UI tests were
  added to the existing `OwnFrameUITests.swift` — **zero pbxproj changes.**
- **Adding a new local Swift package** (when unavoidable): wire it into 6 spots —
  `PBXBuildFile` (one per target frameworks phase), each target's
  `PBXFrameworksBuildPhase` `files`, each target's `packageProductDependencies`, the
  project `packageReferences`, plus the `XCLocalSwiftPackageReference` and
  `XCSwiftPackageProductDependency` sections.
- `.gitignore` ignores `Packages/*`; each local package needs an explicit allow line
  (e.g. `!Packages/ImmichClient/`, `!Packages/OnboardingKit/`).

## Tooling / shell

- **XcodeBuildMCP setup:** `.mcp.json` must invoke `npx -y xcodebuildmcp@latest mcp`
  (the `mcp` subcommand). Without it the server prints usage and the client gets
  `-32000`. Run `/mcp` after a fresh start to confirm the connection.
- **`preferXcodebuild: true`** for `build_sim`/`test_sim` — the incremental builder
  (xcodemake) chokes on project changes. Default sim: **iPad Pro 11-inch (M4)** — pin it by
  `simulatorId`, not by name. An unpinned "iPad Pro 11"" resolves to the **M5**, whose default
  **iOS 26.4** runtime serves 0 StoreKit products and fails all 7 `StoreKitClientTests`; see
  [testing.md](testing.md#known-traps--false-greens-flakes-and-landmines).
- **No `axe`/`idb`** installed → MCP UI automation is read-only
  (`snapshot_ui`/`screenshot`). Drive UI through XCUITest instead.
- **`cd` in a Bash tool call drifts the working directory** for later calls. Use
  `(cd … && …)` subshells or absolute paths, otherwise a later
  `git add <repo-relative-path>` can fail with "pathspec did not match".

## Orchestration (Claude + Codex)

Per [CLAUDE.md](../CLAUDE.md): Claude orchestrates and owns the verification gate;
Codex implements well-scoped slices. Keep **inline** (do not delegate): test design
for shared/concurrent state and timing, security-critical/cross-cutting code
(Keychain, TLS, onboarding wiring, app entry), and any SwiftUI/UI that needs the
simulator to verify. Don't create Xcode files (schemes, etc.) while a Codex job runs
in the same tree — it may "tidy" untracked out-of-scope files.

Operational details:
- Codex needs `--disable-sandbox` + `CLANG_MODULE_CACHE_PATH=/private/tmp/...` for
  SwiftPM (the Home module caches aren't writable in its sandbox). That's a Codex-env
  workaround only — **Claude re-verifies unsandboxed** as the real gate.
- Codex does not auto-commit. Claude verifies (host `swift test` + scope review),
  fixes `.gitignore` for any new package, then commits.
- Poll a running job with `codex-agent capture <id>` grepping for `Worked for [0-9]`
  (don't match `error:` — that fires on the expected red test in a TDD slice).

## Constraints to design *with*, not against
(from [CLAUDE.md](../CLAUDE.md) — repeated here because they shape architecture)

- An iOS app cannot physically power off the display — only dim brightness to ~0.
- Brightness / idle-timer control works **only in the foreground**.
- API keys and MQTT credentials go to the **Keychain**, never UserDefaults/logs.
- TLS validation is never disabled (a valid certificate is assumed for now).
- Verify API paths against the running Immich's OpenAPI spec — don't trust old
  tutorials. (Done for 2.7.5; see [testing.md](testing.md#live-server-contract-check-manual-opt-in).)
