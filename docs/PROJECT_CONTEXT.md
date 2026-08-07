# DocBot — Project Context

_Last updated: 2026-08-07. This document combines the repository state on `develop` with important decisions and lessons from the project conversations that are not otherwise obvious from the source code._

## 1. Purpose

DocBot is an AutoHotkey v2 application for hospital employees. It is distributed to end users as a compiled Windows executable and combines two core workflows:

1. text replacement through personal and bundled hotstrings;
2. telephony assistance through the hospital's internal IP-telephony service, including telephone-number detection from the Windows clipboard.

The application also contains speed dial, an in-app Help page, package management, telemetry, diagnostics, SMS assistance through Edge/UI Automation, and a controlled update/restart mechanism.

The project is deliberately optimized for a managed Windows workplace. Several design choices exist because normal desktop assumptions do not hold there: Windows notifications may be blocked by group policy, OneDrive-backed Documents can temporarily be unavailable for writes, internal telephony endpoints are network-restricted, and SMS pages may already be open as background tabs in Edge.

## 2. Current repository truth

Treat the repository as the source of truth when this document and code ever disagree.

Current top-level structure on `develop`:

- `DocBot.ahk` — the main application. It is large and still intentionally monolithic.
- `Telemetry.ahk` — optional telemetry module.
- `DocBot.local.example.ahk` — safe template for local configuration.
- `Build-EPD_Machine.bat` — build/deployment helper used on Windows.
- `packages/` — versioned bundled hotstring packages plus `manifest.json`.
- `ThirdParty/ColorButton/` — button library and original license.
- `ThirdParty/JXON/` — JSON library and original license.
- `ThirdParty/UIA-v2/` — UI Automation library and original license.
- `README.md` — end-user/developer documentation and the only maintained changelog.
- `AGENTS.md` and `CLAUDE.md` — repository workflow rules for coding agents.
- `LICENSE` — DocBot's own license.

There is currently no conventional `tests/` directory and no `migrations/` directory. Data migrations are implemented in application code through schema-version logic. Functional validation is therefore still heavily dependent on running AutoHotkey v2 on Windows.

## 3. Branch and release status at handover

Repository state checked on 2026-08-07:

- `main` is the production line and represents stable DocBot 2.1.
- `develop` is the central 2.2 development line and currently contains `AppVersion = 2.2-dev.5`.
- `release/2.2-rc.1` exists and contains `AppVersion = 2.2-rc.1`.
- draft PR #10, `Releasecandidate DocBot 2.2-rc.1`, is open from the release branch to `main`.
- `feature/extended-logging` still exists and contains `AppVersion = 2.2-extended-logging.2`.

The release candidate was already created when the project owner explicitly approved one late exception to the feature freeze: the new problem-reporting / consent-based extended-logging feature may still enter 2.2. After that feature is merged into `develop`, it is intended to be merged into the release branch and the RC version must become `2.2-rc.2`, followed by a complete new RC test.

Do not treat `feature/extended-logging` as release-ready merely because its latest commits attempt to fix the reported syntax errors. The recent project conversation contains repeated AutoHotkey v2 syntax failures caused by multiline string concatenation. The latest branch commit is named `Corrigeer multiline concatenaties in probleemrapportage`, but a real AHK v2 parse/compile/run on Windows still needs to confirm the branch before merge.

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
- Bundled package data is extracted to LocalAppData at runtime/build time and validated.
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
- The cancel/SMS/call dialog is keyboard-operable with left/right plus Enter and must paint its initial visual selection correctly.

### 4.5 Help and GUI

- The main GUI uses sidebar navigation and cards.
- Help contains expandable topics and clickable navigation links into DocBot pages.
- Managed Windows environments are part of the design target. `TrayTip()` proved unreliable under group policy and was replaced by a custom always-visible notification window.
- Globals needed while building the GUI must be initialized in the top globals block before the auto-execute section. AutoHotkey v2 executes top-level statements in file order; moving such globals lower in the file can create runtime failures even though function definitions themselves are parsed earlier.

### 4.6 Storage profiles

User data is deliberately isolated by release channel so prerelease builds cannot migrate production data:

- stable numeric versions such as `2.1` -> `%MyDocuments%\DocBot`;
- central `-dev` and `-rc` versions -> `%MyDocuments%\DocBot-test`;
- other lettered prereleases such as feature/fix builds -> `%MyDocuments%\DocBot-dev`.

When a target profile does not yet exist, it is copied once from the most appropriate predecessor and then normal schema migrations run. Existing target folders are never overwritten by this profile bootstrap.

Key user files include:

- `settings.ini`;
- `hotstrings.json`;
- `package-settings.json`;
- `speeddial.json`.

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

Baseline diagnostics on `develop` already include a bounded/buffered background log at `%LocalAppData%\DocBot\debug.log`, a developer-only live debug window, and a route for ordinary users to prepare diagnostic data for support.

The unmerged `feature/extended-logging` expands this into a user-facing `Probleem melden...` flow accessible from Help and the tray menu. The intended design from the project discussion is:

- extended/detailed logging only after explicit user consent;
- the reporting session may stay active when its window is closed and reopened;
- restarting or exiting DocBot ends extended logging;
- normal background logging remains intentionally limited and centrally redacted;
- detailed SMS/UIA logging exists only during the consented session;
- diagnostic output is packaged as a ZIP;
- Classic Outlook may be started and awaited with retries before a draft mail with attachment is opened;
- if Outlook automation is unavailable, provide a clear manual fallback rather than losing the report.

Treat the implementation details as provisional until the feature passes syntax and functional validation.

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
