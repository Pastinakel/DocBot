# DocBot — Decisions

_Last updated: 2026-08-17. This is a compact decision log reconstructed from repository history and project conversations. When code and this file disagree, verify whether a decision has subsequently been superseded._

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

**Status:** Accepted

Stable, central test/RC, and feature/fix builds use different Documents folders.

```text
stable     -> DocBot
-dev/-rc   -> DocBot-test
other pre  -> DocBot-dev
```

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
- Implemented on branch `claude/hotstring-user-instruction-hcv2jw`
  (`AppVersion 2.3-hotstring-instructie.3`); not yet validated on a
  compiled build on Windows (see D-037) — layout math was verified by hand
  against the fixed 1000×700 window size, not by rendering the GUI.
