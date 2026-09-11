#Requires AutoHotkey v2.0
#SingleInstance Off

; Handmatig diagnose-instrument, GEEN onderdeel van de uitgeleverde DocBot-
; applicatie (niet gecompileerd, nergens vanuit DocBot.ahk ge-#Include'd).
; Beantwoordt één vraag, vóórdat de hoofdapplicatie wordt omgebouwd om
; IPTSessionCookie persistent op te slaan: blijft een telefoonkoppeling
; bestaan als je later — met uitsluitend de eerder ontvangen sessiecookie
; (JDMWEBCOOKIE), zonder een nieuwe AllocNumber.xml-aanvraag — opnieuw een
; GetEvent.xml-aanvraag doet, na een herstart van de Ivanti/Windows-sessie?
; Zie docs/DECISIONS.md D-067 voor de volledige achtergrond van dit
; onderzoek.
;
; Gebruik (vanuit een AutoHotkey v2-interpreter, niet compileren):
;   CookiePersistenceProbe.ahk capture   (vandaag: koppelnummer aanvragen,
;                                          laten koppelen, cookie opslaan)
;   CookiePersistenceProbe.ahk resume    (later, bijv. de volgende dag na
;                                          een sessieherstart: uitsluitend
;                                          met de opgeslagen cookie pollen,
;                                          geen nieuwe registratie)
;
; Vereist DocBot.local.ahk naast dit script (dezelfde niet-gecommitte lokale
; configuratie als de hoofdapplicatie). Slaat de cookiewaarde alleen buiten
; de repository op (%A_Temp%), nooit in Git-versiebeheer.
#Include ..\DocBot.local.ahk

CookieProbeFile := A_Temp "\docbot-cookie-probe.txt"
LogFile := A_Temp "\docbot-cookie-probe-log.txt"

baseUrl := LocalConfig["Telephony"]["BaseUrl"]
if !InStr(baseUrl, "https://") {
    MsgBox("Telephony.BaseUrl in DocBot.local.ahk moet met https:// beginnen.", "Cookie-probe", 16)
    ExitApp(1)
}

allocatePage := LocalConfig["Telephony"]["AllocateEndpoint"]
eventPage := LocalConfig["Telephony"]["EventEndpoint"]

mode := A_Args.Length ? A_Args[1] : ""

ProbeLog(tekst) {
    global LogFile
    FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " tekst "`n", LogFile, "UTF-8")
}

; Synchrone aanvraag (Open(..., false)): eenvoudig en zonder event-gedoe,
; prima voor een eenmalig handmatig diagnosescript — anders dan DocBot.ahk
; zelf hoeft dit script de GUI niet responsief te houden.
SendProbeRequest(url, cookie) {
    request := ComObject("Msxml2.ServerXMLHTTP.6.0")
    request.Open("POST", url, false)
    request.SetRequestHeader("Accept-Language", "nl-NL")
    if cookie != ""
        request.SetRequestHeader("Cookie", cookie)
    try
        request.SetTimeouts(5000, 5000, 5000, 15000)

    try {
        request.Send("")
    } catch as err {
        return {status: 0, body: "", xml: "", setCookie: "", error: err.Message}
    }

    setCookie := ""
    try
        setCookie := request.getResponseHeader("Set-Cookie")
    if setCookie != "" {
        semicolonPos := InStr(setCookie, ";")
        setCookie := semicolonPos ? SubStr(setCookie, 1, semicolonPos - 1) : setCookie
    }

    return {status: request.status, body: request.ResponseText, xml: request.responseXML, setCookie: setCookie, error: ""}
}

ExtractEventSummary(xml) {
    try {
        if !IsObject(xml)
            return "(geen XML-respons)"
        root := xml.documentElement
        if !IsObject(root)
            return "(geen event-element)"
        name := root.getAttribute("Name")
        msgNode := root.selectSingleNode("Message")
        textNode := root.selectSingleNode("Text")
        detail := IsObject(msgNode) ? msgNode.text : (IsObject(textNode) ? textNode.text : "")
        return name . (detail != "" ? ": " . detail : "")
    } catch as err {
        return "(kon respons niet verwerken: " . err.Message . ")"
    }
}

if mode = "capture" {
    ProbeLog("=== capture gestart ===")
    allocResult := SendProbeRequest(baseUrl . allocatePage . "?sid=0." . A_TickCount, "")
    if allocResult.error != "" {
        ProbeLog("AllocNumber.xml Send() mislukt: " . allocResult.error)
        MsgBox("AllocNumber.xml-aanvraag mislukt: " . allocResult.error, "Cookie-probe", 16)
        ExitApp(1)
    }
    ProbeLog("AllocNumber.xml status " . allocResult.status . ", Set-Cookie: " . allocResult.setCookie)
    if allocResult.setCookie = "" {
        MsgBox("Geen Set-Cookie ontvangen op AllocNumber.xml. Zie " . LogFile, "Cookie-probe", 16)
        ExitApp(1)
    }

    if FileExist(CookieProbeFile)
        FileDelete(CookieProbeFile)
    FileAppend(allocResult.setCookie, CookieProbeFile, "UTF-8")
    ProbeLog("Cookie opgeslagen in " . CookieProbeFile)

    koppelnummerGetoond := false
    linked := false
    errored := false
    loop 30 {
        pollResult := SendProbeRequest(baseUrl . eventPage . "?sid=0." . A_TickCount, allocResult.setCookie)
        if pollResult.error != "" {
            errored := true
            ProbeLog("GetEvent.xml Send() mislukt: " . pollResult.error)
            MsgBox("GetEvent.xml-aanvraag mislukt: " . pollResult.error . "`n`nCookie staat nog wel opgeslagen in " . CookieProbeFile . ".", "Cookie-probe", 16)
            break
        }
        summary := ExtractEventSummary(pollResult.xml)
        ProbeLog("GetEvent.xml status " . pollResult.status . ": " . summary)

        if InStr(summary, "toestelnummer is") {
            linked := true
            MsgBox(
                "Gekoppeld:`n" . summary
                . "`n`nCookie is opgeslagen in " . CookieProbeFile . "."
                . "`nStart morgen (na de Ivanti/Windows-herstart) dit script met 'resume'.",
                "Cookie-probe — gekoppeld",
                64
            )
            break
        }
        if !koppelnummerGetoond && InStr(summary, "Bel ") {
            koppelnummerGetoond := true
            MsgBox(
                "Koppelnummer ontvangen:`n" . summary
                . "`n`nBel dit nummer om te koppelen. Dit script blijft ondertussen pollen.",
                "Cookie-probe",
                64
            )
        }
        Sleep(2000)
    }
    if !linked && !errored
        MsgBox("Nog niet gekoppeld na ongeveer 60 seconden pollen. Zie " . LogFile . " voor details.", "Cookie-probe", 48)

} else if mode = "resume" {
    ProbeLog("=== resume gestart ===")
    if !FileExist(CookieProbeFile) {
        MsgBox("Geen opgeslagen cookie gevonden (" . CookieProbeFile . "). Draai eerst capture.", "Cookie-probe", 16)
        ExitApp(1)
    }
    savedCookie := Trim(FileRead(CookieProbeFile, "UTF-8"))
    ProbeLog("Opgeslagen cookie gelezen: " . savedCookie)

    result := ""
    loop 5 {
        pollResult := SendProbeRequest(baseUrl . eventPage . "?sid=0." . A_TickCount, savedCookie)
        if pollResult.error != "" {
            ProbeLog("GetEvent.xml Send() mislukt: " . pollResult.error)
            MsgBox("GetEvent.xml-aanvraag mislukt: " . pollResult.error, "Cookie-probe", 16)
            ExitApp(1)
        }
        summary := ExtractEventSummary(pollResult.xml)
        ProbeLog("GetEvent.xml status " . pollResult.status . ", Set-Cookie: " . pollResult.setCookie . ": " . summary)
        if summary != "NULL" {
            result := summary
            break
        }
        Sleep(2000)
    }

    MsgBox(
        "Resultaat met uitsluitend de opgeslagen cookie (geen nieuwe AllocNumber.xml-aanvraag):`n`n"
        . (result != "" ? result : "(alleen NULL-keepalives ontvangen, geen duidelijk resultaat binnen 5 pogingen)")
        . "`n`nBevat dit hetzelfde toestelnummer als gisteren? Dan overleeft de koppeling een"
        . " sessieherstart met uitsluitend de cookie — dat is precies wat IPTSessionCookie-"
        . "persistentie in de hoofdapplicatie zou herstellen."
        . "`n`nVolledig log: " . LogFile,
        "Cookie-probe — resultaat",
        64
    )

} else {
    MsgBox("Gebruik: CookiePersistenceProbe.ahk capture|resume", "Cookie-probe", 48)
}
