# DocBot — Decisions

_Last updated: 2026-08-25. This is a compact decision log reconstructed from repository history and project conversations. When code and this file disagree, verify whether a decision has subsequently been superseded._

## How to read this file

Statuses:

- **Accepted** — current intended direction.
- **Superseded** — was implemented or considered, but a later decision replaced it.
- **Rejected** — deliberately not the desired design.
- **Provisional** — intended for current work, but not yet fully merged/validated.

---

## D-001 — AutoHotkey v2 is the implementation language

**Status:** Accepted

DocBot is an AutoHotkey **v2** project. v1 syntax assumptions are unsafe because expression, function, object, GUI, and continuation rules differ substantially.

**Consequences**

- All code examples, validation, and libraries must be v2-compatible.
- A visually plausible construct borrowed from another language is not sufficient proof of syntax validity.
- The recent multiline-concatenation regressions show that real AHK v2 parsing/compilation should be part of validation.

---

## D-002 — End users receive a compiled executable

**Status:** Accepted

End users do not edit or run the source tree directly. Source changes are committed as `.ahk` files and compiled separately.

**Consequences**

- Runtime behavior must be fixed in source, not by patching deployed user files.
- `FileInstall` and compile-time inclusion are part of release behavior.
- Release validation should include a compiled build, not only interpreter execution.

---

## D-003 — Real local configuration and secrets stay outside Git

**Status:** Accepted

Internal telephony addresses/endpoints, real default local items, SMS target configuration, and telemetry webhook information live in `DocBot.local.ahk`, which is ignored by Git.

`DocBot.local.example.ahk` is the safe committed template.

**Consequences**

- Never commit the real local file.
- Do not copy real endpoint values into documentation, tests, examples, issue text, or logs.
- Ahk2Exe may still include the local file when compiling on the authorized machine.

---

## D-004 — `main` is production; normal work starts from `develop`

**Status:** Accepted

`main` must correspond to the executable running for end users. Normal features/fixes branch from an up-to-date `develop`.

Only an explicitly requested production hotfix starts from `main`.

**Consequences**

- Never write directly to `main` or `develop`.
- Use a feature/fix/release branch and PR.
- A hotfix from `main` must also be brought back into `develop`.

---

## D-005 — AppVersion is branch-aware and commit-coupled to `DocBot.ahk`

**Status:** Accepted

Current scheme, after the DocBot 2.2 release (tag `v2.2` on `main`):

```text
main                 2.2 (stable)
develop              2.3-dev.N
feature/fix          2.3-<short-branch-name>.N
release candidate    2.3-rc
stable release       2.3
```

The same numeric scheme applied to the 2.2 cycle that just shipped:
`main` carried `2.1` until the final `2.2` release; `develop` used
`2.2-dev.N`; feature/fix branches used `2.2-<short-branch-name>.N`; the
release candidate used `2.2-rc.N`.

Every commit that changes `DocBot.ahk` must update `global AppVersion` in that same commit. A commit that does not change `DocBot.ahk` must not change AppVersion.

**Consequences**

- Side-branch counters are local to that branch.
- Merging a feature into `develop` requires a new/higher central `dev.N`; do not carry the feature suffix into develop.
- Release-branch code changes increment `rc.N`.
- Prerelease counter changes are not stable releases and do not receive stable release tags.

---

## D-006 — Merge integration preserves history

**Status:** Accepted for the current project workflow

For the recent DocBot feature/fix/release flow, the project owner has repeatedly required **Create a merge commit**, specifically not squash and not rebase for final integration.

**Consequences**

- Do not silently squash a tested feature branch into develop.
- Release integration should preserve the branch/merge structure expected by the owner.

---

## D-007 — README Changelog is the single version-history source

**Status:** Accepted

The version history is maintained only under `Changelog` in `README.md`. The About screen reads and simplifies this section.

**Rejected alternative:** manually maintaining a second release history in `BuildAboutText()`.

**Consequences**

- Keep changelog newest-first.
- Avoid divergent duplicate history.
- Stable release preparation includes finishing this changelog.

---

## D-008 — Stable releases use annotated `v` tags

**Status:** Accepted

Stable releases receive an annotated tag such as `v2.2` on the stable release commit. Development, feature/fix, and RC versions do not receive stable release tags.

**Consequences**

- A release is not considered fully tagged until the tag exists on `origin`.

---

## D-009 — User data is isolated by release channel

**Status:** Superseded by D-056

Stable, central test/RC, and feature/fix builds use different Documents folders.

```text
stable     -> DocBot
-dev/-rc   -> DocBot-test
other pre  -> DocBot-dev
```

D-056 keeps this same three-way isolation but replaces the prerelease-label
based split between `DocBot-test` and `DocBot-dev` with a build-form
(`A_IsCompiled`) based split.

**Reason**

A prerelease build must not migrate or corrupt production user data.

**Consequences**

- New target profiles are copied once from the appropriate predecessor.
- Existing target profiles are never overwritten by bootstrap copying.
- Schema migration runs after profile bootstrap.

---

## D-010 — Migrations add defaults once, not continuously

**Status:** Accepted

New built-in/local defaults are introduced through explicit schema upgrades. Existence checks use a functional/stable key such as hotstring trigger, speed-dial name, or telephone number.

**Rejected alternative:** re-add a missing default every time DocBot starts.

**Reason**

A user may intentionally delete or edit a default. Startup must not undo that choice.

---

## D-011 — Personal hotstrings keep one replacement model

**Status:** Accepted

Single-line, multiline, short, and long personal hotstrings all use the same `Replacement` field.

**Rejected alternative:** separate persistent types or fields for multiline/long replacements.

**Reason**

The difference is execution strategy, not domain identity. Keeping one model simplifies editing, migration, import, and backwards compatibility.

---

## D-012 — Hotstring execution method is derived automatically

**Status:** Accepted

- short simple single-line text -> ordinary hotstring replacement;
- long/multiline -> callback with `SendText()` and explicit `{Enter}` handling;
- replacement with real key commands -> key-command-compatible execution.

**Consequences**

The user does not choose an execution engine manually.

---

## D-013 — Hotstrings never use the Windows clipboard

**Status:** Accepted

**Rejected alternative:** copy replacement text to the clipboard and paste it for long/multiline hotstrings.

**Reason**

The clipboard is continuously observed by the telephone-number workflow. Reusing it for text replacement creates race conditions and can overwrite the user's existing clipboard content.

**Consequences**

- Use `SendText()` for ordinary callback text.
- Send line breaks separately.
- Treat clipboard contents as telephony input only.

---

## D-014 — Package settings store choices, not package content

**Status:** Accepted

Bundled package JSON is versioned with the app. `package-settings.json` stores only enable/disable/conflict choices.

Editing or explicitly saving a package item creates a complete personal hotstring copy.

**Consequences**

- Package updates can ship without rewriting user settings.
- Personal copies survive package changes/removal.
- Stable package/item IDs matter; UI display text is not a storage key.

---

## D-015 — Personal hotstrings normally win package conflicts

**Status:** Accepted

A personal hotstring has default priority over bundled content unless the user explicitly grants the package item priority.

The stable user-visible statuses are:

- `Inactief`
- `Overruled`
- `Voorrang`
- `Conflict`
- `Actief`

**Consequences**

Do not casually rename statuses or invert default conflict behavior; both are user-facing product semantics.

---

## D-016 — Telephony requests are POST

**Status:** Accepted

Registration, event polling, and dialing all use POST.

**Superseded behavior:** early development used GET for some requests.

**Reason**

Live testing/protocol behavior established POST as the correct integration contract.

---

## D-017 — Telephony uses separate request objects

**Status:** Accepted

Registration, polling, and dialing keep independent request-object references.

**Rejected/superseded alternative:** one shared mutable XHR object passed/bound through multiple asynchronous operations.

**Reason**

A later request can otherwise overwrite the object reference required by an earlier callback.

---

## D-018 — Event polling is chained, not overlapping on a fixed timer

**Status:** Accepted

`IPT_poller()` issues a request and the response path starts/plans the next poll after completion.

**Superseded alternative:** periodic fixed-interval timer for long polling.

**Reason**

Chaining prevents overlapping requests and gives better recovery semantics.

---

## D-019 — Every normal call passes through one central call path

**Status:** Accepted

`IPT_callNumber()` is the central dialing gate for clipboard calls, manual calls, speed-dial calls, and linking behavior.

Ordinary calls are rejected when no telephone is linked; the linking call is the explicit exception.

**Consequences**

New call entry points should delegate to this path rather than bypassing validation/state checks.

---

## D-020 — Four-state `Belactie` replaces AutoCall/DirectCall

**Status:** Accepted

The old combination of booleans was replaced by one user-facing call-action selection that can express:

- ignore;
- confirm then call;
- call immediately;
- choose SMS/call where eligible.

**Reason**

The combined setting is clearer and avoids contradictory checkbox states.

---

## D-021 — SMS is assisted, never automatically sent

**Status:** Accepted

DocBot may navigate to the configured SMS page and fill the telephone field, but the user remains responsible for reviewing and sending the message.

**Rejected alternative:** automatically submit/send the SMS.

**Reason**

Human verification is a deliberate safety/product boundary.

---

## D-022 — UI Automation is primary for SMS page interaction

**Status:** Accepted

The preferred path is direct Edge/window activation plus Windows UI Automation for background-tab selection and field filling. JavaScript is a fallback.

**Rejected alternative:** JavaScript-only automation.

**Reason**

The UIA path is more reliable for the managed Edge workflow and can address already-open background tabs.

---

## D-023 — The SMS action may be one map or an array of maps

**Status:** Accepted

For backwards compatibility, one `SmsCallAction` map and a list of multiple action maps are supported.

The GUI shows `Title`; `WindowTitle` remains technical matching data.

---

## D-024 — Call/SMS dialog must be keyboard-operable

**Status:** Accepted

Left/right changes the selected real button and Enter activates it.

The initial visual state must be repainted after showing the dialog so the chosen button is immediately rendered correctly.

**Historical bug**

The initial button styles were wrong until the mouse passed over them. A forced repaint after show fixed that behavior.

---

## D-025 — Do not rely on `TrayTip()` for important notifications

**Status:** Accepted

**Superseded alternative:** Windows `TrayTip()` notifications.

**Reason**

On some managed hospital Windows images, group policy silently suppresses the OS notification path. AutoHotkey receives no useful error.

**Current direction**

Use DocBot's own always-visible, non-focus-stealing notification GUI for important feedback.

---

## D-026 — No global startup writeability gate

**Status:** Accepted

**Superseded decision:** PR #4 introduced a broad startup storage-writeability check after a telemetry installation-ID persistence problem.

That approach was later removed in PR #8.

**Reason**

Documents may be backed by OneDrive and temporarily unavailable. Blocking all of DocBot because a broad startup test fails makes unrelated functionality unavailable.

**Current design**

- best-effort `attrib -U +P` on the user-data folder;
- failure to pin locally does not block startup;
- real writes handle their own errors;
- telemetry has its own persistence retry path.

---

## D-027 — Existing telemetry InstallationId is read-only during normal startup

**Status:** Accepted

When a persisted installation ID exists, use it immediately and do not rewrite it.

**Reason**

Unnecessary writes created avoidable dependency on OneDrive availability and contributed to identity instability.

---

## D-028 — New telemetry InstallationId must be confirmed before use

**Status:** Accepted

When no installation ID exists:

1. generate one pending GUID;
2. write it;
3. read it back;
4. only then promote it to the active installation ID.

If persistence fails temporarily, retry during the first minutes and later hourly.

**Rejected alternative:** use a newly generated in-memory ID even when it could not be persisted.

**Reason**

That behavior can produce a new installation identity on every startup.

---

## D-029 — Telemetry failure must not disable DocBot

**Status:** Accepted

Telemetry is optional observability. Temporary inability to read/write its identity or contact its webhook must not make core hotstring/telephony functionality unavailable.

---

## D-030 — Telemetry disclosure is a release invariant

**Status:** Accepted

Every active branch/release must keep a clear README `Telemetrie` section explaining what is sent, why, how often, and what sensitive content is deliberately not sent.

New fields or broader collection require explicit project-owner approval.

**Rejected alternative:** silently broadening telemetry or weakening/removing disclosure.

---

## D-031 — Standard logging is limited; detailed logging requires consent

**Status:** Accepted; integrated in the 2.2 development and RC2 lines, shipped in stable 2.2

Baseline troubleshooting logging exists continuously, but detailed session logging can be enabled only after explicit user consent in the `Probleem melden...` workflow.

**Reason**

Diagnostics must be useful without turning normal operation into unrestricted sensitive tracing.

**Consequences**

- standard logs use central redaction/sanitization;
- after explicit consent, the temporary detailed log may contain raw
  telephony URLs/responses, complete called numbers, actually executed
  hotstring triggers/replacements, and detailed SMS/UIA traces;
- telemetry secrets stay protected and local configuration files are not
  packaged;
- process exit/restart ends detailed logging.

---

## D-032 — Problem reporting should degrade to a manual mail path

**Status:** Accepted; integrated in the 2.2 development and RC2 lines (superseded by D-041 for the ZIP-building half, shipped in stable 2.2)

Problem reporting creates a ZIP and prepares a Classic Outlook draft. If Outlook automation cannot be used, the user receives a manual fallback that selects the ZIP in Explorer, attempts to open a message without attachment, and explains that the ZIP must be attached manually.

**Rejected alternative:** fail the whole report because Outlook automation is unavailable.

---

## D-033 — Do not treat source review as sufficient AHK syntax validation

**Status:** Accepted lesson from recent regressions

The extended-logging branch repeatedly contained invalid multiline concatenation despite visual review.

**Consequences**

- after fixing one syntax pattern, search the full changed area for all occurrences;
- use explicit expression concatenation styles already known to work in this codebase;
- run an actual AutoHotkey v2 parse/compile test on Windows before merge where possible.

---

## D-034 — Third-party libraries live under `ThirdParty/<library>/`

**Status:** Accepted

JXON, ColorButton, and UIA-v2 each have their own directory and original license.

**Superseded transitional design:** root-level JXON/ColorButton include shims used temporarily during migration.

The shims were later removed in favor of direct include paths.

**Consequences**

When changing library layout, update includes and file listings in README/AGENTS/CLAUDE together.

---

## D-035 — DocBot's own license is noncommercial; third-party licenses remain intact

**Status:** Accepted

The project owner did not want unrestricted commercial reuse by others. DocBot 2.2+ uses the repository's PolyForm Noncommercial license rather than MIT.

Third-party components retain their original licenses, including MIT where applicable.

**Consequences**

Do not remove third-party license files or imply that DocBot's project license re-licenses third-party code.

---

## D-036 — Temporary GitHub Actions-as-editor workflows are not the preferred development path

**Status:** Accepted process lesson

Large-file connector limitations led to temporary workflows/trigger PRs that modified the feature branch and then removed themselves. They worked around tooling limits but caused noisy Actions emails and complicated the workflow.

**Preferred direction**

Use a normal local git checkout for large source edits/commits/pushes when possible. Use GitHub tooling primarily for repository/PR operations and automation checks, not as a substitute text editor.

---

## D-037 — A Mac can manage Git, but Windows remains the functional validation environment

**Status:** Accepted process constraint

Local development on macOS can handle repository operations and source editing, but AutoHotkey v2 and the actual Edge/UIA/internal-telephony environment are Windows-specific.

**Consequences**

Do not conflate "the patch was edited and pushed successfully" with "DocBot was validated successfully".

---

## D-038 — Release 2.2 may include extended logging as an explicit freeze exception

**Status:** Accepted; shipped in stable 2.2

The 2.2 RC branch was created under a feature freeze. The project owner explicitly approved the extended problem-reporting/logging feature as an exception.

**Integration outcome**

The feature history was merged into `develop`; the updated development state
was then merged into `release/2.2-rc` as RC2. The exception is therefore
integrated. The branch went through RC3 because intended-purpose and related
user-facing wording changed, then RC4–RC6 for further fixes. The RC was
explicitly accepted, and stable `2.2` was released and tagged `v2.2` on
`main`.

Do not use this exception as permission to add unrelated new functionality to the release branch.

---

## D-039 — DocBot is general-purpose productivity software used in healthcare, not MDSW

**Status:** Accepted as a provisional repository-based qualification

DocBot is productivity software intended for employees in a managed business
environment. It originated from needs in a hospital workplace and is used in
hospital workflows, where it processes personal data and potential health
information. Based on the documented intended purpose and implemented
behavior, it is not presently treated as Medical Device Software under
Regulation (EU) 2017/745. Its rules support text entry, communication, storage,
diagnostics, and application management; they do not analyze patient-specific
medical data to produce a diagnosis, prognosis, treatment recommendation,
dosage, clinical alarm, or medical-device control.

The approved intended-purpose statement is recorded in
`docs/INTENDED_PURPOSE.md`. The complete qualification reasoning, evidence,
limitations, standards relevance, and reassessment triggers are recorded in
`docs/REGULATORY_ASSESSMENT.md`.

**Consequences**

- NEN 7510 and systematic patient-safety risk management remain relevant even
  without MDSW qualification.
- Clinical package content requires controlled ownership and review because an
  incorrect insertion can affect a patient record.
- Any patient-specific clinical analysis, recommendation, alarm, or
  medical-device control requires reassessment before implementation.
- This decision is not a legal opinion or certified conformity finding and may
  be superseded by external product claims, deployment facts, or a formal
  regulatory review.

---

## D-040 — Automated AutoHotkey v2 syntax check as a merge gate

**Status:** Accepted; shipped on `main` as part of 2.2, being brought back to `develop`

D-033 called for an actual AutoHotkey v2 parse/compile check after repeated
multiline-concatenation regressions escaped source review. `.github/workflows/ahk-syntax-check.yml`
implements this: on `windows-latest`, it downloads a portable AutoHotkey v2
release, copies `DocBot.local.example.ahk` to `DocBot.local.ahk` as safe CI
configuration, and runs `AutoHotkey64.exe /Validate` against `DocBot.ahk`.
It runs on pull requests touching `.ahk` files and on pushes to `develop`.

**Rejected/superseded alternative:** waiting on `Start-Process -Wait` (or a
bare `&` invocation) for the AutoHotkey process to exit and trusting
`$LASTEXITCODE`. In testing, a genuine parse error could make AutoHotkey show
a blocking error dialog that a headless runner never dismisses, hanging the
job until GitHub's own job timeout cancelled it — a `cancelled` run, not a
clear `failure`. `/ErrorStdOut` alone did not prevent this.

**Current implementation:** the process is started without `-Wait`; the
workflow calls `WaitForExit(60000)` itself, force-kills the process if it
has not exited within 60 seconds, and reports failure explicitly.
`timeout-minutes: 5` on the job is an additional backstop.

**Consequences**

- This check validates syntax only. It does not replace manual/Windows
  functional validation, telephony/network testing, or GUI verification.
- Any future CI step that shells out to a Windows GUI-subsystem executable
  should use the same explicit-timeout pattern rather than relying on the
  process to exit and set `$LASTEXITCODE` cleanly.
- The workflow was merged into `release/2.2-rc` via PR #19 (merge commit
  `2ee42b6`) and reached `main` with the 2.2 release. It is being
  propagated to `develop` in the same step that brings back the other
  release-only fixes (see `docs/TODO.md`).

---

## D-041 — Attach problem-report files individually instead of building a ZIP

**Status:** Accepted; merged into `release/2.2-rc` via PR #22, shipped in stable 2.2

**Supersedes:** the ZIP-building half of D-032. The manual-fallback rationale
in D-032 (degrade to a mail path instead of failing the report outright)
still stands.

A user on a managed hospital workplace consistently hit "Het ZIP-bestand kon
niet worden opgebouwd" when finalizing a problem report, even after the
reliability hardening (three consecutive stable size/name checks, retried
namespace resolution) added for D-032. `CompressDirectoryContents()` builds
the ZIP entirely through the Explorer shell namespace
(`Shell.Application`/`NameSpace()` on a `.zip` path, `CopyHere`) — the same
class of dependency already documented as unreliable on locked-down
Windows images elsewhere in this project (see the 2.0.0-beta.2 `TrayTip()`
group-policy entry in the README changelog). Repeated, non-transient
failure on one machine points at that shell extension being restricted or
disabled by group policy/EDR hardening rather than a timing race.

Since a problem report only ever contains a few small text files,
compression itself has no real benefit. `BuildProblemReportPackage()` now
writes the report files into the temporary directory and returns their
paths directly; `OpenProblemReportEmail()` attaches each file to the
Outlook draft individually via `mail.Attachments.Add()`, and the manual
fallback (`OpenProblemReportFallback()`) opens the report directory in
Explorer instead of selecting a single ZIP. This removes
`CompressDirectoryContents()`, `CreateEmptyZipArchive()`,
`WaitForShellNamespace()` and `ZipArchiveContainsSourceItems()` entirely,
along with the dependency on the Explorer zip-folder shell extension.

**Rejected alternative:** keep hardening the ZIP path further (e.g. an
own-written ZIP writer avoiding Explorer entirely). Rejected for now because
attaching loose files is simpler, removes the failure mode completely, and
compression provides no meaningful benefit for a few text-file attachments;
revisit only if a future report package needs to bundle many/larger files.

**Consequences**

- The problem-report attachment mechanism no longer depends on any Explorer
  shell extension.
- Users now see multiple attachments instead of one ZIP; acceptable for an
  internal diagnostic mail.
- The temporary report directory (not a ZIP file) is the artifact whose
  lifecycle `docs/TODO.md` P1 "Remove temporary problem-report artifacts"
  still needs to address.

---

## D-042 — Keep the AHK syntax check unscoped on `pull_request` and keep `workflow_dispatch`

**Status:** Accepted

D-040/`docs/TODO.md` left two open questions about
`.github/workflows/ahk-syntax-check.yml`: whether the `pull_request` trigger
should be limited to `develop`/`release/*`, and whether `workflow_dispatch`
is still worth keeping now that the workflow lives on `main`.

Project owner decision (2026-08-15):

- **`pull_request` stays unscoped (no `branches:` filter).** Every `.ahk`
  change must be syntax-checked regardless of target branch; old branches
  without live consequences are not being reworked, so there is no
  meaningful case where an unwanted PR triggers a wasted run.
- **`workflow_dispatch` stays.** It lets a feature/fix branch be validated
  on GitHub before/without opening a PR, which matters for local
  Windows-side testing of that branch — the manual trigger is exercised
  directly, not a leftover from before the workflow reached `main`.

**Consequences**

- No workflow change needed; this closes the two open bullets under
  "Propagate the AutoHotkey v2 syntax smoke check to `develop`" in
  `docs/TODO.md`.
- Revisit only if Actions usage/cost from the unscoped trigger becomes a
  real problem, or if `workflow_dispatch` turns out to go unused.

---

## D-043 — Reject non-HTTPS telephony/SMS configuration at startup

**Status:** Accepted

An exploratory test on 2026-08-09 (see `docs/TODO.md`) showed that an
`https://` telephony `BaseUrl` works end-to-end (registration, linking, a
test call), but `ValidateLocalConfiguration()` and
`ValidateSmsCallActionItem()` only checked that `Telephony.BaseUrl` and
every `SmsCallAction.Url` were non-empty — an `http://` value passed
validation and would have been used to register, poll, dial, and fill the
SMS field.

`ValidateLocalConfiguration()` now additionally rejects a `Telephony.BaseUrl`
that does not match `i)^https://`, and `ValidateSmsCallActionItem()` rejects
any `SmsCallAction.Url` that does not match the same pattern, both by
throwing during the existing startup configuration-validation flow (see
`DocBot.ahk`, blocking `MsgBox` + `ExitApp()` on a validation failure). This
reuses the exact pattern already established for
`Telemetry.WebhookUrl` (`Telemetry_ValidateConfiguration()`
in `Telemetry.ahk`) rather than inventing a second HTTPS-check style.

Because `IPTConfig["URL"]` is built directly from the validated
`LocalConfig["Telephony"]["BaseUrl"]`, and every telephony call
(`IPT_register()`, `IPT_poller()`, `IPT_callNumber()`) builds its request URL
from `IPTConfig["URL"]`, rejecting a non-HTTPS `BaseUrl` at startup is
sufficient to keep registration, event polling, and dialing on the same
validated HTTPS base URL — no separate per-call check was needed.

**Rejected alternative:** silently upgrading `http://` to `https://`, or
falling back to HTTP when HTTPS fails. Both were rejected — the project
explicitly does not want a silent production HTTP fallback or a
certificate-validation bypass (see `docs/TODO.md`), and a misconfigured
local file should fail loudly at startup like every other required
`LocalConfig` field, not be silently corrected.

**Consequences**

- `DocBot.local.example.ahk` already used `https://` example values for both
  `Telephony.BaseUrl` and `SmsCallAction.Url`, so the CI syntax-check config
  and normal local setup are unaffected.
- An existing local configuration with an `http://` telephony or SMS URL now
  fails startup with a clear, non-sensitive validation error instead of
  running against an unencrypted endpoint.
- This closes the "Application and documentation" and "Acceptance evidence"
  checklist items in `docs/TODO.md` P1 "Make HTTPS mandatory for telephony
  and SMS URLs" — the latter confirmed by the project owner on a compiled
  test build on managed Windows/the internal hospital network (2026-08-17).
  The "Infrastructure dependencies" items in that same TODO entry
  (production certificate/TLS ownership, reverse-proxy timeouts, disabling
  the HTTP listener) and the separate server-side-authentication question
  remain open — this decision covers application-level enforcement and its
  compiled-build validation, not production infrastructure operations.
- Does not address server/client authentication strength; TLS transport
  encryption alone does not establish client authorization, and that remains
  a separately tracked open question per `docs/TODO.md`.

---

## D-044 — Bound standard-log and problem-report-directory residency to seven days

**Status:** Accepted; implemented on `claude/diagnostics-retention` and
merged into `develop` (final `AppVersion 2.3-diagnostiek-retentie.6`),
confirmed working on a compiled test build.

Covers the two related `docs/TODO.md` P1 items "Limit local standard
diagnostics to seven days" and "Remove temporary problem-report artifacts",
implemented together because both bound how long diagnostic residue sits on
disk.

**Standard-log retention:** `debug.log` and its rotated `debug.log.oud`
previously only shrank via the existing ~2 MB size rotation
(`FlushDebugLog()`); nothing removed old entries by age.
`PruneExpiredDebugLogEntries()` / `PruneExpiredDebugLogFile()` parse each
entry by its own leading timestamp and drop entries older than seven days
from both files independently, rewriting a file only when something was
actually dropped. This also recognizes the pre-`5f72613` (2026-08-07)
undated legacy log format (`^\d{2}:\d{2}:\d{2}\.\d{1,3} `) and treats any
match as unconditionally expired, since the pattern's mere presence proves
the entry predates the current redacted format. An entry matching neither
format is left in place rather than guessed at. This runs once at startup
and then on a repeating 24-hour timer (`RunDiagnosticsMaintenance()`),
because DocBot is a long-running background tool that may not restart for a
long time.

**Problem-report directory lifecycle:** `BuildProblemReportPackage()`
writes loose report files (no ZIP, per D-041) to a temporary
`%TEMP%\DocBot_diagnose_<stamp>` directory.

- Outlook success path (`OpenProblemReportEmail()`): verifies
  `mail.Attachments.Count = files.Length` right after adding attachments,
  then deletes the report directory only after `mail.Display()` succeeds,
  so a later failure in the same `try` block still reaches the fallback
  with an intact directory.
- Manual fallback path (`OpenProblemReportFallback()`): the directory is
  deliberately not auto-deleted, since the user may still need to attach
  the files by hand; it asks explicitly, with "No" as the default so a
  dismissed prompt never deletes anything.
- Abandoned-directory sweep (`PruneAbandonedProblemReportDirs()`) and
  abandoned extended-log sweep (`PruneAbandonedExtendedLogFiles()`) run on
  the same daily timer and delete `DocBot_diagnose_*` directories /
  `problem-report-*.log` files older than seven days, reading the
  timestamp DocBot itself encodes in the filename rather than filesystem
  mtime. This is the backstop for "user chose No and forgot", a crash
  between creation and finalization, or DocBot closing mid-flow. The
  directory-name regex accepts both the current millisecond-suffixed
  format and the older `yyyyMMdd_HHmmss`-only format used before commit
  `2a8127e` (2026-08-08).
- All three sweeps (`PruneExpiredDebugLogFile()`,
  `PruneAbandonedProblemReportDirs()`, `PruneAbandonedExtendedLogFiles()`)
  log a one-line summary every run (counts seen/expired/deleted/failed,
  plus the last error if any deletion failed) — the abandoned-directory and
  extended-log sweeps log unconditionally on every run, not only when
  something was found, kept deliberately on project-owner request as
  ongoing, observable proof in the standard log that the seven-day cleanup
  actually runs.

**Rejected alternatives:** pruning by whole-file modification time instead
of per-entry timestamps (the active log mixes old and recent entries
because it only rotates at ~2 MB, which can take far longer than a week to
fill on a lightly-used installation); deleting the report directory
unconditionally right after building it or right after
`OpenProblemReportEmail()`/`OpenProblemReportFallback()` return (breaks the
manual fallback, which depends on the files still being on disk).

**Consequences**

- Seven days is the shared, documented residency ceiling for the standard
  log, problem-report directories, and orphaned extended-log files; a
  future change to any of them should keep them intentionally in sync or
  explain why they diverge.
- The report-directory sweep depends on `BuildProblemReportPackage()`'s
  exact naming convention (`"DocBot_diagnose_" . FormatTime(A_Now,
  "yyyyMMdd_HHmmss") . "_" . Format("{:03}", A_MSec)`); changing that
  format requires updating the sweep's regex in the same change.
- `InitializeDiagnosticLogging()` still only reads the first 256 bytes at
  startup to decide whether `debug.log` needs wiping, so a not-yet-known
  future log format could still slip past `PruneExpiredDebugLogFile()`'s
  pattern matching the same way the pre-`5f72613` format initially did.
  Tracked separately as `docs/TODO.md` P2 "Harden the standard-log format
  migration check beyond the first 256 bytes" rather than expanding this
  decision's scope.

---

## D-045 — In-product user instruction for safe hotstring content

**Status:** Accepted

`docs/DATA_PROTECTION.md` §3.4 already stated that patient-identifying or
patient-specific information is not intended as content of
`hotstrings.json`, but that the free `Replacement` field has no technical
control enforcing this — compliance was said to rest on user instruction
and organizational policy, while no such instruction actually existed yet
(`docs/TODO.md` P2 "Add a user instruction for safe hotstring content").

The instruction is implemented as a fifth `AddHelpAccordionSection()` entry
on the Help page ("Wat mag ik wel en niet in een hotstring zetten?"),
matching the style of the existing four sections, plus a short, always-
visible hint (`HotPrivacyHint`) on the Tekstvervanging page that links to
that Help section, prefixed with an ℹ️ glyph. The hint sits outside both
`HotEditorCompactCard` and `HotEditorExpandedCard`, so it is visible in
both the compact and the expanded hotstring editor, not only one of them.
`README.md` (Hotstrings section) carries a shorter, consistent summary for
users reading the bundled documentation instead of the in-product Help
page.

Fitting a fifth accordion section required reducing
`RefreshHelpAccordion()`'s `collapsedHeight` from 64 to 54 (and the
matching `AddCard()` height inside `AddHelpAccordionSection()`) so that the
worst case — one section expanded (258) plus four collapsed (4×54) plus
five 12px gaps — still ends at y=638, 16px above the "Probleem melden..."
button at y=654 (unchanged).

Fitting the new hint below the hotstring-editor cards required the
Tekstvervanging page's editor cards to stop extending past y=648 in their
expanded state. `HotEditorExpandedCard` shrank from height 230 to 196
(matching `HotEditorCompactCard`), `HotReplacementMultiGroup`'s height
from 70 to 56, and `HotSaveButton` moved from two conditional positions
(y=590/626, set in `ApplyHotReplacementEditorState()`) to one fixed
position (y=602) that fits under the multiline field in both states. This
in turn made it natural to align the "Snelkiesnummer bewerken" card on
Telefonie (already ending at y=648) with the Over page's content card
(enlarged from height 500 to 556, so it also ends at y=648) — Hotstrings,
Telefonie and Over now share the same bottom edge, at the project owner's
request. The Help page and other non-full-height pages were deliberately
left out of this alignment, since they are not designed to fill the
window.

The hint and the Over page's GitHub link went through two rounds of
project-owner feedback on their exact vertical position. First placed at
y=654 (the row already used by the Help page's "Probleem melden..."
button), they moved to y=672 to match the y-position of the "Sluiten
verbergt DocBot in het systeemvak" footer on Overzicht and Telefonie
instead — `githubLink`'s height shrank from 34 to 24 in that change, since
34 at y=672 would have reached y=706, past the fixed 700px-tall window.
`HotPrivacyHint`'s font grew from s9 to s10 in the same round, matching
`githubLink`'s size; its color stayed `C["Muted"]` (only size was asked to
match, not color).

y=672 turned out to sit close to the window's bottom edge rather than
centered in the space below the cards, so both controls moved again to be
vertically centered in the 52px gap between the shared card bottom (y=648)
and the window edge (700): `HotPrivacyHint` (h=22) to y=663
(`648 + (52-22)/2`, 15px margin above and below) and `githubLink` (h=24) to
y=662 (`648 + (52-24)/2`, 14px margin above and below). This intentionally
no longer matches the Overzicht/Telefonie footer's y=672 or the Help page's
"Probleem melden..." button at y=654 — centering these two specific
controls took priority over sharing an exact row with those.

Ownership of the instruction's content and its periodic review sits with
the project owner; there is, for now, deliberately no separate
organizational-onboarding text — the in-product instruction (Help +
README) is intended to cover this on its own.

Screenshots of the new accordion body and the enlarged Over page surfaced
an unrelated, pre-existing bug in `RoundControl()` (the shared helper
behind `AddRound()`, used to give many controls rounded corners via
`SetWindowRgn`): it built the rounded region from `GetClientRect`, which
by definition excludes any scroll bar, then applied that undersized region
to the whole control window via `SetWindowRgn` — whose region coordinates
are window-relative, not client-relative. The result: the vertical
scroll bar strip fell outside the region and was clipped away entirely,
on any rounded control that has one. Across all `AddRound()` call sites,
that is exactly `bodyEdit` (the Help accordion's RichEdit body, `AddRound`
radius 8) and `aboutEdit` (the Over page's edit control, radius 10) — the
two controls the project owner reported as having no visible way to tell
that scrolling was possible. `RoundControl()` now measures with
`GetWindowRect` instead, which includes the scroll bar. This is a general
fix to a shared helper, not something specific to this decision's own
controls, but it was found and is fixed in the same change because it
directly affects the readability of the Help section added here.

The `HotPrivacyHint` link ("Bekijk de richtlijn op de Help-pagina") only
switched to the Help page, leaving `HelpOpenSection` (which section is
expanded) untouched — the user would still have to find and open the right
accordion section by hand. A new `OpenHotstringHelpSection()` handler now
sets `HelpOpenSection` to `HotstringHelpSectionIndex` (captured as
`HelpSections.Length` right after that section's `AddHelpAccordionSection()`
call, so it tracks the section's position even if sections are reordered
later) before calling `ShowPage("help")`, which already refreshes the
accordion layout and redraws — no separate refresh/redraw call was needed
in the new handler.

The project owner also reported the accordion body sometimes showing a
blue text selection. `FormatHelpBody()` already collapsed its own
formatting selection at the end, so that wasn't the cause; the real cause
is that a plain click or double-click inside a read-only RichEdit is
still, by default, a normal text-selection gesture. `HelpRichEditSubclass()`
already intercepted `WM_LBUTTONDOWN` to detect link clicks, but let every
non-link click fall through to `DefSubclassProc`, which started RichEdit's
normal caret/selection handling. It now returns 0 (swallows the message)
for every `WM_LBUTTONDOWN` and `WM_LBUTTONDBLCLK` on a registered help
body, whether or not the click landed on a link — a link click still
navigates, everything else is now a no-op instead of a selection. This
only covered bodies already registered in `HelpLinkControls`, which
`RegisterHelpLinkControl()` only populated when a section had
`linkTargets`; a future section without any links would have kept the
selection bug. `AddHelpAccordionSection()` now calls the new, idempotent
`EnsureHelpRichEditSubclass()` for every body unconditionally (extracted
from `RegisterHelpLinkControl()`'s subclass-install code, now shared via
`InstallHelpRichEditSubclass()`), so the fix applies regardless of whether
a given section has links.

That fix covered clicks landing directly on a body's own text, but the
project owner then found a second, related selection bug specific to
`OpenHotstringHelpSection()`: clicking "Help" on the hint (on the
Tekstvervanging page) navigates to Help and opens the fifth section, and
its entire body text appeared selected once shown — not just a small
range. `FormatHelpBody()` already collapses its own formatting selection,
but only once, at GUI build time; this happens later, at navigation time.
The likely mechanism: the click originates on a different control
(`HotPrivacyHint`, a SysLink) on a different page; once that control is
hidden by the page switch, Windows appears to hand keyboard focus to the
now-visible RichEdit body, combined with leftover mouse state from the
originating click, which RichEdit interprets as a drag-select from
position 0 to wherever that state maps on screen — far below the body's
visible text, which clamps to "select to end of document." `RefreshHelpAccordion()`
now calls a new `ClearHelpBodySelection()` (`EM_SETSEL` to `0,0`, the same
one-line technique already used in `FormatHelpBody()`) on a section's body
immediately when it becomes the open one — covering the normal
click-a-header-to-toggle path too, not only navigation from the hint.
Because the project owner also observed the selection surviving until a
later, unrelated interaction (double-click, switch windows, switch back),
suggesting whatever sets it can still arrive slightly after this point in
the message queue on the cross-page-navigation path, `RefreshHelpAccordion()`
additionally schedules one deferred re-clear 50ms later via
`SetTimer(ClearHelpBodySelection.Bind(...), -50)`, so a delayed message
doesn't win the race. The exact Windows-internal cause was not confirmed
through live debugging (not available from this environment); the fix is
deliberately unconditional and applied at every section-open, so it holds
regardless of which precise mechanism causes it.

**Rejected alternatives:** a technical content filter on the `Replacement`
field that tries to detect patient-identifying text — rejected because
free text cannot be reliably classified this way (the instruction itself
says so, per the TODO's explicit requirement); leaving the expanded editor
card taller than the compact one — rejected because it would either cover
the new hint in expanded state or force the hint to move depending on
`HotReplacementExpanded`, defeating the "visible in both states"
requirement.

**Consequences**

- Closes all six content requirements and the placement/ownership
  requirement of `docs/TODO.md` P2 "Add a user instruction for safe
  hotstring content"; `docs/DATA_PROTECTION.md` §3.4 no longer needs to
  describe this as an open follow-up action.
- `hotstrings.json` still has no technical enforcement of this policy —
  unchanged from before this decision, and consistent with the rejected
  alternative above.
- Any future change to the Tekstvervanging, Telefonie or Over page layout
  that moves a card's bottom edge away from y=648 should keep
  `HotPrivacyHint` and `githubLink` centered in the space below it (or
  explicitly record why they diverge), independently of the
  Overzicht/Telefonie footer row at y=672.
- The `RoundControl()` fix applies to every current and future
  `AddRound()` target with a scroll bar, not only `bodyEdit`/`aboutEdit`;
  any control that gains both in the future gets a working scroll bar for
  free instead of needing its own fix.
- `HotstringHelpSectionIndex` and `OpenHotstringHelpSection()` only cover
  the one hint on Tekstvervanging; a future "jump straight to an open
  accordion section" link elsewhere would need its own index variable and
  handler, or a small generalization of this pattern.
- `EnsureHelpRichEditSubclass()`/`InstallHelpRichEditSubclass()` mean every
  future `AddHelpAccordionSection()` call automatically gets both the
  link-click handling and the no-selection behavior, with no per-call
  opt-in required.
- `ClearHelpBodySelection()` runs on every section open, from any entry
  point (header click, `OpenHotstringHelpSection()`, or any future
  "open Help at section N" caller), so a future caller does not need to
  remember to clear the selection itself.
- If a compiled test build still shows the selection despite this fix, the
  50ms deferred re-clear's delay may need to increase, or the actual
  Windows-internal cause should be identified rather than tuning the delay
  further blind.
- Implemented on branch `claude/hotstring-user-instruction-hcv2jw`
  (`AppVersion 2.3-hotstring-instructie.6`); not yet validated on a
  compiled build on Windows (see D-037) — layout math was verified by hand
  against the fixed 1000×700 window size, not by rendering the GUI.

---

## D-046 — Log bundled-package load outcomes per file; route every storage error through the standard log

**Status:** Accepted

The project owner built a custom bundled hotstring package that failed to
load, with no way to tell which file was at fault: `InitializeBundledPackages()`
wrapped manifest parsing and every package file in one `try`/`catch`, so a
single bad file discarded `BundledPackages` entirely (silently dropping any
already-valid packages too) and surfaced only one generic message via
`ReportStorageError()`. `ReportStorageError()` itself never wrote to the
standard log (`DebugLog()`) — it only showed a `MsgBox` or a tray
notification — so the failure, and its message, left no trace in
`debug.log` at all.

`InitializeBundledPackages()` now logs the manifest path before parsing it,
then tries each manifest-listed package file in its own inner
`try`/`catch`: a `DebugLog("→", "Pakket laden", ...)` line before the
attempt, a `DebugLog("✓", "Pakket geladen", ...)` line with name, id,
version and item count on success, and — on failure — the file is skipped
(not the whole run) and the error goes through `ReportStorageError()`,
prefixed with the failing file name. A summary line
(`DebugLog("i"/"!", "Pakketten geladen", ...)`) reports how many packages
loaded and how many failed. Manifest-level problems (missing/invalid
manifest, unsupported manifest `schemaVersion`, a malformed `packages`
entry) stay fatal for the whole batch, since they are infrastructure the
per-file packages depend on, not a property of one file.

`ReportStorageError()` now always calls `DebugLog("✕", "Opslagfout", message)`
before showing the `MsgBox` or tray notification, so every caller across the
codebase (bundled packages, `hotstrings.json`, `settings.ini`/JSON blobs,
speed dials) gets its error text into the standard log automatically,
without touching each call site. Two `LoadBundledPackageFile()` error
messages that previously omitted the file path (`Pakketitem N mist veld ...`
and `... bevat een lege id, trigger of vervanging`) now include it, matching
every other error message in that function.

**Rejected alternatives:** adding a manual `DebugLog()` call next to every
existing `ReportStorageError()` call site instead of logging inside
`ReportStorageError()` itself — rejected as repetitive and easy to miss on
a future call site; leaving package-file failures fatal for the whole
manifest — rejected because it means one broken custom package also takes
down every bundled package that loaded fine, which is what produced the
original, hard-to-diagnose report.

**Consequences**

- A broken custom or bundled package file no longer silently empties
  `BundledPackages`; only that package is missing, and `debug.log` names
  the exact file and reason.
- Any future `ReportStorageError()` caller gets standard-log coverage for
  free; no call site needs its own `DebugLog()` call for that purpose.
- `InitializeBundledPackages()`'s return value now reflects whether *any*
  package failed (`failedCount = 0`), not only whether the manifest itself
  parsed; the return value is currently unused by its one call site.
- Not yet validated on a compiled build on Windows (see D-037) — the
  control-flow change (inner `try`/`catch` per package file) was verified
  by source review only.
- Implemented on branch `claude/hotstring-package-load-logging-w4cc5a`
  (`AppVersion 2.3-pakket-logging.1`).

---

## D-047 — Bundled-package file set is dynamic in both the dev and compiled build

**Status:** Superseded by D-048

D-048, agreed the same day, replaces this decision's compiled-build half
(build-time zip + `FileInstall` + `Shell.Application` extraction into a
local cache) with reading package files directly from a network share at
every startup — once the project owner pointed out that the compiled
`DocBot.exe` itself already runs from a network share, so a share outage
already stops DocBot entirely and a separate embedded/local fallback for
packages specifically adds no practical resilience. D-048 also drops this
decision's dev-build local-cache copy step entirely: the dev build now
reads `*.json` files under `packages/` in place instead of copying them to
`%LocalAppData%\DocBot-dev\packages` first. This entry is kept for the
reasoning trail — the `FileInstall`-cannot-embed-a-wildcard constraint
below still holds and still shaped D-048's compiled-build design.

D-046's new per-file logging immediately surfaced the project owner's real
problem: a custom package (`anest.json`) was correctly listed in a locally
edited `packages/manifest.json`, but `InitializeBundledPackages()` reported
"Pakketbestand niet gevonden" for it. The cause was not, as first suspected,
that the uncompiled dev build skips copying packages to a local cache — it
does copy them. The actual cause was `InstallBundledPackageFiles()`
hardcoding the bundled file set in two places that both had to be kept in
sync by hand with `packages/manifest.json`: a `packageFiles` array (used for
`FileCopy` in dev) and one literal `FileInstall` line per file (used for the
compiled build). A new package file added to `packages/` and to the manifest
but not to this array/list silently never reached
`%LocalAppData%\...\packages`, in either build — the dev case is exactly
what the project owner hit.

`InstallBundledPackageFiles()` now derives the file set dynamically on both
paths instead of maintaining a hardcoded list:

- **Dev/uncompiled:** `Loop Files, A_ScriptDir "\packages\*.json"` copies
  every `*.json` file under the source `packages/` directory. No list to
  maintain; any file dropped into `packages/` is picked up on the next
  start.
- **Compiled:** Ahk2Exe's `FileInstall` fundamentally cannot embed a
  wildcard or a dynamically generated list — only literal, individual
  source paths, a hard constraint of the compiler, not a choice made here
  (already noted in the pre-existing code comment this decision replaces).
  The fix moves the dynamism to *build time* instead: `Build-EPD_Machine.bat`
  zips `packages/` into one `packages.zip` immediately before invoking
  Ahk2Exe; `DocBot.ahk` embeds that single, always-literal file via one
  `FileInstall` call. At startup, the compiled app extracts the archive into
  the packages cache using the `Shell.Application` COM object
  (`Namespace(...).CopyHere()`), which ships with Windows and adds no
  external dependency (no PowerShell/`Expand-Archive` subprocess on the
  client machine, unlike `Build-EPD_Machine.bat`'s own build-time use of
  PowerShell, which only runs on the build machine). `CopyHere()` is
  asynchronous, so `ExtractBundledPackagesZip()` polls the destination
  directory's item count against the archive's item count, with a 10-second
  timeout that raises a clear error (through `ReportStorageError()` /
  `debug.log`, per D-046) instead of `InitializeBundledPackages()` silently
  reading a half-extracted directory.

Both paths now also clear the target `packages` cache directory before
(re)installing, so a package file removed or renamed in a later version does
not linger in the cache indefinitely — a pre-existing gap neither the old
`FileCopy` loop nor the old `FileInstall` lines closed, fixed here because
the rewrite already touches this exact code path. Clearing first also makes
`ExtractBundledPackagesZip()`'s item-count wait unambiguous: without it, a
cache already populated by a previous run could satisfy the expected count
before the new `CopyHere()` had actually finished writing, on a build where
the file count happens not to change.

**Rejected alternatives:** manually adding `anest.json` to the existing
hardcoded lists — rejected because it fixes this one report but leaves the
same silent-drop trap for the next custom or bundled package; keeping the
per-file `FileInstall` lines and only fixing the dev-side array — rejected
because the project owner explicitly asked for both build types to be
dynamic, and the compiled build is what end users actually run, so leaving
it manually maintained would leave the more consequential half of the bug
in place.

**Consequences**

- Adding, renaming, or removing a package file under `packages/` (plus its
  `manifest.json` entry) never requires a `DocBot.ahk` change again, in
  either build type — only a rebuild.
- `Build-EPD_Machine.bat` gained a build step and a new failure mode
  (`Compress-Archive` failing, or producing no `packages.zip`), both
  checked explicitly and both abort the build with a clear message before
  Ahk2Exe runs, matching the script's existing pre-flight-check style.
  `packages.zip` is a build artifact: written next to `DocBot.ahk`,
  `.gitignore`d, and deleted again after a successful (or failed) compile.
- The compiled app now depends on the Windows Shell's zip-folder
  functionality (`Shell.Application` opening a `.zip` as a `Namespace`),
  built into Windows since XP but in principle disableable by policy in a
  locked-down managed environment; this has not been confirmed against the
  hospital's actual machine policy.
- Not yet validated on a compiled build on Windows (see D-037) — neither
  the `Compress-Archive` build step, the `FileInstall`-of-a-zip path, nor
  the `Shell.Application` extraction and its polling wait have been
  exercised outside source review. This decision carries more startup-path
  risk than D-046 alone (a failed or slow extraction now sits before every
  other startup step that depends on `BundledPackages`), so compiled-build
  validation matters more here than for most recent decisions.
- Implemented on branch `claude/hotstring-package-load-logging-w4cc5a`
  (`AppVersion 2.3-pakket-logging.2`).

---

## D-048 — Bundled packages are read live from their source, no embedding or local cache

**Status:** Accepted

Before D-047's build-time zip/`FileInstall`/`Shell.Application` approach was
implemented against real machine behavior, the project owner asked whether
package JSON could instead be read "remote" for both build types — from the
`packages/` subdirectory next to the script for the dev build, and from a
fixed network share for the compiled build — with an eye toward later
refreshing that content dynamically. Asked what should happen if that share
is unreachable at startup, the project owner pointed out the deciding fact:
the compiled `DocBot.exe` itself is already distributed and run from a
network share (see `Build-EPD_Machine.bat`'s deploy step), so a share
outage already means DocBot does not run at all. A separate embedded or
locally cached fallback specifically for package content would therefore
not add practical resilience — it can only ever help in the narrow window
where DocBot has already started but the share drops before a later
restart, not the far more common "share down, DocBot never starts" case.

This removes the need for D-047's entire build/embed/extract machinery.
`GetBundledPackageDirectory()` now only resolves *where* to read from, and
`InitializeBundledPackages()` (D-046) reads `manifest.json` and every
package file directly from that location on every start — no copy step, no
local cache, nothing embedded in the executable:

- **Uncompiled/dev build:** `A_ScriptDir "\packages"` — unchanged in
  spirit from before D-047, but now read in place instead of copied to
  `%LocalAppData%\DocBot-dev\packages` first.
- **Compiled build:** `LocalConfig["Packages"]["ShareDir"]` from
  `DocBot.local.ahk`, a UNC path with `manifest.json` and the package files
  directly in it. Real internal paths never belong in Git, so this follows
  the same `DocBot.local.ahk`/`DocBot.local.example.ahk` split already used
  for `Telephony.BaseUrl` and `SmsCallAction.Url` (D-003). Unlike those two,
  `Packages` is an optional `LocalConfig` section:
  `ValidateLocalConfiguration()` only checks `ShareDir`'s shape (non-empty,
  starts with `\\`) when the section is present, and does not require the
  section to exist at all. A missing section, or a configured share that is
  unreachable when `InitializeBundledPackages()` actually tries to read it,
  is reported and logged the same way as any other package load failure
  (D-046) — DocBot simply loads no bundled packages that session rather
  than refusing to start. Personal hotstrings, telephony, and every other
  feature are unaffected either way; only the optional bundled-package
  catalogue depends on this share.

Because every start re-reads the source directly, editing a package file on
the share (or, for developers, under `packages/`) is visible to users at
their next DocBot restart — no rebuild, no recompiling, no redeploying the
executable. This is a stronger and simpler answer to "dynamically
refreshable" than D-047's approach, which still required a full
build-and-redistribute cycle for every package change.

D-047's `Build-EPD_Machine.bat` changes (the `Compress-Archive` step and its
pre-flight checks) and the `/packages.zip` `.gitignore` entry are reverted
in full as part of this decision; the batch script and `.gitignore` are back
to their pre-D-047 state.

**Rejected alternatives:** keeping D-047's embedded default catalogue as a
fallback layer that the share then overlays/refreshes — rejected per the
project owner's own reasoning above: it only covers a narrow, rare failure
window and would keep all of D-047's build/extraction complexity (and its
unvalidated `Shell.Application`/`Compress-Archive` risk, see D-047's
consequences) for that narrow benefit; a local cache of the last
successfully read packages, refreshed opportunistically — rejected for the
same reason, plus it reintroduces a staleness question (how old is "too
old" for cached content) that reading live from the source avoids entirely;
refreshing packages during a running DocBot session, not only at startup —
not rejected outright but deliberately out of scope here (not asked for by
the project owner beyond the initial question, and it would need
re-indexing of active hotstrings/conflicts and the Package Manager UI while
potentially open); can be revisited later without changing this decision's
core read-live-from-source model.

**Consequences**

- Adding, editing, or removing a package file at the source is visible to
  every DocBot instance at their next restart, for both build types, with
  no `DocBot.ahk` change and no compiled-build redistribution — a
  meaningfully stronger property than D-047 delivered.
- `Build-EPD_Machine.bat` no longer has a packaging step; it is back to
  compiling `DocBot.exe` directly, same as before D-047.
- `DocBot.local.example.ahk` gained an optional `Packages.ShareDir` entry
  and `ValidateLocalConfiguration()` gained `ValidatePackagesConfiguration()`
  to check its shape when present. Existing `DocBot.local.ahk` files
  without a `Packages` section keep working unchanged (packages simply
  don't load until the section is added) — this was a deliberate choice to
  avoid retroactively breaking every existing local configuration the way
  making it a required section (like `Telephony`) would have.
  `DocBot.local.ahk` itself is never committed (D-003); only the project
  owner needs to add the real share path there. `Packages` joins
  CLAUDE.md's/AGENTS.md's "Lokale configuratie" list of values that live
  only in `DocBot.local.ahk`.
- No package content is embedded in the executable, at all. DocBot's
  bundled-package catalogue for a given user session now depends entirely
  on the configured share being reachable at startup — acceptable per the
  project owner's stated reasoning, but worth restating plainly: an
  otherwise-running DocBot with a since-dropped share connection keeps
  whichever packages it already loaded at its last successful start (they
  live in memory in `BundledPackages`, not re-read mid-session) until the
  next restart, at which point a still-down share means no packages that
  session, logged per D-046.
- `EnvGet("LocalAppData")`-based caching, `SplitPath`-derived cache roots,
  and every other piece of D-047's local-cache-directory logic are gone;
  `BundledPackageDir` can now be either a local path or a UNC path, and
  every downstream consumer (already only doing ordinary string
  concatenation and `FileRead`/`FileExist`, both UNC-transparent on
  Windows) needed no further changes.
- Windows' SMB timeout behavior for a genuinely unreachable (not merely
  empty) UNC path has not been characterized here; if it turns out to
  block `FileExist`/`FileRead` for many seconds on a dropped share, a
  restart attempt during that specific failure mode could feel like a hang
  rather than a fast, clean "no packages" outcome. Not addressed in this
  decision — flagged for compiled-build validation.
- Not yet validated on a compiled build on Windows (see D-037) — reading
  package JSON from an actual UNC path (permissions, SMB timeout behavior
  on an unreachable share, `ValidatePackagesConfiguration()`'s regex) has
  only been reviewed as source, not run.
- Implemented on branch `claude/hotstring-package-load-logging-w4cc5a`
  (`AppVersion 2.3-pakket-logging.3`).

---

## D-049 — Compiled build auto-detects its package source via A_ScriptDir; `Packages.ShareDir` becomes an override

**Status:** Accepted

D-048 required every compiled deployment to set
`LocalConfig["Packages"]["ShareDir"]` explicitly. The project owner then
asked whether DocBot could determine that network path itself when launched
via Ivanti (a software-deployment/launch tool). The relevant fact: DocBot's
compiled build already reads `A_ScriptDir` for other purposes and — for a
compiled AutoHotkey v2 script — `A_ScriptDir` resolves to the directory
containing the running `.exe`. If a launcher such as Ivanti starts
`DocBot.exe` directly from its network location ("run from source"), rather
than staging a local copy first and running that, `A_ScriptDir` already
equals that network share, with no separate configuration needed at all —
mirroring exactly how the dev build already resolves its own `packages/`
directory.

The failure mode this can't rule out from source alone: some
deployment-tool configurations copy the executable to a local (often
temporary) folder before running it. In that case `A_ScriptDir` resolves to
the local copy's directory, not the share, and a `packages` subfolder would
not exist there. Since this depends entirely on how the project owner's
specific Ivanti Application is configured — information not available from
this environment — the fix combines both pieces the project owner asked
for instead of guessing:

1. `GetBundledPackageDirectory()` now writes `A_ScriptDir`'s value to the
   standard log unconditionally, on every start (dev and compiled alike),
   specifically so a real Ivanti-launched run can be checked against
   `debug.log` to see what DocBot actually sees itself running from.
2. The compiled build tries `LocalConfig["Packages"]["ShareDir"]` first, if
   set; only when that is absent does it fall back to the auto-detected
   `A_ScriptDir "\packages"`. Both branches log which one was used and the
   resulting path (`"i", "Pakketten bron", ...`). `ValidatePackagesConfiguration()`
   (D-048) is unchanged — `Packages` stays an optional `LocalConfig`
   section, now explicitly framed as an override rather than the only way
   to configure this.

This means a correctly "run from source" Ivanti deployment needs zero
`DocBot.local.ahk` configuration for packages at all; a deployment that
turns out to stage a local copy can be fixed by setting `ShareDir`
explicitly, discoverable from the same `A_ScriptDir` log line without
needing to guess or experiment blindly.

**Rejected alternatives:** requiring `Packages.ShareDir` unconditionally
(D-048's original shape) — superseded here specifically because it forces
manual configuration even in the common case where auto-detection already
works, and because keeping the deploy location and the configured
`ShareDir` in two separate places invites them silently drifting apart;
detecting "was this copied locally" some other way (e.g. comparing
`A_ScriptDir` against a known-share-prefix pattern) — rejected as more
complex and less reliable than simply letting an explicit override win when
one is present, which handles the "auto-detection guessed wrong" case
without DocBot needing to guess *why* it guessed wrong.

**Consequences**

- No `DocBot.local.ahk` changes are needed for packages at all, for a
  compiled deployment that runs directly from its network location — the
  common case this was built for.
- The `A_ScriptDir` log line is unconditional and cheap (one `DebugLog`
  call), so it costs nothing on installs that never need it, while being
  the exact piece of evidence needed to diagnose the one case that does
  (local-copy launch).
- `Packages.ShareDir`'s meaning changes from "the only way to configure
  this" (D-048) to "override when auto-detection would be wrong" — existing
  `DocBot.local.ahk` files that already set it keep working identically,
  since an explicit value still always wins.
- Still not yet validated on a compiled build on Windows, and specifically
  not yet validated against an actual Ivanti-launched run (see D-037,
  D-048) — whether the project owner's Ivanti Application configuration
  runs `DocBot.exe` from source or from a local staged copy is exactly the
  open question the new `A_ScriptDir` log line exists to answer, and is not
  yet answered.
- Implemented on branch `claude/hotstring-package-load-logging-w4cc5a`
  (`AppVersion 2.3-pakket-logging.4`).

---

## D-050 — The resolved package path is shown on screen, not in the standard log

**Status:** Accepted

Testing D-049 immediately showed the flaw: `SanitizeLogText()` (D-031's
standard-log sanitization, in place well before this work) unconditionally
redacts anything shaped like a local drive path (`X:\...` → `<lokaal pad
afgeschermd>`) or a UNC path (`\\...` → `<netwerkpad afgeschermd>`) before a
line ever reaches `debug.log` — by design, because the standard log can be
attached to an emailed problem report, and a local path frequently contains
the Windows username. The new `A_ScriptDir`/"Pakketten bron" log lines went
through this same path, so the one piece of information they existed to
show — the actual resolved directory — was exactly what got stripped out
every time. Bypassing sanitization for just these lines was rejected
immediately: it would carve a one-off exception into the same privacy
guarantee D-030/D-031 established for the whole standard log, for a value
that predictably contains the Windows username.

The redacted placeholder text is not entirely useless on its own — which
category matched (`<netwerkpad afgeschermd>` vs. `<lokaal pad afgeschermd>`)
already answers the yes/no version of the Ivanti question (UNC vs. local
drive path) without revealing the path itself — but the project owner
wants the actual path, not just that classification.

The fix moves the diagnostic to a surface that is never written to disk or
emailed: the Hotstringpakketten (Package Manager) window, which is only
ever visible to whoever is already sitting at the machine. The first
attempt appended `BundledPackageDir` to `RefreshPackageManagerItems()`'s
"Selecteer links een pakket." status text — but a screenshot from the
project owner immediately showed why that doesn't work in practice: a
package (and often an item within it) is normally already selected the
moment the window opens, which overwrites that same status-text control
with item/conflict details before it can ever be read. The path now lives
instead in the window's static intro text (`"Kies links een pakket..."`,
just below the title), which no selection-change handler ever touches —
extending its height from 28 to 36px uses space already free above the
list views (`y54 + h36 = 90`, exactly where they start), so no other
control needed to move. The zero-packages case — arguably the most
important one to diagnose, since it means the Package Manager window would
otherwise never open at all — gets the same unsanitized path in its
`MsgBox` instead.

**Rejected alternatives:** bypassing or weakening `SanitizeLogText()` for
this one log label — rejected per D-030/D-031 above; adding a new,
separately-consented "show raw diagnostics" log tier — rejected as
disproportionate for a single path value when an existing, always-available
GUI surface already solves it with no new consent flow or storage.

**Consequences**

- The `A_ScriptDir`/"Pakketten bron" standard-log lines from D-049 stay as
  they are (still sanitized, still useful for the network-vs-local
  classification) — this decision adds a second, complementary surface
  rather than replacing them.
- Anyone diagnosing an Ivanti launch now opens **Pakketten** (or triggers
  its "no packages" message) instead of reading `debug.log` for this
  specific value.
- `ShowPackageManager()` now reads the `BundledPackageDir` global, which it
  did not previously depend on; `RefreshPackageManagerItems()`'s status text
  is unchanged from before this decision.
- The path is visible only while the Package Manager window is open with
  nothing selected, or in the zero-packages message — not a permanent,
  always-on-screen indicator. Acceptable for a diagnostic aid; revisit if
  this needs to be checkable without opening that window.
- Not yet validated on a compiled build on Windows (see D-037) — the
  `MsgBox`/intro-text wording and the two-line static text's rendering
  were reviewed as source only.
- Implemented on branch `claude/hotstring-package-load-logging-w4cc5a`
  (`AppVersion 2.3-pakket-logging.6`).

---

## D-051 — `RefreshPackageManagerItemDetails()` re-checks its status control before every write, not only at entry

**Status:** Accepted

While testing D-050, the project owner hit an unrelated, pre-existing crash
in the Package Manager: `Error: This value of type "Integer" has no
property named "Value"` at `PackageManagerStatusText.Value := detail`
inside `RefreshPackageManagerItemDetails()`. That function already guarded
against a destroyed GUI, but only once, at entry
(`if !IsObject(PackageManagerStatusText) return`). `RefreshPackageManagerItems()`'s
own comments already document why that single check is not enough for this
window: "De gebruiker kan het venster sluiten terwijl de statusindex wordt
opgebouwd" (the user can close the window while the status index is still
being built) — `GetPackageItemStatus()`/`FindPackageItemConflict()` scan
every active package's items for conflicts, which is slow enough on a large
package (the project owner's own test had a 1,393-item package active) that
AHK can dispatch a window-close event mid-function, which runs
`ClosePackageManager()` and resets `PackageManagerStatusText` to `0` before
`RefreshPackageManagerItemDetails()` reaches its own final write — passing
the entry guard is no protection against that happening later in the same
call. This is not a consequence of any of D-046 through D-050's changes;
none of them touch this function. It surfaced now simply because a large
package made the race easier to hit while testing them.

The fix re-checks immediately before each of the function's two writes to
`PackageManagerStatusText`, using `IsLiveGuiControl()` — the same
`DllCall("IsWindow", ...)`-backed helper `RefreshPackageManagerItems()`
already uses for its own controls, for consistency and because it catches a
stale-but-still-object control reference, not only a reset-to-`0` global.

**Rejected alternatives:** wrapping the whole function in `Critical` to
block interruption — rejected because `GetPackageItemStatus()` on a large
package is exactly the kind of long-running work `Critical` would make
worse to interrupt cleanly (e.g. blocking the close button entirely while
it runs, rather than letting the close proceed and this function simply no
one write its now-stale result).

**Consequences**

- Closing the Package Manager window while a large package's status is
  still being computed no longer crashes; the in-flight refresh silently
  discards its result instead, which is correct since there is no longer a
  window to show it in.
- Established the same "re-check `IsLiveGuiControl()` before every write,
  not only at function entry" pattern already used in
  `RefreshPackageManagerItems()` should be considered for equivalent
  functions with slow per-item work — not applied elsewhere in this
  decision, since `RefreshPackageManagerPackages()`'s own loop is a fast
  flat `.Add()` per package with no per-item conflict scan and no report of
  it crashing this way.
- Not yet re-validated on a compiled build on Windows (see D-037) after
  this fix — the original crash was caught on a real compiled build, but
  the fix itself has only been reviewed as source.
- Implemented on branch `claude/hotstring-package-load-logging-w4cc5a`
  (`AppVersion 2.3-pakket-logging.6`).

---

## D-052 — `Build-EPD_Machine.bat` populates each deploy target's `packages` folder

**Status:** Accepted

D-049's auto-detection (`A_ScriptDir "\packages"`) assumed the compiled
`DocBot.exe` and a populated `packages/` folder would end up side by side.
The project owner pointed out the real deploy layout doesn't match that
assumption on its own: `Build-EPD_Machine.bat` compiles `DocBot.exe` next to
`DocBot.ahk` (inside the git checkout), then deploys a *copy* one directory
above it, to `PARENT_DIR\APP_NAME.exe` (the `:deploy` subroutine, already
existing before this branch). `A_ScriptDir` for that deployed, running copy
therefore resolves to `PARENT_DIR` — one level above the checkout that
actually contains `packages/`. Without this decision, D-049's auto-detected
path would reliably point at a `packages` folder that never gets created,
making the "auto" half of D-049 non-functional for the project's own real
deployment shape, not just a hypothetical Ivanti edge case.

`:deploy` now calls a new `:sync_packages` subroutine right after an
executable is successfully placed and verified, once per deploy target
(so both the main `DocBot`/`DocBot-test`/`DocBot-dev` target and the
optional sibling `EPD_Machine` target get their own `packages` folder).
Per the project owner's own two-step reasoning during this conversation —
first proposed as "check whether populated, copy if not, else install the
newest version," then revised to the simpler final shape — the logic is:

- `PARENT_DIR\packages` does not exist yet → copy it fresh from this
  checkout's own `packages\`, no prompt (nothing to lose).
- `PARENT_DIR\packages` already exists → ask interactively (`choice /C JN`,
  the same pattern already used for the EPD_Machine copy question) whether
  to replace it with this checkout's current `packages\`. A "no" leaves it
  untouched — deliberately, so a deploy-target `packages` folder a project
  owner has hand-edited (e.g. added a custom package directly on the share)
  is never silently clobbered by a routine rebuild. A "yes" deletes the
  existing folder and copies fresh, rather than merging, so a package
  removed or renamed in the checkout actually disappears from the deploy
  target too instead of lingering alongside the new set.

**Rejected alternatives:** always overwriting without asking — rejected
because it would silently destroy any package added directly on a deploy
share outside the normal `packages/`-in-git workflow (the project owner's
own `anest.json` experiment, from earlier in this conversation, is exactly
such a case); merging instead of replacing on overwrite — rejected because
a merge can't express "this package was intentionally removed," which
matters just as much here as it did for `InitializeBundledPackages()`'s own
now-removed local-cache-clearing logic (D-048).

**Consequences**

- D-049's auto-detected path now actually resolves to a real, populated
  folder after a normal `Build-EPD_Machine.bat` run, for every deploy
  target the script knows about — closing the gap this decision exists to
  fix.
- Running `Build-EPD_Machine.bat` against a deploy target that already has
  a hand-edited `packages` folder now pauses for a yes/no prompt every
  time, unless answered "yes" to accept the checkout's version once and for
  all going forward (there is no "always overwrite" or "never ask again"
  option here — every run asks again if the folder still exists).
- This is `Build-EPD_Machine.bat`-only; it does not touch `DocBot.ahk`, so
  per the branch-versioning rules in `CLAUDE.md`/`AGENTS.md` this commit
  does not bump `global AppVersion`.
- Not yet validated on a compiled build on Windows (see D-037) — the batch
  logic (`xcopy`/`rd`/`choice` interplay, `errorlevel` propagation through
  `:sync_packages`'s own `setlocal`) has only been reviewed as source, not
  run.
- Implemented on branch `claude/hotstring-package-load-logging-w4cc5a`.

---

## D-053 — Document the migration registry and add an opt-in self-test entry point, without a code module split

**Status:** Accepted; implemented on `claude/schema-migrations-setup-waiigd`,
merged into `claude/hotstring-package-load-logging-w4cc5a`
(`AppVersion 2.3-schema-migraties.1` originally; renumbered from this
branch's own D-046 to D-053 on merge, see that branch's D-046 through D-052
above), confirmed working by the project owner on real Windows/AutoHotkey
v2 (2026-08-19): `AutoHotkey64.exe DocBot.ahk --selftest`, run interpreted
(not yet as a compiled `.exe`), produced all 24 `ok` lines and exited
cleanly, with `%TEMP%\docbot-selftest-results.txt` written and readable as
designed. The project owner also separately confirmed the related
`ReportStorageError()` regression (D-046): a normal hotstring/speed-dial
storage error still shows a clean message and logs to `debug.log`, no
crash.

Requested directly by the project owner ahead of the next feature: "get
schema migrations in order first." `docs/TODO.md` already carried two
relevant P2 items — "Make migration behavior easier to inspect" and, within
"Introduce targeted automated tests where practical", "JSON
migration/default-addition idempotency."

**What this covers:**

1. `docs/MIGRATIONS.md` — a new registry documenting, per storage format
   (`hotstrings.json`, `speeddial.json`, `packages/*.json` +
   `manifest.json`, `package-settings.json`), which schema version added
   which field/default, the functional key used, which legacy
   filenames/formats are still read, and a checklist for adding a future
   migration. Explicitly records that hotstring schema versions 2–4 have no
   dedicated migration block in the current code rather than guessing at
   invented history.
2. Two small shared helpers in `DocBot.ahk`, `ReadSchemaVersion(document)`
   and `RejectNewerSchemaVersion(schemaVersion, currentVersion, subject)`,
   defined once immediately before `InitializeBundledPackages()` and used by
   all five schema-version-parsing/rejection call sites (hotstrings, speed
   dial, package manifest, package file, package settings). This is a
   behavior-preserving extraction of duplicated code, not a new migration
   engine.
3. An opt-in, argument-gated self-test entry point:
   `if HasCommandLineArgument("--selftest")`, reusing the existing
   command-line-argument scanner already used for
   `GetRequestedStartupWindowState()` rather than inventing a second,
   positional way to read `A_Args`. Placed immediately after
   `ValidateLocalConfiguration()` succeeds and before `global AppVersion` —
   i.e. before any GUI, user-data, or network access. It calls
   `RunSelfTests()` from the new `tests/SelfTests.ahk` (`#Include`d as
   function definitions only, so it changes nothing during a normal start)
   and then `ExitApp()`s with a pass/fail exit code. `tests/SelfTests.ahk`
   covers the two new helpers plus the idempotency of
   `AddMissingDefaultHotstrings()`, `AddMissingDefaultSpeedDials()`, and
   `NormalizeHotstringItem()`, temporarily substituting `global LocalConfig`
   with a small fixture so the test is deterministic regardless of the
   developer's real `DocBot.local.ahk` contents (which, per D-003, is never
   committed and may have empty `DefaultHotstrings`/`DefaultSpeedDials`).
   `RunSelfTests()` runs each test case through a small wrapper
   (`RunSelfTestCase()`) that catches any unexpected exception and records it
   as one FAIL line rather than letting it escape uncaught — the same class
   of risk D-040 already had to defend against for `/Validate` (an
   AutoHotkey process can show a blocking error dialog a headless CI runner
   never dismisses instead of exiting with a clear failure).
4. `.github/workflows/ahk-syntax-check.yml` runs `AutoHotkey64.exe
   DocBot.ahk --selftest` as a second step in the same job, immediately
   after the existing `/Validate` step, reusing the same
   no-`-Wait`/`WaitForExit(60000)`/force-kill pattern from D-040 because a
   real AutoHotkey process can hang a CI runner on a blocking dialog the
   same way `/Validate` could. The pass/fail signal is the process exit
   code (`RunSelfTests()`'s return value via `ExitApp(exitCode)`), not
   captured stdout: `AutoHotkey64.exe` is a GUI-subsystem executable, and
   whether `FileAppend(text, "*")` reliably reaches a redirected stdout for
   such a process is not proven anywhere else in this codebase (no existing
   call site uses it). `RunSelfTests()` therefore writes its human-readable
   result lines to a fixed file,
   `%TEMP%\docbot-selftest-results.txt` (overwritten every run,
   `SelfTestLogPath()`), mirroring the existing `%TEMP%`-based diagnostic
   artifact convention (D-041/D-044) rather than the network/GUI-coupled
   rest of the app; the workflow step reads that file for the CI log after
   `WaitForExit` succeeds, and degrades to a warning (not a failure) if the
   file is missing. It still also attempts `FileAppend(text, "*")` as a
   best-effort convenience for someone running `--selftest` interactively
   from a normal console, but nothing depends on that path working.
5. Message-wording unification: the five schema-version-ceiling error
   messages (previously worded slightly differently, and in
   `ReconcilePackageSettings()`'s case not even including the version
   numbers) now share one template via `RejectNewerSchemaVersion()`. This
   changes the exact Dutch wording shown in the rare "file is newer than
   this DocBot build" error dialog; it does not change control flow, and
   these strings are not among the stable product-facing names protected
   elsewhere (D-015's package-status names, D-030's telemetry disclosure).

**Rejected alternative:** moving the pure hotstring/speed-dial
item-construction functions (`CreateHotstringItem`, `NormalizeHotstringItem`,
`AddMissingDefaultHotstrings`, `CreateSpeedDialEntry`,
`AddMissingDefaultSpeedDials`, etc.) into their own included file (mirroring
the existing `Telemetry.ahk` module boundary), which would have let a
separate test script `#Include` just that file without triggering
`DocBot.ahk`'s auto-execute section at all. Rejected for now because these
functions are called from many other subsystems throughout the file
(hotstring editor save, package conflict resolution) and relocating
core, frequently-called logic cannot be validated by this agent (no Windows
runtime available, D-037) — `docs/TODO.md` P2 "Consider gradual
modularization after 2.2" already flags exactly this kind of move as
non-casual, future work requiring careful accounting of AHK v2 top-level
init order and callback/global coupling. The chosen design (self-test
gated by a CLI argument inside the existing monolith) gets equivalent test
coverage of the pure logic without moving any existing call site's file
location.

**Rejected alternative:** a generic, config-driven "migration engine"
(e.g. a table of `{schema, version, migrationFn}` triggered by a shared
loader). Rejected because the four schemas' per-item loops, default-source
functions (`DefaultPersonalHotstrings()` vs `DefaultSpeedDialEntries()`),
and save paths are different enough that a generic engine would mostly be
indirection around four things that are still, in practice, bespoke; the
project's own P2 backlog item asked to document/extract "without changing
behavior immediately," not to build new abstraction.

**Consequences**

- `docs/MIGRATIONS.md` closes `docs/TODO.md` P2 "Make migration behavior
  easier to inspect."
- The "JSON migration/default-addition idempotency" bullet under P2
  "Introduce targeted automated tests where practical" is now covered for
  the pure normalization/default-merge functions; the other bullets in that
  same TODO item (number normalization, execution-mode selection, package
  conflict resolution, telemetry payload/redaction, manifest parsing) remain
  open and are not addressed by this change.
- A future fifth schema (or a fifth storage format) should reuse
  `ReadSchemaVersion()`/`RejectNewerSchemaVersion()` and add both a
  `docs/MIGRATIONS.md` row and a `tests/SelfTests.ahk` case in the same
  change, per the checklist in `docs/MIGRATIONS.md`.
- `tests/SelfTests.ahk` ships inside the compiled executable (it is
  `#Include`d unconditionally, like `Telemetry.ahk`) but is fully inert
  without the `--selftest` argument, which no normal end-user launch path
  supplies; this mirrors already-shipped dev-only code gated by other
  conditions (e.g. `IsDevMode`).
- Confirmed on real Windows (interpreted): `--selftest` exits cleanly and
  `%TEMP%\docbot-selftest-results.txt` is written and readable, as designed
  (see Status above). Still not separately confirmed for a **compiled**
  `.exe` specifically (`DocBot.exe --selftest`) or for the CI runner's own
  read of that same file after `WaitForExit` — both are expected to behave
  identically to the interpreted case validated here, since neither path
  does anything build-type-specific, but that is inference, not a run. If
  either turns out not to work as expected there, fix it rather than
  removing the gate.

---

## D-054 — Package manifest entries hold only `id`/`file`; package files gain an optional free-text `owner`

**Status:** Accepted

The project owner asked for package ownership to be visible in the
structure (motivated directly by `packages/anest.json`, added on this
branch by hand, and the earlier compiled-build testing that made clear
custom packages can now come from multiple people once D-048 moved package
loading to a live-read-from-a-share model). While deciding where an
`owner` field should live, a related question came up: `manifest.json`
entries already duplicate `name`, `version`, and `description` from each
package file's own top-level fields. Checked directly against the code
(`grep "packageEntry\["`): only `packageEntry["id"]` and
`packageEntry["file"]` are ever read anywhere. The other three fields in
every manifest entry are, and always were, dead data — never validated,
never displayed, never cross-checked against the package file's own
values. Adding a fourth duplicated field (`owner`) to both places would
have repeated that mistake going forward instead of fixing it.

**What changed:**

- `packages/manifest.json`: every entry trimmed to `id` + `file` only, both
  in the repository's own copy and in the description of what
  `InitializeBundledPackages()` expects. This did not require a code
  change — the existing validation
  (`if !packageEntry.Has("id") || !packageEntry.Has("file")`) never
  required the other fields either, so removing them from the data breaks
  nothing.
- `owner` (optional free text — who creates/maintains this package) added
  to all six current package files (`nl-taal`, `spelfouten-wikipedia`,
  `medisch-algemeen`, `controles`, `gyn-obst`, `anest`), each as an empty
  `""` placeholder rather than a guessed name — this agent has no reliable
  way to know who actually owns each one, and D-045's own precedent (never
  overwrite/guess user-owned content) applies here too. Filling in the real
  names is left to the project owner.
  `LoadBundledPackageFile()` validates only that, if present, `owner` is
  not an object (a JSON array/nested object there would break later string
  use); it is not required, and adding it did not bump
  `BundledPackageSchemaVersion` — see `docs/MIGRATIONS.md`'s package
  section for why that ceiling exists.
- `owner` is deliberately package-level only, not per-item: items within
  one package file are consistently authored/maintained as a single unit
  (exactly how `anest.json` was just added), so a per-item field would add
  structure without a real use case.
- Surfaced in **Pakketten**: `RefreshPackageManagerItemDetails()`'s status
  line now reads `"<name> (eigenaar: <owner>) · <status>"` (owner segment
  omitted when blank) instead of just `"<name> · <status>"`. This reuses
  the existing dynamic status text rather than adding a new control or
  ListView column — deliberately, to avoid the kind of untested pixel
  layout risk flagged repeatedly elsewhere in this log (D-037, D-045):
  `PackageManagerPackageLV`'s four columns already fill its `w326`, so a
  fifth visible "Eigenaar" column would need shrinking existing columns or
  widening the whole window, neither of which can be checked without
  Windows.

**Rejected alternatives:** keeping `owner` in `manifest.json` instead of
(or in addition to) the package file — rejected because it would recreate
the exact dead-duplication problem this decision otherwise fixes; guessing
real owner names for the six existing packages from context (e.g. crediting
the project owner for the original five) — rejected, an empty placeholder
that is visibly blank is more honest than a plausible-looking guess a
reader might trust as accurate; a dedicated package-details panel/column in
the Package Manager window instead of reusing the status text — not
rejected outright, just deferred as unnecessary complexity/layout risk for
what the status-text change already delivers.

**Consequences**

- Adding a new package (as the project owner already did for `anest.json`)
  now only requires an `id`/`file` pair in the manifest — one less pair of
  fields to keep in sync with the package file's own metadata.
- All six current package files ship with an empty `"owner": ""` needing to
  be filled in; nothing in the code requires this, so an unfilled owner is
  a silent gap, not an error — worth a manual pass by the project owner
  rather than assuming it will get noticed on its own.
- A future package-settings or manifest schema bump for an unrelated reason
  should not reintroduce name/version/description into manifest entries
  "for convenience" without re-checking whether something new actually
  reads them by then.
- Not yet validated on a compiled build on Windows (see D-037) — the
  `IsObject()` guard on `owner`, the status-text change, and the trimmed
  `manifest.json` have only been reviewed as source and checked with a
  local JSON parser, not run through DocBot itself.
- Implemented on branch `claude/hotstring-package-load-logging-w4cc5a`
  (`AppVersion 2.3-pakket-logging.8`).

---

## D-055 — SMS default text: optional `TextFieldId`, best-effort fill, own storage file

**Status:** Accepted

The project owner asked for a per-SMS-page default message text, set by the
end user (not the local-configuration owner) in a multiline field on
Instellingen, filled into a second web-page field alongside the existing
telephone-number fill.

**What changed:**

- `SmsCallAction` gains an optional `TextFieldId` (the `AutomationId`/DOM id
  of the message field), alongside the existing required `FieldId` for the
  telephone number. Kept as a second, separately-named key instead of
  renaming `FieldId` to something like `PhoneFieldId`, so every existing
  `DocBot.local.ahk` deployment keeps working unchanged.
  `ValidateSmsCallActionItem()` only rejects it when present-but-empty; its
  absence is a supported "this page has no configured message field" state,
  not a configuration error.
- New storage file `sms-default-texts.json`, following the exact
  `speeddial.json` pattern (`docs/MIGRATIONS.md`): `schemaVersion` + array
  of `{Title, DefaultText}`, atomic `.tmp`/`.bak` writes. Functional key is
  `Title`, matching `FindSmsCallActionIndexByTitle()`.
- Deliberately **no** `package-settings.json`-style unconditional
  reconciliation/pruning of entries whose `Title` no longer matches a
  configured `SmsCallAction`. A renamed or temporarily-removed page must not
  silently discard text the user typed; the GUI simply hides an item it
  cannot currently match, and a matching `Title` returning makes it visible
  again.
- Instellingen gained a multiline `AddRoundedEditGroup(..., true, ...)`
  field under the existing SMS-page dropdown — the same control already
  used for the hotstring Replacement editor, which already supports real
  newlines without `WantReturn`. Switching the dropdown before clicking
  "Opslaan" keeps not-yet-saved text for every page visited that session in
  an in-memory Map (never written to disk); "Opslaan" is still the only
  thing that persists anything, matching how the rest of this page already
  works (no per-field autosave).
- `RunSmsCallAction()` fills the message field only *after* the phone-number
  fill has already succeeded, and only best-effort: a missing/unfillable
  text field is logged but never turns an otherwise-successful SMS action
  into a reported failure. This keeps D-021 (SMS is assisted, never
  automatically sent) intact — the new fill is one more pre-populated field
  for the user to review, nothing more.
- `FillSmsPhoneFieldWithUIA()` renamed to `FillSmsFieldWithUIA()` and reused
  for both fields — it was already generic (`fieldId`, `value`), with
  nothing phone-specific in its body; keeping the old name would have been
  actively misleading once it also fills a message field.
- `FillSmsDomFieldWithJavaScript()`'s native-setter lookup, previously
  hardcoded to `HTMLInputElement.prototype`, now branches on
  `e.tagName === 'TEXTAREA'` to use `HTMLTextAreaElement.prototype`
  instead. This was a real latent bug for this feature, not a style
  choice: the message field on a typical SMS web form is a `<textarea>`,
  and calling the `<input>` prototype's value setter via `.call()` on a
  `<textarea>` instance throws (mismatched internal slots), so the
  JavaScript fallback would have failed on exactly the element type this
  feature targets most.

**Rejected alternatives:** storing the default text in `settings.ini`
instead of a new JSON file — rejected, INI values are single-line and this
field must preserve real newlines; renaming `FieldId` to `PhoneFieldId` for
symmetry — rejected as an unnecessary breaking change to every existing
local configuration for a purely cosmetic gain; reconciling/pruning stale
`sms-default-texts.json` entries like `package-settings.json` does —
rejected, package-settings prunes references to bundled *package* content
that genuinely stops existing, whereas a renamed/temporarily-misconfigured
`SmsCallAction.Title` is exactly the kind of transient state D-010's "never
overwrite/lose a user-edited value" rule is meant to protect against.

**Consequences**

- A deployment that wants this feature must add `TextFieldId` to the
  relevant `SmsCallAction` item(s) in its own `DocBot.local.ahk`; nothing
  changes for a deployment that does not.
- Not yet validated on a compiled build on Windows (see D-037) — in
  particular the UIA fill against a real `<textarea>`, the JavaScript
  fallback's tagName branch, and the Instellingen layout have only been
  reviewed as source, not run through DocBot itself.
- Implemented on branch `claude/sms-default-text-config-oigp28`.

---

## D-056 — User-data profile selection uses build form, not prerelease label

**Status:** Accepted (supersedes D-009)

Non-stable Documents-profile selection (`DocBot-test` vs. `DocBot-dev`) is
based on `A_IsCompiled`, not on the `-dev`/`-rc`/feature-label distinction in
`AppVersion`. Stable numeric versions still always resolve to `DocBot`
regardless of compilation.

```text
stable                          -> DocBot
non-stable, compiled            -> DocBot-test
non-stable, noncompiled         -> DocBot-dev
```

**Reason**

`GetUserDataProfile()` previously read the prerelease label itself
(`-dev`/`-rc` versus any other lettered prerelease) to choose between
`DocBot-test` and `DocBot-dev`. This left two real gaps in D-009's
data-isolation intent: an uncompiled `develop`/`-rc` checkout run directly
from source landed in the central `DocBot-test` profile shared with real
testers, and a compiled feature/fix acceptance-test build landed in the
isolated `DocBot-dev` profile instead of the shared test profile it was
actually meant to validate against.

A compiled prerelease — whichever branch produced it — is a test of the
deliverable form and should share the central test profile. A noncompiled
prerelease is source-level development and should stay isolated, even when
it happens to carry a `-dev`/`-rc` label. `AppVersion` continues to identify
branch/release state for versioning; it no longer independently determines
the non-stable storage profile.

**Consequences**

- `GetUserDataProfile(appVersion, isCompiled)` gains an explicit `isCompiled`
  parameter instead of reading `A_IsCompiled` internally, keeping it pure
  and directly unit-testable from `tests/SelfTests.ahk`.
- The one-time bootstrap chain in `InitializeUserStorage()` /
  `GetUserDataSeedDirectory()` is unchanged: it already operates on the
  resulting `"main"`/`"test"`/`"dev"` value, not on how that value is
  derived.
- No change to the branch-version scheme (`2.3-dev.N`, `2.3-<branch>.N`,
  `2.3-rc.N`, stable `2.3`) and no change to telemetry payload/interval;
  only the `settings.ini` location it reads from follows the (now
  differently derived) selected profile.
- Implemented on branch `claude/profielselectie-build-vorm-bdkt6j`.

---

## D-057 — `Build-EPD_Machine.bat` requires CRLF line endings

**Status:** Accepted

A colleague hit "The system cannot find the batch label specified -
deploy_wait" while compiling with `Build-EPD_Machine.bat`, even though the
`:deploy_wait` label is present and correctly spelled in the file.

**Root cause**

`Build-EPD_Machine.bat` was committed with Unix (LF-only) line endings —
confirmed on the tracked blob across recent history, not a one-off local
edit. This repository is routinely edited from a Mac (D-037), and no
`.gitattributes` previously forced a line-ending convention, so a `.bat`
file edited outside Windows can end up LF-only in the repository.
`cmd.exe`'s `GOTO`/`CALL` label search is documented to be unreliable on a
batch file with LF-only line endings, especially for labels that are not
near the top of the file; `:deploy_wait` sits roughly 5.7 KB into the file,
which matches the reported failure pattern.

**Current direction**

- Added `.gitattributes` with `*.bat text eol=crlf` so any `.bat` file is
  always checked out with CRLF line endings on every platform, regardless
  of which OS was used to edit or commit it.
- `Build-EPD_Machine.bat` itself now carries a short comment at the top
  documenting this requirement, so a future edit that reintroduces LF-only
  line endings is visible in the diff.
- Do not rely on contributors manually configuring `core.autocrlf`; the
  repository-level `.gitattributes` is the enforcement point.

**Consequences**

- An existing local clone checked out before this change keeps its current
  (LF) copy of `Build-EPD_Machine.bat` until it is re-checked out (e.g.
  `git checkout -- Build-EPD_Machine.bat` after pulling this change, or a
  fresh clone) — merely pulling `.gitattributes` does not retroactively
  rewrite an unchanged tracked file already on disk.
- No `DocBot.ahk` behavior change; no `AppVersion` bump required.
