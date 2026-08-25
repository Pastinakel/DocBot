; Kopieer dit bestand naar DocBot.local.ahk en vul daar de lokale waarden
; in. DocBot.local.ahk wordt door .gitignore uitgesloten van Git.
;
; Ahk2Exe neemt DocBot.local.ahk tijdens compilatie automatisch op in de
; executable. Het bestand hoeft daarom niet naast de uitgeleverde EXE te staan.

global LocalConfig := Map(
    "Telephony", Map(
        "BaseUrl", "https://VUL-HIER-DE-LOKALE-SERVER-IN/",
        "AllocateEndpoint", "VUL-HIER-HET-REGISTRATIE-ENDPOINT-IN",
        "EventEndpoint", "VUL-HIER-HET-EVENT-ENDPOINT-IN",
        "DialEndpoint", "VUL-HIER-HET-BEL-ENDPOINT-IN"
    ),

    ; Optioneel en alleen gebruikt door de gecompileerde applicatie. Zonder
    ; deze sectie leest DocBot meegeleverde hotstringpakketten automatisch
    ; uit een map "packages" naast de draaiende executable zelf
    ; (A_ScriptDir) — logisch als DocBot.exe al rechtstreeks vanaf de juiste
    ; netwerklocatie wordt gestart (bijv. via een launcher als Ivanti die
    ; "vanaf de bron" start, niet een lokale gecachete kopie). Start de
    ; launcher in plaats daarvan een lokale kopie van de executable, dan
    ; wijst A_ScriptDir naar die lokale map in plaats van de share; vul dan
    ; hieronder het echte UNC-pad in als expliciete override (manifest.json
    ; + pakketbestanden direct in die map, geen submap). Ontbreekt deze
    ; sectie of is de uiteindelijke locatie niet bereikbaar, dan laadt
    ; DocBot die sessie gewoon geen pakketten; persoonlijke hotstrings
    ; blijven altijd werken.
    ;
    ; "Packages", Map(
    ;     "ShareDir", "\\VUL-HIER-DE-NETWERKSHARE-VOOR-PAKKETTEN-IN\packages"
    ; ),

    ; Configuratie voor de eerste CallAction/SMS-proof-of-concept.
    ; De echte interne URL blijft uitsluitend in DocBot.local.ahk.
    ; Voeg voor iedere extra SMS-pagina een nieuw Map-item toe aan deze Array,
    ; gescheiden door een komma. Title is de zichtbare naam in Instellingen.
    "SmsCallAction", [
        Map(
            "Title", "SMS Opnameplein",
            "Url", "https://VUL-HIER-DE-SMS-PAGINA-IN/",
            "FieldId", "number",
            "WindowTitle", "SMS opnameplein Funatic"
            ; TextFieldId is optioneel: het AutomationId/element-id van het
            ; berichtveld op deze SMS-pagina (vaak een <textarea>). Zonder
            ; deze regel kan de gebruiker voor deze pagina geen
            ; standaardtekst instellen bij Instellingen — het bijbehorende
            ; veld staat dan uitgeschakeld.
            ; , "TextFieldId", "message"
        )
    ],

    ; Optionele heartbeat naar Power Automate. De webhook-URL is een geheim
    ; en hoort uitsluitend in het niet-gevolgde DocBot.local.ahk.
    "Telemetry", Map(
        "Enabled", false,
        "WebhookUrl", "",
        "HeartbeatIntervalMs", 900000
    ),

    ; Deze items worden alleen door de bestaande schema-upgrade toegevoegd.
    ; Een gebruiker-item met dezelfde naam, hetzelfde nummer of dezelfde
    ; afkorting wordt nooit overschreven.
    ;
    ; Let op de komma na het eerste Map-item wanneer je meerdere waarden
    ; gebruikt. Verwijder de puntkomma's voor de regels die je wilt activeren.
    "DefaultSpeedDials", [
        ; Map(
        ;     "Name", "VUL-HIER-DE-EERSTE-NAAM-IN",
        ;     "Number", "VUL-HIER-HET-EERSTE-NUMMER-IN",
        ;     "Enabled", true
        ; ),
        ; Map(
        ;     "Name", "VUL-HIER-DE-TWEEDE-NAAM-IN",
        ;     "Number", "VUL-HIER-HET-TWEEDE-NUMMER-IN",
        ;     "Enabled", true
        ; )
    ],

    "DefaultHotstrings", [
        ; Map(
        ;     "Trigger", "VUL-HIER-DE-EERSTE-AFKORTING-IN",
        ;     "Replacement", "VUL-HIER-DE-EERSTE-VERVANGTEKST-IN",
        ;     "Enabled", true,
        ;     "Id", "default-eerste-unieke-id"
        ; ),
        ; Map(
        ;     "Trigger", "VUL-HIER-DE-TWEEDE-AFKORTING-IN",
        ;     "Replacement", "VUL-HIER-DE-TWEEDE-VERVANGTEKST-IN",
        ;     "Enabled", true,
        ;     "Id", "default-tweede-unieke-id"
        ; )
        ;
        ; Gebruik voor echte regeleinden in een AHK-string:
        ; "Eerste regel`r`nTweede regel"
    ]
)
