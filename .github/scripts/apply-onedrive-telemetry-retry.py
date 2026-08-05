from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: verwacht 1 overeenkomst, gevonden {count}")
    return text.replace(old, new, 1)


# DocBot.ahk: verwijder de algemene schrijfbaarheidstest en pin de gebruikersmap.
docbot_path = Path("DocBot.ahk")
docbot = docbot_path.read_text(encoding="utf-8-sig")

startup_old = '''InitializeUserStorage()
try ValidateUserStorageAccess()
catch as storageError {
    MsgBox(
        "DocBot kan de gebruikersgegevens niet betrouwbaar opslaan.`n`n"
        . storageError.Message
        . "`n`nControleer de rechten, synchronisatie of beveiliging van "
        . "de genoemde locatie en start DocBot daarna opnieuw.",
        "DocBot - Opslagfout",
        "Icon!"
    )
    ExitApp()
}
InitializeBundledPackages()'''
startup_new = '''InitializeUserStorage()
MarkUserStorageAlwaysAvailable(UserDataDir)
InitializeBundledPackages()'''
docbot = replace_once(docbot, startup_old, startup_new, "startup-opslagblok")

storage_pattern = re.compile(
    r'''\n; Controleer na het voorbereiden van de gebruikersmap.*?\nValidateUserStorageAccess\(\) \{.*?\n\}\n\nAssertUserStorageDirectoryWritable\(directory\) \{.*?\n\}\n\nAssertUserStorageFileWritable\(path\) \{.*?\n\}\n\n(?=RebaseCopiedHotstringPath\(sourceDir\) \{)''',
    re.S,
)
docbot, count = storage_pattern.subn("\n", docbot, count=1)
if count != 1:
    raise RuntimeError(f"opslagcontrolefuncties: verwacht 1 blok, gevonden {count}")

pin_function = '''MarkUserStorageAlwaysAvailable(directory) {
    if !DirExist(directory)
        return false

    try {
        exitCode := RunWait(
            A_ComSpec ' /d /c attrib -U +P "' directory '"',
            ,
            "Hide"
        )
        if exitCode = 0
            return true

        DebugLog(
            "!",
            "OneDrive-map lokaal houden",
            "attrib -U +P gaf exitcode " exitCode ": " directory
        )
    } catch as pinError {
        DebugLog(
            "!",
            "OneDrive-map lokaal houden",
            directory "`n" pinError.Message
        )
    }

    ; Niet fataal: gewone lokale mappen en organisatiebeleid mogen de start
    ; van DocBot niet blokkeren. De echte schrijfacties houden hun eigen
    ; gerichte foutafhandeling.
    return false
}

'''
anchor = "RebaseCopiedHotstringPath(sourceDir) {"
if docbot.count(anchor) != 1:
    raise RuntimeError("anker voor MarkUserStorageAlwaysAvailable niet uniek")
docbot = docbot.replace(anchor, pin_function + anchor, 1)

docbot_path.write_text(docbot, encoding="utf-8")


# Telemetry.ahk: één pending ID, vijf snelle pogingen en daarna ieder uur.
telemetry_path = Path("Telemetry.ahk")
telemetry = telemetry_path.read_text(encoding="utf-8-sig")

telemetry = replace_once(
    telemetry,
    'global TelemetryInstallationId := ""\n',
    '''global TelemetryInstallationId := ""
global TelemetryPendingInstallationId := ""
global TelemetryInstallationIdPersistenceAttempts := 0
global TelemetryInstallationIdQuickRetryMs := 60000
global TelemetryInstallationIdQuickRetryCount := 5
global TelemetryInstallationIdSlowRetryMs := 3600000
global TelemetryIsRunning := false
''',
    "telemetrieglobals",
)

initialize_pattern = re.compile(
    r'''Telemetry_Initialize\(configFile, appVersion, statusProvider\) \{.*?\n\}\n\n(?=Telemetry_Shutdown\(\) \{)''',
    re.S,
)
initialize_replacement = '''Telemetry_Initialize(configFile, appVersion, statusProvider) {
    global TelemetryConfig, TelemetryInstallationId, TelemetryStartedAt
    global TelemetryConfigFile, TelemetryAppVersion, TelemetryStatusProvider
    global TelemetryPhoneActions, TelemetryLongHotstringActions
    global TelemetryPendingInstallationId
    global TelemetryInstallationIdPersistenceAttempts, TelemetryIsRunning

    TelemetryConfigFile := configFile
    TelemetryAppVersion := appVersion
    TelemetryStatusProvider := statusProvider
    TelemetryConfig := Telemetry_BuildConfig()

    TelemetryPhoneActions := Telemetry_ReadCounter("PhoneActions")
    TelemetryLongHotstringActions := Telemetry_ReadCounter("LongHotstringActions")
    TelemetryInstallationId := ""
    TelemetryPendingInstallationId := ""
    TelemetryInstallationIdPersistenceAttempts := 0
    TelemetryIsRunning := false

    if !TelemetryConfig["Enabled"]
        return

    ; Bewaar de echte starttijd, ook als OneDrive het installatie-ID pas later
    ; beschikbaar maakt.
    TelemetryStartedAt := Telemetry_UtcTimestamp()
    Telemetry_TryEnsureInstallationId()
}

Telemetry_TryEnsureInstallationId(*) {
    global TelemetryConfig, TelemetryConfigFile
    global TelemetryInstallationId, TelemetryPendingInstallationId
    global TelemetryInstallationIdPersistenceAttempts
    global TelemetryInstallationIdQuickRetryMs
    global TelemetryInstallationIdQuickRetryCount
    global TelemetryInstallationIdSlowRetryMs

    if !TelemetryConfig["Enabled"] || TelemetryInstallationId != ""
        return

    ; Lees vóór iedere schrijfpoging opnieuw. Een andere DocBot-instantie kan
    ; het ID inmiddels al hebben opgeslagen; die bestaande waarde is leidend.
    try {
        storedInstallationId := Trim(
            IniRead(TelemetryConfigFile, "Telemetry", "InstallationId", "")
        )
    } catch as readError {
        storedInstallationId := ""
        Telemetry_LogError(
            "Installatie-ID kon niet worden gelezen uit "
            . TelemetryConfigFile
            . ": "
            . readError.Message
        )
    }

    if storedInstallationId != "" {
        TelemetryInstallationId := storedInstallationId
        TelemetryPendingInstallationId := ""
        TelemetryInstallationIdPersistenceAttempts := 0
        SetTimer Telemetry_TryEnsureInstallationId, 0
        Telemetry_Start()
        return
    }

    if TelemetryPendingInstallationId = "" {
        try TelemetryPendingInstallationId := Telemetry_CreateInstallationId()
        catch as createError {
            Telemetry_LogError(createError.Message)
            Telemetry_ScheduleInstallationIdRetry()
            return
        }
    }

    try {
        IniWrite(
            TelemetryPendingInstallationId,
            TelemetryConfigFile,
            "Telemetry",
            "InstallationId"
        )

        ; Controleer dat precies hetzelfde ID ook teruggelezen kan worden
        ; voordat telemetrie het als permanente identiteit gebruikt.
        persistedInstallationId := Trim(
            IniRead(TelemetryConfigFile, "Telemetry", "InstallationId", "")
        )
        if persistedInstallationId != TelemetryPendingInstallationId
            throw Error("Het opgeslagen installatie-ID kon niet worden bevestigd.")

        TelemetryInstallationId := persistedInstallationId
        TelemetryPendingInstallationId := ""
        TelemetryInstallationIdPersistenceAttempts := 0
        SetTimer Telemetry_TryEnsureInstallationId, 0
        Telemetry_Start()
    } catch as installationIdError {
        Telemetry_LogError(
            "Installatie-ID kon niet worden opgeslagen in "
            . TelemetryConfigFile
            . ": "
            . installationIdError.Message
        )
        Telemetry_ScheduleInstallationIdRetry()
    }
}

Telemetry_ScheduleInstallationIdRetry() {
    global TelemetryInstallationIdPersistenceAttempts
    global TelemetryInstallationIdQuickRetryMs
    global TelemetryInstallationIdQuickRetryCount
    global TelemetryInstallationIdSlowRetryMs

    TelemetryInstallationIdPersistenceAttempts += 1
    delay := TelemetryInstallationIdPersistenceAttempts < TelemetryInstallationIdQuickRetryCount
        ? TelemetryInstallationIdQuickRetryMs
        : TelemetryInstallationIdSlowRetryMs

    SetTimer Telemetry_TryEnsureInstallationId, -delay
}

Telemetry_Start() {
    global TelemetryConfig, TelemetryInstallationId, TelemetryIsRunning

    if TelemetryIsRunning
        return
    if !TelemetryConfig["Enabled"] || TelemetryInstallationId = ""
        return

    TelemetryIsRunning := true

    ; Geef de telefoniepoller eerst tijd om het gekoppelde nummer te vinden.
    ; De aparte callback voorkomt dat deze eenmalige timer de terugkerende
    ; heartbeat-timer overschrijft.
    SetTimer Telemetry_SendStartupHeartbeat, -10000
    SetTimer Telemetry_SendHeartbeat, TelemetryConfig["HeartbeatIntervalMs"]
}

'''
telemetry, count = initialize_pattern.subn(initialize_replacement, telemetry, count=1)
if count != 1:
    raise RuntimeError(f"Telemetry_Initialize: verwacht 1 blok, gevonden {count}")

shutdown_old = '''Telemetry_Shutdown() {
    global TelemetryRequest

    SetTimer Telemetry_SendStartupHeartbeat, 0
    SetTimer Telemetry_SendHeartbeat, 0
    if IsObject(TelemetryRequest) {
        try TelemetryRequest.abort()
    }
}'''
shutdown_new = '''Telemetry_Shutdown() {
    global TelemetryRequest, TelemetryIsRunning

    SetTimer Telemetry_TryEnsureInstallationId, 0
    SetTimer Telemetry_SendStartupHeartbeat, 0
    SetTimer Telemetry_SendHeartbeat, 0
    TelemetryIsRunning := false
    if IsObject(TelemetryRequest) {
        try TelemetryRequest.abort()
    }
}'''
telemetry = replace_once(telemetry, shutdown_old, shutdown_new, "Telemetry_Shutdown")

telemetry_path.write_text(telemetry, encoding="utf-8")


# README: leg het gewijzigde gedrag vast in de ontwikkelchangelog.
readme_path = Path("README.md")
readme = readme_path.read_text(encoding="utf-8-sig")
changelog_anchor = '''### 2.2 — In ontwikkeling
- Start van de volgende ontwikkelcyclus na de stabiele release van DocBot 2.1.
'''
changelog_replacement = '''### 2.2 — In ontwikkeling
- Start van de volgende ontwikkelcyclus na de stabiele release van DocBot 2.1.
- De gebruikersmap wordt waar mogelijk met `attrib -U +P` als altijd lokaal
  beschikbaar gemarkeerd, zonder dat een mislukte pinactie de start blokkeert.
- DocBot voert bij het opstarten geen algemene schrijfbaarheidstest meer uit;
  iedere echte schrijfactie houdt zijn eigen gerichte foutafhandeling.
- Een ontbrekend telemetrie-installatie-ID wordt pas gebruikt nadat permanente
  opslag is bevestigd. Bij tijdelijke onbeschikbaarheid volgen vijf pogingen
  binnen de eerste minuten en daarna ieder uur een nieuwe poging.
'''
readme = replace_once(readme, changelog_anchor, changelog_replacement, "README-changelog")
readme_path.write_text(readme, encoding="utf-8")


# Eindcontroles.
assert "ValidateUserStorageAccess" not in docbot
assert "AssertUserStorageDirectoryWritable" not in docbot
assert "AssertUserStorageFileWritable" not in docbot
assert "attrib -U +P" in docbot
assert "TelemetryPendingInstallationId" in telemetry
assert "Telemetry_ScheduleInstallationIdRetry" in telemetry
assert "SetTimer Telemetry_TryEnsureInstallationId, 0" in telemetry
assert telemetry.count("Telemetry_Start()") >= 3
