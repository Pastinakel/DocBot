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
global TelemetryStartedAt := ""
global TelemetryRequest := 0
global TelemetryPhoneActions := 0
global TelemetryLongHotstringActions := 0
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
    global TelemetryPhoneActions, TelemetryLongHotstringActions

    TelemetryConfigFile := configFile
    TelemetryAppVersion := appVersion
    TelemetryStatusProvider := statusProvider
    TelemetryConfig := Telemetry_BuildConfig()

    try {
        Telemetry_ValidateStorageAccess(TelemetryConfigFile)
    } catch as storageError {
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

    TelemetryPhoneActions := Telemetry_ReadCounter("PhoneActions")
    TelemetryLongHotstringActions := Telemetry_ReadCounter("LongHotstringActions")

    if !TelemetryConfig["Enabled"]
        return

    TelemetryInstallationId := Trim(
        IniRead(TelemetryConfigFile, "Telemetry", "InstallationId", "")
    )
    if TelemetryInstallationId = "" {
        newInstallationId := Telemetry_CreateInstallationId()

        try {
            IniWrite(
                newInstallationId,
                TelemetryConfigFile,
                "Telemetry",
                "InstallationId"
            )
        } catch as installationIdError {
            TelemetryInstallationId := ""
            Telemetry_LogError(
                "Installatie-ID kon niet worden opgeslagen in "
                . TelemetryConfigFile
                . ": "
                . installationIdError.Message
            )
            return
        }

        ; Gebruik het nieuwe ID pas nadat permanente opslag is gelukt.
        TelemetryInstallationId := newInstallationId
    }

    TelemetryStartedAt := Telemetry_UtcTimestamp()

    ; Geef de telefoniepoller eerst tijd om het gekoppelde nummer te vinden.
    ; De aparte callback voorkomt dat deze eenmalige timer de terugkerende
    ; heartbeat-timer overschrijft.
    SetTimer Telemetry_SendStartupHeartbeat, -10000
    SetTimer Telemetry_SendHeartbeat, TelemetryConfig["HeartbeatIntervalMs"]
}

Telemetry_Shutdown() {
    global TelemetryRequest

    SetTimer Telemetry_SendStartupHeartbeat, 0
    SetTimer Telemetry_SendHeartbeat, 0
    if IsObject(TelemetryRequest) {
        try TelemetryRequest.abort()
    }
}

Telemetry_RecordPhoneAction() {
    global TelemetryPhoneActions
    TelemetryPhoneActions += 1
    Telemetry_WriteCounter("PhoneActions", TelemetryPhoneActions)
    return TelemetryPhoneActions
}

Telemetry_RecordLongHotstring() {
    global TelemetryLongHotstringActions
    TelemetryLongHotstringActions += 1
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

Telemetry_ReadCounter(name) {
    global TelemetryConfigFile

    try return Max(0, Integer(IniRead(TelemetryConfigFile, "Usage", name, 0)))
    catch
        return 0
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
        )
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

; =============================================================================
; Opslagcontrole
; =============================================================================
; De gebruikersmap en ieder bestaand DocBot-gegevensbestand worden apart
; getest. De daadwerkelijke schrijfacties houden daarnaast hun eigen foutvangst.

Telemetry_ValidateStorageAccess(configFile) {
    SplitPath(configFile, , &storageDir)

    if storageDir = ""
        throw Error("De gebruikersmap kon niet uit het instellingenpad worden bepaald.`n`n" configFile)

    if !DirExist(storageDir)
        throw Error("De gebruikersmap bestaat niet.`n`n" storageDir)

    Telemetry_AssertDirectoryWritable(storageDir)

    managedFiles := [
        configFile,
        storageDir "\hotstrings.json",
        storageDir "\package-settings.json",
        storageDir "\speeddial.json"
    ]

    for _, path in managedFiles {
        if FileExist(path)
            Telemetry_AssertFileWritable(path)
    }
}

Telemetry_AssertDirectoryWritable(directory) {
    probePath := directory
        . "\.docbot-write-test-"
        . A_NowUTC
        . "-"
        . A_TickCount
        . "-"
        . Random(100000, 999999)
        . ".tmp"
    probeFile := 0

    try {
        probeFile := FileOpen(probePath, "w", "UTF-8-RAW")
        if !IsObject(probeFile)
            throw Error("Het tijdelijke testbestand kon niet worden geopend.")

        probeFile.Write("DocBot schrijftest")
        probeFile.Close()
        probeFile := 0
        FileDelete(probePath)
    } catch as error {
        if IsObject(probeFile)
            try probeFile.Close()
        if FileExist(probePath)
            try FileDelete(probePath)

        throw Error(
            "DocBot kan niet schrijven in de gebruikersmap.`n`n"
            . directory
            . "`n`n"
            . error.Message
        )
    }
}

Telemetry_AssertFileWritable(path) {
    file := 0

    try {
        attributes := FileGetAttrib(path)

        if InStr(attributes, "D")
            throw Error("DocBot verwachtte een bestand, maar vond een map.`n`n" path)

        if InStr(attributes, "R")
            throw Error("Dit DocBot-bestand is alleen-lezen.`n`n" path)

        file := FileOpen(path, "rw")
        if !IsObject(file)
            throw Error("Het bestand kon niet voor lezen en schrijven worden geopend.`n`n" path)

        file.Close()
        file := 0
    } catch as error {
        if IsObject(file)
            try file.Close()

        if InStr(error.Message, path)
            throw error

        throw Error(
            "DocBot kan dit bestand niet wijzigen.`n`n"
            . path
            . "`n`n"
            . error.Message
        )
    }
}
