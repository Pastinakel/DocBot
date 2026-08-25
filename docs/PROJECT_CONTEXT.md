# DocBot — Project Context

_Last updated: 2026-08-25. This document combines the repository state around the DocBot 2.2 release and the 2.3 development/release-candidate line with important decisions and lessons from the project conversations that are not otherwise obvious from the source code._

## 1. Purpose

DocBot is an AutoHotkey v2 productivity application for employees in a managed business environment. It is distributed to end users as a compiled Windows executable and combines two core workflows:

1. text replacement through personal and bundled hotstrings;
2. communication assistance by detecting and normalizing telephone numbers from the Windows clipboard and, depending on user settings, passing them to a configured internal telephony service or filling them into a configured SMS web application. DocBot does not send SMS messages itself.

DocBot originated from needs in a hospital workplace and is used there. It has no intended medical purpose: it does not medically analyze patient data, draw clinical conclusions, or provide diagnostic, treatment, dosage, or monitoring advice.

The application also contains speed dial, an in-app Help page, package management, telemetry, diagnostics, SMS assistance through Edge/UI Automation, and a controlled update/restart mechanism.

The project is deliberately optimized for a managed Windows workplace. Several design choices exist because normal desktop assumptions do not hold there: Windows notifications may be blocked by group policy, OneDrive-backed Documents can temporarily be unavailable for writes, internal telephony endpoints are network-restricted, and SMS pages may already be open as background tabs in Edge.

## 2. Current repository truth

Treat the repository as the source of truth when this document and code ever disagree.

Current top-level structure:

- `DocBot.ahk` — the main application. It is large and still intentionally monolithic.
- `Telemetry.ahk` — optional telemetry module.
- `DocBot.local.example.ahk` — safe template for local configuration.
- `Build-EPD_Machine.bat` — build/deployment helper used on Windows.
- `packages/` — versioned bundled hotstring packages plus `manifest.json`.
- `ThirdParty/ColorButton/` — button library and original license.
- `ThirdParty/JXON/` — JSON library and original license.
- `ThirdParty/UIA-v2/` — UI Automation library and original license.
- `tests/SelfTests.ahk` — opt-in self-test suite for pure migration-support logic, run via `DocBot.ahk --selftest`; see `tests/README.md` and `docs/DECISIONS.md` D-053.
- `README.md` — end-user/developer documentation and the only maintained changelog.
- `AGENTS.md` and `CLAUDE.md` — repository workflow rules for coding agents.
- `LICENSE` — DocBot's own license.

There is no `migrations/` directory; data migrations are implemented in
application code through schema-version logic, documented in
`docs/MIGRATIONS.md`. There is no conventional test-runner-based `tests/`
directory either — `tests/SelfTests.ahk` is a narrow, opt-in exception
(pure logic only, see D-053), not a general test harness. Functional
validation is therefore still heavily dependent on running AutoHotkey v2 on
Windows.

## 3. Branch and release status at handover

Repository state checked on 2026-08-25:

- `main` is the production line and represents stable **DocBot 2.2**, merged
  from `release/2.2-rc` via PR #27 (merge commit `a156dfe`) and tagged
  `v2.2` on that commit. No further work is expected on `main` outside an
  explicitly requested hotfix.
- `release/2.2-rc` and `release/2.2-finalize` are the historical release
  branches for 2.2; no further work is expected on them.
- `develop` was brought back in line with the released `main` via PR #28
  and started the 2.3 development line at `AppVersion = 2.3-dev.1`. Since
  then, PRs #30–#44 (`claude/docs-sync-and-ci-decision`,
  `claude/https-only-telephony-sms`, `claude/diagnostics-retention`,
  `claude/docs-review-d044-rewrite-wz9ogd`,
  `claude/https-acceptance-evidence-confirmed`,
  `claude/fix-todo-infra-reference`,
  `claude/hotstring-user-instruction-hcv2jw`,
  `claude/schema-migrations-setup-waiigd`,
  `claude/hotstring-package-load-logging-w4cc5a`,
  `claude/schema-migrations-windows-validated`,
  `claude/sms-default-text-config-oigp28`,
  `claude/sms-window-reopen-bug-mmx5ln`,
  `claude/profielselectie-build-vorm-bdkt6j`,
  `claude/docbot-epd-batch-questions-t1rf6j` and
  `claude/sms-window-baseline-logging`) landed the rest of the 2.3 feature
  set described in the README `### 2.3 — In ontwikkeling` changelog
  section. `develop` is currently at `AppVersion = 2.3-dev.9` — verify this
  against `global AppVersion` in `DocBot.ahk` before relying on it.
- `release/2.3-rc` (branched from `develop` at `dev.9`) is currently at
  `AppVersion = 2.3-rc.3` and carries further RC-only fixes not yet merged
  back to `develop` (`docs/DECISIONS.md` D-057, D-058). No pull request into
  `main` is open for it yet.
- `feature/extended-logging` is no longer the branch to test or integrate;
  its work shipped as part of 2.2.
- See `docs/TODO.md`, section "P0 — Release plan: finalize stable DocBot
  2.3", for the current release-readiness status, remaining blockers, the
  2.3-specific acceptance checklist, and the finalization steps — treat that
  section as the up-to-date successor to the paragraph-form status this
  section used to carry, and keep both in sync going forward.

Do not infer functional validation from source integration alone for future
cycles. Both the 2.2 feature work and the D-044 diagnostics-retention work
needed multiple rounds of real Windows/compiled-build testing to catch
issues that source review alone missed (repeated AutoHotkey v2
multiline-concatenation failures for 2.2; a stale legacy log format and two
generations of an unrecognized directory-naming pattern for D-044) — a real
AHK v2 parse/compile/run and functional test on Windows remains required
before declaring a change complete, not just source review.

## 4. Product requirements that must survive refactors

### 4.1 Hotstrings

- Personal hotstrings use one `Replacement` field. Do not create different data types for short, long, single-line, or multiline replacements.
- Output method is selected automatically:
  - short single-line text: normal AutoHotkey hotstring replacement;
  - long text (currently 200+ characters) or multiline text: callback using `SendText()`;
  - text containing key commands such as `{Tab}` or `{Left}`: key-command mode.
- Hotstring replacement must never use the Windows clipboard. The clipboard belongs exclusively to telephone-number detection.
- Multiline callbacks send normal text with `SendText()` and line breaks as separate `{Enter}` actions.
- Dynamic replacement tokens currently include `{{datum}}` and `{{tijd}}`.
- Writes to hotstring JSON use backup + temporary file + validation before replacement.
- Legacy text import converts old `{Enter}` sequences to real line breaks and normalizes escaped punctuation while preserving actual key commands.

### 4.2 Bundled hotstring packages

- Versioned package sources live under `packages/`; `manifest.json` is the index.
- Package data is not embedded or cached; `InitializeBundledPackages()` reads
  and validates it live on every start, directly from the dev build's own
  `packages/` or, for the compiled build, an auto-detected or explicitly
  configured network share (`docs/DECISIONS.md` D-048/D-049).
- User package choices live separately in `package-settings.json`; package content itself is not copied into that settings file.
- Personal hotstrings normally win conflicts unless the user explicitly gives a package item priority.
- Editing/saving a package item creates a full personal copy with stable ID/origin metadata.
- Status names are stable product language and should not be casually renamed: `Inactief`, `Overruled`, `Voorrang`, `Conflict`, `Actief`.
- Defaults are added through one-time schema upgrades, never by re-adding missing defaults on every startup.

### 4.3 Telephony

- Telephony is only useful inside the hospital network.
- Registration, event polling, and dialing all use POST.
- Technical endpoint values and real local defaults are not committed; they come from `DocBot.local.ahk`.
- `IPTConfig` contains technical configuration; live telephony state lives in `State["IPT"]`.
- A call must go through the central call path (`IPT_callNumber()`); ordinary calls are blocked until a phone is linked, except for the linking call itself.
- Request objects are intentionally separate for registration, polling, and dialing. Do not collapse them into one shared mutable XHR object.
- Event polling is chained: the next poll starts after the previous request finishes. Do not restore a fixed-interval overlapping poll timer.
- Clipboard detection supports Dutch external numbers and a deliberately separate path for internal four-digit numbers.

### 4.4 Call action and SMS assistance

The four-state `Belactie` setting replaced the older AutoCall/DirectCall combination. Its user-visible choices are conceptually:

- do nothing;
- call after confirmation;
- call directly;
- let the user choose between cancel/SMS/call for eligible external numbers.

Requirements for the SMS path:

- SMS is offered only when at least one valid local `SmsCallAction` exists and the copied number is an eligible Dutch mobile number.
- A single action map and an array of action maps are supported for backwards compatibility.
- The GUI displays `Title`; `WindowTitle` remains technical matching data.
- First try to activate the matching Edge window/tab; UI Automation is the main background-tab/fill mechanism.
- JavaScript is only a fallback, not the primary implementation.
- DocBot fills the telephone number but does not send the SMS. Final checking and sending stay with the user.
- An `SmsCallAction` may optionally set `TextFieldId`, the field id of a second, message-body field on the same SMS page. Where set, and where the user has configured a default text for that page's `Title` on Instellingen (`sms-default-texts.json`), DocBot best-effort-fills that field too, right after the phone-number fill succeeds — a failed text fill never turns an otherwise-successful SMS action into a reported failure, and is only logged.
- The default-text field on Instellingen is multiline and preserves real newlines (hard Enters), reusing the same control already used for the multiline hotstring Replacement editor.
- The cancel/SMS/call dialog is keyboard-operable with left/right plus Enter and must paint its initial visual selection correctly.
- Only one call-action dialog (confirmation, or the cancel/SMS/call choice) may be open at a time. A newer clipboard-detected number always closes a still-open older dialog first — with a short notification — regardless of which action the new number then triggers (a new dialog, an immediate call, or no action). Do not reintroduce stacking dialogs by adding a new outcome path that skips this close step.
- `State["IPT"]["ClipBoardNumber"]` is cleared immediately once the current action is handed off, completed, or cancelled (call placed, SMS started, dialog cancelled/closed, or no action configured) — not left until the next number is detected or the app exits.

### 4.5 Help and GUI

- The main GUI uses sidebar navigation and cards.
- Help contains expandable topics and clickable navigation links into DocBot pages.
- Managed Windows environments are part of the design target. `TrayTip()` proved unreliable under group policy and was replaced by a custom always-visible notification window.
- Globals needed while building the GUI must be initialized in the top globals block before the auto-execute section. AutoHotkey v2 executes top-level statements in file order; moving such globals lower in the file can create runtime failures even though function definitions themselves are parsed earlier.

### 4.6 Storage profiles

User data is deliberately isolated by release channel so prerelease builds cannot migrate production data. Stable versions take priority; for every non-stable version, build form (`A_IsCompiled`), not the prerelease label, selects the profile:

- stable numeric versions such as `2.1` -> `%MyDocuments%\DocBot`, regardless of build form;
- any non-stable, compiled version (`-dev`, `-rc`, or a feature/fix build) -> `%MyDocuments%\DocBot-test`;
- any non-stable, noncompiled version -> `%MyDocuments%\DocBot-dev`.

When a target profile does not yet exist, it is copied once from the most appropriate predecessor and then normal schema migrations run. Existing target folders are never overwritten by this profile bootstrap.

Key user files include:

- `settings.ini`;
- `hotstrings.json`;
- `package-settings.json`;
- `speeddial.json`;
- `sms-default-texts.json`.

Debug logging lives under LocalAppData, not the Documents profile.

### 4.7 OneDrive / storage behavior

A real production issue occurred because one user's Documents/OneDrive location was not reliably writable at startup. The first attempted fix added a broad startup writeability gate. That proved too aggressive and was later removed.

Current intended behavior:

- do not block the whole application with a generic startup write test;
- best-effort mark the user data folder as always locally available with `attrib -U +P`;
- failure of that pin operation must not block startup;
- each actual write path keeps focused error handling;
- telemetry installation-ID creation has its own retry strategy when persistence is temporarily unavailable.

### 4.8 Telemetry and privacy

Telemetry is optional and locally configured. Secrets/webhook URL stay in `DocBot.local.ahk`.

If enabled, the current payload includes:

- a random persisted installation ID;
- Windows username;
- application name (`DocBot` or `EPD Machine`);
- application version;
- started/last-seen timestamps;
- phone-linked and hotstrings-enabled status;
- cumulative phone-action count;
- cumulative long/multiline-hotstring count.

It deliberately does **not** include computer name, called telephone numbers, hotstring triggers, replacement text, package content, or clipboard content.

The README must always contain a clear `Telemetrie` section matching the actual payload. New fields or broader collection require explicit project-owner approval before release.

Installation-ID durability is important:

- if an ID already exists, read it and start telemetry without rewriting it;
- only create a new ID when missing;
- do not use the new ID until write + readback confirms persistence;
- on temporary failure, retry several times during the first minutes and then hourly;
- do not let telemetry failure disable the rest of DocBot.

### 4.9 Diagnostics and problem reporting

Baseline diagnostics include a bounded/buffered background log at `%LocalAppData%\DocBot\debug.log` and a developer-only live debug window. The current 2.2 development and RC lines also contain the user-facing `Probleem melden...` flow through Help and the tray menu.

The implementation has two reporting paths:

- **Direct reporting** packages the optional description and centrally redacted standard log without enabling extended logging.
- **Reproduce with extended logging** requires an explicit consent checkbox. The in-memory session survives closing/reopening the window, but process exit/restart stops the session and deletes its temporary detailed log.
- During a consented session, existing diagnostic events are additionally written with original values, except that the telemetry webhook remains redacted. Actually executed hotstring triggers/replacements and detailed SMS/UIA traces are logged only while the session is active.
- Starting or stopping the session reloads runtime hotstrings so normal and key-command hotstrings can pass through diagnostic callbacks only for the consented interval.
- Finalization stops extended logging before package/mail handling, flushes both logs, and writes loose files (no ZIP) into a temporary directory under `%TEMP%`: `probleemrapport.txt`, the standard log when available, and the extended log only when requested and present.
- Classic Outlook is started/awaited when necessary and receives a draft with each report file attached individually. If automation fails, DocBot opens a mail fallback where possible, opens the report directory in Explorer, and gives explicit manual attachment instructions.
- Local configuration files are not packaged. The temporary extended log is removed on shutdown, on a new session, and after successful report preparation; the temporary report directory remains available for the user/mail workflow.
- Report files were previously bundled into a ZIP via the Explorer shell namespace ("Compressed (zipped) Folders"). That mechanism proved unreliable/unavailable on some group-policy/EDR-hardened workplaces, causing report finalization itself to fail; see `DECISIONS.md` D-041.

The project owner completed the dedicated compiled-Windows validation of the
problem-reporting flow on RC2 on 2026-08-09, before the switch to loose
attachments in D-041 — that switch still needs its own compiled-Windows
validation. RC2 validation closes the specific pre-D-041
problem-reporting checklist; it does not by itself complete the broader RC3
acceptance test covering the rest of DocBot.

## 5. Build and deployment constraints

- End users receive a compiled executable, not editable source.
- Source changes therefore belong in `.ahk` files and are compiled separately by the project owner.
- `DocBot.local.ahk` is gitignored but is embedded by Ahk2Exe when present during compilation.
- `Build-EPD_Machine.bat` supports controlled replacement of deployed executables and coordinates active clients with `signal.txt`.
- The signal mechanism can request shutdown/reload. A scheduled Windows task is used to restart the application after an update while preserving window state.

## 6. Licensing

The project owner moved DocBot itself away from MIT because unrestricted commercial reuse was not desired. The current repository README identifies DocBot 2.2+ as PolyForm Noncommercial. Third-party libraries keep their original MIT licenses in their own `ThirdParty/<library>/` directories.

Do not remove or consolidate those third-party license files into the project license.

## 7. Engineering workflow requirements

Read `AGENTS.md` completely from the target branch before making any repository change. Read `CLAUDE.md` too when it exists.

Core workflow rules:

- never work directly on `main` or `develop`;
- normal branches start from current `develop`;
- only an explicitly requested production hotfix starts from `main`;
- merge completed feature/fix work into `develop` through a pull request;
- the project owner has repeatedly requested normal merge commits, not squash/rebase, for integration work;
- every commit that changes `DocBot.ahk` must change `global AppVersion` in the same commit according to the branch's version counter;
- a commit that does not change `DocBot.ahk` must not change `AppVersion`;
- feature/fix counters are branch-local and do not determine the central `develop` counter;
- the README Changelog is the only maintained version-history source; do not manually maintain version-history lines in `BuildAboutText()`;
- stable releases get an annotated `vX.Y` tag only after the stable release commit.

Before every commit, explicitly check:

1. branch type and correct AppVersion;
2. whether `DocBot.ahk` changed;
3. if so, whether AppVersion changed in the same commit;
4. whether README/changelog must be updated;
5. whether telemetry documentation must be updated.

## 8. Development-environment lessons

### AutoHotkey validation

Do not assume syntactically plausible code is valid AutoHotkey v2. The recent extended-logging work exposed repeated multiline string-concatenation errors. In particular, assignments spread over several lines are easy to get wrong if continuation/concatenation rules are inferred from another language.

For any nontrivial AHK edit:

- prefer explicit expression concatenation patterns already proven in the codebase;
- search the entire changed block for the same pattern after fixing one syntax error;
- run a real AHK v2 parse/compile check on Windows when possible;
- do not declare a branch fixed solely from visual review.

### GUI event callback pitfalls

Adding the GitHub link on the About page (`OpenGithubLink`, `Link`/SysLink
control) surfaced two runtime-only mistakes that the `/Validate`-based
syntax check (D-040) cannot catch, because that check never executes the
auto-execute section:

- A fixed-arity inline callback (e.g. `(ctrl, info) => Run(info)`) passed to
  `.OnEvent("Click", ...)` failed at registration time with "Invalid
  callback function". AHK v2 validates a callback's parameter count against
  the event, and the exact arity an event will call with is not always
  obvious from the docs. Prefer a named function with a trailing `*` (e.g.
  `Handler(ctrl, *)`), matching the pattern already used elsewhere in
  `DocBot.ahk` (`ClosePhoneActionDialog(dialog, *)`).
- For a `Link` control's `Click` event, `Info` is not reliably the clicked
  anchor's `href`; in practice it returned the 1-based index of the clicked
  link segment instead. Do not assume `Info` is a usable URL — if the
  control only ever has one link, hardcode the target instead of parsing it
  from `Info`.

Both mistakes were only visible by actually running the compiled script on
Windows and clicking the control, not from source review or CI.

### Git/GitHub tooling

Large direct edits to `DocBot.ahk` through GitHub connector/API flows have caused friction. Temporary self-modifying GitHub Actions workflows were used as a workaround, which also produced confusing Actions emails and complicated history.

Preferred direction for future engineering work:

- use a normal local git checkout for large source edits, commits, and pushes;
- use the GitHub connector for structured repository/PR metadata and smaller operations;
- keep temporary workflow-as-editor techniques as a last resort, not a standard development method.

A Mac can be used for local git editing/branching/pushing, but native AutoHotkey v2 runtime validation still requires Windows (or a suitable Windows VM/environment). Separate "can edit Git locally" from "can execute/validate DocBot".

### Pulling with local changes

The project owner has encountered `git pull` being blocked because local edits to `DocBot.ahk` and `README.md` would be overwritten. Before pulling/switching branches, inspect `git status`. Commit intentional work or stash it before pulling; do not discard local changes implicitly.

## 9. Definition of safe handover

A future software-engineering agent should be able to start from these docs plus the repository without the old conversations. The agent should still verify the current branch/PR state because the status sections here are point-in-time snapshots.

When uncertain, preserve these priorities in order:

1. do not risk production user data;
2. do not leak local configuration, telephony endpoints, webhook URLs, or user content;
3. keep DocBot usable when optional telemetry/OneDrive/network integrations fail;
4. preserve user-visible behavior and migration compatibility;
5. obey branch/version/changelog rules;
6. validate AutoHotkey v2 syntax on Windows before declaring source changes complete.
