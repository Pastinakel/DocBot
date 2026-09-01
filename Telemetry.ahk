; =============================================================================
; DocBot telemetrie
; =============================================================================
; Deze module bevat uitsluitend optionele, lokaal geconfigureerde
; statusrapportage. Geheimen blijven in het genegeerde DocBot.local.ahk.

global TelemetryConfig := Map(
    "Enabled", false,
    "WebhookUrl", "",
    "HeartbeatIntervalMs", 900000
)
global TelemetryInstallationId := ""
global TelemetryPendingInstallationId := ""
global TelemetryInstallationIdPersistenceAttempts := 0
global TelemetryInstallationIdQuickRetryMs := 60000
global TelemetryInstallationIdQuickRetryCount := 5
global TelemetryInstallationIdSlowRetryMs := 3600000
global TelemetryIsRunning := false
global TelemetryStartedAt := ""
global TelemetryRequest := 0
global TelemetryPhoneActions := 0
global TelemetryLongHotstringActions := 0
global TelemetrySmsActions := 0
; Wordt pas true nadat de drie gebruikstellers hierboven succesvol uit
; settings.ini zijn gelezen. Vóór die bevestiging schrijft
; Telemetry_RecordPhoneAction() e.a. bewust niets weg: een sessie die door
; een leesfout met een niet-bevestigde 0 begint, mag de echte cumulatieve
; telling nooit overschrijven (zie Telemetry_TryLoadCounters()).
global TelemetryCountersConfirmed := false
global TelemetryCounterRetryAttempts := 0
global TelemetryConfigFile := ""
global TelemetryAppVersion := ""
global TelemetryStatusProvider := 0

Telemetry_ValidateConfiguration(localConfig) {
    if !localConfig.Has("Telemetry")
        return

    telemetry := localConfig["Telemetry"]
    if !(telemetry is Map)
        throw Error("LocalConfig['Telemetry'] moet een Map zijn.")

    if telemetry.Has("Enabled") && telemetry["Enabled"] {
        if !telemetry.Has("WebhookUrl")
            || !RegExMatch(Trim(telemetry["WebhookUrl"]), "i)^https://")
            throw Error("Telemetry.WebhookUrl moet een geldige HTTPS-URL zijn.")

        if telemetry.Has("HeartbeatIntervalMs")
            && telemetry["HeartbeatIntervalMs"] < 60000
            throw Error("Telemetry.HeartbeatIntervalMs moet minimaal 60000 zijn.")
    }
}

Telemetry_BuildConfig() {
    global LocalConfig

    config := Map(
        "Enabled", false,
        "WebhookUrl", "",
        "HeartbeatIntervalMs", 900000
    )

    if !IsSet(LocalConfig) || !(LocalConfig is Map)
        || !LocalConfig.Has("Telemetry")
        return config

    localTelemetry := LocalConfig["Telemetry"]
    if !(localTelemetry is Map)
        return config

    for _, key in ["Enabled", "WebhookUrl", "HeartbeatIntervalMs"] {
        if localTelemetry.Has(key)
            config[key] := localTelemetry[key]
    }

    return config
}

Telemetry_Initialize(configFile, appVersion, statusProvider) {
    global TelemetryConfig, TelemetryInstallationId, TelemetryStartedAt
    global TelemetryConfigFile, TelemetryAppVersion, TelemetryStatusProvider
    global TelemetryPhoneActions, TelemetryLongHotstringActions, TelemetrySmsActions
    global TelemetryCountersConfirmed, TelemetryCounterRetryAttempts
    global TelemetryPendingInstallationId
    global TelemetryInstallationIdPersistenceAttempts, TelemetryIsRunning

    TelemetryConfigFile := configFile
    TelemetryAppVersion := appVersion
    TelemetryStatusProvider := statusProvider
    TelemetryConfig := Telemetry_BuildConfig()

    TelemetryPhoneActions := 0
    TelemetryLongHotstringActions := 0
    TelemetrySmsActions := 0
    TelemetryCountersConfirmed := false
    TelemetryCounterRetryAttempts := 0
    TelemetryInstallationId := ""
    TelemetryPendingInstallationId := ""
    TelemetryInstallationIdPersistenceAttempts := 0
    TelemetryIsRunning := false

    ; Onafhankelijk van of telemetrie zelf aan staat: de tellers voeden ook
    ; de lokale "Gebruik"-kaart op de Overzicht-pagina.
    Telemetry_TryLoadCounters()

    if !TelemetryConfig["Enabled"]
        return

    ; Bewaar de echte starttijd, ook als OneDrive het installatie-ID pas later
    ; beschikbaar maakt.
    TelemetryStartedAt := Telemetry_UtcTimestamp()
    Telemetry_TryEnsureInstallationId()
}

Telemetry_TryLoadCounters(*) {
    global TelemetryConfigFile, TelemetryCountersConfirmed
    global TelemetryPhoneActions, TelemetryLongHotstringActions, TelemetrySmsActions
    global TelemetryCounterRetryAttempts
    global TelemetryInstallationIdQuickRetryMs, TelemetryInstallationIdQuickRetryCount
    global TelemetryInstallationIdSlowRetryMs

    if TelemetryCountersConfirmed
        return

    okPhone := Telemetry_ReadCounter("PhoneActions", &phoneValue)
    okHotstring := Telemetry_ReadCounter("LongHotstringActions", &hotstringValue)
    okSms := Telemetry_ReadCounter("SmsActions", &smsValue)

    if !okPhone || !okHotstring || !okSms {
        Telemetry_LogError(
            "Gebruikstellers konden niet worden gelezen uit " TelemetryConfigFile
        )
        ; Hergebruikt bewust dezelfde snelle/langzame cadans als de
        ; installatie-ID-retry hierboven: beide races op dezelfde
        ; Documents/OneDrive-map, geen reden voor een tweede eigen klok.
        TelemetryCounterRetryAttempts += 1
        delay := TelemetryCounterRetryAttempts < TelemetryInstallationIdQuickRetryCount
            ? TelemetryInstallationIdQuickRetryMs
            : TelemetryInstallationIdSlowRetryMs
        SetTimer Telemetry_TryLoadCounters, -delay
        return
    }

    ; Tel acties die tijdens het wachten al in het geheugen zijn bijgehouden
    ; (Telemetry_RecordPhoneAction() e.a., die vóór bevestiging bewust niet
    ; naar schijf schrijven) op bij de nu bevestigde, echte cumulatieve
    ; waarde, bevestig de tellers, en schrijf het samengevoegde resultaat
    ; direct één keer weg in plaats van te wachten op de volgende actie.
    TelemetryPhoneActions += phoneValue
    TelemetryLongHotstringActions += hotstringValue
    TelemetrySmsActions += smsValue
    TelemetryCountersConfirmed := true
    SetTimer Telemetry_TryLoadCounters, 0

    if TelemetryPhoneActions != phoneValue
        Telemetry_WriteCounter("PhoneActions", TelemetryPhoneActions)
    if TelemetryLongHotstringActions != hotstringValue
        Telemetry_WriteCounter("LongHotstringActions", TelemetryLongHotstringActions)
    if TelemetrySmsActions != smsValue
        Telemetry_WriteCounter("SmsActions", TelemetrySmsActions)

    ; Confirmation can land after StorageRetry_OnAllReady()'s one-time
    ; Overzicht refresh already ran with the pre-confirmation (0) values —
    ; this is on its own independent retry cadence, not gated by
    ; StorageAllReady. Without this, the Gebruik card would stay stuck on 0
    ; until the next recorded action or a restart. Guarded like every other
    ; DocBot.ahk call from this file (see Telemetry_LogError()): harmless if
    ; the GUI isn't built yet.
    try RefreshUsageStatistics()
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

Telemetry_Shutdown() {
    global TelemetryRequest, TelemetryIsRunning

    SetTimer Telemetry_TryEnsureInstallationId, 0
    SetTimer Telemetry_TryLoadCounters, 0
    SetTimer Telemetry_SendStartupHeartbeat, 0
    SetTimer Telemetry_SendHeartbeat, 0
    TelemetryIsRunning := false
    if IsObject(TelemetryRequest) {
        try TelemetryRequest.abort()
    }
}

Telemetry_RecordPhoneAction() {
    global TelemetryPhoneActions, TelemetryCountersConfirmed
    TelemetryPhoneActions += 1
    ; Vóór bevestiging (zie Telemetry_TryLoadCounters()) nog niet wegschrijven:
    ; de echte cumulatieve waarde is dan nog niet bekend, en schrijven zou
    ; die overschrijven met een sessie die bij een niet-bevestigde 0 begon.
    if TelemetryCountersConfirmed
        Telemetry_WriteCounter("PhoneActions", TelemetryPhoneActions)
    return TelemetryPhoneActions
}

Telemetry_RecordLongHotstring() {
    global TelemetryLongHotstringActions, TelemetryCountersConfirmed
    TelemetryLongHotstringActions += 1
    if TelemetryCountersConfirmed
        Telemetry_WriteCounter("LongHotstringActions", TelemetryLongHotstringActions)
    return TelemetryLongHotstringActions
}

Telemetry_GetPhoneActions() {
    global TelemetryPhoneActions
    return TelemetryPhoneActions
}

Telemetry_GetLongHotstringActions() {
    global TelemetryLongHotstringActions
    return TelemetryLongHotstringActions
}

Telemetry_RecordSmsAction() {
    global TelemetrySmsActions, TelemetryCountersConfirmed
    TelemetrySmsActions += 1
    if TelemetryCountersConfirmed
        Telemetry_WriteCounter("SmsActions", TelemetrySmsActions)
    return TelemetrySmsActions
}

Telemetry_GetSmsActions() {
    global TelemetrySmsActions
    return TelemetrySmsActions
}

Telemetry_ReadCounter(name, &value) {
    global TelemetryConfigFile

    ; A missing file is a genuine "not created yet" case (e.g. a real first
    ; run) — same convention as LoadAppSettings() — not a read failure.
    if !FileExist(TelemetryConfigFile) {
        value := 0
        return true
    }

    ; IniRead() with an explicit default never throws for a file it can't
    ; actually read (e.g. still locked right as degraded mode is clearing):
    ; it silently returns that default instead, so a transient access
    ; failure was indistinguishable from a genuinely-zero counter and got
    ; reported as success — defeating Telemetry_TryLoadCounters()'s retry
    ; and permanently confirming a false 0 for the rest of the session.
    ; Probe with a real read first, which does throw on that condition.
    try
        FileRead(TelemetryConfigFile, "UTF-8")
    catch {
        value := 0
        return false
    }

    try {
        value := Max(0, Integer(IniRead(TelemetryConfigFile, "Usage", name, 0)))
        return true
    } catch {
        value := 0
        return false
    }
}

Telemetry_WriteCounter(name, value) {
    global TelemetryConfigFile
    try IniWrite(value, TelemetryConfigFile, "Usage", name)
}

Telemetry_CreateInstallationId() {
    guid := Buffer(16, 0)
    if DllCall("ole32\CoCreateGuid", "ptr", guid, "uint") != 0
        throw Error("Er kon geen installatie-ID worden gemaakt.")

    guidText := Buffer(78, 0)
    if DllCall(
        "ole32\StringFromGUID2",
        "ptr",
        guid,
        "ptr",
        guidText,
        "int",
        39,
        "int"
    ) <= 0
        throw Error("Het installatie-ID kon niet naar tekst worden omgezet.")

    return StrLower(Trim(StrGet(guidText), "{}"))
}

Telemetry_UtcTimestamp() {
    return FormatTime(A_NowUTC, "yyyy-MM-ddTHH:mm:ssZ")
}

Telemetry_GetAppName() {
    executableName := StrLower(RegExReplace(A_ScriptName, "i)\.(exe|ahk)$"))
    executableName := StrReplace(executableName, "_", " ")

    return InStr(executableName, "epd machine")
        ? "EPD Machine"
        : "DocBot"
}

Telemetry_SendStartupHeartbeat(*) {
    Telemetry_SendHeartbeat()
}

Telemetry_SendHeartbeat(*) {
    global TelemetryConfig, TelemetryInstallationId, TelemetryStartedAt
    global TelemetryRequest, TelemetryPhoneActions, TelemetryLongHotstringActions
    global TelemetrySmsActions
    global TelemetryStatusProvider, TelemetryAppVersion

    if !TelemetryConfig["Enabled"] || TelemetryInstallationId = ""
        return

    status := IsObject(TelemetryStatusProvider)
        ? TelemetryStatusProvider.Call()
        : Map("PhoneEnabled", false, "HotstringsEnabled", false)

    innerJson := "{"
        . Telemetry_JsonProperty("installationId", TelemetryInstallationId) ","
        . Telemetry_JsonProperty("userName", A_UserName) ","
        . Telemetry_JsonProperty("appName", Telemetry_GetAppName()) ","
        . Telemetry_JsonProperty("appVersion", TelemetryAppVersion) ","
        . Telemetry_JsonProperty("lastSeen", Telemetry_UtcTimestamp()) ","
        . Telemetry_JsonProperty("startedAt", TelemetryStartedAt) ","
        . Telemetry_JsonRawProperty(
            "phoneEnabled",
            status["PhoneEnabled"] ? "true" : "false"
        ) ","
        . Telemetry_JsonRawProperty(
            "hotstringsEnabled",
            status["HotstringsEnabled"] ? "true" : "false"
        ) ","
        . Telemetry_JsonRawProperty("phoneActions", TelemetryPhoneActions) ","
        . Telemetry_JsonRawProperty(
            "hotstringActions",
            TelemetryLongHotstringActions
        ) ","
        . Telemetry_JsonRawProperty("smsActions", TelemetrySmsActions)
        . "}"

    payload := "{"
        . Telemetry_JsonProperty("type", "message") ","
        . Telemetry_JsonString("attachments") ":[{"
        . Telemetry_JsonProperty(
            "contentType",
            "application/vnd.microsoft.card.adaptive"
        ) ","
        . Telemetry_JsonRawProperty("contentUrl", "null") ","
        . Telemetry_JsonString("content") ":{"
        . Telemetry_JsonProperty("type", "AdaptiveCard") ","
        . Telemetry_JsonProperty(
            "$schema",
            "http://adaptivecards.io/schemas/adaptive-card.json"
        ) ","
        . Telemetry_JsonProperty("version", "1.4") ","
        . Telemetry_JsonString("body") ":[{"
        . Telemetry_JsonProperty("type", "TextBlock") ","
        . Telemetry_JsonProperty("text", innerJson)
        . "}]}}]}"

    try {
        TelemetryRequest := ComObject("Msxml2.XMLHTTP.6.0")
        TelemetryRequest.Open("POST", TelemetryConfig["WebhookUrl"], true)
        TelemetryRequest.SetRequestHeader("Content-Type", "application/json")
        TelemetryRequest.onreadystatechange := Telemetry_Response
        TelemetryRequest.Send(payload)
    } catch as telemetryError {
        Telemetry_LogError(telemetryError.Message)
    }
}

Telemetry_JsonProperty(name, value) {
    return Telemetry_JsonString(name) ":" Telemetry_JsonString(value)
}

Telemetry_JsonRawProperty(name, value) {
    return Telemetry_JsonString(name) ":" value
}

Telemetry_JsonString(value) {
    escaped := StrReplace(value "", Chr(92), Chr(92) Chr(92))
    escaped := StrReplace(escaped, Chr(34), Chr(92) Chr(34))
    escaped := StrReplace(escaped, Chr(13), Chr(92) "r")
    escaped := StrReplace(escaped, Chr(10), Chr(92) "n")
    escaped := StrReplace(escaped, Chr(9), Chr(92) "t")
    return Chr(34) escaped Chr(34)
}

Telemetry_Response() {
    global TelemetryRequest

    if !IsObject(TelemetryRequest) || TelemetryRequest.readyState != 4
        return

    if TelemetryRequest.status < 200 || TelemetryRequest.status >= 300
        Telemetry_LogError(
            "HTTP-status " TelemetryRequest.status ": "
            TelemetryRequest.ResponseText
        )
}

Telemetry_LogError(message) {
    try DebugLog("✕", "Telemetrie", message)
}
