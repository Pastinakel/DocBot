#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent true
#Include ThirdParty\JXON\JXON.ahk
#Include ThirdParty\ColorButton\ColorButton.ahk
#Include Telemetry.ahk
#Include ThirdParty\UIA-v2\UIA.ahk
#Include ThirdParty\UIA-v2\UIA_Browser.ahk
; Alleen functiedefinities; wordt pas uitgevoerd via de --selftest-poort
; hieronder, ná geldige lokale configuratie. Zie docs/MIGRATIONS.md.
#Include tests\SelfTests.ahk

; De echte lokale configuratie wordt bewust niet door Git gevolgd. Tijdens
; compilatie neemt Ahk2Exe dit include-bestand wel in de executable op.
global LocalConfig
#Include *i DocBot.local.ahk

try ValidateLocalConfiguration()
catch as configError {
    MsgBox(
        "De lokale DocBot-configuratie ontbreekt of is ongeldig.`n`n"
        "Kopieer DocBot.local.example.ahk naar DocBot.local.ahk en vul "
        "de lokale waarden in.`n`n" configError.Message,
        "DocBot - Lokale configuratie",
        "Icon!"
    )
    ExitApp()
}

; Poort voor het losstaande zelftestpakket (tests/SelfTests.ahk): alleen
; actief met het expliciete argument --selftest, ná geldige lokale
; configuratie maar vóór elke GUI-, netwerk- of gebruikersdatatoegang. Een
; normale start (dubbelklik of de gecompileerde executable zonder
; argumenten) bereikt deze tak nooit. Zie docs/MIGRATIONS.md en
; tests/README.md.
if HasCommandLineArgument("--selftest") {
    exitCode := RunSelfTests()
    ExitApp(exitCode)
}

global AppVersion := "2.4-rc.1"

; Toegang tot het debugvenster is gekoppeld aan het Windows-account, niet
; aan een instelling die iedereen zelf kan aanzetten.
global IsDevMode := (A_UserName = "n.feenstra")
global StartupWindowState := GetRequestedStartupWindowState()

; Gebruikersgegevens staan buiten de programmamap en zijn bewust per
; releasekanaal gescheiden. Stable gebruikt DocBot. Binnen elke niet-stabiele
; versie bepaalt de buildvorm (A_IsCompiled), niet het prereleaselabel, of
; DocBot-test of DocBot-dev wordt gebruikt: een gecompileerde prerelease test
; de opleverbare vorm en deelt daarom het centrale testprofiel, een
; niet-gecompileerde prerelease is broncode-ontwikkeling en blijft
; geïsoleerd. Een prereleasebuild kan zo nooit productiedata migreren.
global AppDataFolderName := "DocBot"
global UserDataProfile := GetUserDataProfile(AppVersion, A_IsCompiled)
global ProductionUserDataDir := A_MyDocuments "\" AppDataFolderName
global TestUserDataDir := ProductionUserDataDir "-test"
global DevelopmentUserDataDir := ProductionUserDataDir "-dev"
global UserDataDir := UserDataProfile = "main"
    ? ProductionUserDataDir
    : (UserDataProfile = "test" ? TestUserDataDir : DevelopmentUserDataDir)
global ConfigFile := UserDataDir "\settings.ini"
global DefaultHotstringFile := UserDataDir "\hotstrings.json"
global DefaultPackageSettingsFile := UserDataDir "\package-settings.json"
global DefaultSpeedDialFile := UserDataDir "\speeddial.json"
global DefaultSmsDefaultTextFile := UserDataDir "\sms-default-texts.json"

; =============================================================================
; DocBot
; =============================================================================

global C := Map(
    "Window",      "F4F6F9",
    "Sidebar",     "EDF2F8",
    "Card",        "FFFFFF",
    "Shadow",      "DEE3EA",
    "Border",      "D3D9E2",
    "Primary",     "2563EB",
    "PrimarySoft", "DCEAFE",
    "Text",        "111827",
    "Muted",       "667085",
    "Success",     "17803D",
    "Danger",      "B42318",
    "Button",      "E9EDF3"
)

; Technische instellingen mogen in Git staan; adressen en endpointnamen
; worden uitsluitend uit de niet-geversioneerde lokale configuratie gelezen.
global IPTConfig := Map(
    "ComObject", "Msxml2.XMLHTTP.6.0",
    "URL", LocalConfig["Telephony"]["BaseUrl"],
    "AllocatePage", LocalConfig["Telephony"]["AllocateEndpoint"],
    "EventPage", LocalConfig["Telephony"]["EventEndpoint"],
    "DialPage", LocalConfig["Telephony"]["DialEndpoint"],
    "DialPageNumberParam", "number",
    "DialPageSidParam", "sid",
    "RegisterMinIntervalMs", 10000
)

; SmsCallAction mag voor achterwaartse compatibiliteit één Map zijn, of een
; Array met meerdere Maps. In de GUI wordt uitsluitend Title getoond;
; WindowTitle blijft een technische waarde voor de Edge/UIA-herkenning.
global SmsCallActions := GetConfiguredSmsCallActions()

; Signal.txt-mechanisme voor gecoördineerd afsluiten/herladen vanaf de
; centrale netwerklocatie van de executable — zie CheckSignalFile().
global SignalConfig := Map(
    "FileName", "signal.txt",
    "PollIntervalMs", 10000,        ; hoe vaak clients het bestand controleren
    "StartupTimeoutSec", 5,         ; time-out van de meldingsdialoog bij de allereerste check
    "PeriodicTimeoutSec", 10        ; time-out van de meldingsdialoog bij latere checks
)

global State := Map(
    "CallAction", 1,
    "SmsCallActionTitle", SmsCallActions.Length ? SmsCallActions[1]["Title"] : "",
    "TextReplacement", true,
    "AutoSave", true,
    "HotstringFile", DefaultHotstringFile,
    "IPT", Map(
        "UserTel", "",       ; vervangt State["RegisteredPhone"]; leeg = niet gekoppeld
        "UpdateTel", "",     ; vervangt State["RegistrationNumber"]; leeg tot IPT_register() een koppelnummer teruggeeft
        "NeedUpdate", 0,
        "ClipBoardNumber", "",
        "LastRegisterTick", 0  ; A_TickCount van de laatste IPT_register()-aanvraag
    )
)

global HotstringSchemaVersion := 5
global BundledPackageSchemaVersion := 1
global PackageSettingsSchemaVersion := 1
global BundledPackageDir := ""
global BundledPackages := Map()
global PackageSettings := DefaultPackageSettings()

global SpeedDialSchemaVersion := 3
global TraySpeedDialMaxEntries := 10
global SpeedDialEntries := DefaultSpeedDialEntries()
global Hotstrings := DefaultPersonalHotstrings()

; Standaardtekst per SMS-pagina, functionele sleutel = Title (lowercase,
; getrimd). Moet vóór BuildMainGui() gevuld zijn: de Instellingen-pagina
; toont bij constructie meteen de tekst voor de geselecteerde SMS-pagina.
global SmsDefaultTextSchemaVersion := 1
global SmsDefaultTexts := Map()

global MainGui := 0
global Pages := Map("overzicht", [], "telefonie", [], "tekstvervanging", [], "instellingen", [], "help", [], "over", [])
global CurrentPage := ""
global HelpSections := []
global HelpOpenSection := 1
; Index binnen HelpSections van "Wat mag ik wel en niet in een hotstring
; zetten?", gezet in BuildMainGui() direct na die AddHelpAccordionSection()-
; aanroep. Gebruikt door OpenHotstringHelpSection() zodat de link bij de
; hint op Tekstvervanging altijd naar de juiste, actuele sectie-index
; verwijst, ook als de volgorde van accordeonsecties ooit verandert.
global HotstringHelpSectionIndex := 0
; Zelfde principe als HotstringHelpSectionIndex hierboven, maar voor de
; startup-onboardingtips (zie TipDefinitions verderop): gezet in
; BuildMainGui() direct na de bijbehorende AddHelpAccordionSection()-aanroep,
; zodat een tip-link altijd naar de juiste, actuele sectie-index verwijst.
global TipPhoneHelpSectionIndex := 0
global TipSmsHelpSectionIndex := 0
global TipHotstringHelpSectionIndex := 0
global HelpLinkControls := Map()
global NavButtons := Map()
global NavBars := Map()
global RoundQueue := []
global FlatButtons := []
global UiBitmaps := []

global RegisteredNumberText := 0
global RegistrationNumberText := 0
global RegistrationStatusText := 0
global RegistrationRefreshButton := 0
global RegistrationHelperText := 0

; Losse, module-brede request-objecten per IPT-aanroep (i.p.v. één gedeeld
; xhr via .Bind()), zodat een nieuwe aanvraag nooit de referentie van een
; nog lopende aanvraag overschrijft voordat de callback is afgerond.
global IPTRegisterRequest := 0
global IPTPollRequest := 0
global IPTDialRequest := 0

; Beperkte standaardlogging en toestemmingsgebonden uitgebreide logging.
global DebugLogBuffer := ""
global ExtendedDebugLogBuffer := ""
global DebugFlushPending := false
global ExtendedDebugFlushPending := false
global DebugWindow := 0
global DebugLogEdit := 0
global DebugAutoScroll := true

; De probleemrapportagesessie leeft uitsluitend in het geheugen. Het sluiten
; van het venster behoudt de sessie; afsluiten of herstarten van DocBot stopt
; uitgebreide logging en verwijdert het tijdelijke uitgebreide logbestand.
global ProblemReportGui := 0
global ProblemReportDescriptionEdit := 0
global ProblemReportConsentCheck := 0
global ProblemReportSession := Map(
    "Phase", "start",
    "ExtendedActive", false,
    "StartedAt", "",
    "Description", "",
    "ExtendedLogPath", "",
    "Finalizing", false
)

; Eigen, altijd-zichtbaar meldingsvenstertje i.p.v. TrayTip() — zie
; ShowNotification(). Op zakelijk beheerde Windows-machines wordt het
; OS-notificatiesysteem waar TrayTip() op leunt vaak stilzwijgend beperkt
; door group policy (geen foutmelding, de balloon verschijnt gewoon niet).
global NotificationGui := 0

; Gedeelde toetsenbordstatus voor de belbevestiging en de keuze
; Annuleren / SMS / Bellen. Links/rechts verplaatst de visuele selectie;
; Enter voert de geselecteerde echte Button-control uit.
global PhoneActionDialogState := 0

global CallActionSelector := 0
global TextReplacementCheck := 0
global OverviewPhoneActionsText := 0
global OverviewLongHotstringActionsText := 0
global OverviewSmsActionsText := 0

; Startup-onboardingtips (docs/TODO.md): een blijvende gele hint-balk op
; Overzicht die willekeurig één van de onderstaande tips toont, op de plek
; van de vroegere vaste footertekst "Sluiten verbergt DocBot in het
; systeemvak" (die nu zelf tip "TrayClose" is geworden). Zie
; EvaluateStartupTip() en de bijbehorende opslagfuncties.
global TipRepeatCapCount := 5
global TipMinIntervalDays := 10
; Ná TipRepeatCapCount keer tonen stopt een tip niet definitief: hij blijft
; daarna nog steeds geschikt, maar met dit veel ruimere interval (in plaats
; van TipMinIntervalDays) tussen twee keer tonen.
global TipLongTermIntervalMonths := 6
global TipBannerSelected := false   ; deze sessie al geloot? (voorkomt herloten)
global TipBannerActive := false     ; hoort de balk nu zichtbaar te zijn?
global CurrentTipKey := ""
global TipBannerSurface := 0
global TipBannerAccent := 0
global TipBannerLink := 0
global TipBannerCloseButton := 0

; TipDefinitions verwijst naar functienamen (Condition/HelpHandler) die pas
; verderop in het bestand gedefinieerd worden. Dat is geen probleem: AHK v2
; slaat functiedefinities over tijdens de auto-execute-uitvoering, maar de
; functies zelf bestaan al als aanroepbare waarde ongeacht hun positie in het
; bestand (zie de AHK v2-uitleg in CLAUDE.md).
global TipDefinitions := [
    Map(
        "Key", "Phone",
        "Condition", TipConditionPhone,
        "Text", 'Tip: Bellen zonder nummer in te toetsen? DocBot doet dat voor je. Bekijk <a href="help">hier</a> hoe dat werkt.',
        "HelpHandler", OpenPhoneTipHelp
    ),
    Map(
        "Key", "Hotstrings",
        "Condition", TipConditionHotstrings,
        "Text", 'Tip: DocBot kan standaardteksten voor je invoeren door Hotstrings te gebruiken. Bekijk <a href="help">hier</a> hoe.',
        "HelpHandler", OpenHotstringTipHelp
    ),
    Map(
        "Key", "Sms",
        "Condition", TipConditionSms,
        "Text", 'Tip: Een SMS sturen zonder zelf het nummer in te voeren? DocBot kan dat (en meer). Bekijk <a href="help">hier</a> hoe.',
        "HelpHandler", OpenSmsTipHelp
    ),
    Map(
        "Key", "TrayClose",
        "Condition", TipConditionAlways,
        "Text", "Tip: DocBot sluiten verbergt de app alleen in het systeemvak; hij blijft actief op de achtergrond.",
        "HelpHandler", ""
    )
]

; Voor RefreshInstellingenValuesAfterReady(): dezelfde besturingselementen
; als de lokale variabelen in BuildMainGui(), zodat de Instellingen-pagina
; na degraded mode met de dan pas echt geladen waarden ververst kan worden
; in plaats van de bouwtijd-standaardwaarden te blijven tonen.
global InstellingenAutoSaveCheck := 0
global InstellingenFilePathEdit := 0
global InstellingenSmsActionDropDown := 0
global InstellingenSmsDefaultTextEdit := 0
global InstellingenSmsDefaultTextHint := 0
global InstellingenPendingSmsDefaultTexts := 0

global SpeedDialLV := 0
global SpeedDialEnabledCheck := 0
global SpeedDialNameEdit := 0
global SpeedDialNumberEdit := 0

global SidebarPhoneDot := 0
global SidebarPhoneText := 0
global SidebarTextDot := 0
global SidebarTextText := 0

global SpeedDialLV := 0

global HotLV := 0
global HotSearch := 0
global HotTriggerEdit := 0
global HotReplacementSingleGroup := 0
global HotReplacementMultiGroup := 0
global HotReplacementExpandButton := 0
global HotReplacementCollapseButton := 0
global HotEditorCompactCard := 0
global HotEditorExpandedCard := 0
global HotSaveButton := 0
global HotReplacementDraft := ""
global HotReplacementExpanded := false
global HotReplacementSingleIsPreview := false
global HotEnabledCheck := 0
global HotOptionDraft := DefaultHotstringOptions()
; Lange en meerregelige vervangingen krijgen een eigen callback. Die gebruikt
; uitsluitend gesimuleerde tekstinvoer en raakt het Windows-klembord niet aan.
global DirectTextReplacementThreshold := 200

; Los pakketbeheervenster. De rijmappings bewaren de stabiele pakket- en
; item-ID's, zodat sortering of zichtbare namen nooit als opslag-ID dienen.
global PackageManagerGui := 0
global PackageManagerPackageLV := 0
global PackageManagerItemLV := 0
global PackageManagerStatusText := 0

; Bevat de op dit moment bij AutoHotkey geregistreerde dynamische hotstrings.
global RuntimeHotstrings := Map()

; Wordt in InitializeUserStorage() gezet vóór die functie de gebruikersmap
; eventueel aanmaakt/kopieert, zodat later (o.a. LoadAppSettings()) kan
; onderscheiden of een ontbrekend bestand een net gebootstrapte, lege map is
; (normaal, geen fout) of een al bestaande map waar iets tijdelijk
; onbereikbaar is (opslagfout, moet opnieuw geprobeerd worden).
global UserDataDirIsPreexisting := false

; Eén gedeelde achtergrondtimer voor alle opstartladers die op dezelfde
; Documents/OneDrive-map leunen. Ze falen en herstellen doorgaans
; gelijktijdig (dezelfde onderliggende oorzaak, bijv. OneDrive dat bij
; autostart nog niet gemount is), dus draait er niet per lader een eigen
; tijdklok. Elke lader houdt wél zijn eigen resultaat en foutmelding aan:
; het slagen van de één mag het blijven mislukken van een ander nooit
; maskeren. Cadans spiegelt de bestaande Telemetry_TryEnsureInstallationId()
; (D-027/D-028): enkele snelle pogingen, daarna uursgewijs, zonder bovengrens.
; "Gebruikersmap" staat altijd eerst: de overige vijf laders lezen/schrijven
; allemaal binnen UserDataDir en kunnen pas slagen zodra die map er echt is.
global StorageRetryLoaders := [
    Map("Name", "Gebruikersmap", "Fn", InitializeUserStorage, "Ready", false),
    Map("Name", "Instellingen", "Fn", LoadAppSettings, "Ready", false),
    Map("Name", "Hotstrings", "Fn", InitializeHotstringStorage, "Ready", false),
    Map("Name", "Pakketkeuzes", "Fn", InitializePackageSettings, "Ready", false),
    Map("Name", "Snelkiesnummers", "Fn", InitializeSpeedDialStorage, "Ready", false),
    Map("Name", "SMS-standaardteksten", "Fn", InitializeSmsDefaultTextStorage, "Ready", false)
]
global StorageRetryAttempts := 0
global StorageRetryQuickMs := 60000
global StorageRetryQuickCount := 5
global StorageRetrySlowMs := 3600000

; True zodra alle StorageRetryLoaders zijn geladen (alles-of-niets,
; projecteigenaar-besluit 2026-08-28). Bepaalt of data-afhankelijke
; kaarten/pagina's zichtbaar zijn; zie ShowPage(), MarkDegradedGateStart()/
; MarkDegradedGateEnd() en ShowOnlyWhileDegraded() verderop.
global StorageAllReady := false

; Onthoudt, per pagina, vanaf welke index in Pages[pageKey] de eerstvolgende
; MarkDegradedGateEnd() moet gelden. Zie MarkDegradedGateStart().
global DegradedGateRangeStart := Map()

; Twee losse synchrone kansen vóór de achtergrondtimer overneemt: eerst
; alleen de gebruikersmap (moet er al staan vóórdat pakketten/logging iets
; met UserDataDir kunnen), dan — na InitializeBundledPackages(), die geen
; relatie met UserDataDir heeft en zo de bestaande logvolgorde intact
; laat — de overige vijf laders vóór het eerst. StorageRetry_AttemptLoader()
; slaat een al geslaagde lader over, dus de tweede aanroep herprobeert de
; gebruikersmap alleen als die nét nog niet lukte.
StorageRetry_RunInitialAttemptForUserDataDir()
InitializeBundledPackages()
StorageRetry_RunInitialAttempt()
ReloadRuntimeHotstrings()
Telemetry_Initialize(ConfigFile, AppVersion, GetTelemetryStatus)
InitializeDiagnosticLogging()
DebugLog("i", "DocBot gestart", "Versie " AppVersion ".")

if HasCommandLineArgument("--docbot-update-restart")
    SetTimer(CleanupScheduledRestartTask, -2000)

BuildMainGui()
BuildTrayMenu()
OnMessage(0x404, TrayIconMessage)  ; tray-icon notifications
OnMessage(0x0100, PhoneActionDialogKeyDown)  ; WM_KEYDOWN voor beide Belactie-dialogen
OnExit(HandleAppExit)
showOptions := "w1000 h700 Center"
if StartupWindowState = "minimized"
    showOptions .= " Minimize"
else if StartupWindowState = "background"
    showOptions .= " NA"
MainGui.Show(showOptions)
ApplyRoundedControls()
RedrawFlatButtons()
RefreshSidebarStatuses()

SetTimer ClipBoardPoller, 100

; Onafhankelijk van netwerkverkeer: houdt de Verversen-knop-countdown ook
; bijgewerkt als de poll-keten een keer stokt (bijv. tussen Bug 1 en de
; volgende Verversen-klik in).
SetTimer UpdateRegisterButtonState, 1000

; Altijd aanvragen bij opstarten, zodat er in ieder geval een initieel
; koppelnummer bekend is. IPT_poller() start hier de aaneengeschakelde
; poll-lus; elke volgende aanroep wordt door IPT_PollResponse() zelf
; gepland zodra de vorige aanvraag is afgerond (geen vaste interval-timer).
IPT_register(false)   ; geen cooldown bij de automatische aanvraag tijdens opstarten
IPT_poller()

SetTimer CheckSignalFile, SignalConfig["PollIntervalMs"]
CheckSignalFile(SignalConfig["StartupTimeoutSec"])

; =============================================================================
; HOOFDVENSTER
; =============================================================================

BuildMainGui() {
    global MainGui, C, State, AppVersion
    global RegisteredNumberText, RegistrationNumberText, RegistrationStatusText, RegistrationRefreshButton
    global RegistrationHelperText
    global CallActionSelector, TextReplacementCheck
    global OverviewPhoneActionsText, OverviewLongHotstringActionsText, OverviewSmsActionsText
    global HotLV, HotSearch, HotTriggerEdit, HotEnabledCheck
    global HotReplacementSingleGroup, HotReplacementMultiGroup
    global HotReplacementExpandButton, HotReplacementCollapseButton
    global HotEditorCompactCard, HotEditorExpandedCard, HotSaveButton
    global SidebarPhoneDot, SidebarPhoneText, SidebarTextDot, SidebarTextText
    global SpeedDialLV, SpeedDialEnabledCheck, SpeedDialNameEdit, SpeedDialNumberEdit
    global HelpSections, HotstringHelpSectionIndex
    global TipPhoneHelpSectionIndex, TipSmsHelpSectionIndex, TipHotstringHelpSectionIndex
    global TipBannerSurface, TipBannerAccent, TipBannerLink, TipBannerCloseButton
    global InstellingenAutoSaveCheck, InstellingenFilePathEdit, InstellingenSmsActionDropDown
    global InstellingenSmsDefaultTextEdit, InstellingenSmsDefaultTextHint
    global InstellingenPendingSmsDefaultTexts

    MainGui := Gui("-MaximizeBox", "DocBot")
    MainGui.BackColor := C["Window"]
    MainGui.SetFont("s10 c" C["Text"], "Segoe UI")
    MainGui.MarginX := 0
    MainGui.MarginY := 0

    ; Sidebar
    MainGui.AddText("x0 y0 w210 h700 Background" C["Sidebar"], "")

    appTitle := MainGui.AddText("x28 y20 w150 h28 Background" C["Sidebar"], "DocBot")
    appTitle.SetFont("s18 bold c" C["Text"], "Segoe UI")

    appSub := MainGui.AddText("x28 y52 w170 h18 Background" C["Sidebar"], "Telefonie voor de werkplek")
    appSub.SetFont("s9 c" C["Muted"], "Segoe UI")

    AddNavButton("overzicht", Chr(0xE80F), "Overzicht", 110)
    AddNavButton("telefonie", Chr(0xE717), "Telefonie", 162)
    AddNavButton("tekstvervanging", Chr(0xE8FD), "Hotstrings", 214)
    AddNavButton("instellingen", Chr(0xE713), "Instellingen", 266)
    AddNavButton("help", Chr(0xE82D), "Help", 318)
    AddNavButton("over", Chr(0xE946), "Over", 370)

    MainGui.AddText("x24 y426 w164 h1 Background" C["Border"], "")
    AddExitButton(444)

    MainGui.AddText("x24 y548 w162 h1 Background" C["Border"], "")

    phoneHdr := MainGui.AddText("x28 y560 w120 h18 Background" C["Sidebar"], "Telefonie:")
    phoneHdr.SetFont("s9 bold c" C["Text"], "Segoe UI")

    SidebarPhoneDot := MainGui.AddText("x31 y582 w10 h14 Background" C["Sidebar"], "●")
    SidebarPhoneDot.SetFont("s8 c" C["Danger"], "Segoe UI")

    SidebarPhoneText := MainGui.AddText("x54 y582 w126 h20 Background" C["Sidebar"], "")
    SidebarPhoneText.SetFont("s9 c" C["Text"], "Segoe UI")

    textHdr := MainGui.AddText("x28 y616 w128 h18 Background" C["Sidebar"], "Tekst vervangen:")
    textHdr.SetFont("s9 bold c" C["Text"], "Segoe UI")

    SidebarTextDot := MainGui.AddText("x31 y638 w10 h14 Background" C["Sidebar"], "●")
    SidebarTextDot.SetFont("s8 c" C["Danger"], "Segoe UI")

    SidebarTextText := MainGui.AddText("x54 y638 w126 h20 Background" C["Sidebar"], "")
    SidebarTextText.SetFont("s9 c" C["Text"], "Segoe UI")

    versionLabel := MainGui.AddText("x28 y674 w160 h16 Background" C["Sidebar"], AppVersion)
    versionLabel.SetFont("s8 c" C["Muted"], "Segoe UI")

    ; -------------------------------------------------------------------------
    ; PAGINA: OVERZICHT
    ; -------------------------------------------------------------------------

    AddPageHeader("overzicht", "Overzicht", "Registreer je telefoon en beheer de hoofdfuncties van DocBot.")

    ; Compacte kaarten laten ruimte voor statistieken binnen het vaste venster.
    AddCard("overzicht", 236, 92, 736, 142)
    AddCardLabel("overzicht", 260, 108, 220, 20, "Geregistreerd nummer", "s10 c" C["Muted"])
    RegistrationStatusText := AddCardLabel("overzicht", 792, 108, 148, 20, "", "s9 bold c" C["Success"], "Right")
    RegisteredNumberText := AddCardLabel("overzicht", 260, 132, 340, 42, "", "s28 bold c" C["Text"])
    RegistrationHelperText := AddCardLabel("overzicht", 260, 184, 360, 26, "Dit nummer is momenteel gekoppeld aan de sessie.", "s9 c" C["Muted"])
    AddCardLabel("overzicht", 694, 108, 246, 20, "Bel dit nummer om te registreren", "s10 c" C["Muted"], "Right")
    RegistrationNumberText := AddCardLabel("overzicht", 694, 136, 246, 34, State["IPT"]["UpdateTel"], "s21 bold c" C["Text"], "Right")
    RegistrationRefreshButton := AddFlatButton("overzicht", 740, 180, 200, 36, Chr(0xE72C) "  Verversen", RefreshRegistrationStatus, true)

    ; Neemt tijdens degraded mode de plek in van de kaarten hieronder (die
    ; dan verborgen zijn), zodat er geen bestaande y-posities hoeven te
    ; verschuiven. De registratiekaart hierboven blijft altijd zichtbaar:
    ; telefonie-koppeling hangt niet af van settings.ini/hotstrings/
    ; pakketkeuzes/snelkiesnummers/sms-standaardteksten.
    AddDegradedBanner(
        "overzicht",
        246,
        "Instellingen worden geladen. Functionaliteit hieronder is tijdelijk beperkt. Telefonie-koppeling werkt gewoon door."
    )
    MarkDegradedGateStart("overzicht")

    AddCard("overzicht", 236, 246, 736, 142)
    AddCardLabel("overzicht", 260, 262, 180, 22, "Belactie", "s13 bold c" C["Text"])
    CallActionSelector := AddCallActionSelector(
        "overzicht",
        State["CallAction"],
        CallActionChanged
    )
    AddCardLabel(
        "overzicht",
        606,
        346,
        338,
        34,
        HasConfiguredSmsCallActions()
            ? "Bij 'Bellen of sms kiezen' krijgen externe nummers een keuze; interne nummers worden direct gebeld."
            : "Configureer eerst een SMS-pagina om de keuze tussen bellen en sms beschikbaar te maken.",
        "s8 c" C["Muted"]
    )

    AddCard("overzicht", 236, 400, 736, 104)
    AddCardLabel("overzicht", 260, 416, 240, 22, "Tekstvervanging", "s13 bold c" C["Text"])
    TextReplacementCheck := AddToggle("overzicht", 260, 446, "Actief", State["TextReplacement"], SettingChanged.Bind("TextReplacement"))
    AddCardLabel("overzicht", 260, 474, 390, 20, "Vervang opgeslagen afkortingen automatisch tijdens het typen.", "s8 c" C["Muted"])
    AddFlatButton("overzicht", 756, 444, 200, 36, Chr(0xE8FD) "  Hotstrings beheren", ShowPage.Bind("tekstvervanging"), false)

    AddCard("overzicht", 236, 516, 736, 128)
    AddCardLabel("overzicht", 260, 532, 200, 22, "Gebruik", "s13 bold c" C["Text"])
    phoneUsageIcon := AddCardLabel("overzicht", 256, 568, 36, 34, Chr(0xE717), "s20 c" C["Primary"], "Center")
    phoneUsageIcon.SetFont("s20 c" C["Primary"], "Segoe MDL2 Assets")
    AddCardLabel("overzicht", 302, 562, 170, 18, "Belacties", "s9 c" C["Muted"])
    OverviewPhoneActionsText := AddCardLabel("overzicht", 302, 582, 170, 34, Telemetry_GetPhoneActions(), "s22 bold c" C["Text"])
    hotstringUsageIcon := AddCardLabel("overzicht", 501, 568, 36, 34, Chr(0xE8FD), "s20 c" C["Primary"], "Center")
    hotstringUsageIcon.SetFont("s20 c" C["Primary"], "Segoe MDL2 Assets")
    AddCardLabel("overzicht", 547, 562, 170, 18, "Lange hotstrings", "s9 c" C["Muted"])
    OverviewLongHotstringActionsText := AddCardLabel("overzicht", 547, 582, 170, 34, Telemetry_GetLongHotstringActions(), "s22 bold c" C["Text"])
    smsUsageIcon := AddCardLabel("overzicht", 746, 568, 36, 34, Chr(0xE8BD), "s20 c" C["Primary"], "Center")
    smsUsageIcon.SetFont("s20 c" C["Primary"], "Segoe MDL2 Assets")
    AddCardLabel("overzicht", 792, 562, 170, 18, "SMS-acties", "s9 c" C["Muted"])
    OverviewSmsActionsText := AddCardLabel("overzicht", 792, 582, 170, 34, Telemetry_GetSmsActions(), "s22 bold c" C["Text"])

    MarkDegradedGateEnd("overzicht")

    ; Startup-onboardingtip: gele hint-balk op de plek van de vroegere vaste
    ; footertekst. Zichtbaarheid wordt niet via AddPageControl/de generieke
    ; pagina-gating geregeld (die zou de balk bij elke terugkeer naar
    ; Overzicht weer tonen), maar volledig los van Pages[] beheerd door
    ; ApplyTipBannerVisibility() — zie EvaluateStartupTip().
    TipBannerSurface := MainGui.AddText("x236 y653 w736 h38 BackgroundFDF0DE +Hidden", "")
    TipBannerAccent := MainGui.AddText("x236 y653 w4 h38 BackgroundF08200 +Hidden", "")
    TipBannerLink := MainGui.AddLink("x252 y664 w650 h20 BackgroundFDF0DE +Hidden", "")
    TipBannerLink.SetFont("s10 c5C3600", "Segoe UI")
    TipBannerCloseButton := MainGui.AddText("x934 y658 w28 h28 Center 0x200 BackgroundFDF0DE +Hidden", Chr(0xE711))
    TipBannerCloseButton.SetFont("s10 c5C3600", "Segoe MDL2 Assets")
    TipBannerCloseButton.OnEvent("Click", DismissTipBanner)

    ; -------------------------------------------------------------------------
    ; PAGINA: TELEFONIE
    ; -------------------------------------------------------------------------

    AddPageHeader("telefonie", "Telefonie", "Bel en beheer je snelkiesnummers.")

    AddDegradedBanner("telefonie", 92, "Instellingen worden geladen. Snelkiesnummers zijn nog niet beschikbaar.")
    MarkDegradedGateStart("telefonie")

    AddCard("telefonie", 236, 92, 736, 394)
    AddCardLabel("telefonie", 260, 114, 300, 24, "Snelkiesnummers", "s14 bold c" C["Text"])
    AddFlatButton("telefonie", 816, 106, 140, 34, Chr(0xE717) "  Bellen", CallSelectedSpeedDial, true)

    SpeedDialLV := MainGui.AddListView(
        "x252 y152 w704 h274 Grid -Multi",
        ["Actief", "Naam", "Nummer"]
    )
    SpeedDialLV.ModifyCol(1, 60)
    SpeedDialLV.ModifyCol(2, 400)
    SpeedDialLV.ModifyCol(3, 220)
    SpeedDialLV.OnEvent("Click", FillSpeedDialFormFromSelection)
    SpeedDialLV.OnEvent("DoubleClick", EditSelectedSpeedDial)
    AddPageControl("telefonie", SpeedDialLV)

    AddFlatButton("telefonie", 252, 436, 140, 36, Chr(0xE710) "  Nieuw", NewSpeedDial, false)
    AddFlatButton("telefonie", 402, 436, 140, 36, Chr(0xE70F) "  Wijzig", EditSelectedSpeedDial, false)
    AddFlatButton("telefonie", 552, 436, 140, 36, Chr(0xE74D) "  Verwijder", DeleteSelectedSpeedDial, false)
    AddFlatButton("telefonie", 702, 436, 42, 36, Chr(0xE70E), MoveSpeedDialUp, false)
    AddFlatButton("telefonie", 752, 436, 42, 36, Chr(0xE70D), MoveSpeedDialDown, false)

    ; y=500 h=148 eindigt op y=648; Hotstrings en Over sluiten hier op aan.
    AddCard("telefonie", 236, 500, 736, 148)
    AddCardLabel("telefonie", 260, 520, 300, 24, "Snelkiesnummer bewerken", "s12 bold c" C["Text"])
    SpeedDialEnabledCheck := MainGui.AddCheckbox("x260 y560 w82 h24 Background" C["Card"], "Actief")
    SpeedDialEnabledCheck.Value := 1
    AddPageControl("telefonie", SpeedDialEnabledCheck)
    AddCardLabel("telefonie", 350, 566, 48, 20, "Naam", "s10 c" C["Text"])
    SpeedDialNameEdit := AddRoundedEdit("telefonie", 402, 552, 220, 36, "")
    AddCardLabel("telefonie", 638, 566, 58, 20, "Nummer", "s10 c" C["Text"])
    SpeedDialNumberEdit := AddRoundedEdit("telefonie", 700, 552, 120, 36, "")
    AddFlatButton("telefonie", 832, 552, 124, 36, Chr(0xE74E) "  Opslaan", SaveSpeedDialFromForm, true)

    MarkDegradedGateEnd("telefonie")

    ; -------------------------------------------------------------------------
    ; PAGINA: TEKSTVERVANGING
    ; -------------------------------------------------------------------------

    AddPageHeader("tekstvervanging", "Tekstvervanging", "Beheer de hotstrings van DocBot.")

    AddDegradedBanner("tekstvervanging", 92, "Instellingen worden geladen. Hotstrings zijn nog niet beschikbaar.")
    MarkDegradedGateStart("tekstvervanging")

    AddCard("tekstvervanging", 236, 92, 736, 346)
    AddCardLabel("tekstvervanging", 260, 114, 300, 24, "Hotstrings", "s14 bold c" C["Text"])
    AddFlatButton(
        "tekstvervanging",
        584, 106, 140, 36,
        Chr(0xE8F1) "  Pakketten",
        ShowPackageManager,
        false
    )

    HotSearch := AddRoundedEdit("tekstvervanging", 736, 106, 220, 36, "")
    SetCueText(HotSearch, "Zoeken ...")
    HotSearch.OnEvent("Change", RefreshHotstringList)

    HotLV := MainGui.AddListView(
        "x252 y152 w704 h224 Grid -Multi",
        ["Actief", "Afkorting", "Vervanging", "Opties", "ID"]
    )
    HotLV.ModifyCol(1, 60)
    HotLV.ModifyCol(2, 120)
    HotLV.ModifyCol(3, 410)
    HotLV.ModifyCol(4, 90)
    HotLV.ModifyCol(5, 0)  ; stabiele ID blijft aan de rij gekoppeld bij sorteren
    HotLV.OnEvent("Click", FillHotstringFormFromSelection)
    HotLV.OnEvent("DoubleClick", EditSelectedHotstring)
    AddPageControl("tekstvervanging", HotLV)

    AddFlatButton("tekstvervanging", 252, 388, 140, 36, Chr(0xE710) "  Nieuw", NewHotstring, false)
    AddFlatButton("tekstvervanging", 402, 388, 140, 36, Chr(0xE70F) "  Wijzig", EditSelectedHotstring, false)
    AddFlatButton("tekstvervanging", 552, 388, 140, 36, Chr(0xE74D) "  Verwijder", DeleteSelectedHotstring, false)

    ; Beide kaarten eindigen bewust op dezelfde y=648 als de kaart
    ; "Snelkiesnummer bewerken" op de Telefonie-pagina (y=500 h=148), zodat
    ; Hotstrings en Telefonie onderaan gelijk aflopen. Het uitgeklapte
    ; meerregelige veld is daarom iets minder hoog (56 i.p.v. 70) dan vóór
    ; deze uitlijning, en Opslaan staat op een vaste plek die in beide
    ; standen past in plaats van te verspringen tussen y=590 en y=626.
    HotEditorCompactCard := AddCard("tekstvervanging", 236, 452, 736, 196)
    HotEditorExpandedCard := AddCard("tekstvervanging", 236, 452, 736, 196)
    AddCardLabel("tekstvervanging", 260, 472, 220, 22, "Hotstring bewerken", "s12 bold c" C["Text"])
    AddFlatButton("tekstvervanging", 588, 464, 220, 34, "⚙  Geavanceerde opties...", ShowAdvancedHotstringOptions, false)
    HotEnabledCheck := MainGui.AddCheckbox("x840 y472 w100 h22 Background" C["Card"], "Actief")
    HotEnabledCheck.Value := 1
    AddPageControl("tekstvervanging", HotEnabledCheck)
    AddCardLabel("tekstvervanging", 260, 512, 100, 20, "Afkorting", "s10 c" C["Text"])
    HotTriggerEdit := AddRoundedEdit("tekstvervanging", 370, 504, 586, 34, "")
    AddCardLabel("tekstvervanging", 260, 548, 100, 20, "Vervanging", "s10 c" C["Text"])
    HotReplacementSingleGroup := AddRoundedEditGroup("tekstvervanging", 370, 540, 538, 34, "", false, 8)
    HotReplacementMultiGroup := AddRoundedEditGroup("tekstvervanging", 370, 540, 538, 56, "", true, 6)
    HotReplacementSingleGroup["Edit"].OnEvent("Change", UpdateHotReplacementDraft)
    HotReplacementMultiGroup["Edit"].OnEvent("Change", UpdateHotReplacementDraft)
    ; Deze twee eenvoudige klikcontrols worden door Windows betrouwbaarder
    ; opnieuw getekend na hide/show dan twee overlappende custom-draw buttons.
    HotReplacementExpandButton := MainGui.AddText(
        "x920 y540 w36 h34 Center 0x200 Background" C["Button"],
        Chr(0xE740)
    )
    HotReplacementExpandButton.SetFont("s12 c" C["Text"], "Segoe MDL2 Assets")
    AddRound(HotReplacementExpandButton, 10)
    AddPageControl("tekstvervanging", HotReplacementExpandButton)
    HotReplacementExpandButton.OnEvent(
        "Click", ToggleHotReplacementEditor.Bind(true)
    )

    HotReplacementCollapseButton := MainGui.AddText(
        "x920 y540 w36 h34 Center 0x200 Background" C["Button"],
        Chr(0xE73F)
    )
    HotReplacementCollapseButton.SetFont("s12 c" C["Text"], "Segoe MDL2 Assets")
    AddRound(HotReplacementCollapseButton, 10)
    AddPageControl("tekstvervanging", HotReplacementCollapseButton)
    HotReplacementCollapseButton.OnEvent(
        "Click", ToggleHotReplacementEditor.Bind(false)
    )
    ; Vaste positie (was afhankelijk van HotReplacementExpanded): het
    ; meerregelige veld eindigt nu altijd ruim vóór y=638, dus Opslaan hoeft
    ; niet meer te verspringen.
    HotSaveButton := AddFlatButton("tekstvervanging", 808, 602, 148, 36, "💾  Opslaan", SaveHotstringFromForm, true)
    ApplyHotReplacementEditorState()

    ; De privacyhint hieronder blijft bewust ongated: net als de footer op
    ; andere pagina's is dit paginabrede, niet-data-afhankelijke chrome.
    MarkDegradedGateEnd("tekstvervanging")

    ; h=38 gecentreerd in de 52px-ruimte tussen het einde van de kaart
    ; hierboven (y=648) en de vensterrand (700): 648 + (52-38)/2 = 655, met
    ; 7px marge boven en onder. Zelfde gele stijl als de onboardingtip-balk
    ; op Overzicht (TipBannerSurface/-Accent/-Link), maar zonder sluitkruisje
    ; en altijd zichtbaar op deze pagina: dit is een blijvende privacyregel,
    ; geen aan/uit-tip. Als paginabreed element (geen kaartinhoud) blijft de
    ; melding zichtbaar in zowel de compacte als de uitgeklapte weergave van
    ; de hotstringeditor.
    HotPrivacySurface := MainGui.AddText("x236 y655 w736 h38 BackgroundFDF0DE", "")
    AddPageControl("tekstvervanging", HotPrivacySurface)
    HotPrivacyAccent := MainGui.AddText("x236 y655 w4 h38 BackgroundF08200", "")
    AddPageControl("tekstvervanging", HotPrivacyAccent)
    HotPrivacyHint := MainGui.AddLink(
        "x252 y666 w704 h20 BackgroundFDF0DE",
        'ℹ️  Zet geen patiëntgegevens in hotstrings. Bekijk de richtlijn op de <a href="help">Help</a>-pagina.'
    )
    HotPrivacyHint.SetFont("s10 c5C3600", "Segoe UI")
    ; Opent Help mét de bijbehorende accordeonsectie al uitgeklapt, in
    ; plaats van alleen naar de Help-pagina te navigeren.
    HotPrivacyHint.OnEvent("Click", OpenHotstringHelpSection)
    AddPageControl("tekstvervanging", HotPrivacyHint)

    ; -------------------------------------------------------------------------
    ; PAGINA: INSTELLINGEN
    ; -------------------------------------------------------------------------

    AddPageHeader("instellingen", "Instellingen", "Beheer de opslag, import en SMS-integratie.")

    AddDegradedBanner("instellingen", 92, "Instellingen worden geladen. Deze pagina is nog niet beschikbaar.")
    MarkDegradedGateStart("instellingen")

    AddCard("instellingen", 236, 92, 736, 194)
    AddCardLabel("instellingen", 260, 114, 250, 24, "Hotstringbestand", "s14 bold c" C["Text"])

    autoSaveCheck := MainGui.AddCheckbox("x260 y152 w340 h22 Background" C["Card"], "Hotstrings automatisch opslaan en laden")
    autoSaveCheck.Value := State["AutoSave"]
    AddPageControl("instellingen", autoSaveCheck)
    InstellingenAutoSaveCheck := autoSaveCheck

    filePathEdit := AddRoundedEdit("instellingen", 260, 188, 520, 36, State["HotstringFile"])
    InstellingenFilePathEdit := filePathEdit
    AddFlatButton("instellingen", 792, 188, 172, 36, "📁  Bladeren", BrowseHotstringFile.Bind(filePathEdit), false)
    AddFlatButton("instellingen", 260, 230, 220, 36, "↥  Oud .txt importeren", ImportLegacyHotstrings, false)
    AddFlatButton("instellingen", 692, 230, 132, 36, "📂  Laden", ManualLoadHotstrings.Bind(filePathEdit), false)
    AddFlatButton("instellingen", 832, 230, 132, 36, "💾  Opslaan", ManualSaveHotstrings.Bind(filePathEdit), true)

    AddCard("instellingen", 236, 304, 736, 314)
    AddCardLabel("instellingen", 260, 326, 250, 24, "SMS actie", "s14 bold c" C["Text"])
    AddCardLabel("instellingen", 260, 366, 200, 20, "SMS-pagina", "s10 c" C["Muted"])

    smsActionTitles := GetSmsCallActionTitles()
    smsActionOptions := smsActionTitles.Length
        ? smsActionTitles
        : ["Geen SMS-pagina's geconfigureerd"]
    selectedSmsActionIndex := FindSmsCallActionIndexByTitle(State["SmsCallActionTitle"])
    if selectedSmsActionIndex = 0
        selectedSmsActionIndex := 1

    smsActionDropDown := MainGui.AddDropDownList(
        "x260 y390 w688 Choose" selectedSmsActionIndex,
        smsActionOptions
    )
    if smsActionTitles.Length = 0
        smsActionDropDown.Enabled := false
    AddPageControl("instellingen", smsActionDropDown)
    InstellingenSmsActionDropDown := smsActionDropDown

    AddCardLabel(
        "instellingen",
        260, 430, 688, 20,
        "Deze pagina wordt gebruikt bij de belactie 'Bellen of sms kiezen'.",
        "s9 c" C["Muted"]
    )

    ; Standaardtekst per SMS-pagina: meerregelig, harde enters toegestaan
    ; (zelfde Multi/VScroll-opzet als het hotstring-Replacement-veld
    ; hierboven, dat WantReturn al niet nodig blijkt te hebben). Label en
    ; toelichting staan samen op één regel om ruimte te winnen voor het
    ; tekstveld zelf; de losse "N SMS-pagina('s) beschikbaar"-regel is
    ; geschrapt omdat de dropdown daarboven dat al laat zien.
    AddCardLabel(
        "instellingen",
        260, 460, 688, 34,
        "Standaardtekst (wordt samen met het telefoonnummer ingevuld in het berichtveld van deze SMS-pagina):",
        "s10 c" C["Muted"]
    )
    smsDefaultTextGroup := AddRoundedEditGroup("instellingen", 260, 494, 688, 100, "", true, 6)
    smsDefaultTextEdit := smsDefaultTextGroup["Edit"]
    InstellingenSmsDefaultTextEdit := smsDefaultTextEdit
    ; Blijft leeg zolang de standaardtekst gewoon bruikbaar is; toont anders
    ; waarom het veld is uitgeschakeld (zie ApplySmsDefaultTextFieldState()).
    smsDefaultTextHint := AddCardLabel("instellingen", 260, 598, 688, 16, "", "s9 c" C["Muted"])
    InstellingenSmsDefaultTextHint := smsDefaultTextHint

    ; Niet-opgeslagen tekst blijft per SMS-pagina in het geheugen staan
    ; zolang de Instellingen-pagina open is, ook als tussendoor van
    ; SMS-pagina wordt gewisseld. Pas op Opslaan wordt alles weggeschreven
    ; naar sms-default-texts.json, net als de rest van deze pagina.
    pendingSmsDefaultTexts := Map()
    InstellingenPendingSmsDefaultTexts := pendingSmsDefaultTexts
    smsDefaultTextUiState := Map(
        "LastTitle", HasConfiguredSmsCallActions() ? ResolveSmsCallActionTitle(State["SmsCallActionTitle"]) : ""
    )
    ApplySmsDefaultTextFieldState(smsActionDropDown, smsDefaultTextEdit, smsDefaultTextHint, pendingSmsDefaultTexts)
    smsActionDropDown.OnEvent(
        "Change",
        SmsActionSelectionChanged.Bind(
            smsActionDropDown, smsDefaultTextEdit, smsDefaultTextHint,
            pendingSmsDefaultTexts, smsDefaultTextUiState
        )
    )

    AddFlatButton(
        "instellingen",
        824, 638, 140, 38,
        "Opslaan",
        SaveSettings.Bind(
            autoSaveCheck, filePathEdit, smsActionDropDown,
            smsDefaultTextEdit, pendingSmsDefaultTexts, smsDefaultTextUiState
        ),
        true,
        C["Window"]
    )

    MarkDegradedGateEnd("instellingen")

    ; -------------------------------------------------------------------------
    ; PAGINA: HELP
    ; -------------------------------------------------------------------------

    AddPageHeader("help", "Help", "Uitleg over de belangrijkste functies van DocBot.")

    AddHelpAccordionSection(
        "Hoe koppel ik mijn telefoon?",
        "Open Overzicht in DocBot en bel met je werktelefoon het getoonde koppelnummer."
        "`r`n`r`nWordt er geen koppelnummer getoond? Klik dan op Verversen."
        "`r`n`r`nNa het koppelen verschijnt je toestelnummer bij Geregistreerd nummer.",
        ["Overzicht", "Verversen", "Geregistreerd nummer"],
        Map("Overzicht", "overzicht")
    )
    TipPhoneHelpSectionIndex := HelpSections.Length
    AddHelpAccordionSection(
        "Hoe bel of sms ik vanuit een applicatie?",
        "Kies bij Belactie op de pagina Overzicht wat DocBot met een herkend nummer moet doen."
        "`r`n`r`nKopieer in de gebruikte applicatie het gewenste telefoonnummer. "
        "DocBot herkent het nummer en voert de gekozen belactie uit. Bij SMS kan DocBot ook een standaardtekst voor je klaarzetten."
        "`r`n`r`nIn HiX klik je linksboven op het pijltje naast het telefoonnummer van de patiënt "
        "en vervolgens op het getoonde telefoonnummer."
        "`r`n`r`nJe kunt kiezen voor niets doen, bellen na bevestiging, direct bellen of bij externe nummers kiezen tussen bellen en sms. "
        "Interne nummers worden bij die laatste keuze direct gebeld."
        "`r`n`r`nBij een extern Nederlands 06-nummer opent SMS de onder Instellingen gekozen pagina en vult DocBot het telefoonnummer in."
        "`r`n`r`nSoms toont HiX na het kopiëren van het nummer een foutmelding. "
        "Deze melding kun je negeren zonder HiX af te sluiten.",
        ["Belactie", "Overzicht", "niets doen", "bellen na bevestiging", "direct bellen", "bellen en sms", "Interne nummers", "Instellingen", "SMS"],
        Map("Overzicht", "overzicht")
    )
    TipSmsHelpSectionIndex := HelpSections.Length
    AddHelpAccordionSection(
        "Hoe bel ik via snelkiesnummers?",
        "Open Telefonie in DocBot, selecteer een actief snelkiesnummer en klik op Bellen."
        "`r`n`r`nMet Nieuw, Wijzig en Verwijder beheer je de lijst. "
        "De snelkiesnummers zijn ook beschikbaar in het rechtermuisknopmenu "
        "van het DocBot-pictogram in het systeemvak.",
        ["Telefonie", "Bellen", "Nieuw", "Wijzig", "Verwijder"],
        Map("Telefonie", "telefonie")
    )
    AddHelpAccordionSection(
        "Hoe gebruik ik hotstrings?",
        "Controleer op Overzicht in DocBot of Tekstvervanging actief is."
        "`r`n`r`nTyp in een willekeurige applicatie (zoals Outlook, HiX of Word) "
        "een ingestelde afkorting, gevolgd door een spatie of een ander eindteken. "
        "DocBot vervangt de afkorting automatisch."
        "`r`n`r`nOp de pagina Hotstrings in DocBot kun je persoonlijke afkortingen beheren "
        "en hotstringpakketten inschakelen.",
        ["Overzicht", "Tekstvervanging", "Hotstrings"],
        Map("Overzicht", "overzicht", "Hotstrings", "tekstvervanging")
    )
    TipHotstringHelpSectionIndex := HelpSections.Length
    AddHelpAccordionSection(
        "Wat mag ik wel en niet in een hotstring zetten?",
        "Hotstrings zijn bedoeld voor generieke, herbruikbare tekst: vaste zinnen, "
        "standaardformuleringen of afkortingen die je voor meerdere situaties gebruikt."
        "`r`n`r`nZet nooit patiëntidentificerende of patiëntspecifieke gegevens in een "
        "hotstring, zoals een patiëntnaam, geboortedatum, BSN of dossiernummer, of een "
        "tekst die alleen op één patiënt van toepassing is. Hotstrings staan in "
        "hotstrings.json op je eigen computer en zijn niet bedoeld als plek voor "
        "dossierinformatie."
        "`r`n`r`nGenerieke klinische formuleringen die niet aan een identificeerbare "
        "patiënt gekoppeld zijn, mag je wel gebruiken, bijvoorbeeld 'geen afwijkingen' "
        "of 'Op {{datum}} zag ik uw patiënt'. Zulke tekst wordt pas patiëntspecifiek op "
        "het moment dat jij ze in een dossier invoegt en aanvult, niet door de hotstring "
        "zelf."
        "`r`n`r`nOok je eigen naam, telefoonnummer, e-mailadres of ondertekening in een "
        "hotstring kan persoonsgegevens zijn. Dat is toegestaan voor praktisch gebruik, "
        "zoals een vaste afsluiting, maar valt onder het reguliere privacybeleid van je "
        "organisatie."
        "`r`n`r`nDocBot controleert de inhoud van je hotstrings niet automatisch op "
        "patiëntgegevens. Je blijft dus zelf verantwoordelijk voor wat je opslaat."
        "`r`n`r`nBeheer je persoonlijke hotstrings op de pagina Hotstrings in DocBot.",
        [
            "hotstrings.json",
            "patiëntidentificerende of patiëntspecifieke gegevens",
            "controleert de inhoud van je hotstrings niet automatisch",
            "Hotstrings"
        ],
        Map("Hotstrings", "tekstvervanging")
    )
    HotstringHelpSectionIndex := HelpSections.Length
    RefreshHelpAccordion()

    ; De bestaande footer wordt volledig vervangen door een herkenbare
    ; ingang naar dezelfde probleemrapportage als in het systeemvakmenu.
    AddFlatButton(
        "help",
        786, 654, 170, 34,
        "Probleem melden...",
        ShowProblemReportWindow,
        false
    )

    ; -------------------------------------------------------------------------
    ; PAGINA: OVER
    ; -------------------------------------------------------------------------

    AddPageHeader("over", "Over", "Informatie over DocBot.")

    ; Kaarthoogte 556 (i.p.v. voorheen 500) laat deze kaart, net als
    ; Hotstrings en Telefonie, op y=648 eindigen. De GitHub-link hieronder
    ; staat verticaal gecentreerd in de ruimte daaronder.
    AddCard("over", 236, 92, 736, 556)

    aboutShell := MainGui.AddText("x260 y116 w688 h508 Background" C["Border"], "")
    AddRound(aboutShell, 12)
    AddPageControl("over", aboutShell)

    aboutEdit := MainGui.AddEdit(
        "x262 y118 w684 h504 ReadOnly VScroll Multi -E0x200 BackgroundFFFFFF",
        BuildAboutText()
    )
    aboutEdit.SetFont("s10 c" C["Text"], "Segoe UI")
    AddRound(aboutEdit, 10)
    AddPageControl("over", aboutEdit)

    ; y=662 centreert deze 24px-hoge link verticaal in de 52px-ruimte
    ; tussen het einde van de kaart hierboven (y=648) en de vensterrand
    ; (700): 648 + (52-24)/2 = 662, met 14px marge boven en onder.
    githubLink := MainGui.AddLink(
        "x262 y662 w300 h24",
        'Bekijk DocBot op <a href="https://github.com/Pastinakel/DocBot">GitHub</a>'
    )
    githubLink.SetFont("s10 c" C["Text"], "Segoe UI")
    githubLink.OnEvent("Click", OpenGithubLink)
    AddPageControl("over", githubLink)

    RefreshRegistrationTexts()
    RefreshHotstringList()
    RefreshSpeedDialList()
    ShowPage("overzicht")

    ; Doet niets zolang StorageAllReady nog false is (degraded mode): dan
    ; loot StorageRetry_OnAllReady() de tip later alsnog, ná echt geladen
    ; tellers/Hotstrings. Zie EvaluateStartupTip().
    EvaluateStartupTip()

    MainGui.OnEvent("Close", MainGui_Close)
    MainGui.OnEvent("Escape", MainGui_Escape)
}

; Click-event van een Link-control geeft bij deze control geen href terug
; via Info (dat bleek in de praktijk de 1-gebaseerde index van het
; aangeklikte linksegment, geen URL). Er staat hier maar één link, dus de
; URL is vast hardcoded in plaats van uit Info afgeleid. * vangt eventuele
; parameters op die de event meegeeft, zodat het exacte aantal nooit een
; "Invalid callback function"-fout kan veroorzaken.
OpenGithubLink(*) {
    Run("https://github.com/Pastinakel/DocBot")
}

; =============================================================================
; GUI BOUWSTENEN
; =============================================================================

AddNavButton(pageKey, icon, caption, y) {
    global MainGui, C, NavButtons, NavBars

    accent := MainGui.AddText("x16 y" (y + 5) " w4 h34 Background" C["Primary"], "")
    AddRound(accent, 4)
    accent.Opt("+Hidden")
    NavBars[pageKey] := accent

    baseBg := MainGui.AddText("x24 y" y " w164 h44 Background" C["Sidebar"], "")
    AddRound(baseBg, 16)

    activeBg := MainGui.AddText("x24 y" y " w164 h44 Background" C["PrimarySoft"], "")
    AddRound(activeBg, 16)
    activeBg.Opt("+Hidden")

    iconCtrl := MainGui.AddText("x46 y" (y + 10) " w24 h24 Center Background" C["Sidebar"], icon)
    iconCtrl.SetFont("s14 c344054", "Segoe MDL2 Assets")

    textCtrl := MainGui.AddText("x78 y" (y + 10) " w94 h24 Background" C["Sidebar"], caption)
    textCtrl.SetFont("s10 c344054", "Segoe UI")

    for _, ctrl in [baseBg, activeBg, iconCtrl, textCtrl] {
        ctrl.Opt("0x100 0x200")
        ctrl.OnEvent("Click", ShowPage.Bind(pageKey))
    }

    NavButtons[pageKey] := Map(
        "BaseBg", baseBg,
        "ActiveBg", activeBg,
        "Icon", iconCtrl,
        "Text", textCtrl
    )
}


AddHelpAccordionSection(title, bodyText, boldTerms := [], linkTargets := 0) {
    global MainGui, C, HelpSections

    ; Beide kaartformaten worden vooraf als GDI+-bitmap opgebouwd. Bij het
    ; openen wisselen we alleen zichtbaarheid en positie, waardoor de
    ; afgeronde hoeken ook na paginawisselingen stabiel blijven. De hoogtes
    ; hier moeten gelijk blijven aan collapsedHeight/expandedHeight in
    ; RefreshHelpAccordion() — dat bepaalt alleen de tussenruimte, niet de
    ; werkelijke kaartgrootte.
    collapsedCard := AddCard("help", 236, 104, 720, 54)
    expandedCard := AddCard("help", 236, 104, 720, 258)
    expandedCard.Opt("+Hidden")

    titleCtrl := MainGui.AddText(
        "x260 y122 w600 h28 Background" C["Card"],
        title
    )
    titleCtrl.SetFont("s13 bold c" C["Text"], "Segoe UI")
    titleCtrl.Opt("0x100 0x200")
    AddPageControl("help", titleCtrl)

    arrowCtrl := MainGui.AddText(
        "x904 y119 w28 h30 Center Background" C["Card"],
        "›"
    )
    arrowCtrl.SetFont("s18 c" C["Primary"], "Segoe UI")
    arrowCtrl.Opt("0x100 0x200")
    AddPageControl("help", arrowCtrl)

    ; Een gewone Edit-control ondersteunt geen gemengde letterstijlen.
    ; RichEdit laat belangrijke paginanamen en knoppen wel vet zien, terwijl
    ; het tekstvlak gewoon alleen-lezen en verticaal scrollbaar blijft.
    DllCall("LoadLibraryW", "Str", "Msftedit.dll", "Ptr")
    bodyEdit := MainGui.Add(
        "Custom",
        "ClassRICHEDIT50W x260 y162 w672 h184 +0x200844 -E0x200 BackgroundFFFFFF",
        bodyText
    )
    bodyEdit.SetFont("s10 c" C["Text"], "Segoe UI")
    FormatHelpBody(bodyEdit, bodyText, boldTerms, linkTargets)
    ; Ook zonder linkTargets moet HelpRichEditSubclass() klikken kunnen
    ; afvangen, anders zou zo'n sectie alsnog een blauwe tekstselectie
    ; kunnen tonen (zie EnsureHelpRichEditSubclass()).
    EnsureHelpRichEditSubclass(bodyEdit)
    AddRound(bodyEdit, 8)
    bodyEdit.Opt("+Hidden")
    AddPageControl("help", bodyEdit)

    sectionIndex := HelpSections.Length + 1
    clickHandler := ToggleHelpSection.Bind(sectionIndex)
    titleCtrl.OnEvent("Click", clickHandler)
    arrowCtrl.OnEvent("Click", clickHandler)
    collapsedCard.OnEvent("Click", clickHandler)
    ; De geopende kaart zelf krijgt bewust geen klikhandler: het RichEdit-
    ; tekstvlak bevat navigatielinks en mag de accordeon niet inklappen.

    HelpSections.Push(Map(
        "CollapsedCard", collapsedCard,
        "ExpandedCard", expandedCard,
        "Title", titleCtrl,
        "Arrow", arrowCtrl,
        "Body", bodyEdit
    ))
}

FormatHelpBody(bodyCtrl, bodyText, boldTerms, linkTargets := 0) {
    ; CFM_BOLD / CFE_BOLD op iedere opgegeven tekstpassage. Posities voor
    ; EM_SETSEL zijn nulgebaseerd, terwijl InStr() ééngebaseerd zoekt.
    static EM_SETSEL := 0x00B1
    static EM_SETCHARFORMAT := 0x0444
    static SCF_SELECTION := 0x0001
    static SCF_ALL := 0x0004
    static CFM_BOLD := 0x00000001
    static CFM_ITALIC := 0x00000002
    static CFM_UNDERLINE := 0x00000004
    static CFE_BOLD := 0x00000001

    ; RichEdit kan bij het overnemen van de GUI-fontstatus ook effecten van
    ; het vorige control erven. Wis daarom voor de volledige inhoud eerst
    ; expliciet vet, cursief en onderstreept.
    normalFormat := Buffer(92, 0)
    NumPut("UInt", normalFormat.Size, normalFormat, 0)
    NumPut(
        "UInt",
        CFM_BOLD | CFM_ITALIC | CFM_UNDERLINE,
        normalFormat,
        4
    )
    NumPut("UInt", 0, normalFormat, 8)

    DllCall(
        "SendMessageW",
        "Ptr", bodyCtrl.Hwnd,
        "UInt", EM_SETCHARFORMAT,
        "Ptr", SCF_ALL,
        "Ptr", normalFormat.Ptr,
        "Ptr"
    )

    if !(boldTerms is Array)
        return

    ; RichEdit bewaart CRLF intern als één teken. Gebruik dezelfde notatie
    ; voor de selectieposities; anders schuift iedere selectie na een
    ; alinea één positie per regeleinde naar rechts.
    positionText := StrReplace(bodyText, "`r`n", "`r")

    for _, term in boldTerms {
        searchFrom := 1
        while foundAt := InStr(positionText, term, true, searchFrom) {
            selectionStart := foundAt - 1
            selectionEnd := selectionStart + StrLen(term)

            DllCall(
                "SendMessageW",
                "Ptr", bodyCtrl.Hwnd,
                "UInt", EM_SETSEL,
                "Ptr", selectionStart,
                "Ptr", selectionEnd,
                "Ptr"
            )

            charFormat := Buffer(92, 0)
            NumPut("UInt", charFormat.Size, charFormat, 0)
            NumPut("UInt", CFM_BOLD, charFormat, 4)
            NumPut("UInt", CFE_BOLD, charFormat, 8)

            DllCall(
                "SendMessageW",
                "Ptr", bodyCtrl.Hwnd,
                "UInt", EM_SETCHARFORMAT,
                "Ptr", SCF_SELECTION,
                "Ptr", charFormat.Ptr,
                "Ptr"
            )

            searchFrom := foundAt + StrLen(term)
        }
    }

    linkRanges := []
    if linkTargets is Map {
        static CFM_LINK := 0x00000020
        static CFE_LINK := 0x00000020

        for term, pageKey in linkTargets {
            searchFrom := 1
            while foundAt := InStr(positionText, term, true, searchFrom) {
                selectionStart := foundAt - 1
                selectionEnd := selectionStart + StrLen(term)

                DllCall(
                    "SendMessageW",
                    "Ptr", bodyCtrl.Hwnd,
                    "UInt", EM_SETSEL,
                    "Ptr", selectionStart,
                    "Ptr", selectionEnd,
                    "Ptr"
                )

                linkFormat := Buffer(92, 0)
                NumPut("UInt", linkFormat.Size, linkFormat, 0)
                NumPut("UInt", CFM_LINK, linkFormat, 4)
                NumPut("UInt", CFE_LINK, linkFormat, 8)

                DllCall(
                    "SendMessageW",
                    "Ptr", bodyCtrl.Hwnd,
                    "UInt", EM_SETCHARFORMAT,
                    "Ptr", SCF_SELECTION,
                    "Ptr", linkFormat.Ptr,
                    "Ptr"
                )

                linkRanges.Push(Map(
                    "Start", selectionStart,
                    "End", selectionEnd,
                    "Page", pageKey
                ))
                searchFrom := foundAt + StrLen(term)
            }
        }

        if linkRanges.Length
            RegisterHelpLinkControl(bodyCtrl, linkRanges)
    }

    ; Laat na het formatteren geen tekst geselecteerd achter.
    DllCall(
        "SendMessageW",
        "Ptr", bodyCtrl.Hwnd,
        "UInt", EM_SETSEL,
        "Ptr", 0,
        "Ptr", 0,
        "Ptr"
    )
}

RegisterHelpLinkControl(bodyCtrl, linkRanges) {
    global HelpLinkControls

    HelpLinkControls[bodyCtrl.Hwnd] := Map(
        "Control", bodyCtrl,
        "Ranges", linkRanges
    )
    InstallHelpRichEditSubclass(bodyCtrl)
}

; Zorgt dat ook een accordeonsectie zónder linkTargets de subclass krijgt
; die HelpRichEditSubclass() gebruikt om iedere klik/dubbelklik af te
; vangen (zie daar). Zonder deze aanroep zou zo'n sectie geen entry in
; HelpLinkControls hebben en zou een klik alsnog RichEdit's standaard
; tekstselectie starten. Idempotent: doet niets als RegisterHelpLinkControl
; deze hwnd al heeft geregistreerd.
EnsureHelpRichEditSubclass(bodyCtrl) {
    global HelpLinkControls

    if HelpLinkControls.Has(bodyCtrl.Hwnd)
        return

    HelpLinkControls[bodyCtrl.Hwnd] := Map(
        "Control", bodyCtrl,
        "Ranges", []
    )
    InstallHelpRichEditSubclass(bodyCtrl)
}

InstallHelpRichEditSubclass(bodyCtrl) {
    ; Subclass het RichEdit-venster zelf. Daarmee komt WM_LBUTTONDOWN altijd
    ; langs onze handler, onafhankelijk van EN_LINK/EN_MSGFILTER.
    static subclassCallback := 0
    if !subclassCallback
        subclassCallback := CallbackCreate(HelpRichEditSubclass, "", 6)

    if !DllCall(
        "comctl32\SetWindowSubclass",
        "Ptr", bodyCtrl.Hwnd,
        "Ptr", subclassCallback,
        "Ptr", 1,
        "Ptr", 0,
        "Int"
    )
        throw Error("De klikafhandeling in Help kon niet worden geactiveerd.")
}

HelpRichEditSubclass(
    hwnd,
    message,
    wParam,
    lParam,
    subclassId,
    referenceData
) {
    global HelpLinkControls

    static WM_LBUTTONDOWN := 0x0201
    static WM_LBUTTONDBLCLK := 0x0203
    static WM_NCDESTROY := 0x0082
    static EM_CHARFROMPOS := 0x00D7

    ; De hulptekst is alleen-lezen uitlegtekst, geen invoerveld: een klik of
    ; dubbelklik mag nooit een blauwe tekstselectie achterlaten. Alleen een
    ; klik op een geregistreerde linktekst wordt doorgelaten (als navigatie,
    ; niet als selectie); elke andere klik/dubbelklik wordt hier volledig
    ; afgevangen zodat RichEdit's standaard selectiegedrag nooit start.
    if message = WM_LBUTTONDOWN
        && IsSet(HelpLinkControls)
        && IsObject(HelpLinkControls)
        && HelpLinkControls.Has(hwnd) {
        mouseX := lParam & 0xFFFF
        mouseY := (lParam >> 16) & 0xFFFF
        if mouseX & 0x8000
            mouseX -= 0x10000
        if mouseY & 0x8000
            mouseY -= 0x10000

        point := Buffer(8, 0)
        NumPut("Int", mouseX, point, 0)
        NumPut("Int", mouseY, point, 4)
        clickedAt := DllCall(
            "SendMessageW",
            "Ptr", hwnd,
            "UInt", EM_CHARFROMPOS,
            "Ptr", 0,
            "Ptr", point.Ptr,
            "Ptr"
        )

        for _, linkRange in HelpLinkControls[hwnd]["Ranges"] {
            if clickedAt >= linkRange["Start"]
                && clickedAt < linkRange["End"] {
                ShowPage(linkRange["Page"])
                return 0
            }
        }

        return 0
    }

    if message = WM_LBUTTONDBLCLK
        && IsSet(HelpLinkControls)
        && IsObject(HelpLinkControls)
        && HelpLinkControls.Has(hwnd)
        return 0

    if message = WM_NCDESTROY
        && IsSet(HelpLinkControls)
        && IsObject(HelpLinkControls)
        && HelpLinkControls.Has(hwnd)
        HelpLinkControls.Delete(hwnd)

    return DllCall(
        "comctl32\DefSubclassProc",
        "Ptr", hwnd,
        "UInt", message,
        "Ptr", wParam,
        "Ptr", lParam,
        "Ptr"
    )
}

ToggleHelpSection(sectionIndex, *) {
    global HelpOpenSection

    HelpOpenSection := HelpOpenSection = sectionIndex ? 0 : sectionIndex
    RefreshHelpAccordion()
    ApplyRoundedControls(true)
    RedrawMainGui()
}

; Klikhandler voor de hint op de Tekstvervanging-pagina: navigeert naar
; Help en klapt meteen de bijbehorende accordeonsectie open, in plaats van
; de gebruiker die zelf te laten zoeken/aanklikken. ShowPage("help") ververst
; de accordeon en de afgeronde hoeken zelf al, dus dat hoeft hier niet nog
; eens.
OpenHotstringHelpSection(*) {
    global HelpOpenSection, HotstringHelpSectionIndex

    HelpOpenSection := HotstringHelpSectionIndex
    ShowPage("help")
}

; Zelfde constructie als OpenHotstringHelpSection() hierboven, maar voor de
; Help-links in de startup-onboardingtips (TipDefinitions).
OpenPhoneTipHelp(*) {
    global HelpOpenSection, TipPhoneHelpSectionIndex

    HelpOpenSection := TipPhoneHelpSectionIndex
    ShowPage("help")
}

OpenSmsTipHelp(*) {
    global HelpOpenSection, TipSmsHelpSectionIndex

    HelpOpenSection := TipSmsHelpSectionIndex
    ShowPage("help")
}

OpenHotstringTipHelp(*) {
    global HelpOpenSection, TipHotstringHelpSectionIndex

    HelpOpenSection := TipHotstringHelpSectionIndex
    ShowPage("help")
}

RefreshHelpAccordion() {
    global HelpSections, HelpOpenSection

    ; collapsedHeight is bewust kleiner dan de kaarthoogte die
    ; AddHelpAccordionSection() voor iedere ingeklapte kaart aanmaakt (64):
    ; met vijf secties en één opengeklapte sectie (258) moet de opsomming
    ; nog boven de "Probleem melden..."-knop op y=654 eindigen. Bij
    ; collapsedHeight=54 eindigt de langste combinatie (258 + 4×54 + 5×12)
    ; op y=638, met 16px marge tot die knop.
    y := 104
    gap := 12
    collapsedHeight := 54
    expandedHeight := 258

    for index, section in HelpSections {
        isOpen := index = HelpOpenSection

        section["CollapsedCard"].Move(236, y)
        section["ExpandedCard"].Move(236, y)
        section["CollapsedCard"].Opt(isOpen ? "+Hidden" : "-Hidden")
        section["ExpandedCard"].Opt(isOpen ? "-Hidden" : "+Hidden")

        section["Title"].Move(260, y + 18)
        section["Arrow"].Move(904, y + 15)
        section["Arrow"].Text := isOpen ? "⌄" : "›"

        if isOpen {
            section["Body"].Move(260, y + 58, 672, 184)
            section["Body"].Opt("-Hidden")
            ClearHelpBodySelection(section["Body"])
            ; Directe aanroep is niet altijd genoeg: bij navigatie vanaf een
            ; andere control (zoals de hint op Tekstvervanging) komt de
            ; ongewenste selectie soms pas iets later binnen, via een
            ; bericht dat nog in de wachtrij stond op het moment van deze
            ; aanroep. Een eenmalige herhaling na de huidige berichtenronde
            ; wint dan alsnog van dat late bericht.
            SetTimer(ClearHelpBodySelection.Bind(section["Body"]), -50)
        } else {
            section["Body"].Opt("+Hidden")
        }

        y += (isOpen ? expandedHeight : collapsedHeight) + gap
    }
}

; FormatHelpBody() al collapt zijn eigen opmaakselectie na het vet maken
; van termen/links, maar dat gebeurt eenmalig bij het bouwen van de GUI.
; Een sectie die via OpenHotstringHelpSection() wordt geopend terwijl de
; klik nog op een ándere control (de link op Tekstvervanging) plaatsvond,
; kan de hele hoofdtekst blauw geselecteerd tonen zodra het RichEdit-veld
; zichtbaar wordt en onverwacht focus krijgt — vermoedelijk doordat Windows
; automatisch focus verplaatst naar de nu zichtbare RichEdit wanneer de
; eerder gefocuste linkcontrol wegvalt, gecombineerd met een leftover
; muisstatus van die klik. Deze selectie blijft dan zichtbaar staan tot de
; volgende gebruikersinteractie. Dit wist elke keer dat een sectie
; opengaat expliciet de selectie, ongeacht de precieze oorzaak.
ClearHelpBodySelection(bodyCtrl) {
    static EM_SETSEL := 0x00B1

    DllCall(
        "SendMessageW",
        "Ptr", bodyCtrl.Hwnd,
        "UInt", EM_SETSEL,
        "Ptr", 0,
        "Ptr", 0,
        "Ptr"
    )
}

; Geen navigatiepagina — dit sluit de hele applicatie af, inclusief het
; tray-icoon. Bewust visueel afwijkend (kleur, icoon, scheidingslijn) van
; de vier paginaknoppen erboven, die alleen tussen pagina's wisselen.
AddExitButton(y) {
    global MainGui, C

    ; Segoe MDL2 Assets i.p.v. Segoe UI Symbol: U+23FB (POWER SYMBOL) zit in
    ; een later toegevoegd Unicode-blok dat op sommige door IT beheerde
    ; Windows-images ontbreekt in Segoe UI Symbol, terwijl de MDL2-glyph
    ; (Chr(0xE7E8)) via hetzelfde font dat Windows zelf gebruikt in
    ; Instellingen/Start-menu vrijwel gegarandeerd aanwezig is.
    iconCtrl := MainGui.AddText("x46 y" (y + 10) " w24 h24 Center Background" C["Sidebar"], Chr(0xE7E8))
    iconCtrl.SetFont("s14 c" C["Danger"], "Segoe MDL2 Assets")

    textCtrl := MainGui.AddText("x78 y" (y + 10) " w110 h24 Background" C["Sidebar"], "Afsluiten")
    textCtrl.SetFont("s11 c" C["Danger"], "Segoe UI")

    for _, ctrl in [iconCtrl, textCtrl] {
        ctrl.Opt("0x100 0x200")
        ctrl.OnEvent("Click", ConfirmExitApp)
    }
}

ConfirmExitApp(*) {
    if MsgBox(
        "DocBot volledig afsluiten? Dit sluit ook het systeemvak-icoon, en automatische belacties werken dan niet meer totdat je DocBot opnieuw start.",
        "DocBot afsluiten",
        "YesNo Icon!"
    ) = "Yes"
        ExitApp()
}

AddPageHeader(pageKey, title, subtitle) {
    global MainGui, C

    titleCtrl := MainGui.AddText("x236 y22 w430 h40 Background" C["Window"], title)
    titleCtrl.SetFont("s22 bold c" C["Text"], "Segoe UI")
    AddPageControl(pageKey, titleCtrl)

    subtitleCtrl := MainGui.AddText("x236 y64 w560 h20 Background" C["Window"], subtitle)
    subtitleCtrl.SetFont("s10 c" C["Muted"], "Segoe UI")
    AddPageControl(pageKey, subtitleCtrl)
}

AddCard(pageKey, x, y, w, h, radius := 10) {
    global MainGui, C

    ; Eén GDI+-bitmap bevat zowel de antialiased card als de subtiele schaduw.
    ; Daardoor blijft de vorm stabiel bij hide/show en paginawisselingen.
    bitmap := CreateCardBitmap(w, h, radius, C["Card"], C["Window"], C["Shadow"])
    card := MainGui.AddPicture(
        ; WS_CLIPSIBLINGS voorkomt dat de bitmap bij een repaint over andere
        ; child-controls heen tekent.
        "x" x " y" y " w" (w + 3) " h" (h + 4) " 0x4000000",
        "HBITMAP:*" bitmap
    )
    AddPageControl(pageKey, card)
    return card
}

AddCardLabel(pageKey, x, y, w, h, text, fontOptions, alignment := "") {
    global MainGui, C

    opts := "x" x " y" y " w" w " h" h " Background" C["Card"]
    if alignment != ""
        opts .= " " alignment

    ctrl := MainGui.AddText(opts, text)
    ctrl.SetFont(fontOptions, "Segoe UI")
    AddPageControl(pageKey, ctrl)
    return ctrl
}

AddFlatButton(pageKey, x, y, w, h, caption, callback, primary := false, surfaceColor := "") {
    global MainGui, C, FlatButtons

    background := primary ? C["Primary"] : C["Button"]
    textColor := primary ? "FFFFFF" : C["Text"]

    ; Houd iconen en tekst in hun eigen fonts. Segoe MDL2 heeft afwijkende
    ; tekstmetriek; font fallback knipt daardoor staartletters zoals g en p af.
    iconGlyph := ""
    if caption != "" {
        firstChar := SubStr(caption, 1, 1)
        codePoint := Ord(firstChar)
        if codePoint >= 0xE000 && codePoint <= 0xF8FF {
            iconGlyph := firstChar
            caption := Trim(SubStr(caption, 2))
        }
    }

    ; Gebruik een echte Button die zichzelf bij iedere repaint tekent.
    button := MainGui.AddButton(
        "x" x " y" y " w" w " h" h " Center -Tabstop",
        caption
    )
    button._iconGlyph := iconGlyph
    button.SetFont("s11 " (primary ? "bold " : "") "c" textColor, "Segoe UI")
    button.SetColor(
        "0x" background,
        "0x" textColor,
        0,
        "0x" background,
        10  ; vaste visuele hoekstraal in pixels
    )
    button._surfaceColor := _BtnColor.RgbToBgr(
        "0x" (surfaceColor != "" ? surfaceColor : C["Card"])
    )
    button.OnEvent("Click", callback)
    FlatButtons.Push(button)
    AddPageControl(pageKey, button)
    return button
}

RedrawFlatButtons(*) {
    global FlatButtons

    ; De custom-draw-notificatie wordt niet altijd automatisch verstuurd
    ; wanneer een control voor het eerst zichtbaar wordt of via -Hidden
    ; terugkomt. Forceer WM_PAINT direct voor iedere zichtbare flat button.
    for _, button in FlatButtons {
        if DllCall("IsWindowVisible", "ptr", button.Hwnd, "int") {
            ; Custom-draw buttons moeten boven Picture-kaarten blijven.
            DllCall(
                "SetWindowPos",
                "ptr", button.Hwnd,
                "ptr", 0,  ; HWND_TOP
                "int", 0, "int", 0, "int", 0, "int", 0,
                "uint", 0x1 | 0x2 | 0x10  ; NOSIZE | NOMOVE | NOACTIVATE
            )
            DllCall(
                "RedrawWindow",
                "ptr", button.Hwnd,
                "ptr", 0,
                "ptr", 0,
                "uint", 0x1 | 0x4 | 0x100 | 0x400
            )
        }
    }
}

AddCallActionSelector(pageKey, initialValue, callback) {
    options := [
        Map("Value", 0, "X", 260, "Y", 292, "Width", 260, "Caption", "Niets doen"),
        Map("Value", 1, "X", 606, "Y", 292, "Width", 320, "Caption", "Bellen na bevestiging"),
        Map("Value", 2, "X", 260, "Y", 320, "Width", 260, "Caption", "Direct bellen")
    ]
    if HasConfiguredSmsCallActions() {
        options.Push(
            Map("Value", 3, "X", 606, "Y", 320, "Width", 320, "Caption", "Bellen of sms kiezen")
        )
    }
    return CallActionChoiceGroup(pageKey, options, NormalizeCallAction(initialValue), callback)
}

class CallActionChoiceGroup {
    __New(pageKey, options, initialValue, callback) {
        global MainGui, C

        this._value := initialValue
        this.Callback := callback
        this.Choices := []
        this.UnselectedBitmap := CreateRadioChoiceBitmap(false, C["Primary"], C["Border"], C["Card"])
        this.SelectedBitmap := CreateRadioChoiceBitmap(true, C["Primary"], C["Border"], C["Card"])

        for _, option in options {
            picture := MainGui.AddPicture(
                "x" option["X"] " y" option["Y"] " w20 h20",
                "HBITMAP:*" this.UnselectedBitmap
            )
            AddPageControl(pageKey, picture)

            label := MainGui.AddText(
                "x" (option["X"] + 28) " y" option["Y"]
                " w" (option["Width"] - 28) " h22 Background" C["Card"],
                option["Caption"]
            )
            label.SetFont("s10 c" C["Text"], "Segoe UI")
            AddPageControl(pageKey, label)

            clickHandler := ObjBindMethod(this, "HandleClick", option["Value"])
            picture.OnEvent("Click", clickHandler)
            label.OnEvent("Click", clickHandler)
            this.Choices.Push(Map("Value", option["Value"], "Picture", picture))
        }

        this.Render()
    }

    Value {
        get => this._value
        set {
            this._value := value
            this.Render()
            return value
        }
    }

    HandleClick(value, *) {
        this.Value := value
        if IsObject(this.Callback)
            this.Callback.Call(value)
    }

    Render() {
        for _, choice in this.Choices {
            bitmap := choice["Value"] = this._value ? this.SelectedBitmap : this.UnselectedBitmap
            choice["Picture"].Value := "HBITMAP:*" bitmap
            try choice["Picture"].Redraw()
        }
    }
}

CreateRadioChoiceBitmap(isSelected, primaryColor, borderColor, surfaceColor) {
    pBitmap := UiCreateBitmap(20, 20, &graphics)
    DllCall("gdiplus\GdipGraphicsClear", "ptr", graphics, "uint", UiArgb(surfaceColor))

    outerBrush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", UiArgb(isSelected ? primaryColor : borderColor), "ptr*", &outerBrush)
    DllCall("gdiplus\GdipFillEllipse", "ptr", graphics, "ptr", outerBrush, "float", 1.0, "float", 1.0, "float", 18.0, "float", 18.0)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", outerBrush)

    innerBrush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", UiArgb(surfaceColor), "ptr*", &innerBrush)
    DllCall("gdiplus\GdipFillEllipse", "ptr", graphics, "ptr", innerBrush, "float", 3.0, "float", 3.0, "float", 14.0, "float", 14.0)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", innerBrush)

    if isSelected {
        dotBrush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "uint", UiArgb(primaryColor), "ptr*", &dotBrush)
        DllCall("gdiplus\GdipFillEllipse", "ptr", graphics, "ptr", dotBrush, "float", 6.0, "float", 6.0, "float", 8.0, "float", 8.0)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", dotBrush)
    }

    return UiFinishBitmap(pBitmap, graphics)
}

AddToggle(pageKey, x, y, caption, initialValue, callback) {
    return ToggleSwitch(pageKey, x, y, caption, initialValue, callback)
}

class ToggleSwitch {
    __New(pageKey, x, y, caption, initialValue, callback) {
        global MainGui, C

        this._value := !!initialValue
        this.Callback := callback
        this.OffBitmap := CreateToggleBitmap(false, C["Primary"], C["Border"], C["Card"])
        this.OnBitmap := CreateToggleBitmap(true, C["Primary"], C["Border"], C["Card"])

        ; Track en knop worden samen als één antialiased GDI+-beeld getekend.
        this.Track := MainGui.AddPicture(
            "x" x " y" y " w50 h24",
            "HBITMAP:*" (this._value ? this.OnBitmap : this.OffBitmap)
        )
        AddPageControl(pageKey, this.Track)

        this.Label := MainGui.AddText(
            "x" (x + 62) " y" (y + 1) " w150 h22 Background" C["Card"],
            caption
        )
        this.Label.SetFont("s10 c" C["Text"], "Segoe UI")
        AddPageControl(pageKey, this.Label)

        clickHandler := ObjBindMethod(this, "HandleClick")
        this.Track.OnEvent("Click", clickHandler)
        this.Label.OnEvent("Click", clickHandler)
    }

    Value {
        get => this._value
        set {
            this._value := !!value
            this.Render()
            return value
        }
    }

    HandleClick(*) {
        this.Value := !this.Value
        if IsObject(this.Callback)
            this.Callback(this)
    }

    Render() {
        this.Track.Value := "HBITMAP:*" (this._value ? this.OnBitmap : this.OffBitmap)
        try this.Track.Redraw()
    }
}

CreateCardBitmap(width, height, radius, fillColor, surfaceColor, shadowColor) {
    bitmapWidth := width + 3
    bitmapHeight := height + 4
    pBitmap := UiCreateBitmap(bitmapWidth, bitmapHeight, &graphics)

    DllCall("gdiplus\GdipGraphicsClear", "ptr", graphics, "uint", UiArgb(surfaceColor))

    ; Schaduw eerst, daarna de card zelf. De schaduw blijft binnen de bitmap.
    UiFillRoundedRect(graphics, 2.0, 3.0, width, height, radius, UiArgb(shadowColor, 150))
    UiFillRoundedRect(graphics, 0.5, 0.5, width - 1.0, height - 1.0, radius, UiArgb(fillColor))

    return UiFinishBitmap(pBitmap, graphics)
}

CreateToggleBitmap(isOn, primaryColor, offColor, surfaceColor) {
    pBitmap := UiCreateBitmap(50, 24, &graphics)
    DllCall("gdiplus\GdipGraphicsClear", "ptr", graphics, "uint", UiArgb(surfaceColor))

    trackColor := isOn ? primaryColor : offColor
    UiFillRoundedRect(graphics, 0.5, 0.5, 49.0, 23.0, 11.5, UiArgb(trackColor))

    knobX := isOn ? 28.5 : 3.5
    knobBrush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", 0xFFFFFFFF, "ptr*", &knobBrush)
    DllCall(
        "gdiplus\GdipFillEllipse",
        "ptr", graphics,
        "ptr", knobBrush,
        "float", knobX,
        "float", 3.5,
        "float", 17.0,
        "float", 17.0
    )
    DllCall("gdiplus\GdipDeleteBrush", "ptr", knobBrush)

    return UiFinishBitmap(pBitmap, graphics)
}

UiCreateBitmap(width, height, &graphics) {
    static PixelFormat32bppPARGB := 0x26200A
    static gdipToken := 0

    ; Houd deze initialisatie lokaal: een functie uit een #Include wordt door
    ; #Warn hier anders als een onbelegde functievariabele geïnterpreteerd.
    if !gdipToken {
        startupInput := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
        NumPut("uint", 1, startupInput, 0)
        startupStatus := DllCall(
            "gdiplus\GdiplusStartup",
            "ptr*", &gdipToken,
            "ptr", startupInput,
            "ptr", 0,
            "uint"
        )
        if startupStatus != 0
            throw Error("GDI+ kon niet worden gestart (status " startupStatus ").")
    }

    pBitmap := 0
    graphics := 0

    status := DllCall(
        "gdiplus\GdipCreateBitmapFromScan0",
        "int", width,
        "int", height,
        "int", 0,
        "int", PixelFormat32bppPARGB,
        "ptr", 0,
        "ptr*", &pBitmap
    )
    if status != 0
        throw Error("GDI+-bitmap kon niet worden gemaakt (status " status ").")

    DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", pBitmap, "ptr*", &graphics)
    DllCall("gdiplus\GdipSetSmoothingMode", "ptr", graphics, "int", 4)
    DllCall("gdiplus\GdipSetPixelOffsetMode", "ptr", graphics, "int", 4)
    return pBitmap
}

UiFillRoundedRect(graphics, x, y, width, height, radius, argb) {
    diameter := Min(radius * 2.0, width, height)
    right := x + width
    bottom := y + height
    path := 0
    brush := 0

    DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr*", &path)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x, "float", y,
        "float", diameter, "float", diameter, "float", 180.0, "float", 90.0)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", right - diameter, "float", y,
        "float", diameter, "float", diameter, "float", 270.0, "float", 90.0)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", right - diameter, "float", bottom - diameter,
        "float", diameter, "float", diameter, "float", 0.0, "float", 90.0)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x, "float", bottom - diameter,
        "float", diameter, "float", diameter, "float", 90.0, "float", 90.0)
    DllCall("gdiplus\GdipClosePathFigure", "ptr", path)

    DllCall("gdiplus\GdipCreateSolidFill", "uint", argb, "ptr*", &brush)
    DllCall("gdiplus\GdipFillPath", "ptr", graphics, "ptr", brush, "ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", brush)
    DllCall("gdiplus\GdipDeletePath", "ptr", path)
}

UiFinishBitmap(pBitmap, graphics) {
    global UiBitmaps

    hBitmap := 0
    DllCall(
        "gdiplus\GdipCreateHBITMAPFromBitmap",
        "ptr", pBitmap,
        "ptr*", &hBitmap,
        "uint", 0x00FFFFFF
    )
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", graphics)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)

    if !hBitmap
        throw Error("GDI+-bitmap kon niet naar een Windows-bitmap worden omgezet.")

    UiBitmaps.Push(hBitmap)
    return hBitmap
}

UiArgb(color, alpha := 255) {
    rgb := Type(color) = "String"
        ? Number(SubStr(color, 1, 2) = "0x" ? color : "0x" color)
        : color
    return ((alpha & 0xFF) << 24) | (rgb & 0xFFFFFF)
}

AddRoundedEdit(pageKey, x, y, w, h, value := "", verticalInset := 8) {
    return AddRoundedEditGroup(pageKey, x, y, w, h, value, false, verticalInset)["Edit"]
}

AddRoundedEditGroup(pageKey, x, y, w, h, value := "", multiline := false, verticalInset := 8) {
    global MainGui, C
    shell := MainGui.AddText("x" x " y" y " w" w " h" h " Background" C["Border"], "")
    AddRound(shell, 12)
    AddPageControl(pageKey, shell)
    surface := MainGui.AddText("x" (x+2) " y" (y+2) " w" (w-4) " h" (h-4) " BackgroundFFFFFF", "")
    AddRound(surface, 10)
    AddPageControl(pageKey, surface)
    opts := "x" (x+4) " y" (y+verticalInset) " w" (w-8) " h" (h-verticalInset*2) " -E0x200 BackgroundFFFFFF"
    if multiline
        opts .= " Multi VScroll WantTab"
    edit := MainGui.AddEdit(opts, value)
    AddPageControl(pageKey, edit)
    return Map("Shell", shell, "Surface", surface, "Edit", edit)
}

AddPageControl(pageKey, ctrl) {
    global Pages
    Pages[pageKey].Push(ctrl)
}

; Markeert het huidige einde van Pages[pageKey] als startpunt van een reeks
; besturingselementen die tijdens degraded mode verborgen moeten blijven
; (zie MarkDegradedGateEnd()). Werkt op een heel bereik in plaats van los
; per control, zodat een pagina met tientallen besturingselementen in één
; keer gedekt is en er nooit één per ongeluk vergeten wordt.
MarkDegradedGateStart(pageKey) {
    global Pages, DegradedGateRangeStart
    DegradedGateRangeStart[pageKey] := Pages[pageKey].Length
}

; Markeert alle besturingselementen die sinds de laatste
; MarkDegradedGateStart(pageKey) aan Pages[pageKey] zijn toegevoegd als
; "verberg zolang niet alle opslag geladen is" (StorageAllReady=false).
; ShowPage() respecteert dit, onafhankelijk van paginawissels.
MarkDegradedGateEnd(pageKey) {
    global Pages, DegradedGateRangeStart

    startIndex := DegradedGateRangeStart.Has(pageKey) ? DegradedGateRangeStart[pageKey] : 0
    loop Pages[pageKey].Length - startIndex {
        ctrl := Pages[pageKey][startIndex + A_Index]
        ctrl._degradedGate := "hide-while-degraded"
    }
}

; Omgekeerd: ctrl is normaal verborgen en verschijnt uitsluitend zolang
; StorageAllReady nog false is. Voor de degraded-mode-banner, zie
; AddDegradedBanner().
ShowOnlyWhileDegraded(ctrl) {
    ctrl._degradedGate := "show-only-while-degraded"
    return ctrl
}

; Blijvende (niet-vanzelf-verdwijnende) melding dat opslag nog niet
; volledig is geladen — het tegenovergestelde van ShowNotification()/D-025,
; die na een paar seconden vanzelf verdwijnt en dus niet geschikt is voor
; een status die minuten kan duren. Neemt de ruimte in die de eerste, nu
; verborgen kaart/inhoud van de pagina normaal gesproken inneemt, zodat er
; geen bestaande x/y-posities hoeven te verschuiven. Geen geanimeerd
; spinner-icoon: Segoe MDL2-glyphs in dezelfde tekstregel als gewone tekst
; renderen niet correct zonder de custom-draw-aanpak van AddFlatButton(),
; en een los animatietimertje voor uitsluitend dit venstertje weegt niet op
; tegen het effect.
AddDegradedBanner(pageKey, y, message) {
    global MainGui

    surface := MainGui.AddText("x236 y" y " w736 h38 BackgroundFDF0DE", "")
    ShowOnlyWhileDegraded(surface)
    AddPageControl(pageKey, surface)

    accent := MainGui.AddText("x236 y" y " w4 h38 BackgroundF08200", "")
    ShowOnlyWhileDegraded(accent)
    AddPageControl(pageKey, accent)

    body := MainGui.AddText("x252 y" (y + 11) " w704 h20 BackgroundFDF0DE", message)
    body.SetFont("s10 c5C3600", "Segoe UI")
    ShowOnlyWhileDegraded(body)
    AddPageControl(pageKey, body)
}

SetCueText(editCtrl, text) {
    ; EM_SETCUEBANNER = 0x1501
    SendMessage(0x1501, 0, StrPtr(text), editCtrl)
}

; =============================================================================
; STARTUP-ONBOARDINGTIPS
; =============================================================================
; Zie docs/TODO.md ("Startup onboarding tips based on zero-usage counters").
; Eén tip per sessie, willekeurig gekozen uit alle op dat moment geschikte
; kandidaten uit TipDefinitions (globals-blok bovenaan), getoond in de gele
; hint-balk op Overzicht (TipBannerSurface/-Accent/-Link/-CloseButton,
; opgebouwd in BuildMainGui()). "Geschikt" = de conditie is waar, én de
; laatste keer tonen (indien van toepassing) is lang genoeg geleden: minstens
; TipMinIntervalDays dagen zolang de tip nog geen TipRepeatCapCount keer is
; getoond, daarna minstens TipLongTermIntervalMonths maanden — een tip stopt
; dus niet definitief na de cap, maar gaat over op een veel lagere frequentie.

TipConditionPhone() {
    return Telemetry_GetPhoneActions() = 0
}

; Was eerst Hotstrings.Length = 0 (de personal-hotstringlijst zelf, zie het
; oorspronkelijke docs/TODO.md-item). In de praktijk seedt
; DefaultPersonalHotstrings()/AddMissingDefaultHotstrings() elke gebruiker al
; bij de schema-upgrade met LocalConfig["DefaultHotstrings"], dus
; Hotstrings.Length is vrijwel nooit 0 en de tip verscheen daardoor nooit
; (bevestigd door de projecteigenaar). De "Lange hotstrings"-actieteller
; (net als de telefoon-/sms-tellers) meet daadwerkelijk gebruik in plaats van
; alleen lijstlengte, en is dus wél 0 zolang iemand nog geen meerregelige
; hotstring heeft laten uitvoeren.
TipConditionHotstrings() {
    return Telemetry_GetLongHotstringActions() = 0
}

TipConditionSms() {
    return Telemetry_GetSmsActions() = 0
}

TipConditionAlways() {
    return true
}

; Spiegelt Telemetry_ReadCounter()/Telemetry_WriteCounter() (Telemetry.ahk),
; maar leest/schrijft een eigen "[Tips]"-sectie in ConfigFile in plaats van
; "[Usage]" in TelemetryConfigFile: dit is lokale UX-state, losstaand van
; telemetrie-toestemming, zoals docs/TODO.md expliciet vraagt.
Tips_ReadShownCount(key) {
    global ConfigFile

    try
        return Max(0, Integer(IniRead(ConfigFile, "Tips", key "ShownCount", 0)))
    catch
        return 0
}

Tips_WriteShownCount(key, value) {
    global ConfigFile
    try IniWrite(value, ConfigFile, "Tips", key "ShownCount")
}

Tips_ReadLastShownAt(key) {
    global ConfigFile

    try
        return IniRead(ConfigFile, "Tips", key "LastShownAt", "")
    catch
        return ""
}

Tips_WriteLastShownAt(key, value) {
    global ConfigFile
    try IniWrite(value, ConfigFile, "Tips", key "LastShownAt")
}

; Vult de balk met de tekst/Help-link van de gekozen tip. Alleen tellertips
; hebben een HelpHandler (een <a href="help">-link in Text); de
; systeemvak-tip (TrayClose) heeft platte tekst zonder link.
UpdateTipBannerContent(tipDef) {
    global TipBannerLink

    TipBannerLink.Text := tipDef["Text"]
    if tipDef["HelpHandler"] != ""
        TipBannerLink.OnEvent("Click", tipDef["HelpHandler"])
}

; Wordt aangeroepen ná BuildMainGui() (snelle start) én vanuit
; StorageRetry_OnAllReady() (degraded-mode-herstelpad, DocBot.ahk StorageRetry_*
; hierboven): tellers/Hotstrings zijn pas betrouwbaar zodra StorageAllReady.
; Loot precies één keer per sessie (TipBannerSelected-guard) — een latere
; aanroep vanuit het herstelpad na een al-succesvolle snelle start doet dus
; niets.
EvaluateStartupTip() {
    global StorageAllReady, TipBannerSelected, TipDefinitions
    global TipRepeatCapCount, TipMinIntervalDays, TipLongTermIntervalMonths
    global TipBannerActive, CurrentTipKey

    if !StorageAllReady || TipBannerSelected
        return
    TipBannerSelected := true

    ; Twee mogelijke minimumtussenpozen: het korte interval zolang een tip
    ; nog geen TipRepeatCapCount keer is getoond, en het veel langere
    ; interval erna — een tip stopt dus nooit definitief, hij gaat na de cap
    ; alleen over op een veel lagere frequentie.
    shortCutoff := DateAdd(A_Now, -TipMinIntervalDays, "Days")
    longCutoff := DateAdd(A_Now, -TipLongTermIntervalMonths, "Months")
    eligible := []
    for tipDef in TipDefinitions {
        if !tipDef["Condition"].Call()
            continue
        shownCount := Tips_ReadShownCount(tipDef["Key"])
        cutoff := (shownCount >= TipRepeatCapCount) ? longCutoff : shortCutoff
        lastShown := Tips_ReadLastShownAt(tipDef["Key"])
        if lastShown != "" && lastShown >= cutoff
            continue
        eligible.Push(tipDef)
    }
    if !eligible.Length
        return

    chosen := eligible[Random(1, eligible.Length)]
    CurrentTipKey := chosen["Key"]
    UpdateTipBannerContent(chosen)
    Tips_WriteShownCount(chosen["Key"], Tips_ReadShownCount(chosen["Key"]) + 1)
    Tips_WriteLastShownAt(chosen["Key"], FormatTime(, "yyyyMMddHHmmss"))
    TipBannerActive := true
    ApplyTipBannerVisibility()
}

; Bij terugkeer naar Overzicht (ShowPage()): is de conditie van de nu
; getoonde tip inmiddels vervallen (bijv. eerste hotstring net opgeslagen),
; verberg de balk dan. Er wordt bewust geen nieuwe tip geloot zolang de
; sessie loopt — één keuze per sessie, zie EvaluateStartupTip().
ReevaluateTipBannerCondition() {
    global TipBannerActive, CurrentTipKey, TipDefinitions

    if !TipBannerActive
        return
    for tipDef in TipDefinitions {
        if tipDef["Key"] = CurrentTipKey {
            if !tipDef["Condition"].Call()
                TipBannerActive := false
            return
        }
    }
}

; Enige plek die de Hidden-status van de tip-balk zet: losstaand van de
; generieke Pages[]-gating in ShowPage(), omdat de balk binnen een sessie
; zichtbaar moet blijven totdat de voorwaarde vervalt of de gebruiker sluit —
; niet gewoon "aan zodra Overzicht getoond wordt".
ApplyTipBannerVisibility() {
    global TipBannerActive, CurrentPage
    global TipBannerSurface, TipBannerAccent, TipBannerLink, TipBannerCloseButton

    wantVisible := TipBannerActive && CurrentPage = "overzicht"
    for ctrl in [TipBannerSurface, TipBannerAccent, TipBannerLink, TipBannerCloseButton]
        ctrl.Opt(wantVisible ? "-Hidden" : "+Hidden")
}

; Klikhandler van het sluitkruisje. ShownCount/LastShownAt zijn al
; geschreven op het moment van tonen (EvaluateStartupTip()); vroegtijdig
; sluiten verandert daar niets aan, dus telt gewoon mee in de bestaande
; interval-regels (kort tot de cap, daarna het lange interval) na een
; herstart.
DismissTipBanner(*) {
    global TipBannerActive
    TipBannerActive := false
    ApplyTipBannerVisibility()
}

ShowPage(pageKey, *) {
    global Pages, CurrentPage, NavButtons, NavBars, C, StorageAllReady

    CurrentPage := pageKey

    for key, controls in Pages {
        pageVisible := key = pageKey
        for _, ctrl in controls {
            gate := HasProp(ctrl, "_degradedGate") ? ctrl._degradedGate : ""
            show := pageVisible
            if gate = "hide-while-degraded" && !StorageAllReady
                show := false
            else if gate = "show-only-while-degraded" && StorageAllReady
                show := false
            ctrl.Opt(show ? "-Hidden" : "+Hidden")
        }
    }

    ApplyHotReplacementEditorState()

    for key, nav in NavButtons {
        active := key = pageKey
        bgColor := active ? C["PrimarySoft"] : C["Sidebar"]
        fgColor := active ? C["Primary"] : "344054"

        nav["BaseBg"].Opt("Background" C["Sidebar"])
        nav["ActiveBg"].Opt(active ? "-Hidden Background" C["PrimarySoft"] : "+Hidden Background" C["PrimarySoft"])
        nav["Icon"].Opt("Background" bgColor)
        nav["Text"].Opt("Background" bgColor)

        nav["Icon"].SetFont(active ? "s14 bold c" fgColor : "s14 norm c" fgColor, "Segoe MDL2 Assets")
        nav["Text"].SetFont(active ? "s10 bold c" fgColor : "s10 norm c" fgColor, "Segoe UI")
        NavBars[key].Opt(active ? "-Hidden" : "+Hidden")
    }

    if pageKey = "tekstvervanging"
        RefreshHotstringList()
    else if pageKey = "overzicht" {
        UpdateRegisterButtonState()
        ReevaluateTipBannerCondition()
    } else if pageKey = "help"
        RefreshHelpAccordion()

    ; De onboardingtip-balk staat buiten Pages[]/de gating hierboven (zie
    ; ApplyTipBannerVisibility()): elke paginawissel moet 'm alsnog tonen of
    ; verbergen op basis van de huidige pagina + TipBannerActive.
    ApplyTipBannerVisibility()

    ; Herstel regions nadat cards/toggles via -Hidden zichtbaar zijn geworden.
    ; Daarna volgt een volledige redraw en de custom-draw-cyclus van buttons.
    ApplyRoundedControls(true)
    RedrawMainGui()
    RedrawFlatButtons()
}

; RDW_INVALIDATE(0x1) | RDW_ERASE(0x4) | RDW_ALLCHILDREN(0x80) | RDW_UPDATENOW(0x100)
; — forceert een volledige, directe herschildering van het venster en al
; zijn child-controls, ongeacht wat Windows zelf als "vuil" beschouwde.
RedrawMainGui() {
    global MainGui
    DllCall("RedrawWindow", "ptr", MainGui.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x1 | 0x4 | 0x80 | 0x100)
}

; =============================================================================
; OVER-PAGINA
; =============================================================================

; Inleiding overgenomen uit het About-blok van DocBot-LegacyV2.ahk (de
; monolithische voorganger); de versiegeschiedenis bevat uitsluitend
; AppVersion-waarden die daadwerkelijk in de git-geschiedenis van dit
; bestand hebben gestaan. Zie CLAUDE.md voor de procesregel: een versie
; komt hier pas bij zodra AppVersion in de code naar die waarde wordt
; opgehoogd.
BuildAboutText() {
    global AppVersion

    text := "DocBot versie " AppVersion "`r`n`r`n"
    text .= "DocBot is productiviteitssoftware voor medewerkers in een beheerde bedrijfsomgeving. De software vervangt ingestelde afkortingen (hotstrings), herkent en normaliseert telefoonnummers op het Windows-klembord en kan deze doorgeven aan een geconfigureerde interne telefoniedienst of invullen in een geconfigureerde SMS-webapplicatie. DocBot verzendt zelf geen SMS-berichten.`r`n`r`n"
    text .= "DocBot is ontstaan vanuit behoeften in een ziekenhuisomgeving en wordt daar ook toegepast. De software verricht geen medische analyse van patiëntgegevens, trekt geen klinische conclusies en geeft geen diagnose-, behandel-, doserings- of monitoringsadvies.`r`n`r`n"
    text .= "Het is een projectje dat in vrije tijd wordt onderhouden en waar het Meander geen support op levert. Suggesties zijn welkom.`r`n`r`n"
    text .= "DocBot is het resultaat van een langlopende en zeer inspirerende samenwerking vanuit de drive om te innoveren tussen Steven Giesbers, Seyit Seme en onderstaande.`r`n`r`n"
    text .= "Nico Feenstra`r`n`r`n"
    text .= "Versiegeschiedenis`r`n"
    text .= "-------------------------------`r`n"
    text .= LoadReadmeChangelog()
    return text
}

LoadReadmeChangelog() {
    global AppVersion

    readmePath := A_ScriptDir "\README.md"
    if A_IsCompiled {
        readmePath := A_Temp "\DocBot-README-" AppVersion ".md"
        ; De bron moet letterlijk worden genoemd zodat Ahk2Exe README.md als
        ; resource in de executable opneemt.
        FileInstall "README.md", readmePath, true
    }

    try {
        readmeText := FileRead(readmePath, "UTF-8")
        readmeText := LTrim(readmeText, Chr(0xFEFF))
    } catch as error {
        return "De versiegeschiedenis kon niet worden geladen.`r`n`r`n" error.Message
    }

    if !RegExMatch(
        readmeText,
        "smi)^Changelog\R-+\R(.*)$",
        &match
    )
        return "De sectie Changelog ontbreekt in README.md."

    return MarkdownChangelogToPlainText(match[1])
}

MarkdownChangelogToPlainText(markdown) {
    result := ""

    Loop Parse, markdown, "`n", "`r" {
        line := A_LoopField

        if RegExMatch(line, "^#{3,6}\s+(.+)$", &heading)
            line := heading[1]
        else if SubStr(line, 1, 2) = "- "
            line := "• " SubStr(line, 3)

        line := StrReplace(line, "**", "")
        line := StrReplace(line, "``", "")

        result .= (result = "" ? "" : "`r`n") line
    }

    return RTrim(result)
}

; =============================================================================
; MELDINGEN (eigen notificatievenster i.p.v. TrayTip)
; =============================================================================

; Borderless, always-on-top venstertje rechtsonder boven de taakbalk, buiten
; Windows' eigen notificatiesysteem om — dat systeem wordt op zakelijk
; beheerde machines vaak via group policy beperkt (Focus Assist, per-app
; notificatietoestemming), waarbij TrayTip() stilzwijgend niets toont.
; Hergebruikt hetzelfde venster/dezelfde timer bij opeenvolgende meldingen
; i.p.v. te stapelen. Show("NA") toont het venster zonder de foreground-
; focus over te nemen van waar de gebruiker op dat moment in werkt.
ShowNotification(message, durationMs := 3000, kind := "info") {
    global NotificationGui, C

    if !IsObject(NotificationGui)
        BuildNotificationGui()

    accentColor := (kind = "error") ? C["Danger"] : (kind = "warning") ? "F08200" : C["Primary"]
    NotificationGui["Bar"].Opt("Background" accentColor)

    ; Begrenzing tegen een onbegrensd lang bericht (bijv. een opsomming van
    ; hotstring-fouten) dat anders buiten het vaste tekstvak zou vallen —
    ; dezelfde afkap-klasse bug als eerder bij RegistrationHelperText, nu
    ; voorkomen i.p.v. opnieuw geïntroduceerd in een nieuwe component.
    maxLength := 320
    if StrLen(message) > maxLength
        message := SubStr(message, 1, maxLength - 1) "…"

    NotificationGui["Text"].Value := message
    PositionNotificationAboveTray()
    NotificationGui["Window"].Show("NA")   ; NA = tonen zonder de foreground-focus te stelen
    SetTimer HideNotification, -durationMs
}

BuildNotificationGui() {
    global NotificationGui, C

    win := Gui("+AlwaysOnTop -Caption +ToolWindow")
    win.BackColor := C["Card"]
    win.MarginX := 0
    win.MarginY := 0

    bar := win.AddText("x0 y0 w6 h110 Background" C["Primary"], "")
    text := win.AddText("x20 y16 w320 h78 Background" C["Card"], "")
    text.SetFont("s10 c" C["Text"], "Segoe UI")

    win.OnEvent("Close", (*) => win.Hide())

    NotificationGui := Map("Window", win, "Bar", bar, "Text", text)
}

PositionNotificationAboveTray() {
    global NotificationGui

    NotificationGui["Window"].GetPos(, , &w, &h)
    if !w {
        w := 360
        h := 110
    }

    rect := Buffer(16)
    DllCall("SystemParametersInfoW", "UInt", 0x0030, "UInt", 0, "Ptr", rect, "UInt", 0)  ; SPI_GETWORKAREA
    rightWork := NumGet(rect, 8, "Int")
    bottomWork := NumGet(rect, 12, "Int")

    margin := 12
    x := rightWork - w - margin
    y := bottomWork - h - margin

    NotificationGui["Window"].Move(x, y, w, h)
}

HideNotification() {
    global NotificationGui
    if IsObject(NotificationGui)
        NotificationGui["Window"].Hide()
}

; =============================================================================
; TELEFONIE
; =============================================================================

RefreshRegistrationTexts() {
    global State, RegisteredNumberText, RegistrationNumberText, RegistrationStatusText, RegistrationHelperText, C

    hasNumber := Trim(State["IPT"]["UserTel"]) != ""
    hasUpdateTel := Trim(State["IPT"]["UpdateTel"]) != ""

    RegisteredNumberText.Value := hasNumber ? State["IPT"]["UserTel"] : "Geen"
    RegisteredNumberText.SetFont(hasNumber ? "s28 bold c" C["Text"] : "s24 bold c" C["Muted"], "Segoe UI")

    RegistrationStatusText.Value := hasNumber ? "● Gekoppeld" : "● Niet gekoppeld"
    RegistrationStatusText.SetFont(hasNumber ? "s9 bold c" C["Success"] : "s9 bold c" C["Danger"], "Segoe UI")

    RegistrationHelperText.Value := hasNumber
        ? "Dit nummer is momenteel gekoppeld aan de sessie."
        : (hasUpdateTel
            ? "Bel het koppelnummer hiernaast om dit toestel te registreren."
            : "Klik op Verversen om een koppelnummer aan te vragen.")

    RegistrationNumberText.Value := hasUpdateTel ? State["IPT"]["UpdateTel"] : "Geen"
    RegistrationNumberText.Move(694, 132, 246, 38)
    RegistrationNumberText.SetFont(hasUpdateTel ? "s22 bold c" C["Text"] : "s24 bold c" C["Muted"], "Segoe UI")
}

RefreshSidebarStatuses() {
    global State, SidebarPhoneDot, SidebarPhoneText, SidebarTextDot, SidebarTextText, C, StorageAllReady

    if !StorageAllReady {
        ; Beide indicatoren lezen State-velden (CallAction/TextReplacement)
        ; die pas betrouwbaar zijn zodra alle opslag is geladen. Telefonie-
        ; koppeling zelf werkt intussen gewoon door (zie de registratiekaart
        ; op de Overzicht-pagina); dit stipje gaat specifiek over of DocBot
        ; al weet wát er met een herkend nummer moet gebeuren.
        SidebarPhoneDot.SetFont("s8 cF08200", "Segoe UI")
        SidebarPhoneText.Value := "Laden…"
        SidebarTextDot.SetFont("s8 cF08200", "Segoe UI")
        SidebarTextText.Value := "Laden…"
        return
    }

    if State["CallAction"] = 0 {
        SidebarPhoneDot.SetFont("s8 c" C["Danger"], "Segoe UI")
        SidebarPhoneText.Value := "Inactief"
    } else if Trim(State["IPT"]["UserTel"]) = "" {
        SidebarPhoneDot.SetFont("s8 c" C["Danger"], "Segoe UI")
        SidebarPhoneText.Value := "Niet gekoppeld"
    } else {
        SidebarPhoneDot.SetFont("s8 c" C["Success"], "Segoe UI")
        SidebarPhoneText.Value := "Actief"
    }

    if State["TextReplacement"] {
        SidebarTextDot.SetFont("s8 c" C["Success"], "Segoe UI")
        SidebarTextText.Value := "Actief"
    } else {
        SidebarTextDot.SetFont("s8 c" C["Danger"], "Segoe UI")
        SidebarTextText.Value := "Inactief"
    }
}

RefreshRegistrationStatus(*) {
    if IPT_RegisterDue()
        IPT_register()

    RefreshRegistrationTexts()
    RefreshSidebarStatuses()
    BuildTrayMenu()
}

GetTelemetryStatus() {
    global State

    return Map(
        "PhoneEnabled", Trim(State["IPT"]["UserTel"]) != "",
        "HotstringsEnabled", State["TextReplacement"]
    )
}

RefreshUsageStatistics() {
    global OverviewPhoneActionsText, OverviewLongHotstringActionsText, OverviewSmsActionsText

    if IsObject(OverviewPhoneActionsText)
        OverviewPhoneActionsText.Value := Telemetry_GetPhoneActions()
    if IsObject(OverviewLongHotstringActionsText)
        OverviewLongHotstringActionsText.Value := Telemetry_GetLongHotstringActions()
    if IsObject(OverviewSmsActionsText)
        OverviewSmsActionsText.Value := Telemetry_GetSmsActions()
}

CallActionChanged(value, *) {
    global State

    State["CallAction"] := NormalizeCallAction(value)
    SaveAppSettings()
    RefreshSidebarStatuses()
    BuildTrayMenu()
}

SettingChanged(key, control, *) {
    global State
    State[key] := control.Value = 1

    if key = "TextReplacement"
        ReloadRuntimeHotstrings(true)

    SaveAppSettings()
    RefreshSidebarStatuses()
    BuildTrayMenu()
}

ShowPhoneDialog(*) {
    global MainGui, C, State

    dlg := Gui("+Owner" MainGui.Hwnd " -MaximizeBox -MinimizeBox", "DocBot - Nummer registreren")
    dlg.BackColor := C["Window"]
    dlg.SetFont("s10 c" C["Text"], "Segoe UI")

    title := dlg.AddText("x28 y24 w384 h30 Center Background" C["Window"], "Nummer registreren")
    title.SetFont("s18 bold c" C["Text"], "Segoe UI")

    info := dlg.AddText("x34 y60 w372 h38 Center Background" C["Window"], "Bel met de gewenste telefoon het onderstaande nummer. Daarna kun je de status verversen om te zien welk nummer is gekoppeld.")
    info.SetFont("s9 c" C["Muted"], "Segoe UI")

    currentLabel := dlg.AddText("x40 y116 w180 h18 Background" C["Window"], "Huidig geregistreerd nummer")
    currentLabel.SetFont("s9 c" C["Muted"], "Segoe UI")

    currentValue := dlg.AddText("x40 y136 w360 h28 Background" C["Window"], Trim(State["IPT"]["UserTel"]) != "" ? State["IPT"]["UserTel"] : "Geen nummer geregistreerd")
    currentValue.SetFont("s16 bold c" C["Text"], "Segoe UI")

    dialShell := dlg.AddText("x40 y188 w360 h54 Background" C["Border"], "")
    dialValue := dlg.AddText("x50 y201 w340 h28 Center BackgroundFFFFFF", State["IPT"]["UpdateTel"])
    dialValue.SetFont("s18 bold c" C["Text"], "Segoe UI")

    closeBtn := dlg.AddText("x40 y266 w112 h38 Center 0x100 0x200 Background" C["Button"], "Sluiten")
    closeBtn.SetFont("s10 c" C["Text"], "Segoe UI")

    callBtn := dlg.AddText("x164 y266 w112 h38 Center 0x100 0x200 Background" C["Button"], "☎  Bel nu")
    callBtn.SetFont("s10 c" C["Text"], "Segoe UI")

    refreshBtn := dlg.AddText("x288 y266 w112 h38 Center 0x100 0x200 Background" C["Primary"], Chr(0xE72C) "  Verversen")
    refreshBtn.SetFont("s10 bold cFFFFFF", "Segoe UI")

    closeBtn.OnEvent("Click", (*) => dlg.Destroy())
    callBtn.OnEvent("Click", CallRegistrationNumber)
    refreshBtn.OnEvent("Click", (*) => (RefreshRegistrationStatus(), dlg.Destroy()))

    dlg.OnEvent("Escape", (*) => dlg.Destroy())
    dlg.Show("w440 h332 Center")

    RoundControl(dialShell, 12)
    RoundControl(dialValue, 10)
    RoundControl(closeBtn, 19)
    RoundControl(callBtn, 19)
    RoundControl(refreshBtn, 19)
}

CallRegistrationNumber(*) {
    global State
    IPT_callNumber(State["IPT"]["UpdateTel"], true)   ; true = koppelgesprek, guard overslaan
}

CallRegisteredNumber(*) {
    global State

    if Trim(State["IPT"]["UserTel"]) = "" {
        MsgBox("Er is nog geen nummer geregistreerd.", "DocBot", "Icon!")
        return
    }

    IPT_callNumber(State["IPT"]["UserTel"])
}

; =============================================================================
; SNELKIESNUMMERS
; =============================================================================

RefreshSpeedDialList(*) {
    global SpeedDialEntries, SpeedDialLV
    if !IsObject(SpeedDialLV)
        return
    SpeedDialLV.Delete()
    for _, entry in SpeedDialEntries
        SpeedDialLV.Add("", entry["actief"] ? "Ja" : "Nee", entry["naam"], entry["nummer"])
}

FillSpeedDialFormFromSelection(*) {
    global SpeedDialEntries, SpeedDialLV, SpeedDialEnabledCheck, SpeedDialNameEdit, SpeedDialNumberEdit
    row := SpeedDialLV.GetNext()
    if row = 0 || row > SpeedDialEntries.Length
        return
    SpeedDialEnabledCheck.Value := SpeedDialEntries[row]["actief"] ? 1 : 0
    SpeedDialNameEdit.Value := SpeedDialEntries[row]["naam"]
    SpeedDialNumberEdit.Value := SpeedDialEntries[row]["nummer"]
}

NewSpeedDial(*) {
    global SpeedDialLV, SpeedDialEnabledCheck, SpeedDialNameEdit, SpeedDialNumberEdit
    SpeedDialLV.Modify(0, "-Select")
    SpeedDialEnabledCheck.Value := 1
    SpeedDialNameEdit.Value := ""
    SpeedDialNumberEdit.Value := ""
    SpeedDialNameEdit.Focus()
}

CallSelectedSpeedDial(*) {
    global SpeedDialEntries, SpeedDialLV
    row := SpeedDialLV.GetNext()
    if row = 0 {
        MsgBox("Selecteer eerst een snelkiesnummer.", "DocBot", "Iconi")
        return
    }
    entry := SpeedDialEntries[row]
    if !entry["actief"] {
        MsgBox("Dit snelkiesnummer is inactief. Zet het eerst op Actief om te bellen.", "DocBot", "Iconi")
        return
    }
    IPT_callNumber(entry["nummer"])
}

EditSelectedSpeedDial(*) {
    global SpeedDialLV, SpeedDialNameEdit
    if SpeedDialLV.GetNext() = 0 {
        MsgBox("Selecteer eerst een snelkiesnummer.", "DocBot", "Iconi")
        return
    }
    FillSpeedDialFormFromSelection()
    SpeedDialNameEdit.Focus()
}

SaveSpeedDialFromForm(*) {
    global SpeedDialEntries, SpeedDialLV, SpeedDialEnabledCheck, SpeedDialNameEdit, SpeedDialNumberEdit
    global DefaultSpeedDialFile
    naam := Trim(SpeedDialNameEdit.Value)
    if naam = "" {
        MsgBox("Vul eerst een naam in.", "DocBot", "Icon!")
        return
    }
    nummer := NormalizePhoneNumber(SpeedDialNumberEdit.Value)
    if nummer = "" {
        MsgBox("Vul een geldig intern nummer (4 cijfers) of een geldig Nederlands telefoonnummer in.", "DocBot", "Icon!")
        return
    }
    entry := CreateSpeedDialEntry(naam, nummer, SpeedDialEnabledCheck.Value = 1)
    row := SpeedDialLV.GetNext()
    if row > 0 && row <= SpeedDialEntries.Length {
        SpeedDialEntries[row] := entry
        savedRow := row
    } else {
        SpeedDialEntries.Push(entry)
        savedRow := SpeedDialEntries.Length
    }
    RefreshSpeedDialList()
    SpeedDialLV.Modify(savedRow, "Select Focus Vis")
    FillSpeedDialFormFromSelection()
    SaveSpeedDialToJson(DefaultSpeedDialFile, false)
    BuildTrayMenu()
}

DeleteSelectedSpeedDial(*) {
    global SpeedDialEntries, SpeedDialLV, DefaultSpeedDialFile
    row := SpeedDialLV.GetNext()
    if row = 0 {
        MsgBox("Selecteer eerst een snelkiesnummer.", "DocBot", "Iconi")
        return
    }
    naam := SpeedDialEntries[row]["naam"]
    if MsgBox("Snelkiesnummer '" naam "' verwijderen?", "DocBot", "YesNo Icon!") = "Yes" {
        SpeedDialEntries.RemoveAt(row)
        RefreshSpeedDialList()
        NewSpeedDial()
        SaveSpeedDialToJson(DefaultSpeedDialFile, false)
        BuildTrayMenu()
    }
}

MoveSpeedDialUp(*) {
    global SpeedDialEntries, SpeedDialLV, DefaultSpeedDialFile
    row := SpeedDialLV.GetNext()
    if row = 0 {
        MsgBox("Selecteer eerst een snelkiesnummer.", "DocBot", "Iconi")
        return
    }
    if row = 1
        return
    entry := SpeedDialEntries[row]
    SpeedDialEntries.RemoveAt(row)
    SpeedDialEntries.InsertAt(row - 1, entry)
    RefreshSpeedDialList()
    SpeedDialLV.Modify(row - 1, "Select Focus Vis")
    FillSpeedDialFormFromSelection()
    SaveSpeedDialToJson(DefaultSpeedDialFile, false)
    BuildTrayMenu()
}

MoveSpeedDialDown(*) {
    global SpeedDialEntries, SpeedDialLV, DefaultSpeedDialFile
    row := SpeedDialLV.GetNext()
    if row = 0 {
        MsgBox("Selecteer eerst een snelkiesnummer.", "DocBot", "Iconi")
        return
    }
    if row = SpeedDialEntries.Length
        return
    entry := SpeedDialEntries[row]
    SpeedDialEntries.RemoveAt(row)
    SpeedDialEntries.InsertAt(row + 1, entry)
    RefreshSpeedDialList()
    SpeedDialLV.Modify(row + 1, "Select Focus Vis")
    FillSpeedDialFormFromSelection()
    SaveSpeedDialToJson(DefaultSpeedDialFile, false)
    BuildTrayMenu()
}

; =============================================================================
; IP-TELEFONIE (registratie, polling en bellen)
; =============================================================================

IPT_callNumber(telNummer := "", isRegistrationCall := false) {
    global IPTConfig, IPTDialRequest, State

    if telNummer = "" || telNummer <= 0
        return

    if !isRegistrationCall && Trim(State["IPT"]["UserTel"]) = "" {
        ShowNotification("Er is nog geen toestel gekoppeld. Registreer eerst een nummer via de Overzicht-pagina.", 4000, "warning")
        DebugLog("✕", IPTConfig["DialPage"] . " geweigerd", "Geen gekoppeld toestel (UserTel leeg), nummer " . telNummer . " niet gebeld.")
        return
    }

    if StrLen(telNummer) > 4
        telNummer := "0" . telNummer

    url := IPTConfig["URL"] . IPTConfig["DialPage"]
        . "?" . IPTConfig["DialPageNumberParam"] . "=" . telNummer
        . "&" . IPTConfig["DialPageSidParam"] . "=0." . A_TickCount . A_TimeIdle

    DebugLog("→", IPTConfig["DialPage"], url)

    IPTDialRequest := ComObject(IPTConfig["ComObject"])
    IPTDialRequest.Open("POST", url, true)
    IPTDialRequest.SetRequestHeader("Accept-Language", "nl-NL")
    IPTDialRequest.onreadystatechange := IPT_DialResponse
    IPTDialRequest.Send("")
    Telemetry_RecordPhoneAction()
    RefreshUsageStatistics()
}

; Simpele ERROR-check, net als bij IPT_RegisterResponse — DialNumber geeft
; geen event-XML terug.
IPT_DialResponse() {
    global IPTConfig, IPTDialRequest

    if IPTDialRequest.readyState != 4
        return

    DebugLog("←", IPTConfig["DialPage"] . " status " . IPTDialRequest.status, IPTDialRequest.ResponseText)

    if InStr(IPTDialRequest.ResponseText, "ERROR")
        ShowNotification("Er is een fout opgetreden bij het bellen.", 4000, "error")
}

; startCooldown := false bij de automatische aanvraag tijdens opstarten,
; zodat de Verversen-knop niet meteen na het starten al op een aftellende
; cooldown staat terwijl de gebruiker nog niets heeft geklikt. Een
; handmatige klik (via RefreshRegistrationStatus()) roept dit zonder
; argument aan en start de cooldown dus wel, zoals voorheen.
IPT_register(startCooldown := true) {
    global IPTConfig, State, IPTRegisterRequest

    url := IPTConfig["URL"] . IPTConfig["AllocatePage"] . "?sid=0." . A_TickCount . A_TimeIdle

    DebugLog("→", IPTConfig["AllocatePage"], url)

    IPTRegisterRequest := ComObject(IPTConfig["ComObject"])
    IPTRegisterRequest.Open("POST", url, true)
    IPTRegisterRequest.SetRequestHeader("Accept-Language", "nl-NL")
    IPTRegisterRequest.onreadystatechange := IPT_RegisterResponse
    IPTRegisterRequest.Send("")

    ; Herstart de poll-keten als die gestopt was (bijv. na een eerdere
    ; StopEventLoop). Alleen opnieuw starten als hij niet al loopt, anders
    ; ontstaan er dubbele ketens.
    pollChainWasStopped := State["IPT"]["NeedUpdate"] <= -1

    State["IPT"]["NeedUpdate"] := 1

    if startCooldown {
        State["IPT"]["LastRegisterTick"] := A_TickCount
        UpdateRegisterButtonState()
    }

    if pollChainWasStopped
        IPT_poller()
}

; Simpele ERROR-check, geen XML-parsing — de server geeft hier geen
; event-XML terug (dat gebeurt uitsluitend via IPT_poller/GetEvent).
IPT_RegisterResponse() {
    global IPTConfig, IPTRegisterRequest

    if IPTRegisterRequest.readyState != 4
        return

    DebugLog("←", IPTConfig["AllocatePage"] . " status " . IPTRegisterRequest.status, IPTRegisterRequest.ResponseText)

    if InStr(IPTRegisterRequest.ResponseText, "ERROR")
        ShowNotification("Aanmelden bij de telefonieserver is mislukt.", 4000, "error")
}

; Voorkomt dat de Verversen-knop bij elke klik een nieuw koppelnummer aanvraagt.
IPT_RegisterDue() {
    global IPTConfig, State
    return (A_TickCount - State["IPT"]["LastRegisterTick"]) >= IPTConfig["RegisterMinIntervalMs"]
}

; Zet de Verversen-knop op inactief met een aftellende tekst zolang de
; laatste IPT_register()-aanvraag korter dan RegisterMinIntervalMs geleden is.
UpdateRegisterButtonState() {
    global IPTConfig, State, RegistrationRefreshButton, CurrentPage

    if !IsObject(RegistrationRefreshButton)
        return

    ; De timer loopt op iedere pagina door. Gebruik de logische paginastatus
    ; in plaats van IsWindowVisible: custom-drawn controls kunnen tijdens een
    ; repaint tijdelijk als zichtbaar rapporteren.
    if CurrentPage != "overzicht"
        return

    remainingMs := IPTConfig["RegisterMinIntervalMs"] - (A_TickCount - State["IPT"]["LastRegisterTick"])

    if remainingMs > 0 {
        RegistrationRefreshButton.Enabled := false
        RegistrationRefreshButton.Text := "Verversen: " Ceil(remainingMs / 1000) " sec"
    } else {
        RegistrationRefreshButton.Enabled := true
        RegistrationRefreshButton.Text := "Verversen"
    }
}

IPT_poller() {
    global IPTConfig, State, IPTPollRequest

    UpdateRegisterButtonState()

    if State["IPT"]["NeedUpdate"] <= -1 {
        State["IPT"]["NeedUpdate"] := -1
        return
    }

    url := IPTConfig["URL"] . IPTConfig["EventPage"] . "?sid=0." . A_TickCount . A_TimeIdle

    DebugLog("→", IPTConfig["EventPage"], url)

    IPTPollRequest := ComObject(IPTConfig["ComObject"])
    IPTPollRequest.Open("POST", url, true)
    IPTPollRequest.SetRequestHeader("Accept-Language", "nl-NL")

    if IPTConfig["ComObject"] = "WinHttp.WinHttpRequest.5.1"
        IPTPollRequest.OnResponseDataAvailable := IPT_PollResponse
    else
        IPTPollRequest.onreadystatechange := IPT_PollResponse

    IPTPollRequest.Send("")
}

IPT_PollResponse() {
    global IPTConfig, State, IPTPollRequest

    if IPTPollRequest.readyState != 4  ; Nog niet klaar, callback vuurt opnieuw.
        return

    if IPTPollRequest.status != 200 && IPTPollRequest.status != 201 {
        DebugLog("←", IPTConfig["EventPage"] . " FOUT status " . IPTPollRequest.status, "")
    } else {
        DebugLog("←", IPTConfig["EventPage"] . " status " . IPTPollRequest.status, IPTPollRequest.ResponseText)

        ; Onbekende/afwijkende XML-structuur mag de poller nooit laten
        ; crashen — bij een fout loggen we de ruwe respons en gaan we door.
        try {
            xml := IPTPollRequest.responseXML
            if IsObject(xml) {
                root := xml.documentElement
                if IsObject(root) {
                    eventName := root.getAttribute("Name")

                    switch eventName {
                        case "NULL":
                            ; niets te doen, keep-alive
                        case "StopEventLoop":
                            State["IPT"]["NeedUpdate"] := -1
                        case "SetUpperText":
                            msgNode := root.selectSingleNode("Message")
                            if IsObject(msgNode)
                                ParsePhoneNumbersFromMessage(msgNode.text)
                        case "ShowAlert":
                            msgNode := root.selectSingleNode("Text")
                            if IsObject(msgNode)
                                ShowNotification(msgNode.text, 4000, "info")
                    }
                }
            }
        } catch as err {
            DebugLog("←", IPTConfig["EventPage"] . " PARSE-FOUT: " . err.Message, IPTPollRequest.ResponseText)
        }

        RefreshRegistrationTexts()
        RefreshSidebarStatuses()
        BuildTrayMenu()
    }

    ; Poll-keten voortzetten: pas ná afronding van deze aanvraag een nieuwe
    ; plannen (eenmalige timer, geen vaste interval), zodat er nooit meer
    ; dan één het event-endpoint-aanvraag tegelijk onderweg is.
    if State["IPT"]["NeedUpdate"] > -1
        SetTimer IPT_poller, -10
}

; Bevat de bestaande regex-logica, nu toegepast op de geëxtraheerde
; berichttekst van een SetUpperText-event i.p.v. de ruwe XML-respons.
ParsePhoneNumbersFromMessage(messageText) {
    global State

    if RegExMatch(messageText, "[^0-9]([0-9]{4})[^0-9]", &info) > 0
        State["IPT"]["UserTel"] := info[1]

    if RegExMatch(messageText, "[^0-9]([0-9]{7})[^0-9]", &info) > 0
        State["IPT"]["UpdateTel"] := info[1]
    else
        State["IPT"]["UpdateTel"] := ""   ; geen geldig koppelnummer meer -> verbergen
}

; =============================================================================
; SIGNAL.TXT (gecoördineerd afsluiten/herladen)
; =============================================================================

; Periodiek gepolld bestand naast de executable, op de centrale
; netwerklocatie waar deze vandaan draait — de eenvoudigste vorm van
; cross-machine-signalering zonder aparte achtergrondservice of
; netwerk-brede messaging-infrastructuur. Elke regel:
; <doel>:<commando>:<optioneel bericht>, waarbij <doel> ALL, een
; computernaam of een gebruikersnaam is (hoofdletterongevoelig, geen
; typeaanduiding nodig — beide worden los herkend). Eerste toepasselijke
; regel wint; verdere regels worden niet meer bekeken.
CheckSignalFile(timeoutSec := 10) {
    global SignalConfig, MainGui

    dir := ""
    SplitPath(A_ScriptFullPath, , &dir)
    if (dir != "" && SubStr(dir, StrLen(dir), 1) != "\")
        dir .= "\"

    signalPath := dir . SignalConfig["FileName"]

    if !FileExist(signalPath)
        return

    try
        contents := FileRead(signalPath, "UTF-8")
    catch
        return

    if contents = ""
        return

    Loop Parse, contents, "`n", "`r" {
        line := Trim(A_LoopField)
        if line = ""
            continue

        parts := StrSplit(line, ":", , 3)
        if parts.Length < 2
            continue

        target := Trim(parts[1])
        command := StrLower(Trim(parts[2]))
        customMessage := parts.Length >= 3 ? Trim(parts[3]) : ""

        isTargeted := (StrLower(target) = "all")
            || (StrLower(target) = StrLower(A_ComputerName))
            || (StrLower(target) = StrLower(A_UserName))

        if !isTargeted
            continue

        if command = "shutdown" {
            message := customMessage != "" ? customMessage
                : "DocBot wordt op afstand afgesloten."
            MsgBox(message, "DocBot - Afsluiten", "Icon! Owner" MainGui.Hwnd " T" . timeoutSec)
            ExitApp()
        } else if command = "update" {
            restartWindowState := GetCurrentMainWindowState()
            message := customMessage != "" ? customMessage
                : "DocBot wordt bijgewerkt en daarna automatisch opnieuw gestart."
            MsgBox(message, "DocBot - Update", "Iconi Owner" MainGui.Hwnd " T" . timeoutSec)

            if !ScheduleUpdateRestart(restartWindowState) {
                MsgBox(
                    "De automatische herstart kon niet in de Windows Taakplanner worden voorbereid."
                    . "`nDocBot sluit wel af; start het programma na de update handmatig opnieuw.",
                    "DocBot - Update",
                    "Icon! Owner" MainGui.Hwnd " T5"
                )
            }
            ExitApp()
        } else if command = "reload" {
            message := customMessage != "" ? customMessage : "DocBot wordt automatisch herladen."
            ShowNotification(message, 3000, "info")
            Sleep(1000)   ; geef de melding even tijd om zichtbaar te worden vóór het herladen
            Reload()
        }

        ; Een regel voor deze client met een onbekend commando mag een geldige
        ; opdracht verderop in signal.txt niet blokkeren.
        continue
    }
}

HasCommandLineArgument(expectedArgument) {
    for argument in A_Args {
        if argument = expectedArgument
            return true
    }
    return false
}

GetRequestedStartupWindowState() {
    prefix := "--docbot-window-state="

    for argument in A_Args {
        if InStr(argument, prefix) = 1 {
            requestedState := SubStr(argument, StrLen(prefix) + 1)
            if requestedState = "active"
                || requestedState = "background"
                || requestedState = "minimized"
                return requestedState
        }
    }

    return "active"
}

GetCurrentMainWindowState() {
    global MainGui

    if !IsObject(MainGui)
        return "active"

    hwnd := MainGui.Hwnd

    if !DllCall("IsWindow", "ptr", hwnd, "int")
        return "active"

    ; Zowel verborgen in het systeemvak als geminimaliseerd in de taakbalk
    ; moet na de update geminimaliseerd terugkomen.
    if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
        || DllCall("IsIconic", "ptr", hwnd, "int")
        return "minimized"

    return DllCall("GetForegroundWindow", "ptr") = hwnd
        ? "active"
        : "background"
}

ScheduleUpdateRestart(windowState) {
    static TASK_TRIGGER_TIME := 1
    static TASK_ACTION_EXEC := 0
    static TASK_CREATE_OR_UPDATE := 6
    static TASK_LOGON_INTERACTIVE_TOKEN := 3
    static TASK_RUNLEVEL_LUA := 0

    try {
        taskService := ComObject("Schedule.Service")
        taskService.Connect()
        rootFolder := taskService.GetFolder("\")
        taskDefinition := taskService.NewTask(0)

        taskDefinition.RegistrationInfo.Description :=
            "Start DocBot opnieuw nadat de centrale executable is bijgewerkt."

        taskDefinition.Principal.LogonType := TASK_LOGON_INTERACTIVE_TOKEN
        taskDefinition.Principal.RunLevel := TASK_RUNLEVEL_LUA

        settings := taskDefinition.Settings
        settings.Enabled := true
        settings.StartWhenAvailable := true
        settings.DisallowStartIfOnBatteries := false
        settings.StopIfGoingOnBatteries := false
        settings.ExecutionTimeLimit := "PT5M"
        settings.MultipleInstances := 2  ; TASK_INSTANCES_IGNORE_NEW

        trigger := taskDefinition.Triggers.Create(TASK_TRIGGER_TIME)
        trigger.Id := "DocBotUpdateRestartTrigger"
        trigger.StartBoundary := FormatTime(
            DateAdd(A_Now, 30, "Seconds"),
            "yyyy-MM-ddTHH:mm:ss"
        )
        trigger.Enabled := true

        restartExecutable := A_IsCompiled
            ? GetUniversalNetworkPath(A_ScriptFullPath)
            : A_AhkPath
        restartScript := GetUniversalNetworkPath(A_ScriptFullPath)
        restartWorkingDir := GetUniversalNetworkPath(A_ScriptDir)
        quote := Chr(34)
        windowStateArgument := "--docbot-window-state=" windowState
        restartArguments := A_IsCompiled
            ? "--docbot-update-restart " windowStateArgument
            : quote restartScript quote " --docbot-update-restart " windowStateArgument

        action := taskDefinition.Actions.Create(TASK_ACTION_EXEC)
        action.Path := restartExecutable
        action.Arguments := restartArguments
        action.WorkingDirectory := restartWorkingDir

        taskName := GetUpdateRestartTaskName()
        rootFolder.RegisterTaskDefinition(
            taskName,
            taskDefinition,
            TASK_CREATE_OR_UPDATE,
            "",
            "",
            TASK_LOGON_INTERACTIVE_TOKEN
        )

        DebugLog(
            "✓",
            "Update-helper",
            "Taakplanner-taak geregistreerd: " taskName
                . " -> " restartExecutable
        )
        return true
    } catch as schedulerError {
        DebugLog("✕", "Update-helper", schedulerError.Message)
        return false
    }
}

CleanupScheduledRestartTask() {
    taskName := GetUpdateRestartTaskName()

    try {
        taskService := ComObject("Schedule.Service")
        taskService.Connect()
        rootFolder := taskService.GetFolder("\")
        rootFolder.DeleteTask(taskName, 0)
        DebugLog("✓", "Update-helper", "Taakplanner-taak verwijderd: " taskName)
    } catch as cleanupError {
        ; Een reeds verwijderde of door beleid afgeschermde taak is na een
        ; geslaagde herstart niet fataal, maar blijft wel zichtbaar in het log.
        DebugLog("!", "Update-helper", cleanupError.Message)
    }
}

GetUpdateRestartTaskName() {
    appName := RegExReplace(A_ScriptName, "\.[^.]+$", "")
    ; Een whitelist voorkomt zowel ongeldige taaknaamtekens als lastige
    ; quote-escaping in een AHK-regexliteral.
    safeIdentity := RegExReplace(
        A_UserName "-" appName,
        "[^A-Za-z0-9._-]",
        "_"
    )
    return "DocBot Update Restart - " safeIdentity
}

GetUniversalNetworkPath(path) {
    static UNIVERSAL_NAME_INFO_LEVEL := 1
    static ERROR_MORE_DATA := 234

    if !RegExMatch(path, "i)^[A-Z]:\\")
        return path

    bufferSize := 0
    status := DllCall(
        "mpr\WNetGetUniversalNameW",
        "str", path,
        "uint", UNIVERSAL_NAME_INFO_LEVEL,
        "ptr", 0,
        "uint*", &bufferSize,
        "uint"
    )

    if status != ERROR_MORE_DATA || bufferSize = 0
        return path

    buffer := Buffer(bufferSize, 0)
    status := DllCall(
        "mpr\WNetGetUniversalNameW",
        "str", path,
        "uint", UNIVERSAL_NAME_INFO_LEVEL,
        "ptr", buffer.Ptr,
        "uint*", &bufferSize,
        "uint"
    )

    if status != 0
        return path

    universalNamePointer := NumGet(buffer, 0, "ptr")
    return universalNamePointer
        ? StrGet(universalNamePointer, "UTF-16")
        : path
}

; =============================================================================
; DIAGNOSTIEK, LOGGING & PROBLEEMRAPPORTAGE
; =============================================================================

; De standaardlog is bewust beperkt en centraal geschoond. Na expliciete
; toestemming kopieert DebugLog() dezelfde gebeurtenis met de oorspronkelijke
; waarden naar het tijdelijke uitgebreide log. Aanvullende SMS/UIA- en
; hotstringdetails worden uitsluitend rechtstreeks via ExtendedDebugLog()
; geschreven zolang die toegestane sessie actief is.
DebugLog(richting, label, tekst := "") {
    global DebugLogBuffer, DebugFlushPending, DebugLogEdit, DebugAutoScroll
    global ProblemReportSession

    veiligeLabel := SanitizeLogText(label)
    veiligeTekst := SanitizeStandardLogText(veiligeLabel, tekst)
    regel := BuildDebugLogLine(richting, veiligeLabel, veiligeTekst)
    DebugLogBuffer .= regel

    if !DebugFlushPending {
        DebugFlushPending := true
        SetTimer FlushDebugLog, -2000
    }

    AppendDebugWindowLine(regel)

    if ProblemReportSession["ExtendedActive"] {
        ; De telemetrie-webhook blijft ook tijdens een toegestane sessie een
        ; lokaal geheim. Voor alle overige bestaande diagnosegebeurtenissen
        ; bewaart het uitgebreide log juist de oorspronkelijke waarden.
        extendedText := StrLower(label "") = "telemetrie"
            ? SanitizeLogText(tekst)
            : tekst
        ExtendedDebugLog(richting, label, extendedText)
    }
}

ExtendedDebugLog(richting, label, tekst := "") {
    global ProblemReportSession, ExtendedDebugLogBuffer
    global ExtendedDebugFlushPending

    if !ProblemReportSession["ExtendedActive"]
        return

    regel := BuildDebugLogLine(
        richting,
        label "",
        tekst ""
    )
    ExtendedDebugLogBuffer .= regel

    if !ExtendedDebugFlushPending {
        ExtendedDebugFlushPending := true
        SetTimer FlushExtendedDebugLog, -500
    }

    AppendDebugWindowLine("[UITGEBREID] " regel)
}

BuildDebugLogLine(richting, label, tekst := "") {
    tijd := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "." A_MSec
    regel := tijd " " richting " " label
    if Trim(tekst) != ""
        regel .= "`r`n" tekst
    return regel "`r`n───`r`n"
}

SanitizeStandardLogText(label, tekst) {
    veilig := SanitizeLogText(tekst)
    labelLower := StrLower(label)

    if veilig != ""
        && (
            InStr(labelLower, " status ")
            || InStr(labelLower, "response")
            || InStr(labelLower, "parse-fout")
        )
        return "<responsinhoud niet opgenomen in standaardlog>"

    return veilig
}

SanitizeLogText(value) {
    veilig := value ""

    veilig := RegExReplace(
        veilig,
        "\\\\[^\s\r\n]+",
        "<netwerkpad afgeschermd>"
    )
    veilig := RegExReplace(
        veilig,
        "i)\b[A-Z]:\\[^\r\n]+",
        "<lokaal pad afgeschermd>"
    )

    userProfile := EnvGet("USERPROFILE")
    if userProfile != ""
        veilig := StrReplace(veilig, userProfile, "%USERPROFILE%")
    if A_UserName != ""
        veilig := StrReplace(veilig, A_UserName, "<gebruiker>")
    if A_ComputerName != ""
        veilig := StrReplace(veilig, A_ComputerName, "<computer>")

    veilig := RegExReplace(veilig, "i)https?://\S+", "<url afgeschermd>")
    veilig := RegExReplace(
        veilig,
        "\b(?:(?:\+31|0031|0)6\d{8}|0\d{9})\b",
        "<telefoonnummer afgeschermd>"
    )
    veilig := RegExReplace(veilig, "\b\d{4}\b", "<intern nummer afgeschermd>")

    trimmed := Trim(veilig)
    if (
        (SubStr(trimmed, 1, 1) = "<" && InStr(trimmed, ">"))
        || (SubStr(trimmed, 1, 1) = "{" && SubStr(trimmed, -1) = "}")
    )
        veilig := "<gestructureerde inhoud niet opgenomen>"

    if StrLen(veilig) > 2000
        veilig := SubStr(veilig, 1, 2000) "… <afgekapt>"

    return veilig
}

AppendDebugWindowLine(regel) {
    global DebugLogEdit, DebugAutoScroll

    if !IsObject(DebugLogEdit)
        return

    DebugLogEdit.Value .= regel
    if StrLen(DebugLogEdit.Value) > 500000 {
        volledigeTekst := DebugLogEdit.Value
        DebugLogEdit.Value := SubStr(
            volledigeTekst,
            StrLen(volledigeTekst) // 2
        )
    }
    if DebugAutoScroll
        SendMessage(0x115, 7, 0, DebugLogEdit)
}

GetStandardDebugLogPath() {
    return EnvGet("LocalAppData") "\DocBot\debug.log"
}

InitializeDiagnosticLogging() {
    static formatMarker := "DocBot standaardlog v2"
    logPath := GetStandardDebugLogPath()
    SplitPath(logPath, , &logDir)

    try {
        if !DirExist(logDir)
            DirCreate(logDir)

        isCurrentFormat := false
        if FileExist(logPath) {
            try {
                logFile := FileOpen(logPath, "r", "UTF-8")
                header := logFile.Read(256)
                logFile.Close()
                isCurrentFormat := InStr(header, formatMarker) > 0
            } catch {
                isCurrentFormat := false
            }
        }

        ; Oudere DocBot-versies konden volledige URL's en ruwe responsen
        ; vastleggen. Neem zo'n historisch bestand nooit stilzwijgend op in
        ; een nieuw probleemrapport.
        if !isCurrentFormat {
            if FileExist(logPath)
                FileDelete(logPath)
            if FileExist(logPath ".oud")
                FileDelete(logPath ".oud")
        }

        if !FileExist(logPath) {
            FileAppend(
                formatMarker "`r`n"
                "Alle regels vanaf dit punt zijn centraal geschoond.`r`n"
                "───`r`n",
                logPath,
                "UTF-8"
            )
        }
    } catch {
        ; Diagnostiek mag de normale start van DocBot nooit blokkeren.
    }

    ; Opschonen mag nooit de rest van de opstart blokkeren en staat daarom
    ; los van het try-blok hierboven; RunDiagnosticsMaintenance() vangt
    ; fouten per onderdeel zelf af.
    RunDiagnosticsMaintenance()
    SetTimer(RunDiagnosticsMaintenance, 86400000)
}

; Draait bij opstart en daarna eenmaal per dag: schoont het standaardlog op
; naar bewaartermijn en ruimt vergeten tijdelijke probleemrapport- en
; uitgebreide-logbestanden op. Eén gedeelde timer in plaats van losse timers
; per onderdeel.
RunDiagnosticsMaintenance() {
    PruneExpiredDebugLogEntries()
    PruneAbandonedProblemReportDirs()
    PruneAbandonedExtendedLogFiles()
    PruneAbandonedUserStorageProbeDirs()
}

; Verwijdert individuele standaardlogregels ouder dan DebugLogRetentionDays,
; in zowel het actieve logbestand als het geroteerde .oud-bestand. Werkt per
; regel (op basis van de tijdstempel vooraan iedere regel), niet op
; bestandsniveau, zodat een actief bestand met zowel oude als recente regels
; correct wordt opgeschoond. Draait bij opstart en daarna eenmaal per dag,
; zodat een langdurig actieve sessie niet wacht op een herstart.
PruneExpiredDebugLogEntries() {
    logPath := GetStandardDebugLogPath()
    try PruneExpiredDebugLogFile(logPath, "actieve standaardlog")
    try PruneExpiredDebugLogFile(logPath ".oud", "geroteerd .oud-standaardlog")
}

; Classificeert één standaardlogregel/-chunk (de tekst tussen twee
; scheidingsregels) voor PruneExpiredDebugLogFile(). Puur op tekst
; gebaseerd, zonder bestands-I/O, zodat dit via --selftest te controleren
; is (zie tests/SelfTests.ahk). cutoffStamp is een "yyyyMMddHHmmss"-
; vergelijkbare tijdstempel, zoals geleverd door DateAdd(A_Now, ...).
;
; Sinds docs/DECISIONS.md D-062 valt inhoud die aan geen enkel bekend
; formaat voldoet (huidig of legacy) onder "onherkend-verlopen" en wordt
; dus onvoorwaardelijk verwijderd, in plaats van voor altijd bewaard: de
; formaatcontrole in InitializeDiagnosticLogging() leest bij opstart alleen
; de eerste 256 bytes van het bestand en ziet een niet-conform formaat
; verderop in het bestand dus niet.
ClassifyDebugLogChunk(chunk, cutoffStamp) {
    ; Trim() negeert standaard alleen spatie/tab, geen CR/LF: een chunk die
    ; uitsluitend uit regeleinden bestaat (de lege staart ná de laatste
    ; scheidingsregel) moet hier expliciet worden meegenomen, anders valt
    ; die ten onrechte door naar "onherkend-verlopen".
    if Trim(chunk, " `t`r`n") = ""
        return "leeg"  ; lege staart na de laatste scheidingsregel

    if RegExMatch(chunk, "^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})", &m) {
        entryStamp := m[1] m[2] m[3] m[4] m[5] m[6]
        return (entryStamp < cutoffStamp) ? "verlopen" : "geldig"
    }

    ; Regels van vóór de "v2"-opschoning (tot en met commit 5f72613,
    ; 2026-08-07) hadden geen datum, alleen "HH:mm:ss.mmm", en werden
    ; nooit URL-geschoond. Zo'n regel kan hier alleen staan als een
    ; oudere, niet-geschoonde build ooit naar hetzelfde bestand heeft
    ; geschreven nadat de v2-kopregel al aanwezig was. Zo'n regel is per
    ; definitie (ver) ouder dan de bewaartermijn: onvoorwaardelijk laten
    ; vervallen in plaats van voor altijd te bewaren.
    if RegExMatch(chunk, "^\d{2}:\d{2}:\d{2}\.\d{1,3} ")
        return "legacy-verlopen"

    return "onherkend-verlopen"
}

PruneExpiredDebugLogFile(path, label) {
    static delimiter := "───`r`n"
    static DebugLogRetentionDays := 7

    if !FileExist(path)
        return

    try {
        content := FileRead(path, "UTF-8")
    } catch {
        return
    }

    if Trim(content) = ""
        return

    delen := StrSplit(content, delimiter)
    if delen.Length <= 1
        return  ; alleen het kopblok (of niets herkenbaars): niets te knippen

    cutoff := DateAdd(A_Now, -DebugLogRetentionDays, "Days")
    nieuweInhoud := delen[1] delimiter  ; het kopblok blijft altijd staan
    verlopenAantal := 0
    onherkendAantal := 0

    loop delen.Length - 1 {
        chunk := delen[A_Index + 1]
        classificatie := ClassifyDebugLogChunk(chunk, cutoff)

        if (classificatie = "leeg")
            continue
        if (classificatie = "geldig") {
            nieuweInhoud .= chunk delimiter
            continue
        }
        if (classificatie = "onherkend-verlopen")
            onherkendAantal += 1
        else
            verlopenAantal += 1
    }

    verwijderdAantal := verlopenAantal + onherkendAantal
    if (verwijderdAantal = 0)
        return

    tempPath := path ".tmp"
    try {
        if FileExist(tempPath)
            FileDelete(tempPath)
        FileAppend(nieuweInhoud, tempPath, "UTF-8")
        FileMove(tempPath, path, true)
        samenvatting := verwijderdAantal " verlopen regel(s) verwijderd uit " label "."
        if (onherkendAantal > 0)
            samenvatting .= " Daarvan " onherkendAantal " met een formaat dat bij geen enkel bekend patroon past."
        DebugLog("i", "Standaardlog opschonen", samenvatting)
    } catch as writeError {
        if FileExist(tempPath)
            try FileDelete(tempPath)
        DebugLog(
            "!",
            "Standaardlog opschonen",
            "Wegschrijven van opgeschoond " label " mislukt: " writeError.Message
        )
    }
}

FlushDebugLog() {
    global DebugLogBuffer, DebugFlushPending

    if DebugLogBuffer = "" {
        DebugFlushPending := false
        return
    }

    logPath := GetStandardDebugLogPath()
    SplitPath(logPath, , &logDir)

    try {
        if !DirExist(logDir)
            DirCreate(logDir)

        if FileExist(logPath) && FileGetSize(logPath) > 2000000 {
            FileMove(logPath, logPath ".oud", true)
            FileAppend(
                "DocBot standaardlog v2`r`n"
                "Alle regels vanaf dit punt zijn centraal geschoond.`r`n"
                "───`r`n",
                logPath,
                "UTF-8"
            )
        }

        FileAppend(DebugLogBuffer, logPath, "UTF-8")
        DebugLogBuffer := ""
    } catch {
        ; Logging mag de hoofdfunctionaliteit nooit blokkeren.
    } finally {
        DebugFlushPending := false
    }
}

FlushExtendedDebugLog() {
    global ExtendedDebugLogBuffer, ExtendedDebugFlushPending
    global ProblemReportSession

    if ExtendedDebugLogBuffer = "" {
        ExtendedDebugFlushPending := false
        return
    }

    logPath := ProblemReportSession["ExtendedLogPath"]
    if logPath = "" {
        ExtendedDebugLogBuffer := ""
        ExtendedDebugFlushPending := false
        return
    }

    try FileAppend(ExtendedDebugLogBuffer, logPath, "UTF-8")
    catch {
        ; Ook uitgebreide logging mag DocBot niet laten vastlopen.
    } finally {
        ExtendedDebugLogBuffer := ""
        ExtendedDebugFlushPending := false
    }
}

; Live debugvenster — alleen bereikbaar via het systeemvakmenu als IsDevMode.
ShowDebugWindow(*) {
    global DebugWindow, DebugLogEdit, DebugAutoScroll

    if IsObject(DebugWindow) {
        DebugWindow.Show()
        return
    }

    DebugWindow := Gui("+Resize", "DocBot - Telefonie debug")
    DebugLogEdit := DebugWindow.AddEdit(
        "w700 h400 ReadOnly VScroll +Wrap",
        ""
    )
    DebugLogEdit.SetFont("s9", "Consolas")

    clearBtn := DebugWindow.AddButton("w100", "Wissen")
    clearBtn.OnEvent("Click", (*) => DebugLogEdit.Value := "")

    autoScrollCheck := DebugWindow.AddCheckbox(
        "x+10 y+0 Checked",
        "Automatisch meescrollen"
    )
    autoScrollCheck.OnEvent(
        "Click",
        (*) => DebugAutoScroll := autoScrollCheck.Value
    )

    DebugWindow.OnEvent(
        "Close",
        (*) => (DebugWindow := 0, DebugLogEdit := 0)
    )
    DebugWindow.Show()
}

ShowProblemReportWindow(*) {
    global ProblemReportGui

    if IsObject(ProblemReportGui) {
        try {
            if DllCall("IsWindow", "ptr", ProblemReportGui.Hwnd, "int") {
                ProblemReportGui.Show()
                WinActivate("ahk_id " ProblemReportGui.Hwnd)
                return
            }
        } catch {
        }
    }

    BuildProblemReportWindow()
}

BuildProblemReportWindow() {
    global MainGui, C, ProblemReportGui, ProblemReportDescriptionEdit
    global ProblemReportConsentCheck, ProblemReportSession

    CaptureProblemReportDescription()

    if IsObject(ProblemReportGui)
        try ProblemReportGui.Destroy()

    ProblemReportDescriptionEdit := 0
    ProblemReportConsentCheck := 0

    ProblemReportGui := Gui(
        "+Owner" MainGui.Hwnd " -MaximizeBox -MinimizeBox",
        "DocBot - Probleem melden"
    )
    ProblemReportGui.BackColor := C["Window"]
    ProblemReportGui.SetFont("s10 c" C["Text"], "Segoe UI")
    ProblemReportGui.MarginX := 0
    ProblemReportGui.MarginY := 0

    if ProblemReportSession["Phase"] = "start"
        BuildProblemReportStartState(ProblemReportGui)
    else
        BuildProblemReportProgressState(ProblemReportGui)

    ProblemReportGui.OnEvent("Close", HideProblemReportWindow)
    ProblemReportGui.OnEvent("Escape", HideProblemReportWindow)
    ProblemReportGui.Show("w680 h620 Center")
}

BuildProblemReportStartState(gui) {
    global C, ProblemReportDescriptionEdit, ProblemReportConsentCheck
    global ProblemReportSession

    title := gui.AddText(
        "x28 y22 w624 h38 Background" C["Window"],
        "Probleem melden"
    )
    title.SetFont("s22 bold c" C["Text"], "Segoe UI")

    intro := gui.AddText(
        "x28 y66 w624 h42 Background" C["Window"],
        "Loop je ergens tegenaan? Met dit scherm kun je een probleemrapport "
        "maken en opsturen."
    )
    intro.SetFont("s10 c" C["Text"], "Segoe UI")

    gui.AddText(
        "x28 y116 w624 h20 Background" C["Window"],
        "Korte beschrijving (optioneel)"
    )
    ProblemReportDescriptionEdit := gui.AddEdit(
        "x28 y140 w624 h92 Multi VScroll",
        ProblemReportSession["Description"]
    )
    SetCueText(
        ProblemReportDescriptionEdit,
        "Wat gaat er mis? Wanneer gebeurt het?"
    )

    directCard := gui.AddText(
        "x28 y250 w624 h82 BackgroundFFFFFF",
        ""
    )
    directTitle := gui.AddText(
        "x50 y262 w330 h22 BackgroundFFFFFF",
        "Probleem direct melden"
    )
    directTitle.SetFont("s11 bold c" C["Text"], "Segoe UI")
    directText := gui.AddText(
        "x50 y288 w360 h28 BackgroundFFFFFF",
        "Gebruik alleen de beperkte standaardlog die al beschikbaar is."
    )
    directText.SetFont("s9 c" C["Muted"], "Segoe UI")
    directButton := gui.AddButton(
        "x462 y272 w166 h38",
        "Direct melden"
    )
    directButton.OnEvent(
        "Click",
        FinalizeProblemReport.Bind(false)
    )

    extendedCard := gui.AddText(
        "x28 y348 w624 h210 Background" C["PrimarySoft"],
        ""
    )
    extendedTitle := gui.AddText(
        "x50 y360 w360 h22 Background" C["PrimarySoft"],
        "Probleem opnieuw reproduceren"
    )
    extendedTitle.SetFont("s11 bold c" C["Text"], "Segoe UI")
    extendedText := gui.AddText(
        "x50 y386 w570 h34 Background" C["PrimarySoft"],
        "Schakel tijdelijk uitgebreide logging in, voer het probleem opnieuw "
        "uit en rond daarna het rapport af."
    )
    extendedText.SetFont("s9 c" C["Text"], "Segoe UI")

    privacyTitle := gui.AddText(
        "x50 y426 w218 h22 Background" C["PrimarySoft"],
        "Privacy en Expliciete toestemming:"
    )
    privacyTitle.SetFont("s9 bold c" C["Danger"], "Segoe UI")
    privacyText := gui.AddText(
        "x268 y426 w352 h22 Background" C["PrimarySoft"],
        "Met toestemming logt DocBot tijdelijk ook"
    )
    privacyText.SetFont("s9 c" C["Text"], "Segoe UI")
    privacyTextContinuation := gui.AddText(
        "x50 y450 w570 h22 Background" C["PrimarySoft"],
        "volledige serverresponsen, telefoonnummers en gebruikte hotstringteksten."
    )
    privacyTextContinuation.SetFont("s9 c" C["Text"], "Segoe UI")

    ProblemReportConsentCheck := gui.AddCheckbox(
        "x50 y510 w400 h24 Background" C["PrimarySoft"],
        "Ik geef toestemming om gevoelige inhoud tijdelijk te loggen."
    )
    ProblemReportConsentCheck.OnEvent(
        "Click",
        UpdateProblemReportStartButton.Bind(gui)
    )

    startButton := gui.AddButton(
        "x462 y506 w166 h34 Disabled vProblemReportStartButton",
        "Logging starten"
    )
    startButton.OnEvent("Click", StartExtendedProblemLogging)

    cancelButton := gui.AddButton(
        "x508 y574 w120 h34",
        "Annuleren"
    )
    cancelButton.OnEvent("Click", HideProblemReportWindow)

    for card in [directCard, extendedCard]
        RoundControl(card, 12)
}

UpdateProblemReportStartButton(gui, *) {
    global ProblemReportConsentCheck

    try startButton := gui["ProblemReportStartButton"]
    catch
        return

    startButton.Enabled := IsObject(ProblemReportConsentCheck)
        && ProblemReportConsentCheck.Value = 1
}

BuildProblemReportProgressState(gui) {
    global C, ProblemReportDescriptionEdit, ProblemReportSession

    isActive := ProblemReportSession["ExtendedActive"]
    title := gui.AddText(
        "x28 y22 w624 h38 Background" C["Window"],
        "Probleem melden"
    )
    title.SetFont("s22 bold c" C["Text"], "Segoe UI")

    bannerColor := isActive ? "EAF7EC" : "FFF4E5"
    bannerTextColor := isActive ? C["Success"] : "9A6700"
    banner := gui.AddText(
        "x28 y76 w624 h94 Background" bannerColor,
        ""
    )
    statusTitle := gui.AddText(
        "x52 y92 w570 h24 Background" bannerColor,
        isActive
            ? "●  Uitgebreide logging is actief"
            : "●  Uitgebreide logging is gestopt"
    )
    statusTitle.SetFont(
        "s12 bold c" bannerTextColor,
        "Segoe UI"
    )
    statusText := gui.AddText(
        "x52 y122 w570 h36 Background" bannerColor,
        isActive
            ? "Voer nu het probleem opnieuw uit. Kom daarna terug naar dit "
                "scherm om het probleemrapport af te ronden."
            : "De verzamelde logging is bewaard. Je kunt het probleemrapport "
                "nu afronden."
    )
    statusText.SetFont("s9 c" C["Text"], "Segoe UI")

    helper := gui.AddText(
        "x28 y184 w624 h42 Background" C["Window"],
        isActive
            ? "Je mag dit venster tussendoor sluiten. Open daarna opnieuw "
                "“Probleem melden...” om verder te gaan."
            : "Controleer je beschrijving en klik op Probleemrapport afronden."
    )
    helper.SetFont("s9 c" C["Muted"], "Segoe UI")

    startedAt := ProblemReportSession["StartedAt"] != ""
        ? FormatTime(ProblemReportSession["StartedAt"], "HH:mm")
        : "-"
    sessionInfo := gui.AddText(
        "x28 y232 w624 h48 Center 0x200 BackgroundFFFFFF",
        "Logging gestart: " startedAt
        "    ·    Status: "
        . (isActive ? "Wacht op reproductie" : "Gereed om af te ronden")
    )
    sessionInfo.SetFont("s10 c" C["Text"], "Segoe UI")

    gui.AddText(
        "x28 y298 w624 h20 Background" C["Window"],
        "Korte beschrijving (optioneel)"
    )
    ProblemReportDescriptionEdit := gui.AddEdit(
        "x28 y322 w624 h92 Multi VScroll",
        ProblemReportSession["Description"]
    )

    stepsCard := gui.AddText(
        "x28 y432 w624 h84 BackgroundFFFFFF",
        ""
    )
    stepsTitle := gui.AddText(
        "x48 y444 w150 h22 BackgroundFFFFFF",
        "Wat nu?"
    )
    stepsTitle.SetFont("s11 bold c" C["Text"], "Segoe UI")
    stepsText := gui.AddText(
        "x48 y470 w570 h36 BackgroundFFFFFF",
        isActive
            ? "1. Laat het probleem opnieuw optreden.   2. Kom terug naar dit "
                "scherm.   3. Rond het probleemrapport af."
            : "De logging is gestopt. Rond het rapport af of begin opnieuw."
    )
    stepsText.SetFont("s9 c" C["Text"], "Segoe UI")

    leftButton := gui.AddButton(
        "x28 y548 w150 h38",
        isActive ? "Logging stoppen" : "Opnieuw beginnen"
    )
    if isActive
        leftButton.OnEvent("Click", StopExtendedProblemLoggingFromUi)
    else
        leftButton.OnEvent("Click", ResetProblemReportForNewSession)

    closeButton := gui.AddButton(
        "x190 y548 w130 h38",
        "Venster sluiten"
    )
    closeButton.OnEvent("Click", HideProblemReportWindow)

    finishButton := gui.AddButton(
        "x414 y548 w238 h38 Default",
        "Probleemrapport afronden"
    )
    finishButton.OnEvent(
        "Click",
        FinalizeProblemReport.Bind(true)
    )

    for card in [banner, sessionInfo, stepsCard]
        RoundControl(card, 12)
}

CaptureProblemReportDescription() {
    global ProblemReportDescriptionEdit, ProblemReportSession

    if IsObject(ProblemReportDescriptionEdit) {
        try {
            ProblemReportSession["Description"] :=
                ProblemReportDescriptionEdit.Value
        } catch {
        }
    }
}

HideProblemReportWindow(guiObj := 0, *) {
    global ProblemReportGui

    CaptureProblemReportDescription()
    if IsObject(ProblemReportGui)
        try ProblemReportGui.Hide()
    return true
}

StartExtendedProblemLogging(*) {
    global AppVersion, ProblemReportConsentCheck, ProblemReportSession

    if !IsObject(ProblemReportConsentCheck)
        || ProblemReportConsentCheck.Value != 1 {
        MsgBox(
            "Geef eerst toestemming om uitgebreide logging in te schakelen.",
            "DocBot - Probleem melden",
            "Iconi"
        )
        return
    }

    CaptureProblemReportDescription()

    logDir := EnvGet("LocalAppData") "\DocBot"
    try {
        if !DirExist(logDir)
            DirCreate(logDir)

        logPath := (
            logDir "\problem-report-"
            . FormatTime(A_Now, "yyyyMMdd-HHmmss")
            . ".log"
        )
        if FileExist(logPath)
            FileDelete(logPath)

        ProblemReportSession["ExtendedLogPath"] := logPath
        ProblemReportSession["StartedAt"] := A_Now
        ProblemReportSession["ExtendedActive"] := true
        ProblemReportSession["Phase"] := "active"

        FileAppend(
            "DocBot uitgebreid diagnose-log`r`n"
            "Versie: " AppVersion "`r`n"
            "Gestart: " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`r`n"
            "Toestemming: expliciet gegeven voor ongeschoonde uitgebreide logging`r`n"
            "───`r`n",
            logPath,
            "UTF-8"
        )
        ExtendedDebugLog(
            "i",
            "Probleemrapport",
            "Uitgebreide logging gestart na expliciete toestemming."
        )
        ReloadRuntimeHotstrings(false)
    } catch as logError {
        if IsSet(logPath) && FileExist(logPath)
            try FileDelete(logPath)

        ProblemReportSession["ExtendedActive"] := false
        ProblemReportSession["Phase"] := "start"
        ProblemReportSession["ExtendedLogPath"] := ""
        MsgBox(
            "Uitgebreide logging kon niet worden gestart.`n`n"
            logError.Message,
            "DocBot - Probleem melden",
            "Icon!"
        )
        return
    }

    BuildTrayMenu()
    BuildProblemReportWindow()
}

StopExtendedProblemLogging(
    showMessage := true,
    rebuildWindow := true
) {
    global ProblemReportSession

    if !ProblemReportSession["ExtendedActive"] {
        ; Herstel ook een eventueel verouderd venster. Dit kan gebeuren als
        ; de mail- of Outlook-fallback afbreekt nadat de sessie al is gestopt.
        if rebuildWindow
            BuildProblemReportWindow()
        return
    }

    ExtendedDebugLog(
        "i",
        "Probleemrapport",
        "Uitgebreide logging gestopt."
    )
    FlushExtendedDebugLog()
    ProblemReportSession["ExtendedActive"] := false
    ProblemReportSession["Phase"] := "captured"
    ReloadRuntimeHotstrings(false)
    BuildTrayMenu()

    if showMessage
        ShowNotification(
            "Uitgebreide logging is gestopt. Het rapport kan nu worden afgerond.",
            4500,
            "info"
        )

    if rebuildWindow
        BuildProblemReportWindow()
}

StopExtendedProblemLoggingFromUi(*) {
    StopExtendedProblemLogging(true, true)
}

ResetProblemReportForNewSession(*) {
    global ProblemReportSession

    CaptureProblemReportDescription()
    DeleteProblemReportExtendedLog()
    ProblemReportSession["Phase"] := "start"
    ProblemReportSession["ExtendedActive"] := false
    ProblemReportSession["StartedAt"] := ""
    ProblemReportSession["ExtendedLogPath"] := ""
    BuildTrayMenu()
    BuildProblemReportWindow()
}

ShutdownProblemReportLogging() {
    global ProblemReportSession

    if ProblemReportSession["ExtendedActive"] {
        ExtendedDebugLog(
            "i",
            "Probleemrapport",
            "Uitgebreide logging gestopt bij afsluiten van DocBot."
        )
        FlushExtendedDebugLog()
    }

    ProblemReportSession["ExtendedActive"] := false
    DeleteProblemReportExtendedLog()
}

FinalizeProblemReport(includeExtended, *) {
    global ProblemReportSession

    if ProblemReportSession["Finalizing"]
        return
    ProblemReportSession["Finalizing"] := true

    try {
        CaptureProblemReportDescription()

        ; Werk het venster meteen bij. Outlook en de handmatige mailfallback zijn
        ; externe vervolgstappen en mogen nooit een oude status "logging actief"
        ; in DocBot achterlaten wanneer een van die stappen niet beschikbaar is.
        if includeExtended && ProblemReportSession["ExtendedActive"]
            StopExtendedProblemLogging(false, true)

        FlushDebugLog()
        FlushExtendedDebugLog()

        package := BuildProblemReportPackage(includeExtended)
        if package = ""
            return

        if OpenProblemReportEmail(
            package,
            ProblemReportSession["Description"],
            includeExtended
        )
            ResetProblemReportAfterCompletion()
    } finally {
        ProblemReportSession["Finalizing"] := false
    }
}

; Bouwt de losse rapportbestanden op (geen ZIP): dat maakt de bijlage
; onafhankelijk van de Explorer-shellextensie "Compressed (zipped) Folders",
; die op sommige beheerde werkplekken door group policy/EDR wordt beperkt en
; daardoor eerder onbetrouwbaar bleek. Retourneert een Map met "Dir" (de
; tijdelijke map) en "Files" (de aangemaakte bestandspaden), of "" bij een
; fout.
BuildProblemReportPackage(includeExtended) {
    global AppVersion, ProblemReportSession

    stamp := FormatTime(A_Now, "yyyyMMdd_HHmmss")
        . "_" Format("{:03}", A_MSec)
    reportDir := A_Temp "\DocBot_diagnose_" stamp
    files := []

    try {
        if DirExist(reportDir)
            DirDelete(reportDir, true)
        DirCreate(reportDir)

        description := (
            Trim(ProblemReportSession["Description"]) != ""
                ? ProblemReportSession["Description"]
                : "<geen beschrijving>"
        )

        reportText := Format(
            "DocBot-probleemrapport`r`n"
            . "Versie: {1}`r`n"
            . "Aangemaakt: {2}`r`n"
            . "Uitgebreide logging gebruikt: {3}`r`n`r`n"
            . "Beschrijving van de gebruiker:`r`n"
            . "{4}",
            AppVersion,
            FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"),
            includeExtended ? "ja" : "nee",
            description
        )

        reportPath := reportDir "\probleemrapport.txt"
        FileAppend(reportText, reportPath, "UTF-8")
        files.Push(reportPath)

        standardPath := GetStandardDebugLogPath()
        if FileExist(standardPath) {
            standardCopyPath := reportDir "\standaardlog.txt"
            FileCopy(standardPath, standardCopyPath, true)
            files.Push(standardCopyPath)
        }

        extendedPath := ProblemReportSession["ExtendedLogPath"]
        if includeExtended
            && extendedPath != ""
            && FileExist(extendedPath) {
            extendedCopyPath := reportDir "\uitgebreid-log.txt"
            FileCopy(extendedPath, extendedCopyPath, true)
            files.Push(extendedCopyPath)
        }

        ; De losse bestanden blijven in %TEMP% staan: Outlook heeft ze nodig
        ; als bijlage, en bij de handmatige fallback moet de gebruiker ze zelf
        ; nog kunnen toevoegen.
        return Map("Dir", reportDir, "Files", files)
    } catch as packageError {
        MsgBox(
            "Het probleemrapport kon niet worden gemaakt.`n`n"
            packageError.Message,
            "DocBot - Probleem melden",
            "Icon!"
        )
        if DirExist(reportDir)
            try Run('explorer.exe "' reportDir '"')
        return ""
    }
}

OpenProblemReportEmail(package, description, usedExtended) {
    global AppVersion

    reportDir := package["Dir"]
    files := package["Files"]

    subject := "DocBot probleem - versie " AppVersion
    bodyDescription := (
        Trim(description) != ""
            ? description
            : "<geen beschrijving>"
    )
    body := Format(
        "Hoi Nico,`r`n`r`n"
        . "Ik wil het volgende probleem met {1} melden:`r`n`r`n"
        . "{2}`r`n`r`n"
        . "Diagnosepakket bijgevoegd. Uitgebreide logging gebruikt: {3}.`r`n`r`n"
        . "Met vriendelijke groet",
        A_ScriptName,
        bodyDescription,
        usedExtended ? "ja" : "nee"
    )

    try {
        outlook := GetOutlookApplication()
        if !IsObject(outlook)
            throw Error("Classic Outlook kon niet worden gestart.")

        mail := 0
        deadline := A_TickCount + 15000
        while A_TickCount < deadline {
            try {
                mail := outlook.CreateItem(0)
                if IsObject(mail)
                    break
            } catch {
                Sleep(500)
            }
        }

        if !IsObject(mail)
            throw Error("Outlook was gestart, maar nog niet gereed voor een bericht.")

        fullName := ""
        try fullName := Trim(outlook.Session.CurrentUser.Name)
        if fullName != ""
            body .= ",`r`n" fullName
        else
            body .= "."

        mail.To := "n.feenstra@meandermc.nl"
        mail.Subject := subject
        mail.Body := body
        for attachmentPath in files
            mail.Attachments.Add(attachmentPath)
        if mail.Attachments.Count != files.Length
            throw Error("Outlook heeft niet alle bestanden als bijlage overgenomen.")
        mail.Display()
        try {
            inspector := mail.GetInspector
            inspector.Activate()
        } catch {
        }

        ; Outlook heeft de bijlagen nu in het conceptbericht overgenomen (het
        ; aantal is hierboven geverifieerd) en het venster staat open; de
        ; tijdelijke rapportmap op schijf is vanaf hier niet meer nodig. Dit
        ; gebeurt bewust na Display() en niet direct na Attachments.Add(), zodat
        ; een latere fout in dit blok nog steeds via de catch naar de
        ; handmatige fallback kan met een intacte rapportmap.
        try DirDelete(reportDir, true)

        DebugLog(
            "✓",
            "Probleemrapport",
            "Conceptmail met diagnosepakket geopend."
        )
        return true
    } catch as outlookError {
        DebugLog(
            "!",
            "Probleemrapport Outlook",
            "Conceptmail kon niet worden geopend: " outlookError.Message
        )
        return OpenProblemReportFallback(
            reportDir,
            subject,
            body,
            outlookError.Message
        )
    }
}

GetOutlookApplication() {
    try return ComObjActive("Outlook.Application")
    catch {
    }

    try outlook := ComObject("Outlook.Application")
    catch
        return 0

    deadline := A_TickCount + 15000
    while A_TickCount < deadline {
        try {
            session := outlook.Session
            if IsObject(session)
                return outlook
        } catch {
            Sleep(500)
        }
    }

    return outlook
}

OpenProblemReportFallback(
    reportDir,
    subject,
    body,
    outlookError
) {
    fallbackBody := (
        SubStr(body, 1, 1500)
        . "`r`n`r`nVoeg de bestanden uit deze map handmatig toe:`r`n"
        . reportDir
    )
    mailto := (
        "mailto:n.feenstra@meandermc.nl?subject="
        . UriEncode(subject)
        . "&body="
        . UriEncode(fallbackBody)
    )

    mailOpened := false
    try {
        Run(mailto)
        mailOpened := true
    } catch {
    }

    try Run('explorer.exe "' reportDir '"')

    MsgBox(
        "Classic Outlook kon het conceptbericht niet automatisch openen."
        . "`n`nDe rapportmap is in Verkenner geopend."
        . (mailOpened
            ? " Er is daarnaast een nieuw e-mailbericht zonder bijlage geopend."
            : "")
        . "`nVoeg de bestanden handmatig toe en verstuur het bericht."
        . "`n`nTechnische melding: "
        . SanitizeLogText(outlookError),
        "DocBot - Probleem melden",
        "Icon!"
    )

    ; De rapportmap blijft bewust staan tot de gebruiker heeft aangegeven
    ; klaar te zijn: op dit moment kan de e-mail nog onverzonden open staan.
    ; Bij twijfel (bijvoorbeeld dit venster gewoon wegklikken) is "Nee" de
    ; standaardknop, zodat er nooit per ongeluk bestanden verdwijnen vóór
    ; verzending.
    completed := mailOpened || DirExist(reportDir)

    if DirExist(reportDir) {
        cleanupChoice := MsgBox(
            "Is de e-mail met het probleemrapport verzonden, of heb je de "
            "bestanden niet meer nodig?"
            . "`n`nJa: ruim de rapportmap nu op."
            . "`nNee: laat de rapportmap staan (bijvoorbeeld omdat je de "
            "bijlagen nog moet toevoegen en verzenden). DocBot ruimt een "
            "vergeten rapportmap later automatisch op.",
            "DocBot - Probleem melden",
            "YesNo Icon? Default2"
        )
        if cleanupChoice = "Yes"
            try DirDelete(reportDir, true)
    }

    return completed
}

UriEncode(text) {
    static safeCharacters := (
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        . "abcdefghijklmnopqrstuvwxyz"
        . "0123456789-_.~"
    )

    byteCount := StrPut(text, "UTF-8")
    bytes := Buffer(byteCount, 0)
    StrPut(text, bytes, "UTF-8")

    result := ""
    Loop byteCount - 1 {
        value := NumGet(bytes, A_Index - 1, "UChar")
        character := Chr(value)
        result .= InStr(safeCharacters, character, true)
            ? character
            : "%" Format("{:02X}", value)
    }
    return result
}

DeleteProblemReportExtendedLog() {
    global ProblemReportSession

    extendedPath := ProblemReportSession["ExtendedLogPath"]
    if extendedPath != "" && FileExist(extendedPath)
        try FileDelete(extendedPath)
}

; Vangnet voor tijdelijke rapportmappen (BuildProblemReportPackage()) die om
; welke reden dan ook nooit zijn opgeruimd: de handmatige fallback waarbij de
; gebruiker "Nee" koos of het venster wegklikte, een crash tussen het
; aanmaken van de map en het afronden van de melding, of het afsluiten van
; DocBot midden in de flow. Gebruikt de tijdstempel die DocBot zelf in de
; mapnaam codeert (niet de bestandssysteem-wijzigingstijd), zodat een latere
; kopieer- of scanactie op de map de bewaartermijn niet per ongeluk verlengt.
; Alleen mappen die aan een bekend eigen naampatroon voldoen worden
; verwijderd. Het millisecondesuffix is optioneel: vóór commit 2a8127e
; (2026-08-08) heette de map "DocBot_diagnose_yyyyMMdd_HHmmss" zonder dat
; suffix. Zulke mappen konden destijds achterblijven wanneer het (inmiddels
; met D-041 verwijderde) ZIP-opbouwproces mislukte vóórdat de map werd
; opgeruimd — bevestigd aanwezig op een echte testmachine.
PruneAbandonedProblemReportDirs() {
    static maxAgeDays := 7

    cutoff := DateAdd(A_Now, -maxAgeDays, "Days")
    SplitPath(A_Temp, &tempMapnaam)  ; alleen de laatste mapnaam, geen volledig pad (privacygevoelig)
    gezien := 0
    onherkend := 0
    voorbeeldOnherkend := ""
    verlopen := 0
    verwijderd := 0
    mislukt := 0
    laatsteFout := ""

    try {
        Loop Files, A_Temp "\DocBot_diagnose_*", "D" {
            gezien += 1
            if !RegExMatch(A_LoopFileName, "^DocBot_diagnose_(\d{8})_(\d{6})(?:_\d+)?$", &m) {
                onherkend += 1
                if (voorbeeldOnherkend = "")
                    voorbeeldOnherkend := A_LoopFileName
                continue  ; onbekende mapnaam: niet aanraken
            }

            stamp := m[1] m[2]
            if (stamp < cutoff) {
                verlopen += 1
                try {
                    DirDelete(A_LoopFileFullPath, true)
                    verwijderd += 1
                } catch as dirError {
                    mislukt += 1
                    laatsteFout := dirError.Message
                }
            }
        }
    } catch as sweepError {
        DebugLog(
            "!",
            "Probleemrapportmap opschonen",
            "Doorzoeken van %TEMP% mislukt: " sweepError.Message
        )
        return
    }

    ; Altijd loggen, ook bij 0 gezien: bevestigd via een reëel testrapport
    ; (zie docs/DECISIONS.md D-044 addendum 3) dat dit onderscheid nodig is
    ; om te kunnen zien of de sweep daadwerkelijk draait. De projecteigenaar
    ; wil deze regel bovendien bewust als dagelijks/opstart-bewijs dat de
    ; opschoning werkt, niet alleen als foutopsporingshulpmiddel.
    ; "doorzocht in ...\<mapnaam>" toont alleen de laatste mapnaam van A_Temp
    ; (bijv. "Temp" of "2"), niet het volledige pad, om geen gebruikersnaam
    ; of ander lokaal pad in het log te zetten.
    samenvatting := Format(
        "{1} map(pen) gezien, {2} niet herkend op naampatroon, {3} verlopen (>7 dagen), {4} verwijderd, {5} mislukt. Doorzocht in ...\{6}\.",
        gezien, onherkend, verlopen, verwijderd, mislukt, tempMapnaam
    )
    if (onherkend > 0)
        samenvatting .= " Voorbeeld onherkende naam: " SanitizeLogText(voorbeeldOnherkend)
    if (mislukt > 0)
        samenvatting .= " Laatste fout: " SanitizeLogText(laatsteFout)
    DebugLog("i", "Probleemrapportmap opschonen", samenvatting)
}

; Vangnet voor een tijdelijke UserStorageProbe_*-map (zie InitializeUserStorage())
; die overblijft als DocBot crasht/geforceerd stopt tussen het aanmaken en
; het hernoemen naar UserDataDir of opruimen ervan. Zelfde patroon als
; PruneAbandonedProblemReportDirs() hierboven, alleen in A_MyDocuments in
; plaats van A_Temp. De volledige A_MyDocuments-pad wordt bewust niet
; gelogd (kan de Windows-gebruikersnaam bevatten).
PruneAbandonedUserStorageProbeDirs() {
    static maxAgeDays := 7

    cutoff := DateAdd(A_Now, -maxAgeDays, "Days")
    gezien := 0
    onherkend := 0
    voorbeeldOnherkend := ""
    verlopen := 0
    verwijderd := 0
    mislukt := 0
    laatsteFout := ""

    try {
        Loop Files, A_MyDocuments "\DocBot_userdata_probe_*", "D" {
            gezien += 1
            if !RegExMatch(A_LoopFileName, "^DocBot_userdata_probe_(\d{8})_(\d{6})_\d+$", &m) {
                onherkend += 1
                if (voorbeeldOnherkend = "")
                    voorbeeldOnherkend := A_LoopFileName
                continue  ; onbekende mapnaam: niet aanraken
            }

            stamp := m[1] m[2]
            if (stamp < cutoff) {
                verlopen += 1
                try {
                    DirDelete(A_LoopFileFullPath, true)
                    verwijderd += 1
                } catch as dirError {
                    mislukt += 1
                    laatsteFout := dirError.Message
                }
            }
        }
    } catch as sweepError {
        DebugLog(
            "!",
            "Tijdelijke gebruikersmap opschonen",
            "Doorzoeken van Documents mislukt: " sweepError.Message
        )
        return
    }

    ; Altijd loggen, ook bij 0 gezien — zelfde reden als bij
    ; PruneAbandonedProblemReportDirs() hierboven (D-044 addendum 3).
    samenvatting := Format(
        "{1} map(pen) gezien, {2} niet herkend op naampatroon, {3} verlopen (>7 dagen), {4} verwijderd, {5} mislukt.",
        gezien, onherkend, verlopen, verwijderd, mislukt
    )
    if (onherkend > 0)
        samenvatting .= " Voorbeeld onherkende naam: " SanitizeLogText(voorbeeldOnherkend)
    if (mislukt > 0)
        samenvatting .= " Laatste fout: " SanitizeLogText(laatsteFout)
    DebugLog("i", "Tijdelijke gebruikersmap opschonen", samenvatting)
}

; Vangnet voor het losse uitgebreide-logbestand van StartExtendedProblemLogging()
; (%LocalAppData%\DocBot\problem-report-<tijdstip>.log). DeleteProblemReportExtendedLog()
; ruimt dat bestand alleen op vanuit het lopende ProblemReportSession — na een
; crash, geforceerd afsluiten of Windows-herstart tijdens een actieve sessie
; is er geen enkele andere plek die dat bestand nog kent. Zelfde aanpak als
; PruneAbandonedProblemReportDirs(): tijdstempel uit de bestandsnaam, niet de
; bestandssysteem-wijzigingstijd.
PruneAbandonedExtendedLogFiles() {
    static maxAgeDays := 7

    cutoff := DateAdd(A_Now, -maxAgeDays, "Days")
    logDir := EnvGet("LocalAppData") "\DocBot"
    gezien := 0
    verlopen := 0
    verwijderd := 0
    mislukt := 0
    laatsteFout := ""

    try {
        Loop Files, logDir "\problem-report-*.log" {
            gezien += 1
            if !RegExMatch(A_LoopFileName, "^problem-report-(\d{8})-(\d{6})\.log$", &m)
                continue  ; onbekende bestandsnaam: niet aanraken

            stamp := m[1] m[2]
            if (stamp < cutoff) {
                verlopen += 1
                try {
                    FileDelete(A_LoopFileFullPath)
                    verwijderd += 1
                } catch as fileError {
                    mislukt += 1
                    laatsteFout := fileError.Message
                }
            }
        }
    } catch as sweepError {
        DebugLog(
            "!",
            "Uitgebreid log opschonen",
            "Doorzoeken van " logDir " mislukt: " sweepError.Message
        )
        return
    }

    ; Altijd loggen, ook bij 0 gezien: zelfde afweging als bij
    ; PruneAbandonedProblemReportDirs() — bewijst dat de opschoning draait,
    ; niet alleen een foutopsporingshulpmiddel.
    samenvatting := Format(
        "{1} bestand(en) gezien, {2} verlopen (>7 dagen), {3} verwijderd, {4} mislukt.",
        gezien, verlopen, verwijderd, mislukt
    )
    if (mislukt > 0)
        samenvatting .= " Laatste fout: " SanitizeLogText(laatsteFout)
    DebugLog("i", "Uitgebreid log opschonen", samenvatting)
}

ResetProblemReportAfterCompletion() {
    global ProblemReportGui, ProblemReportDescriptionEdit
    global ProblemReportConsentCheck, ProblemReportSession

    DeleteProblemReportExtendedLog()

    ProblemReportSession := Map(
        "Phase", "start",
        "ExtendedActive", false,
        "StartedAt", "",
        "Description", "",
        "ExtendedLogPath", "",
        "Finalizing", false
    )

    if IsObject(ProblemReportGui)
        try ProblemReportGui.Destroy()

    ProblemReportGui := 0
    ProblemReportDescriptionEdit := 0
    ProblemReportConsentCheck := 0
    BuildTrayMenu()

    ShowNotification(
        "Het probleemrapport is voorbereid.",
        4000,
        "info"
    )
}

ClipBoardPoller() {
    global State, StorageAllReady
    static lastSeq := DllCall("GetClipboardSequenceNumber")  ; voorkomt dat de klembordinhoud bij opstarten al wordt opgepakt

    seq := DllCall("GetClipboardSequenceNumber")
    if seq = lastSeq
        return

    lastSeq := seq

    externalTel := NormalizePhoneNumberExternal(A_ClipBoard)
    internalTel := externalTel = "" ? NormalizePhoneNumberInternal(A_ClipBoard) : ""

    if externalTel = "" && internalTel = ""
        return

    if !StorageAllReady {
        ; CallAction en de andere instellingen die de belactie-flow
        ; hieronder gebruikt zijn nog niet betrouwbaar geladen. Niet
        ; stilzwijgend niets doen (dat lijkt alsof DocBot het nummer niet
        ; heeft gezien) en niet handelen op een mogelijk onjuiste
        ; standaardwaarde: laat het via een korte melding weten. Zie ook de
        ; banner op de Overzicht-pagina.
        ShowNotification(
            "Telefoonnummer herkend, maar instellingen laden nog. Probeer het over een moment opnieuw.",
            5000,
            "warning"
        )
        return
    }

    if externalTel != "" {
        SetClipBoardNumber(externalTel)
        HandleClipboardNumberDetected()
        return
    }

    SetClipBoardNumber(internalTel)
    HandleInternalClipboardNumberDetected()
}

; Centrale set/clear van het klembordnummer in de IPT-status, met een
; geschoonde logregel (nooit het nummer zelf) zodat in het debugvenster
; zichtbaar is wanneer de status gevuld of geleegd wordt. Zie
; docs/DATA_PROTECTION.md §3.1: het nummer mag na overdracht, afronding of
; annulering van de actuele actie niet langer dan nodig in de centrale
; status blijven staan.
SetClipBoardNumber(number) {
    global State

    State["IPT"]["ClipBoardNumber"] := number
    DebugLog("i", "Klembordnummer", "Nieuw nummer herkend en in status gezet.")
}

ClearClipBoardNumber(reden) {
    global State

    if State["IPT"]["ClipBoardNumber"] = ""
        return

    State["IPT"]["ClipBoardNumber"] := ""
    DebugLog("i", "Klembordnummer", "Status geleegd (" . reden . ").")
}

; Ruime validatie/normalisatie: accepteert zowel een kaal 4-cijferig intern
; nummer als een NL-nationaal nummer (0 + 9 cijfers), ook genoteerd met
; +31/0031. Gebruikt door het snelkiesnummer-invoegvenster, waar beide
; soorten nummer geldige invoer zijn — in tegenstelling tot de
; klemborddetectie, die de twee soorten bewust gescheiden houdt (zie
; ClipBoardPoller). Bewust géén generieke landcodes (zie
; NormalizePhoneNumberExternal): alleen intern of NL blijft geldig.
NormalizePhoneNumber(input) {
    cb := Trim(input)
    cb := RegExReplace(cb, "[\s\-\(\)]", "")   ; spaties/streepjes/haakjes negeren bij het typen/plakken

    internal := NormalizePhoneNumberInternal(cb)
    if internal != ""
        return internal

    ; NL nationaal of internationaal genoteerd (+31/0031/0), altijd 9 cijfers na de prefix
    tel := ""
    if StrLen(cb) >= 10 && StrLen(cb) <= 13 && RegExMatch(cb, "^(\+31|0031|0)(\d{9})$") {
        tel := RegExReplace(cb, "\+31", "0031")
        tel := RegExReplace(tel, "^0031", "0")
    }

    return StrLen(tel) >= 10 ? tel : ""
}

; Uitsluitend externe (10-cijferige) NL-nummers, met of zonder landcode.
; Dit is de ongewijzigde regex-logica van vóór de interne-nummerdetectie,
; nu in een eigen functie met een expliciet, smal bereik.
NormalizePhoneNumberExternal(input) {
    cb := Trim(input)
    tel := ""

    if StrLen(cb) >= 10 && StrLen(cb) <= 13 && RegExMatch(cb, "^(\+\d{2}|00\d{2}|0)(\d{9})$") {
        tel := RegExReplace(cb, "\+", "00")
        tel := RegExReplace(tel, "0031", "0")
    }

    return StrLen(tel) >= 10 ? tel : ""
}

; Uitsluitend een kaal 4-cijferig intern nummer, niets anders.
NormalizePhoneNumberInternal(input) {
    cb := Trim(input)
    return RegExMatch(cb, "^\d{4}$") ? cb : ""
}

HandleClipboardNumberDetected() {
    global State

    ; Elke klemborddetectie maakt eerst schoon wat een vorige detectie nog
    ; openstaand liet — ongeacht welke actie hierna volgt (nieuwe dialoog,
    ; direct bellen of niets doen). Zo kan een intern nummer dat direct wordt
    ; gebeld nooit een nog niet afgehandeld venster van een eerder extern
    ; nummer laten "achterblijven". Handmatige acties in de DocBot-interface
    ; (snelkies, rechtermuisknop) gaan hier niet doorheen en laten een
    ; openstaand venster bewust met rust.
    CloseExistingPhoneActionDialog()

    action := State["CallAction"]
    switch action {
        case 0:
            ClearClipBoardNumber("geen belactie geconfigureerd")
        case 1:
            ShowCallConfirmationDialog()
        case 2:
            IPT_callNumber(State["IPT"]["ClipBoardNumber"])
            ClearClipBoardNumber("direct gebeld")
        case 3:
            ShowCallOrSmsChoiceDialog()
    }
}

; Een intern 4-cijferig nummer volgt dezelfde Belactie, behalve bij de
; keuze bellen/sms: SMS is alleen beschikbaar voor externe nummers en
; daarom wordt een intern nummer in stand 3 direct gebeld.
HandleInternalClipboardNumberDetected() {
    global State

    CloseExistingPhoneActionDialog()

    action := State["CallAction"]
    switch action {
        case 0:
            ClearClipBoardNumber("geen belactie geconfigureerd")
        case 1:
            ShowCallConfirmationDialog()
        case 2, 3:
            IPT_callNumber(State["IPT"]["ClipBoardNumber"])
            ClearClipBoardNumber("direct gebeld")
    }
}

; CloseExistingPhoneActionDialog() is al aangeroepen door de aanroepende
; Handle...ClipboardNumberDetected()-functie, de enige plek vanwaar deze
; functie wordt aangeroepen.
ShowCallConfirmationDialog() {
    global MainGui, C, State, PhoneActionDialogState

    number := State["IPT"]["ClipBoardNumber"]

    dlg := Gui("+Owner" MainGui.Hwnd " -MaximizeBox -MinimizeBox", "DocBot - Nummer bellen")
    dlg.BackColor := C["Window"]
    dlg.SetFont("s10 c" C["Text"], "Segoe UI")

    title := dlg.AddText("x28 y24 w304 h30 Center Background" C["Window"], "Nummer bellen?")
    title.SetFont("s18 bold c" C["Text"], "Segoe UI")

    numberShell := dlg.AddText("x28 y72 w304 h64 Background" C["Card"], "")

    numberValue := dlg.AddText("x28 y83 w304 h42 Center Background" C["Card"], number)
    numberValue.SetFont("s28 bold c" C["Text"], "Segoe UI")

    ; Echte Button-controls delen dezelfde custom-draw en toetsenbordbediening
    ; met de keuze Annuleren / SMS / Bellen.
    cancelBtn := dlg.AddButton("x28 y156 w140 h40 Center", "Annuleren")
    callBtn := dlg.AddButton("x192 y156 w140 h40 Center Default", "Bellen")
    cancelBtn._iconGlyph := Chr(0xE711)
    callBtn._iconGlyph := Chr(0xE717)

    ; Registreer Bellen al vóór de eerste paint als blauwe selectie.
    for buttonIndex, button in [cancelBtn, callBtn] {
        selected := buttonIndex = 2
        background := selected ? C["Primary"] : C["Button"]
        textColor := selected ? "FFFFFF" : C["Text"]

        button.SetFont("s10 " (selected ? "bold " : "") "c" textColor, "Segoe UI")
        button.SetColor(
            "0x" background,
            "0x" textColor,
            0,
            "0x" background,
            10
        )
    }

    cancelBtn.OnEvent("Click", ClosePhoneActionDialog.Bind(dlg))
    callBtn.OnEvent("Click", ExecutePhoneActionCallChoice.Bind(dlg, number))

    dlg.OnEvent("Close", ClosePhoneActionDialog.Bind(dlg))
    dlg.OnEvent("Escape", ClosePhoneActionDialog.Bind(dlg))

    PhoneActionDialogState := Map(
        "Dialog", dlg,
        "DialogHwnd", dlg.Hwnd,
        "Buttons", [cancelBtn, callBtn],
        "Selected", 2
    )

    dlg.Show("w360 h224 Center")

    SetPhoneActionDialogSelection(2)
    RedrawPhoneActionDialogButtons()
    DllCall("SetFocus", "ptr", callBtn.Hwnd, "ptr")

    RoundControl(numberShell, 16)
}

; CloseExistingPhoneActionDialog() is al aangeroepen door de aanroepende
; Handle...ClipboardNumberDetected()-functie, de enige plek vanwaar deze
; functie wordt aangeroepen.
ShowCallOrSmsChoiceDialog() {
    global MainGui, C, State, PhoneActionDialogState

    number := State["IPT"]["ClipBoardNumber"]

    dlg := Gui("+Owner" MainGui.Hwnd " -MaximizeBox -MinimizeBox", "DocBot - Belactie")
    dlg.BackColor := C["Window"]
    dlg.SetFont("s10 c" C["Text"], "Segoe UI")

    title := dlg.AddText("x28 y24 w444 h30 Center Background" C["Window"], "Wat wil je doen?")
    title.SetFont("s18 bold c" C["Text"], "Segoe UI")

    numberShell := dlg.AddText("x28 y72 w444 h64 Background" C["Card"], "")
    numberValue := dlg.AddText("x28 y83 w444 h42 Center Background" C["Card"], number)
    numberValue.SetFont("s28 bold c" C["Text"], "Segoe UI")

    ; Echte Button-controls zijn focusbaar en reageren op Enter. Het pictogram
    ; wordt apart in Segoe MDL2 Assets getekend, zodat er geen puntje ontstaat.
    cancelBtn := dlg.AddButton("x28 y156 w132 h40 Center", "Annuleren")
    smsBtn := dlg.AddButton("x184 y156 w132 h40 Center", "SMS")
    callBtn := dlg.AddButton("x340 y156 w132 h40 Center Default", "Bellen")
    cancelBtn._iconGlyph := Chr(0xE711)
    smsBtn._iconGlyph := Chr(0xE8BD)
    callBtn._iconGlyph := Chr(0xE717)

    ; Registreer de initiële selectie meteen in de custom-draw kleuren.
    ; Als alle knoppen eerst grijs worden aangemaakt en de selectie pas na
    ; Show() wijzigt, verwerkt Windows die wijziging soms pas bij de eerste
    ; hover. Bellen moet daarom al bij de allereerste paint blauw zijn.
    for buttonIndex, button in [cancelBtn, smsBtn, callBtn] {
        selected := buttonIndex = 3
        background := selected ? C["Primary"] : C["Button"]
        textColor := selected ? "FFFFFF" : C["Text"]

        button.SetFont("s10 " (selected ? "bold " : "") "c" textColor, "Segoe UI")
        button.SetColor(
            "0x" background,
            "0x" textColor,
            0,
            "0x" background,
            10
        )
    }

    cancelBtn.OnEvent("Click", ClosePhoneActionDialog.Bind(dlg))
    smsBtn.OnEvent("Click", StartSmsCallAction.Bind(dlg, number))
    callBtn.OnEvent("Click", ExecutePhoneActionCallChoice.Bind(dlg, number))

    dlg.OnEvent("Close", ClosePhoneActionDialog.Bind(dlg))
    dlg.OnEvent("Escape", ClosePhoneActionDialog.Bind(dlg))

    PhoneActionDialogState := Map(
        "Dialog", dlg,
        "DialogHwnd", dlg.Hwnd,
        "Buttons", [cancelBtn, smsBtn, callBtn],
        "Selected", 3
    )

    dlg.Show("w500 h224 Center")

    ; SetColor vóór Show() is niet voldoende: Windows toont dan eerst kort de
    ; native knoprand en stuurt pas bij hover een betrouwbare custom-draw.
    ; Pas de selectie daarom toe op het zichtbare venster en forceer WM_PAINT.
    SetPhoneActionDialogSelection(3)
    RedrawPhoneActionDialogButtons()
    DllCall("SetFocus", "ptr", callBtn.Hwnd, "ptr")

    RoundControl(numberShell, 16)
}

RedrawPhoneActionDialogButtons() {
    global PhoneActionDialogState

    if !IsObject(PhoneActionDialogState)
        return

    for _, button in PhoneActionDialogState["Buttons"] {
        if !DllCall("IsWindowVisible", "ptr", button.Hwnd, "int")
            continue

        DllCall(
            "SetWindowPos",
            "ptr", button.Hwnd,
            "ptr", 0,  ; HWND_TOP
            "int", 0, "int", 0, "int", 0, "int", 0,
            "uint", 0x1 | 0x2 | 0x10  ; NOSIZE | NOMOVE | NOACTIVATE
        )
        DllCall(
            "RedrawWindow",
            "ptr", button.Hwnd,
            "ptr", 0,
            "ptr", 0,
            "uint", 0x1 | 0x4 | 0x100 | 0x400
        )
    }
}

SetPhoneActionDialogSelection(index) {
    global PhoneActionDialogState, C

    if !IsObject(PhoneActionDialogState)
        return

    buttons := PhoneActionDialogState["Buttons"]
    if index < 1
        index := buttons.Length
    else if index > buttons.Length
        index := 1

    PhoneActionDialogState["Selected"] := index

    for buttonIndex, button in buttons {
        selected := buttonIndex = index
        background := selected ? C["Primary"] : C["Button"]
        textColor := selected ? "FFFFFF" : C["Text"]

        button.BackColor := "0x" background
        button.TextColor := "0x" textColor
        button.SetFont("s10 " (selected ? "bold " : "") "c" textColor, "Segoe UI")
        button.Redraw()
    }

    DllCall("SetFocus", "ptr", buttons[index].Hwnd, "ptr")
}

PhoneActionDialogKeyDown(wParam, lParam, message, hwnd) {
    global PhoneActionDialogState

    if !IsObject(PhoneActionDialogState)
        return
    if !WinActive("ahk_id " PhoneActionDialogState["DialogHwnd"])
        return

    switch wParam {
        case 0x25:  ; VK_LEFT
            SetPhoneActionDialogSelection(PhoneActionDialogState["Selected"] - 1)
            return 1
        case 0x27:  ; VK_RIGHT
            SetPhoneActionDialogSelection(PhoneActionDialogState["Selected"] + 1)
            return 1
        case 0x0D:  ; VK_RETURN
            button := PhoneActionDialogState["Buttons"][PhoneActionDialogState["Selected"]]
            DllCall(
                "PostMessageW",
                "ptr", button.Hwnd,
                "uint", 0x00F5,  ; BM_CLICK
                "ptr", 0,
                "ptr", 0
            )
            return 1
    }
}

; Zorgt dat er nooit meer dan één telefoonactie-dialoog tegelijk open kan
; staan: een klemborddetectie tijdens een nog niet afgehandeld venster
; vervangt dat venster in plaats van eronder te blijven liggen. Zonder dit
; kon een oud, nooit weggeklikt venster later weer tevoorschijn komen zodra
; het nieuwere erbovenop werd afgehandeld — de gebruiker moest dan telkens
; controleren of het zichtbare nummer wel het net gekopieerde nummer was.
CloseExistingPhoneActionDialog() {
    global PhoneActionDialogState

    if !IsObject(PhoneActionDialogState)
        return

    existing := PhoneActionDialogState["Dialog"]
    PhoneActionDialogState := 0
    try existing.Destroy()

    ShowNotification(
        "Nieuw nummer herkend — vorig (nog niet bevestigd) belvenster is gesloten.",
        4000,
        "info"
    )
}

ClosePhoneActionDialog(dialog, *) {
    global PhoneActionDialogState

    if IsObject(PhoneActionDialogState)
        && PhoneActionDialogState["DialogHwnd"] = dialog.Hwnd {
        PhoneActionDialogState := 0
        ClearClipBoardNumber("belvenster afgerond of geannuleerd")
    }

    try dialog.Destroy()
}

ExecutePhoneActionCallChoice(dialog, number, *) {
    ClosePhoneActionDialog(dialog)
    IPT_callNumber(number)
}

StartSmsCallAction(dialog, number, *) {
    ClosePhoneActionDialog(dialog)
    DebugLog("→", "SMS actie", "SMS-route gestart.")

    smsNumber := NormalizeSmsPhoneNumber(number)
    if smsNumber = "" {
        ShowNotification(
            "SMS versturen is alleen mogelijk naar een Nederlands 06-nummer.",
            4500,
            "warning"
        )
        ExtendedDebugLog(
            "✕",
            "SMS actie geweigerd",
            "Het herkende externe nummer is geen geldig Nederlands 06-nummer."
        )
        return
    }

    smsConfig := GetSelectedSmsCallAction()
    if !IsObject(smsConfig) {
        ShowNotification(
            "Er is geen geldige SMS-pagina geselecteerd. Controleer Instellingen.",
            4500,
            "warning"
        )
        ExtendedDebugLog("✕", "SMS actie geweigerd", "Geen geselecteerde SmsCallAction gevonden.")
        return
    }

    try {
        ; Succes is direct zichtbaar doordat Edge met het ingevulde veld op de
        ; voorgrond staat. Toon alleen nog een melding als de actie mislukt.
        if !RunSmsCallAction(smsConfig, smsNumber) {
            DebugLog(
                "✕",
                "SMS actie",
                "SMS-route vond geen bruikbare pagina of invoerveld."
            )
            ShowNotification(
                "De SMS-pagina of het telefoonveld kon niet worden gevonden.",
                5000,
                "error"
            )
        } else {
            DebugLog("✓", "SMS actie", "SMS-route afgerond.")
            Telemetry_RecordSmsAction()
            RefreshUsageStatistics()
        }
    } catch as smsError {
        DebugLog("✕", "SMS actie", "SMS-route is mislukt.")
        ExtendedDebugLog("✕", "SMS actie", smsError.Message)
        ShowNotification(
            "De SMS-actie is mislukt. Controleer het debuglog voor details.",
            5000,
            "error"
        )
    }
}

RunSmsCallAction(smsConfig, number) {
    previousTitleMatchMode := A_TitleMatchMode
    previousDetectHiddenWindows := A_DetectHiddenWindows
    previousDetectHiddenText := A_DetectHiddenText

    ; WindowTitle mag als deel van de volledige Edge-titel voorkomen. Deze
    ; instellingen worden na de actie hersteld om andere DocBot-routes niet
    ; onbedoeld te beïnvloeden.
    SetTitleMatchMode(2)
    DetectHiddenWindows(true)
    DetectHiddenText(true)

    ExtendedDebugLog(
        "→",
        "SMS actie",
        "Start voor '" smsConfig["Title"] "' met nummer "
            MaskSmsPhoneNumber(number) ". Eerst WinActivate(WindowTitle), daarna UIA."
    )

    try {
        gebruiktPad := "WinActivate(WindowTitle)"
        edge := ActivateSmsEdgeWindowByTitle(smsConfig["WindowTitle"])

        if !IsObject(edge) {
            gebruiktPad := "UIA-tabselectie"
            edge := ActivateSmsEdgeTabByTitle(smsConfig["WindowTitle"])
        }

        if !IsObject(edge) {
            gebruiktPad := "URL-fallback (nieuw venster/tab)"
            edge := OpenSmsPage(smsConfig["Url"], smsConfig["WindowTitle"])
        }

        if !IsObject(edge) {
            DebugLog(
                "✕",
                "SMS vensterselectie",
                "Geen van de drie paden (WinActivate, UIA-tabselectie, URL-fallback) "
                    "vond een bruikbare Edge-tab voor WindowTitle '"
                    smsConfig["WindowTitle"] "'."
            )
            ExtendedDebugLog(
                "✕",
                "SMS vensterselectie",
                "WinActivate, UIA-tabselectie en URL-fallback vonden geen bruikbare Edge-tab."
            )
            return false
        }

        DebugLog(
            "✓",
            "SMS vensterselectie",
            "Pad '" gebruiktPad "' leverde de gebruikte Edge-tab voor WindowTitle '"
                smsConfig["WindowTitle"] "'."
        )

        phoneFilled := FillSmsFieldWithUIA(edge, smsConfig["FieldId"], number)
        if phoneFilled {
            ExtendedDebugLog(
                "✓",
                "SMS veldinvulling",
                "AutomationId '" smsConfig["FieldId"] "' via UI Automation ingevuld."
            )
        } else {
            ExtendedDebugLog(
                "→",
                "SMS veldinvulling",
                "UIA Edit-element niet gevonden; JavaScriptfallback wordt uitgevoerd."
            )
            phoneFilled := FillSmsDomFieldWithJavaScript(edge, smsConfig["FieldId"], number)
        }

        ; Standaardtekst is best-effort: een mislukte tekstinvulling mag een
        ; al geslaagde telefoonnummerinvulling niet tot een mislukte
        ; SMS-actie maken.
        if phoneFilled
            FillSmsDefaultTextField(edge, smsConfig)

        return phoneFilled
    } finally {
        SetTitleMatchMode(previousTitleMatchMode)
        DetectHiddenWindows(previousDetectHiddenWindows)
        DetectHiddenText(previousDetectHiddenText)
    }
}

ActivateSmsEdgeWindowByTitle(targetTitle) {
    startedAt := A_TickCount

    try WinActivate(targetTitle)
    catch as activateError {
        DebugLog(
            "←",
            "SMS WinActivate",
            "Geen titelmatch voor WindowTitle '" targetTitle "'."
        )
        ExtendedDebugLog(
            "←",
            "SMS WinActivate",
            "Geen titelmatch na " (A_TickCount - startedAt) " ms: "
                activateError.Message
        )
        return 0
    }

    hwnd := WinWaitActive(targetTitle, , 1)
    if !hwnd {
        DebugLog(
            "←",
            "SMS WinActivate",
            "Titelmatch voor WindowTitle '" targetTitle "' werd niet binnen 1 seconde actief."
        )
        ExtendedDebugLog(
            "←",
            "SMS WinActivate",
            "Titelmatch werd niet binnen 1 seconde actief."
        )
        return 0
    }

    try {
        edge := UIA_Browser(hwnd)
        DebugLog(
            "✓",
            "SMS WinActivate",
            "Edge-venster met WindowTitle '" targetTitle "' geactiveerd en UIA_Browser gekoppeld."
        )
        ExtendedDebugLog(
            "✓",
            "SMS WinActivate",
            "Edge-venster actief en UIA_Browser gekoppeld in "
                (A_TickCount - startedAt) " ms."
        )
        return edge
    } catch as browserError {
        DebugLog(
            "✕",
            "SMS WinActivate",
            "Venster met WindowTitle '" targetTitle "' actief, maar UIA_Browser koppelen mislukte."
        )
        ExtendedDebugLog(
            "✕",
            "SMS WinActivate",
            "Venster actief, maar UIA_Browser koppelen mislukte: "
                browserError.Message
        )
        return 0
    }
}

GetUsableEdgeBrowserWindows() {
    windows := []

    for hwnd in WinGetList("ahk_exe msedge.exe ahk_class Chrome_WidgetWin_1") {
        if !DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
            continue

        try title := Trim(WinGetTitle("ahk_id " hwnd))
        catch
            continue

        if title = ""
            continue

        windows.Push(hwnd)
    }

    return windows
}

ActivateSmsEdgeTabByTitle(targetTitle) {
    startedAt := A_TickCount
    edgeWindows := GetUsableEdgeBrowserWindows()

    DebugLog(
        "→",
        "SMS UIA-tabselectie",
        edgeWindows.Length " bruikbare Edge-venster(s) gevonden voor WindowTitle '"
            targetTitle "'."
    )
    ExtendedDebugLog(
        "→",
        "SMS UIA-tabselectie",
        edgeWindows.Length " bruikbare Edge-browservenster(s) gevonden; "
            "TabExist wordt per venster uitgevoerd."
    )

    for index, hwnd in edgeWindows {
        try {
            if WinGetMinMax("ahk_id " hwnd) = -1
                WinRestore("ahk_id " hwnd)

            edge := UIA_Browser(hwnd)
            tab := edge.TabExist(targetTitle, 2, false)
            if !tab {
                DebugLog(
                    "←",
                    "SMS UIA-tabselectie",
                    "Venster " index "/" edgeWindows.Length
                        ": geen tab met WindowTitle '" targetTitle "' gevonden."
                )
                continue
            }

            edge.SelectTab(tab)
            WinActivate("ahk_id " hwnd)
            if WinWaitActive("ahk_id " hwnd, , 2) {
                DebugLog(
                    "✓",
                    "SMS UIA-tabselectie",
                    "Venster " index "/" edgeWindows.Length
                        ": tab met WindowTitle '" targetTitle "' gevonden en geactiveerd."
                )
                ExtendedDebugLog(
                    "✓",
                    "SMS UIA-tabselectie",
                    "Tab gevonden in Edge-browservenster " index
                        " en geactiveerd in " (A_TickCount - startedAt) " ms."
                )
                return edge
            }

            DebugLog(
                "←",
                "SMS UIA-tabselectie",
                "Venster " index "/" edgeWindows.Length
                    ": tab gevonden maar niet binnen 2 seconden actief geworden."
            )
        } catch as windowError {
            DebugLog(
                "←",
                "SMS UIA-tabselectie",
                "Venster " index "/" edgeWindows.Length
                    " overgeslagen (fout bij koppelen/selecteren)."
            )
            ExtendedDebugLog(
                "←",
                "SMS UIA-tabselectie",
                "Edge-browservenster " index " overgeslagen: "
                    windowError.Message
            )
        }
    }

    DebugLog(
        "←",
        "SMS UIA-tabselectie",
        "Geen passende tab gevonden in " edgeWindows.Length
            " bruikbare Edge-venster(s) voor WindowTitle '" targetTitle
            "'; URL-fallback volgt."
    )
    ExtendedDebugLog(
        "←",
        "SMS UIA-tabselectie",
        "Geen passende tab gevonden in " edgeWindows.Length
            " bruikbare Edge-browservenster(s), duur "
            (A_TickCount - startedAt) " ms."
    )
    return 0
}

OpenSmsPage(url, targetTitle) {
    ExtendedDebugLog(
        "→",
        "SMS URL-fallback",
        "Geen bestaande tab gevonden; de lokaal geconfigureerde pagina wordt in Edge geopend."
    )

    try Run('msedge.exe "' url '"')
    catch as runError {
        DebugLog("✕", "SMS URL-fallback", "Edge starten mislukte.")
        ExtendedDebugLog("✕", "SMS URL-fallback", "Edge starten mislukte: " runError.Message)
        return 0
    }

    ; Bewust uitsluitend WindowTitle gebruiken. De POC heeft aangetoond dat
    ; een samengestelde query met ahk_exe in deze werkomgeving niet betrouwbaar is.
    hwnd := WinWaitActive(targetTitle, , 10)
    if !hwnd {
        DebugLog(
            "✕",
            "SMS URL-fallback",
            "Nieuw geopende pagina met WindowTitle '" targetTitle
                "' werd niet binnen 10 seconden actief."
        )
        ExtendedDebugLog(
            "✕",
            "SMS URL-fallback",
            "De geconfigureerde WindowTitle werd niet binnen 10 seconden actief."
        )
        return 0
    }

    try {
        edge := UIA_Browser(hwnd)
        DebugLog(
            "✓",
            "SMS URL-fallback",
            "Nieuwe Edge-tab met WindowTitle '" targetTitle "' actief en UIA_Browser gekoppeld."
        )
        ExtendedDebugLog("✓", "SMS URL-fallback", "Nieuwe Edge-tab actief en UIA_Browser gekoppeld.")
        return edge
    } catch as browserError {
        DebugLog(
            "✕",
            "SMS URL-fallback",
            "UIA_Browser koppelen aan de nieuwe tab met WindowTitle '" targetTitle "' mislukte."
        )
        ExtendedDebugLog(
            "✕",
            "SMS URL-fallback",
            "UIA_Browser koppelen aan de nieuwe tab mislukte: " browserError.Message
        )
        return 0
    }
}

; Generiek genoeg voor zowel het telefoonnummerveld als het optionele
; standaardtekstveld: beide zijn UIA "Edit"-elementen (een <textarea>
; verschijnt in Edge's toegankelijkheidsboom net als een <input> als Edit,
; met IsMultiLine=true), dus dezelfde AutomationId-opzoeking en
; Value-toewijzing werkt voor allebei.
FillSmsFieldWithUIA(edge, fieldId, value, timeoutMs := 5000) {
    deadline := A_TickCount + timeoutMs
    attempts := 0
    lastError := ""

    while A_TickCount < deadline {
        attempts += 1
        try {
            document := edge.GetCurrentDocumentElement()
            field := document.FindElement({
                Type: "Edit",
                AutomationId: fieldId
            })

            field.Value := value
            field.SetFocus()
            ExtendedDebugLog(
                "✓",
                "SMS UIA-veldinvulling",
                "Veld gevonden en ingevuld na " attempts " poging(en)."
            )
            return true
        } catch as fieldError {
            lastError := fieldError.Message
            Sleep(250)
        }
    }

    ExtendedDebugLog(
        "←",
        "SMS UIA-veldinvulling",
        "Veld niet gevonden na " attempts " poging(en) en " timeoutMs
            " ms. Laatste fout: " lastError
    )
    return false
}

FillSmsDomFieldWithJavaScript(edge, fieldId, value) {
    escapedFieldId := EscapeSmsJavaScriptString(fieldId)
    escapedValue := EscapeSmsJavaScriptString(value)

    ; Het standaardtekstveld is doorgaans een <textarea> in plaats van een
    ; <input>; de native value-setter zit dan op HTMLTextAreaElement.prototype
    ; in plaats van HTMLInputElement.prototype. Aanroepen via de verkeerde
    ; prototype-setter faalt op een element van het andere type, dus wordt de
    ; setter hier op basis van tagName gekozen in plaats van vast aangenomen.
    js := "(()=>{"
        . "const e=document.getElementById('" escapedFieldId "');"
        . "if(!e){throw new Error('DocBot: SMS-veld niet gevonden');}"
        . "const proto=e.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;"
        . "const s=Object.getOwnPropertyDescriptor(proto,'value').set;"
        . "s.call(e,'" escapedValue "');"
        . "e.dispatchEvent(new Event('input',{bubbles:true}));"
        . "e.dispatchEvent(new Event('change',{bubbles:true}));"
        . "e.focus();"
        . "return true;"
        . "})()"

    try {
        edge.JSExecute(js)
        ExtendedDebugLog(
            "✓",
            "SMS JavaScriptfallback",
            "Veld '" fieldId "' ingevuld; input- en change-events verstuurd."
        )
        return true
    } catch as jsError {
        ExtendedDebugLog("✕", "SMS JavaScriptfallback", jsError.Message)
        return false
    }
}

; Best-effort: vult het optionele TextFieldId met de standaardtekst van deze
; SMS-pagina, als beide geconfigureerd zijn. Ontbreekt TextFieldId of is er
; geen standaardtekst ingesteld, dan gebeurt er bewust niets — de al
; geslaagde telefoonnummerinvulling blijft dan het enige resultaat.
FillSmsDefaultTextField(edge, smsConfig) {
    if !smsConfig.Has("TextFieldId") || Trim(smsConfig["TextFieldId"]) = ""
        return

    defaultText := GetSmsDefaultText(smsConfig["Title"])
    if Trim(defaultText) = ""
        return

    if FillSmsFieldWithUIA(edge, smsConfig["TextFieldId"], defaultText) {
        ExtendedDebugLog(
            "✓",
            "SMS standaardtekst",
            "AutomationId '" smsConfig["TextFieldId"] "' via UI Automation ingevuld."
        )
        return
    }

    if FillSmsDomFieldWithJavaScript(edge, smsConfig["TextFieldId"], defaultText) {
        ExtendedDebugLog("✓", "SMS standaardtekst", "Veld ingevuld via JavaScriptfallback.")
    } else {
        ExtendedDebugLog(
            "✕",
            "SMS standaardtekst",
            "Kon het geconfigureerde tekstveld niet vinden of vullen; het telefoonnummer is wel ingevuld."
        )
    }
}

NormalizeSmsPhoneNumber(input) {
    digits := RegExReplace(Trim(input), "\D")

    if RegExMatch(digits, "^316\d{8}$")
        digits := "0" SubStr(digits, 3)
    else if RegExMatch(digits, "^00316\d{8}$")
        digits := "0" SubStr(digits, 5)

    return RegExMatch(digits, "^06\d{8}$") ? digits : ""
}

MaskSmsPhoneNumber(number) {
    return StrLen(number) >= 4
        ? SubStr(number, 1, 2) "******" SubStr(number, -2)
        : "<afgeschermd>"
}

EscapeSmsJavaScriptString(value) {
    value := StrReplace(value, "\", "\\")
    value := StrReplace(value, "'", "\'")
    value := StrReplace(value, Chr(13), "\r")
    value := StrReplace(value, Chr(10), "\n")
    return value
}

; =============================================================================
; HOTSTRINGS
; =============================================================================

; =============================================================================
; HOTSTRINGPAKKETTEN — BEHEERVENSTER
; =============================================================================

ShowPackageManager(*) {
    global MainGui, C, BundledPackages, BundledPackageDir
    global PackageManagerGui, PackageManagerPackageLV, PackageManagerItemLV
    global PackageManagerStatusText

    if BundledPackages.Count = 0 {
        ; De pakketbron wordt hier expliciet op het scherm getoond (niet
        ; alleen in het standaardlog): dat log schermt lokale/netwerkpaden
        ; altijd af omdat het ongewijzigd in een probleemrapport terecht kan
        ; komen, terwijl dit venster alleen zichtbaar is voor wie al achter
        ; de machine zit. Precies bij nul geladen pakketten is dit pad de
        ; belangrijkste aanwijzing om te controleren.
        MsgBox(
            "Er zijn geen meegeleverde hotstringpakketten beschikbaar.`n`n"
            "Pakketbron: " (BundledPackageDir != "" ? BundledPackageDir : "(onbekend)"),
            "DocBot - Hotstringpakketten",
            "Icon!"
        )
        return
    }

    if IsObject(PackageManagerGui) {
        try {
            PackageManagerGui.Show()
            return
        }
    }

    PackageManagerGui := Gui(
        "+Owner" MainGui.Hwnd " -MaximizeBox -MinimizeBox",
        "DocBot - Hotstringpakketten"
    )
    PackageManagerGui.BackColor := C["Window"]
    PackageManagerGui.SetFont("s10 c" C["Text"], "Segoe UI")
    PackageManagerGui.MarginX := 0
    PackageManagerGui.MarginY := 0

    title := PackageManagerGui.AddText(
        "x24 y18 w500 h34 Background" C["Window"],
        "Hotstringpakketten"
    )
    title.SetFont("s19 bold c" C["Text"], "Segoe UI")

    ; Statische tekst (nooit overschreven door een selectiewijziging, in
    ; tegenstelling tot PackageManagerStatusText hieronder) — vandaar dat de
    ; pakketbron hier staat en niet alleen in het standaardlog, dat
    ; lokale/netwerkpaden altijd afschermt (`docs/DECISIONS.md` D-050).
    intro := PackageManagerGui.AddText(
        "x24 y54 w852 h36 Background" C["Window"],
        "Kies links een pakket en bekijk rechts eerst de inhoud en eventuele conflicten.`n"
        "Pakketbron: " BundledPackageDir
    )
    intro.SetFont("s9 c" C["Muted"], "Segoe UI")

    PackageManagerPackageLV := PackageManagerGui.AddListView(
        "x24 y90 w326 h354 Grid -Multi vPackageManagerPackageList",
        ["Actief", "Pakket", "Items", "ID"]
    )
    PackageManagerPackageLV.ModifyCol(1, 58)
    PackageManagerPackageLV.ModifyCol(2, 205)
    PackageManagerPackageLV.ModifyCol(3, 58)
    PackageManagerPackageLV.ModifyCol(4, 0)
    PackageManagerPackageLV.OnEvent("Click", PackageManagerPackageSelectionChanged)
    PackageManagerPackageLV.OnEvent("DoubleClick", ToggleSelectedPackage)

    PackageManagerItemLV := PackageManagerGui.AddListView(
        "x366 y90 w510 h354 Grid -Multi vPackageManagerItemList",
        ["Status", "Afkorting", "Vervanging", "ID"]
    )
    PackageManagerItemLV.ModifyCol(1, 150)
    PackageManagerItemLV.ModifyCol(2, 105)
    PackageManagerItemLV.ModifyCol(3, 230)
    PackageManagerItemLV.ModifyCol(4, 0)
    PackageManagerItemLV.OnEvent("Click", RefreshPackageManagerItemDetails)
    PackageManagerItemLV.OnEvent("DoubleClick", ToggleSelectedPackageItem)

    PackageManagerStatusText := PackageManagerGui.AddText(
        "x24 y454 w852 h34 Background" C["Window"],
        ""
    )
    PackageManagerStatusText.SetFont("s9 c" C["Muted"], "Segoe UI")

    togglePackageButton := PackageManagerGui.AddButton(
        "x24 y504 w150 h36",
        "Pakket aan/uit"
    )
    toggleItemButton := PackageManagerGui.AddButton(
        "x184 y504 w150 h36",
        "Item aan/uit"
    )
    copyButton := PackageManagerGui.AddButton(
        "x344 y504 w150 h36",
        "Als eigen bewaren"
    )
    preferenceButton := PackageManagerGui.AddButton(
        "x504 y504 w180 h36",
        "Conflictvoorkeur"
    )
    closeButton := PackageManagerGui.AddButton(
        "x726 y504 w150 h36 Default",
        "Sluiten"
    )

    togglePackageButton.OnEvent("Click", ToggleSelectedPackage)
    toggleItemButton.OnEvent("Click", ToggleSelectedPackageItem)
    copyButton.OnEvent("Click", CopySelectedPackageItemToCustom)
    preferenceButton.OnEvent("Click", ToggleSelectedPackageConflictPreference)
    closeButton.OnEvent("Click", ClosePackageManager)
    PackageManagerGui.OnEvent("Close", ClosePackageManager)
    PackageManagerGui.OnEvent("Escape", ClosePackageManager)

    RefreshPackageManagerPackages()
    PackageManagerGui.Show("w900 h564 Center")

    for _, button in [
        togglePackageButton,
        toggleItemButton,
        copyButton,
        preferenceButton,
        closeButton
    ]
        RoundControl(button, 10)
}

ClosePackageManager(*) {
    global PackageManagerGui, PackageManagerPackageLV, PackageManagerItemLV
    global PackageManagerStatusText

    if IsObject(PackageManagerGui)
        try PackageManagerGui.Destroy()

    PackageManagerGui := 0
    PackageManagerPackageLV := 0
    PackageManagerItemLV := 0
    PackageManagerStatusText := 0
}

GetPackageManagerPackageListView() {
    global PackageManagerGui

    if !IsObject(PackageManagerGui)
        return 0
    try return PackageManagerGui["PackageManagerPackageList"]
    return 0
}

GetPackageManagerItemListView() {
    global PackageManagerGui

    if !IsObject(PackageManagerGui)
        return 0
    try return PackageManagerGui["PackageManagerItemList"]
    return 0
}

RefreshPackageManagerPackages(selectPackageId := "", selectItemId := "") {
    global BundledPackages

    ; Gebruik tijdens de hele bewerking één lokale controlreferentie. Deze kan
    ; niet door een tussentijdse GUI-callback of timer worden overschreven.
    packageListView := GetPackageManagerPackageListView()
    if !IsObject(packageListView)
        return

    ; Leg beide stabiele ID's vast vóór Delete(). Een ListView-rij is alleen
    ; een tijdelijke schermpositie en mag nooit als pakket- of item-ID dienen.
    previousItem := GetSelectedPackageManagerItem()
    if selectPackageId = ""
        selectPackageId := GetSelectedPackageManagerPackageId()
    if selectItemId = ""
        && IsObject(previousItem)
        && previousItem["PackageId"] = selectPackageId {
        selectItemId := previousItem["ItemId"]
    }

    packageListView.Delete()

    for packageId, package in BundledPackages {
        packageListView.Add(
            "",
            IsPackageEnabled(packageId) ? "Ja" : "Nee",
            package["name"],
            package["items"].Length,
            packageId
        )
    }

    selectedRow := FindListViewRowById(
        packageListView,
        4,
        selectPackageId
    )
    if selectedRow = 0 && packageListView.GetCount() > 0
        selectedRow := 1
    if selectedRow > 0
        packageListView.Modify(selectedRow, "Select Focus Vis")

    RefreshPackageManagerItems(selectItemId)
}

GetSelectedPackageManagerPackageId() {
    packageListView := GetPackageManagerPackageListView()
    if !IsObject(packageListView)
        return ""

    row := packageListView.GetNext()
    return row > 0 ? packageListView.GetText(row, 4) : ""
}

PackageManagerPackageSelectionChanged(*) {
    RefreshPackageManagerItems()
}

RefreshPackageManagerItems(selectItemId := "") {
    global BundledPackages, PackageManagerStatusText

    ; De globale variabele kan tijdens callbacks opnieuw worden geraakt.
    ; Werk daarom uitsluitend met deze lokale, benoemde GUI-control.
    itemListView := GetPackageManagerItemListView()
    if !IsObject(itemListView)
        return

    packageId := GetSelectedPackageManagerPackageId()
    if packageId = "" || !BundledPackages.Has(packageId) {
        itemListView.Delete()
        if IsObject(PackageManagerStatusText)
            PackageManagerStatusText.Value := "Selecteer links een pakket."
        return
    }

    ; Bewaar de geselecteerde stabiele item-ID als alleen de zichtbare status
    ; wordt ververst. Zo blijven selectie en scrollpositie bij hetzelfde item.
    if selectItemId = "" {
        previousItem := GetSelectedPackageManagerItem()
        if IsObject(previousItem)
            && previousItem["PackageId"] = packageId {
            selectItemId := previousItem["ItemId"]
        }
    }

    ; Bereken alle statussen eerst in het geheugen. GetPackageItemStatus()
    ; doorzoekt voor één item alle persoonlijke hotstrings en alle actieve
    ; pakketten; dat per rij herhalen maakt grote pakketten kwadratisch of
    ; erger en hield de GUI minutenlang bezig.
    statusByItemId := BuildPackageItemStatusMap(packageId)
    package := BundledPackages[packageId]
    rows := []
    for _, item in package["items"] {
        itemId := item["id"]
        rows.Push([
            statusByItemId.Has(itemId)
                ? statusByItemId[itemId]
                : "Inactief",
            item["trigger"],
            item["replacement"],
            itemId
        ])
    }

    ; De gebruiker kan het venster sluiten terwijl de statusindex wordt
    ; opgebouwd. Raak in dat geval de inmiddels vernietigde control niet aan.
    if !IsLiveGuiControl(itemListView)
        return

    ; Vul de ListView als één visuele batch. Dit voorkomt dat Windows na
    ; iedere afzonderlijke Add() de volledige lijst opnieuw tekent.
    itemListView.Opt("-Redraw")
    try {
        itemListView.Delete()
        for _, rowValues in rows {
            if !IsLiveGuiControl(itemListView)
                return
            itemListView.Add(
                "",
                rowValues[1],
                rowValues[2],
                rowValues[3],
                rowValues[4]
            )
        }

        selectedRow := FindListViewRowById(
            itemListView,
            4,
            selectItemId
        )
        if selectedRow = 0 && itemListView.GetCount() > 0
            selectedRow := 1
        if selectedRow > 0
            itemListView.Modify(selectedRow, "Select Focus Vis")
    } finally {
        if IsLiveGuiControl(itemListView)
            itemListView.Opt("+Redraw")
    }

    if IsLiveGuiControl(itemListView)
        RefreshPackageManagerItemDetails()
}

GetSelectedPackageManagerItem() {
    packageId := GetSelectedPackageManagerPackageId()
    itemListView := GetPackageManagerItemListView()

    if packageId = "" || !IsObject(itemListView)
        return 0

    row := itemListView.GetNext()
    if row = 0
        return 0

    itemId := itemListView.GetText(row, 4)
    if itemId = ""
        return 0

    return Map(
        "PackageId", packageId,
        "ItemId", itemId
    )
}

FindListViewRowById(listView, idColumn, stableId) {
    if !IsObject(listView) || stableId = ""
        return 0

    Loop listView.GetCount() {
        if listView.GetText(A_Index, idColumn) = stableId
            return A_Index
    }
    return 0
}

CreateBundledRuntimeItem(packageId, itemId) {
    global BundledPackages

    packageItem := FindBundledPackageItem(packageId, itemId)
    if !IsObject(packageItem) || !BundledPackages.Has(packageId)
        return 0

    package := BundledPackages[packageId]
    return CreateHotstringItem(
        packageItem["trigger"],
        packageItem["replacement"],
        "Pakket: " package["name"],
        true,
        DefaultHotstringOptions(),
        "package-" packageId "-" itemId,
        Map(
            "Type", "package",
            "PackageId", packageId,
            "ItemId", itemId,
            "PackageVersion", package["version"]
        )
    )
}

FindPackageItemConflict(packageId, itemId) {
    global Hotstrings, BundledPackages

    packageRuntimeItem := CreateBundledRuntimeItem(packageId, itemId)
    if !IsObject(packageRuntimeItem)
        return 0

    identity := BuildHotstringIdentity(packageRuntimeItem)

    for _, rawCustom in Hotstrings {
        custom := NormalizeHotstringItem(rawCustom)
        if BuildHotstringIdentity(custom) = identity {
            return Map(
                "Type", "custom",
                "Id", custom["Id"],
                "Label", custom["Trigger"]
            )
        }
    }

    for otherPackageId, otherPackage in BundledPackages {
        if otherPackageId = packageId || !IsPackageEnabled(otherPackageId)
            continue

        for _, otherItem in otherPackage["items"] {
            if IsPackageItemDisabled(otherPackageId, otherItem["id"])
                continue
            if otherItem.Has("enabledByDefault") && !otherItem["enabledByDefault"]
                continue

            otherRuntimeItem := CreateBundledRuntimeItem(
                otherPackageId,
                otherItem["id"]
            )
            if IsObject(otherRuntimeItem)
                && BuildHotstringIdentity(otherRuntimeItem) = identity {
                return Map(
                    "Type", "package",
                    "Id", otherItem["id"],
                    "PackageId", otherPackageId,
                    "Label", otherPackage["name"]
                )
            }
        }
    }

    return 0
}

IsLiveGuiControl(control) {
    if !IsObject(control)
        return false

    try return DllCall("IsWindow", "ptr", control.Hwnd, "int") != 0
    return false
}

BuildBundledPackageItemIdentity(packageItem) {
    ; Meegeleverde pakketitems gebruiken dezelfde standaardopties als
    ; CreateBundledRuntimeItem(). Daardoor kan de identiteit direct uit het
    ; reeds beschikbare item worden opgebouwd, zonder opnieuw lineair in het
    ; pakket naar datzelfde item te zoeken.
    return BuildHotstringIdentity(
        CreateHotstringItem(
            packageItem["trigger"],
            packageItem["replacement"],
            "",
            true,
            DefaultHotstringOptions()
        )
    )
}

BuildPackageItemStatusMap(packageId) {
    global Hotstrings, BundledPackages

    statuses := Map()
    if packageId = "" || !BundledPackages.Has(packageId)
        return statuses

    package := BundledPackages[packageId]
    if !IsPackageEnabled(packageId) {
        for _, item in package["items"]
            statuses[item["id"]] := "Inactief"
        return statuses
    }

    ; Eén index voor persoonlijke hotstrings. Bij dubbele identiteiten blijft
    ; net als in FindPackageItemConflict() de eerste persoonlijke hotstring
    ; bepalend.
    customByIdentity := Map()
    for _, rawCustom in Hotstrings {
        custom := NormalizeHotstringItem(rawCustom)
        identity := BuildHotstringIdentity(custom)
        if !customByIdentity.Has(identity)
            customByIdentity[identity] := custom
    }

    ; Eén set met identiteiten uit alle andere actieve pakketten. De dure
    ; geneste zoekactie hoeft zo niet voor iedere zichtbare rij opnieuw.
    packageConflictIdentities := Map()
    for otherPackageId, otherPackage in BundledPackages {
        if otherPackageId = packageId || !IsPackageEnabled(otherPackageId)
            continue

        for _, otherItem in otherPackage["items"] {
            if IsPackageItemDisabled(otherPackageId, otherItem["id"])
                continue
            if otherItem.Has("enabledByDefault")
                && !otherItem["enabledByDefault"]
                continue

            identity := BuildBundledPackageItemIdentity(otherItem)
            packageConflictIdentities[identity] := true
        }
    }

    for _, item in package["items"] {
        itemId := item["id"]
        if IsPackageItemDisabled(packageId, itemId) {
            statuses[itemId] := "Inactief"
            continue
        }

        identity := BuildBundledPackageItemIdentity(item)
        if customByIdentity.Has(identity) {
            custom := customByIdentity[identity]
            statuses[itemId] := PackageChoiceUsesPackage(
                custom["Id"],
                packageId,
                itemId
            ) ? "Voorrang" : "Overruled"
        } else if packageConflictIdentities.Has(identity) {
            statuses[itemId] := "Conflict"
        } else {
            statuses[itemId] := "Actief"
        }
    }

    return statuses
}

GetPackageItemStatus(packageId, itemId) {
    if !IsPackageEnabled(packageId)
        return "Inactief"
    if IsPackageItemDisabled(packageId, itemId)
        return "Inactief"

    conflict := FindPackageItemConflict(packageId, itemId)
    if !IsObject(conflict)
        return "Actief"

    if conflict["Type"] = "package"
        return "Conflict"

    return PackageChoiceUsesPackage(
        conflict["Id"],
        packageId,
        itemId
    ) ? "Voorrang" : "Overruled"
}

RefreshPackageManagerItemDetails(*) {
    global BundledPackages, PackageManagerStatusText

    ; De gebruiker kan het venster sluiten terwijl GetPackageItemStatus()/
    ; FindPackageItemConflict() voor een groot pakket nog aan het rekenen
    ; is (zie dezelfde opmerking bij RefreshPackageManagerItems()). Toets
    ; daarom niet alleen bij binnenkomst, maar ook vlak vóór iedere
    ; schrijfactie opnieuw of de control nog bestaat.
    if !IsLiveGuiControl(PackageManagerStatusText)
        return

    selected := GetSelectedPackageManagerItem()
    if !IsObject(selected) {
        if IsLiveGuiControl(PackageManagerStatusText)
            PackageManagerStatusText.Value := "Selecteer een pakketitem."
        return
    }

    packageId := selected["PackageId"]
    itemId := selected["ItemId"]
    package := BundledPackages[packageId]
    packageItem := FindBundledPackageItem(packageId, itemId)
    conflict := FindPackageItemConflict(packageId, itemId)

    status := GetPackageItemStatus(packageId, itemId)
    packageOwner := package.Has("owner") ? Trim(package["owner"] "") : ""
    ownerSuffix := packageOwner != "" ? " (eigenaar: " packageOwner ")" : ""
    detail := package["name"] ownerSuffix " · " status

    switch status {
        case "Inactief":
            detail .= !IsPackageEnabled(packageId)
                ? " · pakket uitgeschakeld"
                : " · item handmatig uitgeschakeld"
            ; Een uitgeschakeld item kan daarnaast nog steeds dezelfde
            ; afkorting hebben als een persoonlijke hotstring of ander pakket.
            if IsObject(conflict) {
                detail .= conflict["Type"] = "custom"
                    ? " · persoonlijke hotstring met dezelfde afkorting"
                    : " · ook aanwezig in " conflict["Label"]
            }
        case "Overruled":
            detail .= " · persoonlijke hotstring heeft voorrang"
        case "Voorrang":
            detail .= " · pakketitem heeft voorrang op persoonlijke hotstring"
        case "Conflict":
            if IsObject(conflict)
                detail .= " · ook aanwezig in " conflict["Label"]
    }

    if packageItem.Has("note") && Trim(packageItem["note"]) != ""
        detail .= " · " packageItem["note"]

    if IsLiveGuiControl(PackageManagerStatusText)
        PackageManagerStatusText.Value := detail
}

ToggleSelectedPackage(*) {
    selectedPackageId := GetSelectedPackageManagerPackageId()
    if selectedPackageId = "" {
        MsgBox(
            "Selecteer eerst een pakket.",
            "DocBot - Hotstringpakketten",
            "Iconi"
        )
        return
    }

    SetPackageEnabled(
        selectedPackageId,
        !IsPackageEnabled(selectedPackageId)
    )
    RefreshPackageManagerPackages(selectedPackageId)
}

ToggleSelectedPackageItem(*) {
    selected := GetSelectedPackageManagerItem()
    if !IsObject(selected) {
        MsgBox(
            "Selecteer eerst een pakketitem.",
            "DocBot - Hotstringpakketten",
            "Iconi"
        )
        return
    }

    packageId := selected["PackageId"]
    itemId := selected["ItemId"]
    SetPackageItemEnabled(
        packageId,
        itemId,
        IsPackageItemDisabled(packageId, itemId)
    )
    RefreshPackageManagerPackages(packageId, itemId)
}

CopySelectedPackageItemToCustom(*) {
    selected := GetSelectedPackageManagerItem()
    if !IsObject(selected) {
        MsgBox(
            "Selecteer eerst een pakketitem.",
            "DocBot - Hotstringpakketten",
            "Iconi"
        )
        return
    }

    packageId := selected["PackageId"]
    itemId := selected["ItemId"]
    conflict := FindPackageItemConflict(packageId, itemId)

    if IsObject(conflict) && conflict["Type"] = "custom" {
        MsgBox(
            "Er bestaat al een persoonlijke hotstring met deze afkorting.",
            "DocBot - Hotstringpakketten",
            "Iconi"
        )
        return
    }

    customId := PromotePackageItemToCustom(packageId, itemId)
    if customId = "" {
        MsgBox(
            "Het pakketitem kon niet als persoonlijke hotstring worden opgeslagen.",
            "DocBot - Hotstringpakketten",
            "Icon!"
        )
        return
    }

    RefreshPackageManagerPackages(packageId, itemId)
    ShowNotification(
        "Het pakketitem is als persoonlijke hotstring opgeslagen.",
        3500
    )
}

ToggleSelectedPackageConflictPreference(*) {
    selected := GetSelectedPackageManagerItem()
    if !IsObject(selected) {
        MsgBox(
            "Selecteer eerst een pakketitem.",
            "DocBot - Hotstringpakketten",
            "Iconi"
        )
        return
    }

    packageId := selected["PackageId"]
    itemId := selected["ItemId"]
    conflict := FindPackageItemConflict(packageId, itemId)

    if !IsObject(conflict) || conflict["Type"] != "custom" {
        MsgBox(
            "Dit item heeft geen conflict met een persoonlijke hotstring.",
            "DocBot - Hotstringpakketten",
            "Iconi"
        )
        return
    }

    usePackage := !PackageChoiceUsesPackage(
        conflict["Id"],
        packageId,
        itemId
    )

    if usePackage {
        if !IsPackageEnabled(packageId)
            SetPackageEnabled(packageId, true)
        if IsPackageItemDisabled(packageId, itemId)
            SetPackageItemEnabled(packageId, itemId, true)
    }

    SetPackageConflictChoice(
        conflict["Id"],
        packageId,
        itemId,
        usePackage ? "package" : "custom"
    )
    RefreshPackageManagerPackages(packageId, itemId)
}

SetControlGroupVisible(group, visible) {
    if !IsObject(group)
        return
    for _, control in group
        control.Opt(visible ? "-Hidden" : "+Hidden")
}
BuildReplacementPreview(value, maxLength := 140) {
    preview := StrReplace(value, Chr(13) Chr(10), " · ")
    preview := StrReplace(preview, Chr(10), " · ")
    preview := StrReplace(preview, Chr(13), " · ")
    return StrLen(preview) > maxLength ? SubStr(preview, 1, maxLength - 1) "…" : preview
}
UpdateHotReplacementDraft(control, *) {
    global HotReplacementDraft, HotReplacementSingleGroup, HotReplacementSingleIsPreview
    HotReplacementDraft := control.Value
    if IsObject(HotReplacementSingleGroup) && control.Hwnd = HotReplacementSingleGroup["Edit"].Hwnd
        HotReplacementSingleIsPreview := false
}
SetHotReplacementValue(value, autoExpand := true) {
    global HotReplacementDraft, HotReplacementSingleGroup, HotReplacementMultiGroup, HotReplacementSingleIsPreview
    HotReplacementDraft := value
    multi := InStr(value, Chr(10)) || InStr(value, Chr(13))
    HotReplacementSingleIsPreview := multi
    HotReplacementSingleGroup["Edit"].Value := multi ? BuildReplacementPreview(value, 500) : value
    HotReplacementMultiGroup["Edit"].Value := value
    SetHotReplacementEditorExpanded(autoExpand && multi)
}
GetHotReplacementValue() {
    global HotReplacementDraft, HotReplacementExpanded, HotReplacementSingleGroup, HotReplacementMultiGroup, HotReplacementSingleIsPreview
    if HotReplacementExpanded
        HotReplacementDraft := HotReplacementMultiGroup["Edit"].Value
    else if !HotReplacementSingleIsPreview
        HotReplacementDraft := HotReplacementSingleGroup["Edit"].Value
    return HotReplacementDraft
}
ToggleHotReplacementEditor(expanded, *) {
    global HotReplacementDraft, HotReplacementSingleGroup, HotReplacementMultiGroup, HotReplacementSingleIsPreview
    if expanded {
        if !HotReplacementSingleIsPreview
            HotReplacementDraft := HotReplacementSingleGroup["Edit"].Value
        HotReplacementMultiGroup["Edit"].Value := HotReplacementDraft
    } else {
        HotReplacementDraft := HotReplacementMultiGroup["Edit"].Value
        multi := InStr(HotReplacementDraft, Chr(10)) || InStr(HotReplacementDraft, Chr(13))
        HotReplacementSingleIsPreview := multi
        HotReplacementSingleGroup["Edit"].Value := multi ? BuildReplacementPreview(HotReplacementDraft, 500) : HotReplacementDraft
    }
    SetHotReplacementEditorExpanded(expanded)
}
SetHotReplacementEditorExpanded(expanded) {
    global HotReplacementExpanded
    HotReplacementExpanded := expanded ? true : false
    ApplyHotReplacementEditorState()
}
ApplyHotReplacementEditorState() {
    global CurrentPage, StorageAllReady, HotReplacementExpanded, HotReplacementSingleGroup, HotReplacementMultiGroup
    global HotReplacementExpandButton, HotReplacementCollapseButton, HotEditorCompactCard, HotEditorExpandedCard, HotSaveButton
    if !IsObject(HotReplacementSingleGroup)
        return
    ; StorageAllReady moet hier ook gelden: dit overschrijft anders de
    ; hide-while-degraded-gate die ShowPage() vlak hiervoor al toepaste op
    ; dezelfde besturingselementen (zie MarkDegradedGateStart/End rond de
    ; Hotstrings-editorkaart) en toont het formulier weer terwijl opslag nog
    ; niet klaar is — in strijd met docs/DECISIONS.md D-064.
    visible := CurrentPage = "tekstvervanging" && StorageAllReady
    SetControlGroupVisible(HotReplacementSingleGroup, visible && !HotReplacementExpanded)
    SetControlGroupVisible(HotReplacementMultiGroup, visible && HotReplacementExpanded)
    HotEditorCompactCard.Opt(visible && !HotReplacementExpanded ? "-Hidden" : "+Hidden")
    HotEditorExpandedCard.Opt(visible && HotReplacementExpanded ? "-Hidden" : "+Hidden")
    HotReplacementExpandButton.Opt(visible && !HotReplacementExpanded ? "-Hidden" : "+Hidden")
    HotReplacementCollapseButton.Opt(visible && HotReplacementExpanded ? "-Hidden" : "+Hidden")
    ; Opslaan staat sinds de bodemuitlijning met Telefonie/Over op een vaste
    ; positie (y=602) die in zowel de compacte als de uitgeklapte kaart past,
    ; dus hoeft hier niet meer te verspringen.
}

RefreshHotstringList(selectItemId := "", *) {
    global Hotstrings, HotLV, HotSearch

    if !IsObject(HotLV)
        return

    ; Een Change-event geeft het Edit-control als eerste argument door.
    ; Gebruik dat nooit als ID, maar behoud bij verversen de huidige selectie.
    if IsObject(selectItemId)
        selectItemId := ""
    if selectItemId = ""
        selectItemId := GetSelectedHotstringId()

    HotLV.Delete()
    filter := StrLower(Trim(HotSearch.Value))

    for _, rawItem in Hotstrings {
        item := NormalizeHotstringItem(rawItem)
        searchable := StrLower(item["Trigger"] " " item["Replacement"])

        if filter != "" && !InStr(searchable, filter)
            continue

        HotLV.Add(
            "",
            item["Enabled"] ? "Ja" : "Nee",
            item["Trigger"],
            BuildReplacementPreview(item["Replacement"]),
            BuildHotstringFlags(item),
            item["Id"]
        )
    }

    selectedRow := FindListViewRowById(HotLV, 5, selectItemId)
    if selectedRow > 0
        HotLV.Modify(selectedRow, "Select Focus Vis")
}

GetSelectedHotstringId() {
    global HotLV

    if !IsObject(HotLV)
        return ""

    row := HotLV.GetNext()
    return row > 0 ? HotLV.GetText(row, 5) : ""
}

FindHotstringIndexById(itemId) {
    global Hotstrings

    if itemId = ""
        return 0

    for index, rawItem in Hotstrings {
        item := NormalizeHotstringItem(rawItem)
        if item["Id"] = itemId
            return index
    }
    return 0
}

GetSelectedHotstringIndex() {
    return FindHotstringIndexById(GetSelectedHotstringId())
}

FillHotstringFormFromSelection(*) {
    global Hotstrings, HotEnabledCheck, HotTriggerEdit, HotOptionDraft
    index := GetSelectedHotstringIndex()
    if index = 0
        return
    item := NormalizeHotstringItem(Hotstrings[index])
    HotEnabledCheck.Value := item["Enabled"]
    HotTriggerEdit.Value := item["Trigger"]
    SetHotReplacementValue(item["Replacement"], true)
    HotOptionDraft := CopyHotstringOptions(item["Options"])
}
NewHotstring(*) {
    global HotLV, HotEnabledCheck, HotTriggerEdit, HotOptionDraft
    HotLV.Modify(0, "-Select")
    HotEnabledCheck.Value := 1
    HotTriggerEdit.Value := ""
    SetHotReplacementValue("", false)
    HotOptionDraft := DefaultHotstringOptions()
    HotTriggerEdit.Focus()
}

EditSelectedHotstring(*) {
    if GetSelectedHotstringIndex() = 0 {
        MsgBox("Selecteer eerst een hotstring.", "DocBot", "Iconi")
        return
    }

    FillHotstringFormFromSelection()
}

SaveHotstringFromForm(*) {
    global Hotstrings
    global HotEnabledCheck, HotTriggerEdit
    global HotOptionDraft

    trigger := Trim(HotTriggerEdit.Value)
    replacement := GetHotReplacementValue()

    if trigger = "" {
        MsgBox("Vul eerst een afkorting in.", "DocBot", "Icon!")
        return
    }

    if Trim(replacement) = "" {
        MsgBox("Vul eerst een vervanging in.", "DocBot", "Icon!")
        return
    }

    existingIndex := GetSelectedHotstringIndex()
    existingId := ""
    existingOrigin := 0
    if existingIndex > 0 {
        existingItem := NormalizeHotstringItem(Hotstrings[existingIndex])
        existingId := existingItem["Id"]
        existingOrigin := existingItem["Origin"]
    }

    item := CreateHotstringItem(
        trigger,
        replacement,
        "",
        HotEnabledCheck.Value = 1,
        HotOptionDraft,
        existingId,
        existingOrigin
    )

    if existingIndex > 0
        Hotstrings[existingIndex] := item
    else
        Hotstrings.Push(item)

    RefreshHotstringList(item["Id"])
    ReloadRuntimeHotstrings(true)
    AutoSaveHotstrings()
}

DeleteSelectedHotstring(*) {
    global Hotstrings
    global PackageSettings, DefaultPackageSettingsFile

    index := GetSelectedHotstringIndex()
    if index = 0 {
        MsgBox("Selecteer eerst een hotstring.", "DocBot", "Iconi")
        return
    }

    trigger := Hotstrings[index]["Trigger"]

    if MsgBox("Hotstring '" trigger "' verwijderen?", "DocBot", "YesNo Icon!") = "Yes" {
        Hotstrings.RemoveAt(index)
        PackageSettings := ReconcilePackageSettings(PackageSettings)
        SavePackageSettingsToJson(DefaultPackageSettingsFile)
        RefreshHotstringList()
        ReloadRuntimeHotstrings(true)
        AutoSaveHotstrings()
    }
}

; =============================================================================
; DYNAMISCHE HOTSTRING-UITVOER
; =============================================================================

ReloadRuntimeHotstrings(showErrors := false) {
    global RuntimeHotstrings, State, ProblemReportSession

    UnregisterRuntimeHotstrings()

    if !State["TextReplacement"]
        return true

    errors := []
    effectiveHotstrings := BuildEffectiveHotstrings()

    for index, item in effectiveHotstrings {

        if !item["Enabled"]
            continue

        trigger := Trim(item["Trigger"])
        replacement := item["Replacement"]

        if trigger = "" || replacement = ""
            continue

        hotstringSpec := BuildRuntimeHotstringSpec(item)

        try {
            mode := GetHotstringInsertionMode(item)
            if mode = "direct-text" {
                callback := SendHotstringText.Bind(trigger, replacement)
                Hotstring(hotstringSpec, callback, true)
                RuntimeHotstrings[hotstringSpec] := callback
            } else if mode = "dynamic-text" {
                callback := SendDynamicHotstringText.Bind(trigger, replacement)
                Hotstring(hotstringSpec, callback, true)
                RuntimeHotstrings[hotstringSpec] := callback
            } else if mode = "dynamic-keys" {
                callback := SendDynamicHotstringKeys.Bind(trigger, replacement)
                Hotstring(hotstringSpec, callback, true)
                RuntimeHotstrings[hotstringSpec] := callback
            } else if mode = "keys" && ProblemReportSession["ExtendedActive"] {
                callback := SendDiagnosticHotstringKeys.Bind(trigger, replacement)
                Hotstring(hotstringSpec, callback, true)
                RuntimeHotstrings[hotstringSpec] := callback
            } else if mode = "normal" && ProblemReportSession["ExtendedActive"] {
                callback := SendDiagnosticHotstringText.Bind(trigger, replacement)
                Hotstring(hotstringSpec, callback, true)
                RuntimeHotstrings[hotstringSpec] := callback
            } else {
                Hotstring(hotstringSpec, replacement, true)
                RuntimeHotstrings[hotstringSpec] := replacement
            }
        } catch as error {
            errors.Push(
                Format(
                    "{1}. {2}: {3}",
                    index,
                    trigger,
                    error.Message
                )
            )
        }
    }

    if errors.Length = 0
        return true

    message := "Niet alle hotstrings konden worden geactiveerd:`n`n" . JoinText(errors, "`n")

    if showErrors
        MsgBox(message, "DocBot - Hotstrings", "Icon!")
    else
        ShowNotification(message, 5000, "error")

    return false
}

GetHotstringInsertionMode(item) {
    item := NormalizeHotstringItem(item)
    replacement := item["Replacement"]
    options := item["Options"]
    hasDynamicCodes := HasDynamicHotstringCodes(replacement)
    keyCommandProbe := StrReplace(replacement, "{{datum}}", "")
    keyCommandProbe := StrReplace(keyCommandProbe, "{{tijd}}", "")

    ; Expliciete AHK-toetsopdrachten blijven door de normale hotstring-engine
    ; verwerkt worden. Dynamische codes worden vlak voor de Send-opdracht
    ; ingevuld, zodat datum en tijd actueel zijn.
    if !options["SendRaw"] && !options["TextRaw"] && RegExMatch(keyCommandProbe, "\{[^{}]+\}")
        return hasDynamicCodes ? "dynamic-keys" : "keys"

    if hasDynamicCodes
        return "dynamic-text"

    ; Een callback voorkomt dat lange of meerregelige tekst via het klembord
    ; hoeft te worden geplakt. Korte enkelregelige tekst blijft de efficiënte
    ; ingebouwde hotstringvervanging gebruiken.
    if IsLongOrMultilineHotstring(replacement)
        return "direct-text"

    return "normal"
}

HasDynamicHotstringCodes(replacement) {
    return InStr(replacement, "{{datum}}")
        || InStr(replacement, "{{tijd}}")
}

ExpandDynamicHotstringCodes(replacement) {
    timestamp := A_Now
    expanded := StrReplace(
        replacement,
        "{{datum}}",
        FormatTime(timestamp, "dd-MM-yyyy")
    )
    return StrReplace(
        expanded,
        "{{tijd}}",
        FormatTime(timestamp, "HH:mm")
    )
}

IsLongOrMultilineHotstring(replacement) {
    global DirectTextReplacementThreshold

    return InStr(replacement, Chr(10))
        || InStr(replacement, Chr(13))
        || StrLen(replacement) >= DirectTextReplacementThreshold
}

SendHotstringText(trigger, replacement, *) {
    LogExtendedHotstringExecution(trigger, replacement, "tekst")
    Telemetry_RecordLongHotstring()
    RefreshUsageStatistics()
    SendPlainHotstringText(replacement)
}

SendDynamicHotstringText(trigger, replacement, *) {
    expanded := ExpandDynamicHotstringCodes(replacement)
    LogExtendedHotstringExecution(trigger, expanded, "dynamische tekst")

    if IsLongOrMultilineHotstring(expanded) {
        Telemetry_RecordLongHotstring()
        RefreshUsageStatistics()
    }

    SendPlainHotstringText(expanded)
}

SendDynamicHotstringKeys(trigger, replacement, *) {
    expanded := ExpandDynamicHotstringCodes(replacement)
    LogExtendedHotstringExecution(trigger, expanded, "dynamische toetsen")
    Send(expanded)
}

SendDiagnosticHotstringText(trigger, replacement, *) {
    LogExtendedHotstringExecution(trigger, replacement, "korte tekst")
    SendPlainHotstringText(replacement)
}

SendDiagnosticHotstringKeys(trigger, replacement, *) {
    LogExtendedHotstringExecution(trigger, replacement, "toetsen")
    Send(replacement)
}

LogExtendedHotstringExecution(trigger, replacement, insertionMode) {
    ExtendedDebugLog(
        "→",
        "Hotstring uitgevoerd",
        "Modus: " insertionMode
            . "`r`nAfkorting: " trigger
            . "`r`nVervangtekst:`r`n" replacement
    )
}

SendPlainHotstringText(replacement) {
    ; SendText verstuurt gewone Unicode-tekst zonder AHK-toetsopdrachten te
    ; interpreteren. Regeleinden worden afzonderlijk als Enter uitgevoerd,
    ; zodat ook programma's die een letterlijke LF niet accepteren correct
    ; meerregelige invoer ontvangen.
    normalized := StrReplace(replacement, "`r`n", "`n")
    normalized := StrReplace(normalized, "`r", "`n")
    startPos := 1

    while lineBreakPos := InStr(normalized, "`n", , startPos) {
        if lineBreakPos > startPos
            SendText(SubStr(normalized, startPos, lineBreakPos - startPos))
        Send("{Enter}")
        startPos := lineBreakPos + 1
    }

    if startPos <= StrLen(normalized)
        SendText(SubStr(normalized, startPos))
}

UnregisterRuntimeHotstrings() {
    global RuntimeHotstrings

    for hotstringSpec, _ in RuntimeHotstrings {
        try Hotstring(hotstringSpec, , false)
    }

    RuntimeHotstrings := Map()
}

BuildRuntimeHotstringSpec(item) {
    item := NormalizeHotstringItem(item)
    options := item["Options"]
    flags := ""

    if options["NoEndChar"]
        flags .= "*"

    ; C en C1 zijn twee varianten van dezelfde case-instelling en worden
    ; daarom niet tegelijk toegepast.
    if options["CaseSensitive"]
        flags .= "C"
    else if options["NoConformCase"]
        flags .= "C1"

    if options["TriggerInside"]
        flags .= "?"
    if options["NoAutoBack"]
        flags .= "B0"
    if options["OmitEndChar"]
        flags .= "O"
    if options["SendRaw"]
        flags .= "R"
    if options["TextRaw"]
        flags .= "T"

    return ":" flags ":" item["Trigger"]
}

; =============================================================================
; GEAVANCEERDE HOTSTRINGOPTIES EN JSON-VRIENDELIJK MODEL
; =============================================================================

DefaultPersonalHotstrings() {
    global LocalConfig

    defaults := []
    for _, configuredItem in LocalConfig["DefaultHotstrings"] {
        defaults.Push(
            CreateHotstringItem(
                configuredItem["Trigger"],
                configuredItem["Replacement"],
                "",
                configuredItem.Has("Enabled") ? !!configuredItem["Enabled"] : true,
                configuredItem.Has("Options") ? configuredItem["Options"] : DefaultHotstringOptions(),
                configuredItem.Has("Id") ? configuredItem["Id"] : ""
            )
        )
    }
    return defaults
}

AddMissingDefaultHotstrings(items) {
    existingTriggers := Map()
    for _, rawItem in items {
        item := NormalizeHotstringItem(rawItem)
        existingTriggers[StrLower(Trim(item["Trigger"]))] := true
    }

    added := 0
    for _, defaultItem in DefaultPersonalHotstrings() {
        triggerKey := StrLower(Trim(defaultItem["Trigger"]))
        if existingTriggers.Has(triggerKey)
            continue
        items.Push(defaultItem)
        existingTriggers[triggerKey] := true
        added += 1
    }
    return added
}

DefaultHotstringOptions() {
    return Map(
        "NoEndChar", false,       ; *
        "CaseSensitive", false,   ; C
        "TriggerInside", false,   ; ?
        "NoConformCase", false,   ; C1
        "NoAutoBack", false,      ; B0
        "OmitEndChar", false,     ; O
        "SendRaw", false,         ; R
        "TextRaw", false          ; T
    )
}

CreateHotstringItem(
    trigger,
    replacement,
    note := "",
    enabled := true,
    options := 0,
    id := "",
    origin := 0
) {
    if !IsObject(options)
        options := DefaultHotstringOptions()
    if Trim(id) = ""
        id := CreateCustomHotstringId()

    return Map(
        "Id", id,
        "Enabled", enabled,
        "Trigger", trigger,
        "Replacement", replacement,
        "Options", CopyHotstringOptions(options),
        "Origin", NormalizeHotstringOrigin(origin)
    )
}

CreateCustomHotstringId() {
    static sequence := 0
    sequence += 1
    return Format(
        "custom-{1}-{2:06}-{3}",
        FormatTime(, "yyyyMMddHHmmss"),
        Random(0, 999999),
        sequence
    )
}

NormalizeHotstringOrigin(origin) {
    if !(origin is Map) || !origin.Has("Type") || origin["Type"] != "package"
        return Map("Type", "custom")

    return Map(
        "Type", "package",
        "PackageId", origin.Has("PackageId") ? origin["PackageId"] : "",
        "ItemId", origin.Has("ItemId") ? origin["ItemId"] : "",
        "PackageVersion", origin.Has("PackageVersion") ? origin["PackageVersion"] : ""
    )
}

NormalizeHotstringItem(item) {
    normalized := CreateHotstringItem(
        item.Has("Trigger") ? item["Trigger"] : "",
        item.Has("Replacement") ? item["Replacement"] : "",
        "",
        item.Has("Enabled") ? item["Enabled"] : true,
        item.Has("Options") ? item["Options"] : DefaultHotstringOptions(),
        item.Has("Id") ? item["Id"] : "",
        item.Has("Origin") ? item["Origin"] : 0
    )
    if item.Has("ActionType") && item["ActionType"] = "execute"
        normalized["Enabled"] := false
    return normalized
}

CopyHotstringOptions(source) {
    result := DefaultHotstringOptions()

    if !IsObject(source)
        return result

    for key, defaultValue in result {
        if source.Has(key)
            result[key] := source[key] = true || source[key] = 1
    }

    return result
}

BuildHotstringDocument() {
    global Hotstrings, HotstringSchemaVersion

    items := []
    for _, item in Hotstrings
        items.Push(NormalizeHotstringItem(item))

    return Map(
        "schemaVersion", HotstringSchemaVersion,
        "hotstrings", items
    )
}

BuildHotstringFlags(item) {
    item := NormalizeHotstringItem(item)
    options := item["Options"]
    flags := []

    if options["NoEndChar"]
        flags.Push("*")
    if options["CaseSensitive"]
        flags.Push("C")
    if options["TriggerInside"]
        flags.Push("?")
    if options["NoConformCase"]
        flags.Push("C1")
    if options["NoAutoBack"]
        flags.Push("B0")
    if options["OmitEndChar"]
        flags.Push("O")
    if options["SendRaw"]
        flags.Push("R")
    if options["TextRaw"]
        flags.Push("T")
    return JoinText(flags, " ")
}

JoinText(values, separator := " ") {
    result := ""

    for index, value in values
        result .= (index > 1 ? separator : "") value

    return result
}

ShowAdvancedHotstringOptions(*) {
    global MainGui, C
    global HotOptionDraft

    dlg := Gui(
        "+Owner" MainGui.Hwnd " -MaximizeBox -MinimizeBox",
        "DocBot - Geavanceerde hotstringopties"
    )
    dlg.BackColor := C["Window"]
    dlg.SetFont("s10 c" C["Text"], "Segoe UI")

    heading := dlg.AddText(
        "x24 y18 w560 h30 Background" C["Window"],
        "Geavanceerde hotstringopties"
    )
    heading.SetFont("s16 bold c" C["Text"], "Segoe UI")

    explanation := dlg.AddText(
        "x24 y50 w560 h34 Background" C["Window"],
        "Deze opties bepalen hoe AutoHotkey de tekstvervanging activeert en verstuurt."
    )
    explanation.SetFont("s9 c" C["Muted"], "Segoe UI")

    optionsCard := dlg.AddText("x24 y94 w552 h222 Background" C["Card"], "")
    RoundControl(optionsCard, 16)

    optionTitle := dlg.AddText(
        "x44 y112 w220 h22 Background" C["Card"],
        "AutoHotkey-opties"
    )
    optionTitle.SetFont("s12 bold c" C["Text"], "Segoe UI")

    checks := Map()

    checks["NoEndChar"] := dlg.AddCheckbox(
        "x44 y150 w230 h22 Background" C["Card"],
        "Geen eindkarakter (*)"
    )
    checks["CaseSensitive"] := dlg.AddCheckbox(
        "x44 y182 w230 h22 Background" C["Card"],
        "Case sensitive (C)"
    )
    checks["TriggerInside"] := dlg.AddCheckbox(
        "x44 y214 w230 h22 Background" C["Card"],
        "Trigger binnen ander woord (?)"
    )
    checks["NoAutoBack"] := dlg.AddCheckbox(
        "x44 y246 w245 h22 Background" C["Card"],
        "Afkorting niet verwijderen (B0)"
    )

    checks["NoConformCase"] := dlg.AddCheckbox(
        "x302 y150 w240 h22 Background" C["Card"],
        "Volg niet getypte case (C1)"
    )
    checks["OmitEndChar"] := dlg.AddCheckbox(
        "x302 y182 w240 h22 Background" C["Card"],
        "Sla laatste karakter over (O)"
    )
    checks["SendRaw"] := dlg.AddCheckbox(
        "x302 y214 w240 h22 Background" C["Card"],
        "Stuur raw (R)"
    )
    checks["TextRaw"] := dlg.AddCheckbox(
        "x302 y246 w240 h22 Background" C["Card"],
        "Stuur tekst raw (T)"
    )

    for key, control in checks
        control.Value := HotOptionDraft[key]

    cancelButton := dlg.AddButton("x302 y336 w128 h36", "Annuleren")
    saveButton := dlg.AddButton("x448 y336 w128 h36 Default", "Toepassen")

    cancelButton.OnEvent("Click", (*) => dlg.Destroy())
    saveButton.OnEvent(
        "Click",
        SaveAdvancedHotstringOptions.Bind(dlg, checks)
    )

    dlg.OnEvent("Escape", (*) => dlg.Destroy())
    dlg.Show("w600 h396 Center")
}

SaveAdvancedHotstringOptions(dialog, checks, *) {
    global HotOptionDraft

    HotOptionDraft := DefaultHotstringOptions()

    for key, control in checks
        HotOptionDraft[key] := control.Value = 1

    dialog.Destroy()
}

; =============================================================================
; INSTELLINGEN
; =============================================================================

BrowseHotstringFile(pathEdit, *) {
    selected := FileSelect("S16", pathEdit.Value, "Kies het hotstringbestand", "JSON-bestanden (*.json)")
    if selected != ""
        pathEdit.Value := selected
}

ImportLegacyHotstrings(*) {
    global Hotstrings

    fileName := FileSelect(
        1,
        ,
        "Importeer een oud DocBot-hotstringbestand",
        "Tekstbestanden (*.txt)"
    )

    if fileName = ""
        return

    try contents := FileRead(fileName, "UTF-8")
    catch as error {
        MsgBox(
            "Het oude hotstringbestand kon niet worden gelezen.`n`n" error.Message,
            "DocBot - Importeren",
            "Icon!"
        )
        return
    }

    parsed := ParseLegacyHotstringText(contents)
    importedItems := parsed["Items"]
    unsupportedX := parsed["UnsupportedX"]

    if importedItems.Length = 0 {
        message := Format(
            "Er zijn geen geldige hotstrings gevonden in dit tekstbestand.`n`nNiet herkende regels: {1}`nNiet ondersteunde X-acties: {2}",
            parsed["InvalidLines"],
            unsupportedX
        )
        MsgBox(message, "DocBot - Importeren", "Icon!")
        return
    }

    question := Format(
        "Er zijn {1} hotstrings gevonden.`n`nJa: vervang de huidige vervanglijst.`nNee: voeg toe en overschrijf alleen overeenkomende hotstrings.`nAnnuleren: importeer niets.",
        importedItems.Length
    )
    choice := MsgBox(
        question,
        "DocBot - Oud tekstbestand importeren",
        "YesNoCancel Icon?"
    )

    if choice = "Cancel"
        return

    replacedCount := 0
    addedCount := 0

    if choice = "Yes"
        Hotstrings := []

    for _, item in importedItems {
        existingIndex := FindMatchingHotstringIndex(item)

        if existingIndex > 0 {
            Hotstrings[existingIndex] := item
            replacedCount += 1
        } else {
            Hotstrings.Push(item)
            addedCount += 1
        }
    }

    RefreshHotstringList()
    ReloadRuntimeHotstrings(true)
    autoSaved := AutoSaveHotstrings()

    storageMessage := "Automatisch opslaan staat uit; gebruik Opslaan om de lijst naar JSON te schrijven."
    if State["AutoSave"]
        storageMessage := autoSaved
            ? "De geïmporteerde lijst is automatisch als JSON opgeslagen."
            : "Automatisch opslaan is mislukt; controleer het bestandspad."

    summary := Format(
        "Import voltooid.`n`nToegevoegd: {1}`nBijgewerkt: {2}`nNiet herkende regels: {3}`nNiet ondersteunde X-acties: {4}`n`n{5}",
        addedCount,
        replacedCount,
        parsed["InvalidLines"],
        unsupportedX,
        storageMessage
    )

    MsgBox(summary, "DocBot - Importeren", "Iconi")
}

ParseLegacyHotstringText(contents) {
    items := []
    invalidLines := 0
    unsupportedX := 0

    lineNumber := 0
    Loop Parse, contents, "`n", "`r" {
        lineNumber += 1
        line := A_LoopField

        if lineNumber = 1
            line := LTrim(line, Chr(0xFEFF))

        if Trim(line) = ""
            continue

        ; Oud formaat:
        ; :<opties>:<afkorting>::<vervanging> ;<notitie>
        if !RegExMatch(line, "s)^:([^:]*):(.*?)::(.*)$", &match) {
            invalidLines += 1
            continue
        }

        optionText := match[1]
        trigger := match[2]
        body := match[3]
        replacement := body
        note := ""

        ; De oude versie schreef de notitie als: spatie + puntkomma + notitie.
        ; Gebruik de laatste scheiding, zodat een eerdere puntkomma in de
        ; vervanging behouden blijft. Dit vermijdt ook parserproblemen met een
        ; puntkomma in een reguliere expressie.
        commentSeparator := " " Chr(59)
        commentPos := InStr(body, commentSeparator, false, -1)
        if commentPos > 0 {
            replacement := SubStr(body, 1, commentPos - 1)
            note := SubStr(body, commentPos + StrLen(commentSeparator))
        }

        replacement := LegacyConvertSendTokens(
            LegacyUnescapeControlCharacters(replacement)
        )
        note := LegacyUnescapeControlCharacters(note)

        ; X stond in de oude versie voor een uitvoeractie. Deze gecompileerde
        ; DocBot ondersteunt bewust alleen tekstvervangingen.
        if InStr(optionText, "X", true) {
            unsupportedX += 1
            continue
        }

        options := LegacyFlagsToOptions(optionText)

        items.Push(
            CreateHotstringItem(
                trigger,
                replacement,
                note,
                true,
                options
            )
        )
    }

    return Map(
        "Items", items,
        "InvalidLines", invalidLines,
        "UnsupportedX", unsupportedX
    )
}

LegacyFlagsToOptions(optionText) {
    options := DefaultHotstringOptions()
    remaining := optionText

    ; Samengestelde vlaggen eerst verwijderen, zodat C1 niet ook als C wordt
    ; geïnterpreteerd.
    if InStr(remaining, "C1", true) {
        options["NoConformCase"] := true
        remaining := StrReplace(remaining, "C1", "", true)
    }

    if InStr(remaining, "B0", true) {
        options["NoAutoBack"] := true
        remaining := StrReplace(remaining, "B0", "", true)
    }

    options["NoEndChar"] := InStr(remaining, "*", true) > 0
    options["CaseSensitive"] := InStr(remaining, "C", true) > 0
    options["TriggerInside"] := InStr(remaining, "?", true) > 0
    options["OmitEndChar"] := InStr(remaining, "O", true) > 0
    options["SendRaw"] := InStr(remaining, "R", true) > 0
    options["TextRaw"] := InStr(remaining, "T", true) > 0

    return options
}

LegacyUnescapeControlCharacters(value) {
    value := StrReplace(value, "``n", "`n")
    value := StrReplace(value, "``t", "`t")
    value := StrReplace(value, "``b", "`b")
    return value
}

LegacyConvertSendTokens(value) {
    ; Oude AHK-hotstrings gebruikten Send-codes. Regeleinden worden echte
    ; CRLF-tekens, zodat DocBot het veld automatisch uitklapt en lange
    ; sjablonen via de snelle klembordmethode kan plakken.
    value := RegExReplace(value, "i)\{Enter\}", "`r`n")

    ; Een enkel niet-alfanumeriek teken tussen accolades was een escape voor
    ; een letterlijk teken, bijvoorbeeld {;}, {)}, {+}, {-}, {/}, {'}, {:}
    ; en {>}. Echte toetsopdrachten zoals {Tab} en {Left} blijven behouden.
    value := RegExReplace(value, "\{([^A-Za-z0-9\s])\}", "$1")
    return value
}

FindMatchingHotstringIndex(candidate) {
    global Hotstrings

    candidate := NormalizeHotstringItem(candidate)
    candidateFlags := BuildHotstringFlags(candidate)

    for index, current in Hotstrings {
        current := NormalizeHotstringItem(current)

        if (
            current["Trigger"] = candidate["Trigger"]
            && BuildHotstringFlags(current) = candidateFlags
        )
            return index
    }

    return 0
}

ManualLoadHotstrings(pathEdit, *) {
    global State

    path := Trim(pathEdit.Value)
    if path = "" {
        MsgBox("Kies eerst een JSON-bestand.", "DocBot - Hotstrings laden", "Icon!")
        return
    }

    if LoadHotstringsFromJson(path, true) {
        State["HotstringFile"] := path
        SaveAppSettings()
    }
}

ManualSaveHotstrings(pathEdit, *) {
    global State

    path := Trim(pathEdit.Value)
    if path = "" {
        MsgBox("Kies eerst een JSON-bestand.", "DocBot - Hotstrings opslaan", "Icon!")
        return
    }

    if SaveHotstringsToJson(path, true) {
        State["HotstringFile"] := path
        SaveAppSettings()
    }
}

; =============================================================================
; MEEGELEVERDE HOTSTRINGPAKKETTEN
; =============================================================================

; Levert de map waaruit pakketbestanden rechtstreeks worden gelezen — geen
; lokale kopie, geen inbakken in de executable. DocBot leest bij iedere
; start live vanaf deze locatie, zodat een wijziging op de bron (nieuw,
; aangepast of verwijderd pakketbestand) direct meekomt bij de volgende
; start, zonder herbouw of herdistributie van de executable.
;
; Voor de gecompileerde versie geldt, als die is ingevuld, eerst
; Packages.ShareDir uit DocBot.local.ahk. Zonder die expliciete override
; neemt DocBot aan dat de executable zelf al rechtstreeks vanaf de juiste
; netwerklocatie draait (bijvoorbeeld via een launcher als Ivanti die "vanaf
; de bron" start, niet een lokale gecachete kopie) en leest packages\ naast
; zichzelf, af te leiden uit A_ScriptDir — vandaar dat die hieronder altijd
; wordt gelogd. Start de launcher in plaats daarvan een lokale kopie van de
; executable, dan wijst A_ScriptDir naar die lokale map in plaats van de
; share; zet dan Packages.ShareDir expliciet (`docs/DECISIONS.md` D-048,
; D-049).
GetBundledPackageDirectory() {
    global LocalConfig

    DebugLog("i", "Pakketten bron", "A_ScriptDir: " A_ScriptDir)

    if A_IsCompiled {
        shareDir := ""
        if IsSet(LocalConfig) && LocalConfig is Map && LocalConfig.Has("Packages")
            && LocalConfig["Packages"] is Map && LocalConfig["Packages"].Has("ShareDir")
            shareDir := Trim(LocalConfig["Packages"]["ShareDir"])

        if shareDir != "" {
            DebugLog("i", "Pakketten bron", "Handmatig geconfigureerd (Packages.ShareDir): " shareDir)
            return shareDir
        }

        autoDir := A_ScriptDir "\packages"
        DebugLog("i", "Pakketten bron", "Automatisch afgeleid van A_ScriptDir: " autoDir)
        return autoDir
    }

    ; Ontwikkelversie leest rechtstreeks uit de broncode-map, zodat een
    ; lokaal toegevoegd of gewijzigd pakketbestand direct meekomt bij de
    ; volgende start.
    return A_ScriptDir "\packages"
}

; Schema migraties: gedeelde bouwstenen voor het lezen en afwijzen van
; schemaVersion-waarden, gebruikt door alle vijf de opslagformaten
; (pakketmanifest, pakketbestanden, package-settings.json, hotstrings.json,
; speeddial.json). Zie docs/MIGRATIONS.md voor het volledige overzicht per
; formaat: welke versie welk veld/standaardwaarde toevoegde en welke oude
; bestandsnamen/formaten nog worden ondersteund.
ReadSchemaVersion(document) {
    return document.Has("schemaVersion") ? (document["schemaVersion"] + 0) : 1
}

RejectNewerSchemaVersion(schemaVersion, currentVersion, subject) {
    if schemaVersion > currentVersion
        throw Error(
            Format(
                "{1} gebruikt schemaVersion {2}, maar deze DocBot-versie ondersteunt maximaal versie {3}.",
                subject,
                schemaVersion,
                currentVersion
            )
        )
}

InitializeBundledPackages() {
    global BundledPackageDir, BundledPackages, BundledPackageSchemaVersion

    try {
        BundledPackageDir := GetBundledPackageDirectory()
        manifestPath := BundledPackageDir "\manifest.json"
        DebugLog("i", "Pakketten laden", "Manifest: " manifestPath)
        manifest := LoadBundledJsonFile(manifestPath)

        if !(manifest is Map)
            throw Error("Het pakketmanifest moet een JSON-object zijn: " manifestPath)

        schemaVersion := ReadSchemaVersion(manifest)
        RejectNewerSchemaVersion(schemaVersion, BundledPackageSchemaVersion, "Het pakketmanifest")

        if !manifest.Has("packages") || !(manifest["packages"] is Array)
            throw Error("Het veld 'packages' ontbreekt in het pakketmanifest: " manifestPath)

        loadedPackages := Map()
        failedCount := 0

        ; Eén ongeldig pakketbestand mag de overige, wel geldige pakketten
        ; niet meeslepen. Elk bestand wordt daarom los geprobeerd en gelogd,
        ; zodat precies zichtbaar is welk bestand faalde en waarom.
        for _, packageEntry in manifest["packages"] {
            if !(packageEntry is Map)
                throw Error("Een pakketvermelding in het manifest is ongeldig: " manifestPath)

            if !packageEntry.Has("id") || !packageEntry.Has("file")
                throw Error("Een pakketvermelding mist 'id' of 'file': " manifestPath)

            packageId := Trim(packageEntry["id"])
            fileName := Trim(packageEntry["file"])
            filePath := BundledPackageDir "\\" fileName

            DebugLog("→", "Pakket laden", "Bestand: " fileName " (manifest-id: " packageId ")")

            try {
                package := LoadBundledPackageFile(filePath)

                if package["id"] != packageId {
                    throw Error(
                        Format(
                            "Pakket-id '{1}' komt niet overeen met manifest-id '{2}': {3}",
                            package["id"],
                            packageId,
                            filePath
                        )
                    )
                }

                if loadedPackages.Has(packageId)
                    throw Error("Dubbel pakket-id in manifest: " packageId " (" filePath ")")

                loadedPackages[packageId] := package
                DebugLog(
                    "✓",
                    "Pakket geladen",
                    Format(
                        "{1} ({2}), versie {3}, {4} items — {5}",
                        package["name"],
                        packageId,
                        package["version"],
                        package["items"].Length,
                        fileName
                    )
                )
            } catch as packageError {
                failedCount += 1
                ReportStorageError(
                    Format(
                        "Hotstringpakket '{1}' kon niet worden geladen.`n`n{2}",
                        fileName,
                        packageError.Message
                    ),
                    false
                )
            }
        }

        BundledPackages := loadedPackages
        DebugLog(
            failedCount ? "!" : "i",
            "Pakketten geladen",
            Format(
                "{1} pakket(ten) geladen, {2} mislukt.",
                loadedPackages.Count,
                failedCount
            )
        )
        return failedCount = 0
    } catch as error {
        BundledPackages := Map()
        ReportStorageError(
            "De meegeleverde hotstringpakketten konden niet worden geladen.`n`n"
            error.Message,
            false
        )
        return false
    }
}

LoadBundledJsonFile(path) {
    if !FileExist(path)
        throw Error("Pakketbestand niet gevonden: " path)

    jsonText := FileRead(path, "UTF-8")
    jsonText := LTrim(jsonText, Chr(0xFEFF))
    return Jxon_Load(&jsonText)
}

LoadBundledPackageFile(path) {
    global BundledPackageSchemaVersion

    package := LoadBundledJsonFile(path)
    if !(package is Map)
        throw Error("Een hotstringpakket moet een JSON-object zijn: " path)

    schemaVersion := ReadSchemaVersion(package)
    RejectNewerSchemaVersion(schemaVersion, BundledPackageSchemaVersion, "Pakket " path)

    for _, requiredField in ["id", "name", "version", "items"] {
        if !package.Has(requiredField)
            throw Error("Pakket mist verplicht veld '" requiredField "': " path)
    }

    ; 'owner' is optioneel vrije tekst: wie dit pakket aanmaakt of onderhoudt.
    ; Geen schemaVersion-eis, geen manifest-kopie — het pakketbestand zelf is
    ; de enige plek waar dit staat (`docs/DECISIONS.md` D-054).
    if package.Has("owner") && IsObject(package["owner"])
        throw Error("Pakket " package["id"] ": 'owner' moet tekst zijn, geen object: " path)

    if !(package["items"] is Array)
        throw Error("Het veld 'items' moet een lijst zijn: " path)

    seenIds := Map()
    seenTriggers := Map()

    for index, item in package["items"] {
        if !(item is Map)
            throw Error("Ongeldig pakketitem op positie " index ": " path)

        for _, requiredField in ["id", "trigger", "replacement"] {
            if !item.Has(requiredField)
                throw Error("Pakketitem " index " mist veld '" requiredField "': " path)
        }

        itemId := Trim(item["id"])
        trigger := StrLower(Trim(item["trigger"]))
        replacement := item["replacement"] ""

        if itemId = "" || trigger = "" || replacement = ""
            throw Error("Pakketitem " index " bevat een lege id, trigger of vervanging: " path)

        if seenIds.Has(itemId)
            throw Error("Dubbel item-id in pakket: " itemId)
        if seenTriggers.Has(trigger)
            throw Error("Dubbele afkorting in pakket: " trigger)

        seenIds[itemId] := true
        seenTriggers[trigger] := true
    }

    package["sourcePath"] := path
    return package
}

DefaultPackageSettings() {
    return Map(
        "schemaVersion", 1,
        "enabledPackages", [],
        "disabledItems", Map(),
        "conflictChoices", []
    )
}

InitializePackageSettings() {
    global DefaultPackageSettingsFile, PackageSettings

    if FileExist(DefaultPackageSettingsFile)
        return LoadPackageSettingsFromJson(DefaultPackageSettingsFile)

    PackageSettings := DefaultPackageSettings()
    return SavePackageSettingsToJson(DefaultPackageSettingsFile)
}

LoadPackageSettingsFromJson(path) {
    global PackageSettings

    try {
        document := LoadBundledJsonFile(path)
        PackageSettings := ReconcilePackageSettings(document)
        ; Schrijf ook opgeschoonde verwijzingen direct atomisch terug.
        return SavePackageSettingsToJson(path)
    } catch as error {
        PackageSettings := DefaultPackageSettings()
        ReportStorageError(
            "De pakketkeuzes konden niet worden geladen. Standaard worden geen pakketten geactiveerd.`n`n"
            error.Message,
            false
        )
        return false
    }
}

ReconcilePackageSettings(document) {
    global BundledPackages, Hotstrings, PackageSettingsSchemaVersion

    if !(document is Map)
        throw Error("package-settings.json moet een JSON-object zijn.")

    schemaVersion := ReadSchemaVersion(document)
    RejectNewerSchemaVersion(schemaVersion, PackageSettingsSchemaVersion, "package-settings.json")

    result := DefaultPackageSettings()
    result["schemaVersion"] := PackageSettingsSchemaVersion

    enabledSeen := Map()
    if document.Has("enabledPackages") && document["enabledPackages"] is Array {
        for _, packageId in document["enabledPackages"] {
            packageId := Trim(packageId)
            if packageId != "" && BundledPackages.Has(packageId) && !enabledSeen.Has(packageId) {
                result["enabledPackages"].Push(packageId)
                enabledSeen[packageId] := true
            }
        }
    }

    if document.Has("disabledItems") && document["disabledItems"] is Map {
        for packageId, itemIds in document["disabledItems"] {
            if !BundledPackages.Has(packageId) || !(itemIds is Array)
                continue

            validIds := PackageItemIdMap(packageId)
            cleanedIds := []
            cleanedSeen := Map()
            for _, itemId in itemIds {
                itemId := Trim(itemId)
                if validIds.Has(itemId) && !cleanedSeen.Has(itemId) {
                    cleanedIds.Push(itemId)
                    cleanedSeen[itemId] := true
                }
            }
            if cleanedIds.Length > 0
                result["disabledItems"][packageId] := cleanedIds
        }
    }

    customItemsById := Map()
    for _, item in Hotstrings {
        normalized := NormalizeHotstringItem(item)
        customItemsById[normalized["Id"]] := normalized
    }

    if document.Has("conflictChoices") && document["conflictChoices"] is Array {
        choiceSeen := Map()
        for _, choice in document["conflictChoices"] {
            if !(choice is Map)
                continue
            if !choice.Has("customItemId") || !choice.Has("packageId")
                || !choice.Has("packageItemId") || !choice.Has("choice")
                continue

            customId := Trim(choice["customItemId"])
            packageId := Trim(choice["packageId"])
            packageItemId := Trim(choice["packageItemId"])
            selectedChoice := StrLower(Trim(choice["choice"]))

            ; 'custom' is de standaard en hoeft nooit te worden opgeslagen.
            if selectedChoice != "package" || !customItemsById.Has(customId)
                continue
            if !BundledPackages.Has(packageId)
                continue

            packageItem := FindBundledPackageItem(packageId, packageItemId)
            if !IsObject(packageItem)
                continue

            packageRuntimeItem := CreateHotstringItem(
                packageItem["trigger"],
                packageItem["replacement"],
                "",
                true,
                DefaultHotstringOptions(),
                "package-" packageId "-" packageItemId,
                Map(
                    "Type", "package",
                    "PackageId", packageId,
                    "ItemId", packageItemId,
                    "PackageVersion", BundledPackages[packageId]["version"]
                )
            )
            if BuildHotstringIdentity(customItemsById[customId])
                != BuildHotstringIdentity(packageRuntimeItem)
                continue

            choiceKey := customId "|" packageId "|" packageItemId
            if choiceSeen.Has(choiceKey)
                continue

            result["conflictChoices"].Push(
                Map(
                    "customItemId", customId,
                    "packageId", packageId,
                    "packageItemId", packageItemId,
                    "choice", "package"
                )
            )
            choiceSeen[choiceKey] := true
        }
    }

    return result
}

SavePackageSettingsToJson(path) {
    global PackageSettings, PackageSettingsSchemaVersion

    tempPath := path ".tmp"
    backupPath := path ".bak"

    try {
        SplitPath(path, , &directory)
        if directory != "" && !DirExist(directory)
            DirCreate(directory)

        PackageSettings["schemaVersion"] := PackageSettingsSchemaVersion
        jsonText := Jxon_Dump(PackageSettings, 2)

        if FileExist(tempPath)
            FileDelete(tempPath)
        FileAppend(jsonText, tempPath, "UTF-8-RAW")

        verifyText := FileRead(tempPath, "UTF-8")
        verifyDocument := Jxon_Load(&verifyText)
        if !(verifyDocument is Map) || !verifyDocument.Has("enabledPackages")
            throw Error("Controle van package-settings.json is mislukt.")

        if FileExist(path)
            FileCopy(path, backupPath, true)
        FileMove(tempPath, path, true)
        return true
    } catch as error {
        if FileExist(tempPath)
            try FileDelete(tempPath)
        ReportStorageError(
            "De pakketkeuzes konden niet worden opgeslagen.`n`n" error.Message,
            false
        )
        return false
    }
}

PackageItemIdMap(packageId) {
    global BundledPackages

    result := Map()
    if !BundledPackages.Has(packageId)
        return result

    for _, item in BundledPackages[packageId]["items"]
        result[item["id"]] := item
    return result
}

FindBundledPackageItem(packageId, itemId) {
    items := PackageItemIdMap(packageId)
    return items.Has(itemId) ? items[itemId] : 0
}

IsPackageEnabled(packageId) {
    global PackageSettings

    for _, enabledId in PackageSettings["enabledPackages"] {
        if enabledId = packageId
            return true
    }
    return false
}

IsPackageItemDisabled(packageId, itemId) {
    global PackageSettings

    if !PackageSettings["disabledItems"].Has(packageId)
        return false
    for _, disabledId in PackageSettings["disabledItems"][packageId] {
        if disabledId = itemId
            return true
    }
    return false
}

SetPackageEnabled(packageId, enabled) {
    global BundledPackages, PackageSettings, DefaultPackageSettingsFile

    if !BundledPackages.Has(packageId)
        return false

    foundIndex := 0
    for index, currentId in PackageSettings["enabledPackages"] {
        if currentId = packageId {
            foundIndex := index
            break
        }
    }

    if enabled && foundIndex = 0
        PackageSettings["enabledPackages"].Push(packageId)
    else if !enabled && foundIndex > 0
        PackageSettings["enabledPackages"].RemoveAt(foundIndex)

    SavePackageSettingsToJson(DefaultPackageSettingsFile)
    ReloadRuntimeHotstrings(true)
    return true
}

SetPackageItemEnabled(packageId, itemId, enabled) {
    global PackageSettings, DefaultPackageSettingsFile

    if !IsObject(FindBundledPackageItem(packageId, itemId))
        return false

    if !PackageSettings["disabledItems"].Has(packageId)
        PackageSettings["disabledItems"][packageId] := []
    disabled := PackageSettings["disabledItems"][packageId]

    foundIndex := 0
    for index, disabledId in disabled {
        if disabledId = itemId {
            foundIndex := index
            break
        }
    }

    if enabled && foundIndex > 0
        disabled.RemoveAt(foundIndex)
    else if !enabled && foundIndex = 0
        disabled.Push(itemId)

    if disabled.Length = 0
        PackageSettings["disabledItems"].Delete(packageId)

    SavePackageSettingsToJson(DefaultPackageSettingsFile)
    ReloadRuntimeHotstrings(true)
    return true
}

SetPackageConflictChoice(customItemId, packageId, packageItemId, choice) {
    global Hotstrings, PackageSettings, DefaultPackageSettingsFile

    customItem := 0
    for _, item in Hotstrings {
        normalized := NormalizeHotstringItem(item)
        if normalized["Id"] = customItemId {
            customItem := normalized
            break
        }
    }

    packageItem := FindBundledPackageItem(packageId, packageItemId)
    if !IsObject(customItem) || !IsObject(packageItem)
        return false

    packageRuntimeItem := CreateHotstringItem(
        packageItem["trigger"],
        packageItem["replacement"],
        "",
        true,
        DefaultHotstringOptions(),
        "package-" packageId "-" packageItemId,
        Map(
            "Type", "package",
            "PackageId", packageId,
            "ItemId", packageItemId,
            "PackageVersion", ""
        )
    )
    if BuildHotstringIdentity(customItem) != BuildHotstringIdentity(packageRuntimeItem)
        return false

    choices := PackageSettings["conflictChoices"]
    existingIndex := 0
    for index, current in choices {
        if current["customItemId"] = customItemId
            && current["packageId"] = packageId
            && current["packageItemId"] = packageItemId {
            existingIndex := index
            break
        }
    }

    if existingIndex > 0
        choices.RemoveAt(existingIndex)

    ; Alleen de afwijking 'package' wordt bewaard; custom blijft de standaard.
    if StrLower(Trim(choice)) = "package" {
        choices.Push(
            Map(
                "customItemId", customItemId,
                "packageId", packageId,
                "packageItemId", packageItemId,
                "choice", "package"
            )
        )
    }

    SavePackageSettingsToJson(DefaultPackageSettingsFile)
    ReloadRuntimeHotstrings(true)
    return true
}

PackageChoiceUsesPackage(customItemId, packageId, packageItemId) {
    global PackageSettings

    for _, choice in PackageSettings["conflictChoices"] {
        if choice["customItemId"] = customItemId
            && choice["packageId"] = packageId
            && choice["packageItemId"] = packageItemId
            && choice["choice"] = "package"
            return true
    }
    return false
}

BuildHotstringIdentity(item) {
    item := NormalizeHotstringItem(item)
    trigger := Trim(item["Trigger"])
    if !item["Options"]["CaseSensitive"]
        trigger := StrLower(trigger)
    return trigger "|" BuildHotstringFlags(item)
}

BuildEffectiveHotstrings() {
    global Hotstrings, BundledPackages, PackageSettings

    effective := []
    identities := Map()
    suppressedCustomIds := Map()
    preferredPackageByIdentity := Map()

    ; Een expliciete pakketkeuze onderdrukt de eigen variant alleen zolang
    ; dat pakket en dat concrete item daadwerkelijk beschikbaar en actief zijn.
    for _, choice in PackageSettings["conflictChoices"] {
        packageId := choice["packageId"]
        itemId := choice["packageItemId"]
        packageItem := FindBundledPackageItem(packageId, itemId)
        if IsPackageEnabled(packageId)
            && !IsPackageItemDisabled(packageId, itemId)
            && IsObject(packageItem) {
            customItem := 0
            for _, candidate in Hotstrings {
                normalizedCandidate := NormalizeHotstringItem(candidate)
                if normalizedCandidate["Id"] = choice["customItemId"] {
                    customItem := normalizedCandidate
                    break
                }
            }
            if !IsObject(customItem)
                continue

            preferredItem := CreateHotstringItem(
                packageItem["trigger"],
                packageItem["replacement"],
                "",
                true,
                DefaultHotstringOptions(),
                "package-" packageId "-" itemId,
                Map(
                    "Type", "package",
                    "PackageId", packageId,
                    "ItemId", itemId,
                    "PackageVersion", BundledPackages[packageId]["version"]
                )
            )
            identity := BuildHotstringIdentity(preferredItem)
            if identity != BuildHotstringIdentity(customItem)
                continue

            suppressedCustomIds[choice["customItemId"]] := true
            preferredPackageByIdentity[identity] := packageId "|" itemId
        }
    }

    for _, rawItem in Hotstrings {
        item := NormalizeHotstringItem(rawItem)
        if !item["Enabled"] || suppressedCustomIds.Has(item["Id"])
            continue
        identity := BuildHotstringIdentity(item)
        if identities.Has(identity)
            continue
        identities[identity] := Map("Source", "custom", "Id", item["Id"])
        effective.Push(item)
    }

    for _, packageId in PackageSettings["enabledPackages"] {
        if !BundledPackages.Has(packageId)
            continue

        package := BundledPackages[packageId]
        for _, packageItem in package["items"] {
            if packageItem.Has("enabledByDefault") && !packageItem["enabledByDefault"]
                continue
            if IsPackageItemDisabled(packageId, packageItem["id"])
                continue

            origin := Map(
                "Type", "package",
                "PackageId", packageId,
                "ItemId", packageItem["id"],
                "PackageVersion", package["version"]
            )
            item := CreateHotstringItem(
                packageItem["trigger"],
                packageItem["replacement"],
                "Pakket: " package["name"],
                true,
                DefaultHotstringOptions(),
                "package-" packageId "-" packageItem["id"],
                origin
            )
            identity := BuildHotstringIdentity(item)

            if preferredPackageByIdentity.Has(identity)
                && preferredPackageByIdentity[identity] != packageId "|" packageItem["id"]
                continue

            if identities.Has(identity) {
                existing := identities[identity]
                if existing["Source"] != "custom"
                    continue
                if !PackageChoiceUsesPackage(existing["Id"], packageId, packageItem["id"])
                    continue

                ; De eigen variant is hierboven al onderdrukt; deze identity
                ; mag nu door de expliciet gekozen pakketvariant worden gevuld.
                if identities.Has(identity)
                    identities.Delete(identity)
            }

            identities[identity] := Map("Source", "package", "Id", packageItem["id"])
            effective.Push(item)
        }
    }

    return effective
}

PromotePackageItemToCustom(packageId, itemId) {
    global BundledPackages, Hotstrings, PackageSettings
    global DefaultPackageSettingsFile

    packageItem := FindBundledPackageItem(packageId, itemId)
    if !IsObject(packageItem) || !BundledPackages.Has(packageId)
        return ""

    package := BundledPackages[packageId]
    origin := Map(
        "Type", "package",
        "PackageId", packageId,
        "ItemId", itemId,
        "PackageVersion", package["version"]
    )
    customItem := CreateHotstringItem(
        packageItem["trigger"],
        packageItem["replacement"],
        "Overgenomen uit pakket: " package["name"],
        true,
        DefaultHotstringOptions(),
        "",
        origin
    )
    Hotstrings.Push(customItem)

    ; De eigen kopie is voortaan leidend en het bronitem wordt expliciet
    ; uitgeschakeld om onverwachte terugval bij het uitzetten van de kopie te voorkomen.
    if !PackageSettings["disabledItems"].Has(packageId)
        PackageSettings["disabledItems"][packageId] := []
    alreadyDisabled := false
    for _, disabledId in PackageSettings["disabledItems"][packageId] {
        if disabledId = itemId {
            alreadyDisabled := true
            break
        }
    }
    if !alreadyDisabled
        PackageSettings["disabledItems"][packageId].Push(itemId)

    AutoSaveHotstrings()
    SavePackageSettingsToJson(DefaultPackageSettingsFile)
    RefreshHotstringListIfReady()
    ReloadRuntimeHotstrings(true)
    return customItem["Id"]
}

InitializeHotstringStorage() {
    global State

    if !State["AutoSave"]
        return true

    path := Trim(State["HotstringFile"])
    if path = ""
        return true

    if FileExist(path)
        return LoadHotstringsFromJson(path, false)

    ; Bij de eerste start wordt het standaardmodel direct aangemaakt.
    return SaveHotstringsToJson(path, false)
}

LoadHotstringsFromJson(path, showMessage := false) {
    global Hotstrings, HotstringSchemaVersion

    path := Trim(path)
    if path = "" {
        ReportStorageError("Er is geen JSON-bestand ingesteld.", showMessage)
        return false
    }

    if !FileExist(path) {
        ReportStorageError("Het JSON-bestand bestaat niet:`n`n" path, showMessage)
        return false
    }

    try {
        jsonText := FileRead(path, "UTF-8")
        jsonText := LTrim(jsonText, Chr(0xFEFF))
        document := Jxon_Load(&jsonText)

        if !(document is Map)
            throw Error("De JSON-hoofdstructuur moet een object zijn.")

        schemaVersion := ReadSchemaVersion(document)
        RejectNewerSchemaVersion(schemaVersion, HotstringSchemaVersion, "Dit bestand")

        if !document.Has("hotstrings") || !(document["hotstrings"] is Array)
            throw Error("Het veld 'hotstrings' ontbreekt of is geen lijst.")

        loadedItems := []
        skipped := 0
        disabledLegacyActions := 0
        needsMigration := schemaVersion < HotstringSchemaVersion
        seenIds := Map()

        for _, rawItem in document["hotstrings"] {
            if !(rawItem is Map) {
                skipped += 1
                continue
            }

            hadLegacyAction := rawItem.Has("ActionType") && rawItem["ActionType"] = "execute"
            if !rawItem.Has("Id") || !rawItem.Has("Origin")
                needsMigration := true

            item := NormalizeHotstringItem(rawItem)
            if hadLegacyAction
                disabledLegacyActions += 1

            if Trim(item["Trigger"]) = "" {
                skipped += 1
                continue
            }

            if seenIds.Has(item["Id"]) {
                item["Id"] := CreateCustomHotstringId()
                needsMigration := true
            }
            seenIds[item["Id"]] := true
            loadedItems.Push(item)
        }

        Hotstrings := loadedItems

        ; Schema 5 voegt de persoonlijke defaults één keer toe. Bestaande
        ; afkortingen blijven altijd leidend en worden nooit overschreven.
        if schemaVersion < 5
            AddMissingDefaultHotstrings(Hotstrings)

        ; Schema 1 krijgt stabiele IDs en origin=custom. De bestaande
        ; atomaire opslag maakt eerst een .bak voordat het bestand wijzigt.
        if needsMigration
            SaveHotstringsToJson(path, false)

        RefreshHotstringListIfReady()
        ClearHotstringEditorIfReady()
        ReloadRuntimeHotstrings(showMessage)

        if showMessage {
            message := Format(
                "Hotstrings geladen: {1}`nOvergeslagen: {2}`nOude X-acties uitgeschakeld: {3}`n`n{4}",
                loadedItems.Length,
                skipped,
                disabledLegacyActions,
                path
            )
            MsgBox(message, "DocBot - Hotstrings laden", "Iconi")
        } else if disabledLegacyActions > 0 {
            ShowNotification(
                disabledLegacyActions " oude X-actie(s) zijn uitgeschakeld.",
                4000,
                "warning"
            )
        }

        return true
    } catch as error {
        ReportStorageError(
            Format(
                "Het JSON-bestand kon niet worden geladen.`n`n{1}`n`n{2}",
                path,
                error.Message
            ),
            showMessage
        )
        return false
    }
}

SaveHotstringsToJson(path, showMessage := false) {
    path := Trim(path)
    if path = "" {
        ReportStorageError("Er is geen JSON-bestand ingesteld.", showMessage)
        return false
    }

    tempPath := path ".tmp"
    backupPath := path ".bak"

    try {
        SplitPath(path, , &directory)
        if directory != "" && !DirExist(directory)
            DirCreate(directory)

        document := BuildHotstringDocument()
        jsonText := Jxon_Dump(document, 2)

        if FileExist(tempPath)
            FileDelete(tempPath)

        FileAppend(jsonText, tempPath, "UTF-8-RAW")

        ; Controleer het tijdelijke bestand vóór het bestaande bestand wordt
        ; vervangen. Zo blijft de vorige versie intact bij corrupte uitvoer.
        verifyText := FileRead(tempPath, "UTF-8")
        verifyDocument := Jxon_Load(&verifyText)
        if !(verifyDocument is Map) || !verifyDocument.Has("hotstrings")
            throw Error("Controle van het tijdelijke JSON-bestand is mislukt.")

        if FileExist(path)
            FileCopy(path, backupPath, true)

        FileMove(tempPath, path, true)

        if showMessage {
            MsgBox(
                "Hotstrings opgeslagen.`n`n" path
                (FileExist(backupPath) ? "`n`nBack-up: " backupPath : ""),
                "DocBot - Hotstrings opslaan",
                "Iconi"
            )
        }

        return true
    } catch as error {
        if FileExist(tempPath)
            try FileDelete(tempPath)

        ReportStorageError(
            Format(
                "De hotstrings konden niet worden opgeslagen.`n`n{1}`n`n{2}",
                path,
                error.Message
            ),
            showMessage
        )
        return false
    }
}

AutoSaveHotstrings(*) {
    global State

    if !State["AutoSave"]
        return true

    return SaveHotstringsToJson(State["HotstringFile"], false)
}

ReportStorageError(message, showMessage := false) {
    ; Iedere opslagfout moet terug te vinden zijn in het standaardlog, ook
    ; wanneer de gebruiker de melding zelf nooit ziet (bijv. stille
    ; achtergrondacties) of wegklikt.
    DebugLog("✕", "Opslagfout", message)

    if showMessage {
        MsgBox(message, "DocBot - JSON", "Icon!")
        return
    }

    ; Automatisch laden/opslaan mag de gebruiker niet met modale vensters
    ; onderbreken. Een traymelding is daarvoor minder storend.
    ShowNotification(message, 5000, "error")
}

RefreshHotstringListIfReady() {
    global HotLV

    if IsObject(HotLV)
        RefreshHotstringList()
}

RefreshSpeedDialListIfReady() {
    global SpeedDialLV

    if IsObject(SpeedDialLV)
        RefreshSpeedDialList()
}

; =============================================================================
; OPSLAG - GEDEELDE RETRY BIJ TIJDELIJK NIET-BESCHIKBARE OPSLAG
; =============================================================================
; Zie de globals StorageRetryLoaders/StorageRetryAttempts hierboven voor de
; achtergrond. StorageRetry_RunInitialAttempt() vervangt de vroegere directe
; aanroepen van de vijf laders in het auto-execute-gedeelte: eerste, snelle
; poging blijft synchroon (faalt vandaag al in ruim onder een seconde, dus
; vertraagt dit MainGui.Show() niet), maar elke hérpoging loopt via
; SetTimer op de achtergrond, ná het tonen van het venster.

; Eén poging voor precies deze lader; werkt zowel voor de synchrone eerste
; kans(en) als voor elke latere tick. Slaat een al geslaagde lader over
; (idempotent: veilig om StorageRetry_RunInitialAttempt() twee keer aan te
; roepen). Geeft de staat vóór deze poging terug, zodat de aanroeper kan
; zien of dit een verse overgang naar "klaar" is.
StorageRetry_AttemptLoader(loader) {
    wasReady := loader["Ready"]
    if wasReady
        return wasReady

    try {
        loader["Ready"] := !!loader["Fn"].Call()
    } catch as error {
        loader["Ready"] := false
        DebugLog(
            "✕",
            "Opslagfout",
            loader["Name"] " gaf een onverwachte fout: " error.Message
        )
    }

    return wasReady
}

StorageRetry_RunInitialAttemptForUserDataDir() {
    global StorageRetryLoaders
    StorageRetry_AttemptLoader(StorageRetryLoaders[1])
}

StorageRetry_RunInitialAttempt() {
    global StorageRetryLoaders

    for loader in StorageRetryLoaders
        StorageRetry_AttemptLoader(loader)

    StorageRetry_ScheduleIfNeeded()
}

StorageRetry_Tick(*) {
    global StorageRetryLoaders

    for loader in StorageRetryLoaders {
        wasReady := StorageRetry_AttemptLoader(loader)
        if loader["Ready"] && !wasReady
            StorageRetry_OnLoaderReady(loader["Name"])
    }

    StorageRetry_ScheduleIfNeeded()
}

StorageRetry_AllLoadersReady() {
    global StorageRetryLoaders

    for loader in StorageRetryLoaders {
        if !loader["Ready"]
            return false
    }
    return true
}

StorageRetry_ScheduleIfNeeded() {
    global StorageRetryLoaders, StorageRetryAttempts, StorageAllReady
    global StorageRetryQuickMs, StorageRetryQuickCount, StorageRetrySlowMs

    if !StorageRetry_AllLoadersReady() {
        StorageRetryAttempts += 1
        delay := StorageRetryAttempts < StorageRetryQuickCount
            ? StorageRetryQuickMs
            : StorageRetrySlowMs
        SetTimer StorageRetry_Tick, -delay
        return
    }

    ; Alle laders zijn geladen: geen verdere pogingen meer nodig.
    SetTimer StorageRetry_Tick, 0

    if !StorageAllReady {
        StorageAllReady := true
        StorageRetry_OnAllReady()
    }
}

; Wordt precies één keer aangeroepen, de eerste keer dat alle laders klaar
; zijn. Vóór BuildMainGui() (de gewone, snelle start zonder degraded mode)
; bestaat MainGui nog niet: dan is er niets te verversen, want de eenmalige
; ShowPage("overzicht") aan het eind van BuildMainGui() past de juiste
; zichtbaarheid vanzelf toe met de dan al correcte StorageAllReady-waarde.
; Ná een echte achtergrond-hersteld (degraded mode was actief) ververst dit
; zowel de zichtbaarheid (banner weg, kaarten/pagina's terug) als de
; getoonde waarden die tijdens BuildMainGui() nog met standaardwaarden zijn
; opgebouwd.
StorageRetry_OnAllReady() {
    global MainGui, CurrentPage

    if !IsObject(MainGui)
        return

    RefreshOverzichtValuesAfterReady()
    RefreshInstellingenValuesAfterReady()
    EvaluateStartupTip()
    ShowPage(CurrentPage)
    RefreshSidebarStatuses()
    BuildTrayMenu()
}

RefreshOverzichtValuesAfterReady() {
    global CallActionSelector, TextReplacementCheck, State
    global OverviewPhoneActionsText, OverviewLongHotstringActionsText, OverviewSmsActionsText

    if IsObject(CallActionSelector)
        CallActionSelector.Value := State["CallAction"]
    if IsObject(TextReplacementCheck)
        TextReplacementCheck.Value := State["TextReplacement"]
    if IsObject(OverviewPhoneActionsText)
        OverviewPhoneActionsText.Value := Telemetry_GetPhoneActions()
    if IsObject(OverviewLongHotstringActionsText)
        OverviewLongHotstringActionsText.Value := Telemetry_GetLongHotstringActions()
    if IsObject(OverviewSmsActionsText)
        OverviewSmsActionsText.Value := Telemetry_GetSmsActions()
}

; De Instellingen-velden zijn, anders dan CallActionSelector/
; TextReplacementCheck hierboven, geen losse klasse met een settable
; .Value die zichzelf herschildert — dit herhaalt daarom hetzelfde stukje
; opbouwlogica uit BuildMainGui() (SMS-paginakeuze + bijbehorend
; standaardtekstveld) met de dan pas echt geladen State/SmsDefaultTexts.
RefreshInstellingenValuesAfterReady() {
    global InstellingenAutoSaveCheck, InstellingenFilePathEdit, InstellingenSmsActionDropDown
    global InstellingenSmsDefaultTextEdit, InstellingenSmsDefaultTextHint
    global InstellingenPendingSmsDefaultTexts, State

    if !IsObject(InstellingenAutoSaveCheck)
        return

    InstellingenAutoSaveCheck.Value := State["AutoSave"]
    InstellingenFilePathEdit.Value := State["HotstringFile"]

    smsActionTitles := GetSmsCallActionTitles()
    if smsActionTitles.Length {
        selectedIndex := FindSmsCallActionIndexByTitle(State["SmsCallActionTitle"])
        if selectedIndex = 0
            selectedIndex := 1
        InstellingenSmsActionDropDown.Choose(selectedIndex)
    }

    ApplySmsDefaultTextFieldState(
        InstellingenSmsActionDropDown,
        InstellingenSmsDefaultTextEdit,
        InstellingenSmsDefaultTextHint,
        InstellingenPendingSmsDefaultTexts
    )
}

StorageRetry_OnLoaderReady(name) {
    switch name {
        case "Gebruikersmap":
            ; Geen eigen verversing nodig: de overige laders in dezelfde
            ; tick (zie StorageRetry_Tick()) krijgen nu pas een kans om te
            ; slagen en verversen dan zelf wat nodig is.
        case "Instellingen":
            ; Bekende beperking: als Hotstrings vóór Instellingen al (met
            ; toen nog de code-standaardwaarden van State) is geladen, en de
            ; gebruiker een niet-standaard State["HotstringFile"] heeft
            ; ingesteld, wordt dat afwijkende pad pas na een volgende
            ; herstart gebruikt. Zeldzaam — de meeste installaties gebruiken
            ; het standaardpad — en niet erger dan het huidige gedrag zonder
            ; retry, dus bewust niet in deze stap opgelost.
            RefreshSidebarStatuses()
        case "Hotstrings", "Pakketkeuzes":
            ; Pakketstatus beïnvloedt welke hotstrings actief/Overruled/
            ; Conflict zijn; ververs daarom bij beide dezelfde twee dingen.
            ReloadRuntimeHotstrings()
            RefreshHotstringListIfReady()
        case "Snelkiesnummers":
            RefreshSpeedDialListIfReady()
        case "SMS-standaardteksten":
            ; Geen aparte lijstweergave: de Instellingen-pagina leest
            ; SmsDefaultTexts pas op het moment dat die pagina wordt geopend.
    }
}

; =============================================================================
; SNELKIESNUMMERS - OPSLAG
; =============================================================================

DefaultSpeedDialEntries() {
    global LocalConfig

    defaults := []
    for _, configuredEntry in LocalConfig["DefaultSpeedDials"] {
        defaults.Push(
            CreateSpeedDialEntry(
                configuredEntry["Name"],
                configuredEntry["Number"],
                configuredEntry.Has("Enabled") ? !!configuredEntry["Enabled"] : true
            )
        )
    }
    return defaults
}

AddMissingDefaultSpeedDials(entries) {
    added := 0
    for _, defaultEntry in DefaultSpeedDialEntries() {
        alreadyExists := false
        for _, entry in entries {
            if StrLower(Trim(entry["naam"])) = StrLower(Trim(defaultEntry["naam"]))
                || Trim(entry["nummer"]) = Trim(defaultEntry["nummer"]) {
                alreadyExists := true
                break
            }
        }
        if alreadyExists
            continue
        entries.Push(defaultEntry)
        added += 1
    }
    return added
}

CreateSpeedDialEntry(naam, nummer, actief := true) {
    return Map(
        "naam", naam,
        "nummer", nummer,
        "actief", actief ? true : false
    )
}

BuildSpeedDialDocument() {
    global SpeedDialEntries, SpeedDialSchemaVersion

    return Map(
        "schemaVersion", SpeedDialSchemaVersion,
        "entries", SpeedDialEntries
    )
}

InitializeSpeedDialStorage() {
    global DefaultSpeedDialFile, UserDataDir

    if FileExist(DefaultSpeedDialFile)
        return LoadSpeedDialFromJson(DefaultSpeedDialFile, false)

    ; Oudere versies gebruikten verschillende bestandsnamen en soms de
    ; programmamap. Neem de eerste gevonden versie veilig over; het laden
    ; hieronder migreert vervolgens ook de inhoud naar het actuele schema.
    legacyCandidates := [
        UserDataDir "\snelkiesnummers.json",
        A_ScriptDir "\snelkiesnummers.json",
        A_ScriptDir "\speeddial.json"
    ]
    for _, legacyPath in legacyCandidates {
        if !FileExist(legacyPath)
            continue
        try FileCopy(legacyPath, DefaultSpeedDialFile, false)
        if FileExist(DefaultSpeedDialFile)
            return LoadSpeedDialFromJson(DefaultSpeedDialFile, false)
    }

    ; Bij de eerste start wordt een lege lijst direct aangemaakt.
    return SaveSpeedDialToJson(DefaultSpeedDialFile, false)
}

LoadSpeedDialFromJson(path, showMessage := false) {
    global SpeedDialEntries, SpeedDialSchemaVersion

    path := Trim(path)
    if path = "" {
        ReportStorageError("Er is geen JSON-bestand ingesteld.", showMessage)
        return false
    }

    if !FileExist(path) {
        ReportStorageError("Het JSON-bestand bestaat niet:`n`n" path, showMessage)
        return false
    }

    try {
        jsonText := FileRead(path, "UTF-8")
        jsonText := LTrim(jsonText, Chr(0xFEFF))
        document := Jxon_Load(&jsonText)

        if !(document is Map)
            throw Error("De JSON-hoofdstructuur moet een object zijn.")

        schemaVersion := ReadSchemaVersion(document)
        RejectNewerSchemaVersion(schemaVersion, SpeedDialSchemaVersion, "Dit bestand")

        if !document.Has("entries") || !(document["entries"] is Array)
            throw Error("Het veld 'entries' ontbreekt of is geen lijst.")

        loadedEntries := []
        skipped := 0
        needsMigration := schemaVersion < SpeedDialSchemaVersion

        for _, rawEntry in document["entries"] {
            if !(rawEntry is Map) {
                skipped += 1
                continue
            }

            naam := rawEntry.Has("naam") ? Trim(rawEntry["naam"]) : ""
            nummer := rawEntry.Has("nummer") ? Trim(rawEntry["nummer"]) : ""
            actief := rawEntry.Has("actief") ? !!rawEntry["actief"] : true

            if naam = "" || nummer = "" {
                skipped += 1
                continue
            }

            if !rawEntry.Has("actief")
                needsMigration := true

            loadedEntries.Push(CreateSpeedDialEntry(naam, nummer, actief))
        }

        SpeedDialEntries := loadedEntries

        ; Schema 3 voegt lokaal ingestelde standaardnummers één keer toe.
        ; Een bestaande naam of hetzelfde nummer blijft ongemoeid.
        if schemaVersion < 3
            AddMissingDefaultSpeedDials(SpeedDialEntries)

        ; Schema 1 en naamloze legacy-items krijgen standaard actief=true.
        ; Sla meteen atomisch terug op, inclusief de bestaande .bak-strategie.
        if needsMigration
            SaveSpeedDialToJson(path, false)

        if showMessage {
            MsgBox(
                Format(
                    "Snelkiesnummers geladen: {1}`nOvergeslagen: {2}`n`n{3}",
                    loadedEntries.Length,
                    skipped,
                    path
                ),
                "DocBot - Snelkiesnummers laden",
                "Iconi"
            )
        }

        return true
    } catch as error {
        ReportStorageError(
            Format(
                "Het JSON-bestand kon niet worden geladen.`n`n{1}`n`n{2}",
                path,
                error.Message
            ),
            showMessage
        )
        return false
    }
}

SaveSpeedDialToJson(path, showMessage := false) {
    path := Trim(path)
    if path = "" {
        ReportStorageError("Er is geen JSON-bestand ingesteld.", showMessage)
        return false
    }

    tempPath := path ".tmp"
    backupPath := path ".bak"

    try {
        SplitPath(path, , &directory)
        if directory != "" && !DirExist(directory)
            DirCreate(directory)

        document := BuildSpeedDialDocument()
        jsonText := Jxon_Dump(document, 2)

        if FileExist(tempPath)
            FileDelete(tempPath)

        FileAppend(jsonText, tempPath, "UTF-8-RAW")

        ; Controleer het tijdelijke bestand vóór het bestaande bestand wordt
        ; vervangen. Zo blijft de vorige versie intact bij corrupte uitvoer.
        verifyText := FileRead(tempPath, "UTF-8")
        verifyDocument := Jxon_Load(&verifyText)
        if !(verifyDocument is Map) || !verifyDocument.Has("entries")
            throw Error("Controle van het tijdelijke JSON-bestand is mislukt.")

        if FileExist(path)
            FileCopy(path, backupPath, true)

        FileMove(tempPath, path, true)

        if showMessage {
            MsgBox(
                "Snelkiesnummers opgeslagen.`n`n" path
                (FileExist(backupPath) ? "`n`nBack-up: " backupPath : ""),
                "DocBot - Snelkiesnummers opslaan",
                "Iconi"
            )
        }

        return true
    } catch as error {
        if FileExist(tempPath)
            try FileDelete(tempPath)

        ReportStorageError(
            Format(
                "De snelkiesnummers konden niet worden opgeslagen.`n`n{1}`n`n{2}",
                path,
                error.Message
            ),
            showMessage
        )
        return false
    }
}

; =============================================================================
; SMS-STANDAARDTEKST — sms-default-texts.json
; =============================================================================
; Zelfde opzet als speeddial.json hierboven: schemaVersion + atomair
; wegschrijven via .tmp/.bak. Functionele sleutel is Title (lowercase,
; getrimd), net als FindSmsCallActionIndexByTitle() elders in dit bestand.
; Anders dan package-settings.json wordt hier bewust niets stilzwijgend
; verwijderd wanneer een Title niet (meer) voorkomt in de huidige
; SmsCallActions: de GUI toont zo'n item dan simpelweg niet, maar de tekst
; blijft bewaard voor het geval de titel later terugkeert (bijv. na een
; tijdelijke configuratiefout).

GetSmsDefaultText(title) {
    global SmsDefaultTexts

    key := StrLower(Trim(title))
    return (key != "" && SmsDefaultTexts.Has(key)) ? SmsDefaultTexts[key]["DefaultText"] : ""
}

SetSmsDefaultText(title, text) {
    global SmsDefaultTexts

    key := StrLower(Trim(title))
    if key = ""
        return

    if Trim(text) = "" {
        if SmsDefaultTexts.Has(key)
            SmsDefaultTexts.Delete(key)
        return
    }

    SmsDefaultTexts[key] := Map("Title", Trim(title), "DefaultText", text)
}

BuildSmsDefaultTextDocument() {
    global SmsDefaultTexts, SmsDefaultTextSchemaVersion

    items := []
    for _, entry in SmsDefaultTexts
        items.Push(Map("Title", entry["Title"], "DefaultText", entry["DefaultText"]))

    return Map("schemaVersion", SmsDefaultTextSchemaVersion, "items", items)
}

InitializeSmsDefaultTextStorage() {
    global DefaultSmsDefaultTextFile

    if FileExist(DefaultSmsDefaultTextFile)
        return LoadSmsDefaultTextsFromJson(DefaultSmsDefaultTextFile, false)

    ; Bij de eerste start wordt een lege lijst direct aangemaakt.
    return SaveSmsDefaultTextsToJson(DefaultSmsDefaultTextFile, false)
}

LoadSmsDefaultTextsFromJson(path, showMessage := false) {
    global SmsDefaultTexts, SmsDefaultTextSchemaVersion

    path := Trim(path)
    if path = "" {
        ReportStorageError("Er is geen JSON-bestand ingesteld.", showMessage)
        return false
    }

    if !FileExist(path) {
        ReportStorageError("Het JSON-bestand bestaat niet:`n`n" path, showMessage)
        return false
    }

    try {
        jsonText := FileRead(path, "UTF-8")
        jsonText := LTrim(jsonText, Chr(0xFEFF))
        document := Jxon_Load(&jsonText)

        if !(document is Map)
            throw Error("De JSON-hoofdstructuur moet een object zijn.")

        schemaVersion := ReadSchemaVersion(document)
        RejectNewerSchemaVersion(schemaVersion, SmsDefaultTextSchemaVersion, "sms-default-texts.json")

        if !document.Has("items") || !(document["items"] is Array)
            throw Error("Het veld 'items' ontbreekt of is geen lijst.")

        loaded := Map()
        skipped := 0

        for _, rawItem in document["items"] {
            if !(rawItem is Map) {
                skipped += 1
                continue
            }

            title := rawItem.Has("Title") ? Trim(rawItem["Title"]) : ""
            text := rawItem.Has("DefaultText") ? rawItem["DefaultText"] : ""

            if title = "" {
                skipped += 1
                continue
            }

            loaded[StrLower(title)] := Map("Title", title, "DefaultText", text)
        }

        SmsDefaultTexts := loaded

        if showMessage {
            MsgBox(
                Format(
                    "SMS-standaardteksten geladen: {1}`nOvergeslagen: {2}`n`n{3}",
                    loaded.Count,
                    skipped,
                    path
                ),
                "DocBot - SMS-standaardteksten laden",
                "Iconi"
            )
        }

        return true
    } catch as error {
        ReportStorageError(
            Format(
                "Het JSON-bestand kon niet worden geladen.`n`n{1}`n`n{2}",
                path,
                error.Message
            ),
            showMessage
        )
        return false
    }
}

SaveSmsDefaultTextsToJson(path, showMessage := false) {
    path := Trim(path)
    if path = "" {
        ReportStorageError("Er is geen JSON-bestand ingesteld.", showMessage)
        return false
    }

    tempPath := path ".tmp"
    backupPath := path ".bak"

    try {
        SplitPath(path, , &directory)
        if directory != "" && !DirExist(directory)
            DirCreate(directory)

        document := BuildSmsDefaultTextDocument()
        jsonText := Jxon_Dump(document, 2)

        if FileExist(tempPath)
            FileDelete(tempPath)

        FileAppend(jsonText, tempPath, "UTF-8-RAW")

        ; Controleer het tijdelijke bestand vóór het bestaande bestand wordt
        ; vervangen. Zo blijft de vorige versie intact bij corrupte uitvoer.
        verifyText := FileRead(tempPath, "UTF-8")
        verifyDocument := Jxon_Load(&verifyText)
        if !(verifyDocument is Map) || !verifyDocument.Has("items")
            throw Error("Controle van het tijdelijke JSON-bestand is mislukt.")

        if FileExist(path)
            FileCopy(path, backupPath, true)

        FileMove(tempPath, path, true)

        if showMessage {
            MsgBox(
                "SMS-standaardteksten opgeslagen.`n`n" path
                (FileExist(backupPath) ? "`n`nBack-up: " backupPath : ""),
                "DocBot - SMS-standaardteksten opslaan",
                "Iconi"
            )
        }

        return true
    } catch as error {
        if FileExist(tempPath)
            try FileDelete(tempPath)

        ReportStorageError(
            Format(
                "De SMS-standaardteksten konden niet worden opgeslagen.`n`n{1}`n`n{2}",
                path,
                error.Message
            ),
            showMessage
        )
        return false
    }
}

ClearHotstringEditorIfReady() {
    global HotLV, HotEnabledCheck, HotTriggerEdit
    global HotOptionDraft

    if !IsObject(HotLV)
        return

    HotLV.Modify(0, "-Select")
    HotEnabledCheck.Value := 1
    HotTriggerEdit.Value := ""
    SetHotReplacementValue("", false)
    HotOptionDraft := DefaultHotstringOptions()
}

ValidateLocalConfiguration() {
    global LocalConfig

    if !IsSet(LocalConfig) || !(LocalConfig is Map)
        throw Error("DocBot.local.ahk ontbreekt of definieert geen LocalConfig-map.")

    for _, section in ["Telephony", "DefaultSpeedDials", "DefaultHotstrings"] {
        if !LocalConfig.Has(section)
            throw Error("LocalConfig mist de sectie '" section "'.")
    }

    telephony := LocalConfig["Telephony"]
    if !(telephony is Map)
        throw Error("LocalConfig['Telephony'] moet een Map zijn.")
    for _, key in ["BaseUrl", "AllocateEndpoint", "EventEndpoint", "DialEndpoint"] {
        if !telephony.Has(key) || Trim(telephony[key]) = ""
            throw Error("Telephony mist een ingevulde waarde voor '" key "'.")
    }
    if !RegExMatch(Trim(telephony["BaseUrl"]), "i)^https://")
        throw Error("Telephony.BaseUrl moet een HTTPS-URL zijn (http:// wordt niet geaccepteerd).")

    Telemetry_ValidateConfiguration(LocalConfig)
    ValidateSmsCallActionsConfiguration(LocalConfig)
    ValidatePackagesConfiguration(LocalConfig)

    if !(LocalConfig["DefaultSpeedDials"] is Array)
        throw Error("DefaultSpeedDials moet een Array zijn.")
    for index, entry in LocalConfig["DefaultSpeedDials"] {
        if !(entry is Map)
            throw Error("DefaultSpeedDials item " index " moet een Map zijn.")
        if !entry.Has("Name") || Trim(entry["Name"]) = ""
            throw Error("DefaultSpeedDials item " index " mist Name.")
        if !entry.Has("Number") || Trim(entry["Number"]) = ""
            throw Error("DefaultSpeedDials item " index " mist Number.")
    }

    if !(LocalConfig["DefaultHotstrings"] is Array)
        throw Error("DefaultHotstrings moet een Array zijn.")
    for index, item in LocalConfig["DefaultHotstrings"] {
        if !(item is Map)
            throw Error("DefaultHotstrings item " index " moet een Map zijn.")
        if !item.Has("Trigger") || Trim(item["Trigger"]) = ""
            throw Error("DefaultHotstrings item " index " mist Trigger.")
        if !item.Has("Replacement") || item["Replacement"] = ""
            throw Error("DefaultHotstrings item " index " mist Replacement.")
    }
}

ValidateSmsCallActionsConfiguration(config) {
    if !config.Has("SmsCallAction")
        return

    source := config["SmsCallAction"]
    if source is Map {
        ValidateSmsCallActionItem(source, 1)
        return
    }

    if !(source is Array)
        throw Error("SmsCallAction moet een Map of een Array met Maps zijn.")

    titles := Map()
    for index, item in source {
        ValidateSmsCallActionItem(item, index)
        normalizedTitle := StrLower(Trim(item["Title"]))
        if titles.Has(normalizedTitle)
            throw Error("SmsCallAction bevat de dubbele Title '" item["Title"] "'.")
        titles[normalizedTitle] := true
    }
}

ValidateSmsCallActionItem(item, index) {
    if !(item is Map)
        throw Error("SmsCallAction item " index " moet een Map zijn.")

    for _, key in ["Title", "Url", "FieldId", "WindowTitle"] {
        if !item.Has(key) || Trim(item[key]) = ""
            throw Error("SmsCallAction item " index " mist een ingevulde waarde voor '" key "'.")
    }
    if !RegExMatch(Trim(item["Url"]), "i)^https://")
        throw Error("SmsCallAction item " index " ('" item["Title"] "'): Url moet een HTTPS-URL zijn (http:// wordt niet geaccepteerd).")

    ; TextFieldId is optioneel: zonder deze waarde is er simpelweg geen
    ; doelveld voor een standaardtekst en blijft die functionaliteit voor
    ; deze pagina uitgeschakeld. Is de sleutel wel aanwezig, dan mag hij
    ; niet leeg zijn (waarschijnlijk een vergeten placeholder).
    if item.Has("TextFieldId") && Trim(item["TextFieldId"]) = ""
        throw Error("SmsCallAction item " index " ('" item["Title"] "'): TextFieldId mag niet leeg zijn als het aanwezig is.")
}

; De sectie 'Packages' is optioneel: zonder haar leidt de gecompileerde
; applicatie de pakketlocatie automatisch af uit A_ScriptDir (zie
; GetBundledPackageDirectory()) en blokkeert een ontbrekende sectie de
; opstart dus nooit. Staat de sectie er wel — als expliciete override, bijv.
; omdat een launcher zoals Ivanti een lokale kopie start in plaats van de
; executable rechtstreeks vanaf de netwerklocatie — dan moet ShareDir wél
; een ingevuld, geldig UNC-pad zijn; dat vangt een vergeten
; placeholderwaarde af.
ValidatePackagesConfiguration(config) {
    if !config.Has("Packages")
        return

    packages := config["Packages"]
    if !(packages is Map)
        throw Error("LocalConfig['Packages'] moet een Map zijn.")

    if !packages.Has("ShareDir") || Trim(packages["ShareDir"]) = ""
        throw Error("Packages mist een ingevulde waarde voor 'ShareDir'.")

    if !RegExMatch(Trim(packages["ShareDir"]), "^\\\\")
        throw Error("Packages.ShareDir moet een netwerkpad zijn dat begint met \\ (UNC-pad).")
}

GetConfiguredSmsCallActions() {
    global LocalConfig

    actions := []
    if !IsSet(LocalConfig) || !(LocalConfig is Map) || !LocalConfig.Has("SmsCallAction")
        return actions

    source := LocalConfig["SmsCallAction"]
    if source is Map {
        actions.Push(source)
        return actions
    }

    if source is Array {
        for _, item in source
            actions.Push(item)
    }
    return actions
}

GetSmsCallActionTitles() {
    global SmsCallActions

    titles := []
    for _, action in SmsCallActions
        titles.Push(action["Title"])
    return titles
}

HasConfiguredSmsCallActions() {
    global SmsCallActions
    return SmsCallActions.Length > 0
}

FindSmsCallActionIndexByTitle(title) {
    global SmsCallActions

    wanted := StrLower(Trim(title))
    for index, action in SmsCallActions {
        if StrLower(Trim(action["Title"])) = wanted
            return index
    }
    return 0
}

ResolveSmsCallActionTitle(title) {
    global SmsCallActions

    index := FindSmsCallActionIndexByTitle(title)
    if index > 0
        return SmsCallActions[index]["Title"]
    return SmsCallActions.Length ? SmsCallActions[1]["Title"] : ""
}

GetSelectedSmsCallAction() {
    global State, SmsCallActions

    index := FindSmsCallActionIndexByTitle(State["SmsCallActionTitle"])
    return index > 0 ? SmsCallActions[index] : 0
}

; Vult het standaardtekst-veld op de Instellingen-pagina voor de op dit
; moment in de dropdown gekozen SMS-pagina: niet-opgeslagen tekst uit
; pendingSmsDefaultTexts krijgt voorrang boven de opgeslagen waarde, en het
; veld wordt uitgeschakeld zolang die pagina geen TextFieldId heeft.
ApplySmsDefaultTextFieldState(smsActionDropDown, smsDefaultTextEdit, smsDefaultTextHint, pendingSmsDefaultTexts) {
    global SmsCallActions

    title := HasConfiguredSmsCallActions() ? ResolveSmsCallActionTitle(smsActionDropDown.Text) : ""
    index := title != "" ? FindSmsCallActionIndexByTitle(title) : 0
    smsConfig := index > 0 ? SmsCallActions[index] : 0
    hasTextField := IsObject(smsConfig) && smsConfig.Has("TextFieldId") && Trim(smsConfig["TextFieldId"]) != ""

    if !hasTextField {
        smsDefaultTextEdit.Value := ""
        smsDefaultTextEdit.Enabled := false
        smsDefaultTextHint.Text := title = ""
            ? "Configureer eerst een SMS-pagina om een standaardtekst in te stellen."
            : "Voor '" title "' is geen tekstveld geconfigureerd. Vraag de beheerder om TextFieldId toe te voegen aan DocBot.local.ahk."
        return
    }

    key := StrLower(title)
    smsDefaultTextEdit.Value := pendingSmsDefaultTexts.Has(key)
        ? pendingSmsDefaultTexts[key]
        : GetSmsDefaultText(title)
    smsDefaultTextEdit.Enabled := true
    ; De toelichting staat al in het label boven het veld; hier blijft de
    ; regel dus leeg zolang er niets mis is.
    smsDefaultTextHint.Text := ""
}

; Bewaart de nog niet opgeslagen tekst van de vorige selectie in het geheugen
; vóórdat de tekst van de nieuw gekozen SMS-pagina wordt geladen.
SmsActionSelectionChanged(smsActionDropDown, smsDefaultTextEdit, smsDefaultTextHint, pendingSmsDefaultTexts, smsDefaultTextUiState, *) {
    previousTitle := smsDefaultTextUiState["LastTitle"]
    if previousTitle != ""
        pendingSmsDefaultTexts[StrLower(previousTitle)] := smsDefaultTextEdit.Value

    ApplySmsDefaultTextFieldState(smsActionDropDown, smsDefaultTextEdit, smsDefaultTextHint, pendingSmsDefaultTexts)

    smsDefaultTextUiState["LastTitle"] := HasConfiguredSmsCallActions()
        ? ResolveSmsCallActionTitle(smsActionDropDown.Text)
        : ""
}

NormalizeCallAction(value, fallback := 1) {
    value := ParseCallActionSetting(value, fallback)
    return value = 3 && !HasConfiguredSmsCallActions() ? fallback : value
}

GetUserDataProfile(appVersion, isCompiled) {
    normalizedVersion := StrLower(Trim(appVersion))

    ; Een stabiele SemVer bestaat hier uitsluitend uit cijfers en punten.
    ; Stable heeft voorrang: die gebruikt altijd het productieprofiel,
    ; ongeacht buildvorm.
    if RegExMatch(normalizedVersion, "^\d+(?:\.\d+)*$")
        return "main"

    ; Voor elke niet-stabiele versie bepaalt de buildvorm het profiel, niet
    ; het prereleaselabel (-dev, -rc of een feature-/fixnaam): een
    ; gecompileerde build test de opleverbare vorm en deelt daarom het
    ; centrale testprofiel; een niet-gecompileerde build is
    ; broncode-ontwikkeling en blijft geïsoleerd in het devprofiel.
    return isCompiled ? "test" : "dev"
}

GetUserDataSeedDirectory() {
    global UserDataProfile, ProductionUserDataDir, TestUserDataDir

    if UserDataProfile = "test"
        return ProductionUserDataDir

    if UserDataProfile = "dev"
        return DirExist(TestUserDataDir)
            ? TestUserDataDir
            : ProductionUserDataDir

    return ""
}

; Beslist niet langer in één keer, op basis van alleen DirExist(UserDataDir),
; of dit een eerste start is: die passieve check ziet er identiek uit
; zowel wanneer de gebruiker DocBot echt nog nooit heeft gedraaid, als
; wanneer OneDrive bij autostart de map nog niet laat zien. Bestaat de map
; al, dan is er sowieso geen twijfel — ga direct verder. Bestaat de map nog
; niet, dan beslist UserStorageProbe_TryBootstrap() dat via een echte
; schrijftest (zie hieronder) in plaats van een gok; lukt die schrijftest
; niet, dan geeft deze functie false terug en herprobeert de gedeelde
; StorageRetry-achtergrondtimer het later opnieuw — DocBot start voortaan
; altijd gewoon door (geen MsgBox()/ExitApp() meer op deze plek).
InitializeUserStorage() {
    global UserDataDir, UserDataDirIsPreexisting

    UserDataDirIsPreexisting := DirExist(UserDataDir) ? true : false

    if UserDataDirIsPreexisting {
        MigrateLegacyUserData()
        return true
    }

    return UserStorageProbe_TryBootstrap()
}

; Eenmalige, voorzichtige migratie vanaf oudere versies die hun bestanden
; naast het script bewaarden. Bestaande bestanden in de gebruikersmap
; worden nooit overschreven. Losgetrokken van InitializeUserStorage() zodat
; zowel het bestaande-map-pad hierboven als beide paden van
; UserStorageProbe_* hieronder 'm kunnen aanroepen.
MigrateLegacyUserData() {
    global ConfigFile, DefaultHotstringFile

    legacyConfig := A_ScriptDir "\DocBot.ini"
    legacyHotstrings := A_ScriptDir "\hotstrings.json"

    if !FileExist(DefaultHotstringFile) && FileExist(legacyHotstrings) {
        try FileCopy(legacyHotstrings, DefaultHotstringFile, false)
    }

    if !FileExist(ConfigFile) && FileExist(legacyConfig) {
        try {
            FileCopy(legacyConfig, ConfigFile, false)

            storedPath := IniRead(
                ConfigFile,
                "Hotstrings",
                "File",
                ""
            )

            ; Alleen het oude standaardpad wordt omgezet. Een bewust gekozen
            ; ander pad van de gebruiker blijft intact.
            if storedPath = ""
                || StrLower(Trim(storedPath)) = StrLower(legacyHotstrings) {
                IniWrite(
                    DefaultHotstringFile,
                    ConfigFile,
                    "Hotstrings",
                    "File"
                )
            }
        }
    }
}

; Maakt een uniek genoemde tijdelijke map aan onder A_MyDocuments — een
; echte schrijftest, sterker dan nogmaals DirExist() pollen: een nog niet
; gemounte OneDrive hoort een echte schrijfpoging te laten mislukken, niet
; alleen leeg te ogen. Lukt dat schrijven niet, dan is "opslag nog niet
; beschikbaar" bewezen (geen "eerste start"-conclusie) en volgt een nieuwe
; poging via de gedeelde StorageRetry-timer. De naam is herkenbaar voor
; PruneAbandonedUserStorageProbeDirs() (zie diagnostiek-sectie), voor het
; geval DocBot crasht tussen aanmaken en hernoemen/opruimen.
UserStorageProbe_TryBootstrap() {
    ; AutoHotkey kent geen ingebouwde A_PID-variabele (in v1 noch v2); het
    ; huidige proces-ID moet via DllCall worden opgevraagd.
    probeDir := A_MyDocuments "\DocBot_userdata_probe_"
        FormatTime(A_Now, "yyyyMMdd_HHmmss") "_" DllCall("GetCurrentProcessId")

    try {
        DirCreate(probeDir)
    } catch as error {
        DebugLog(
            "✕",
            "Opslagfout",
            "Gebruikersmap kon nog niet worden voorbereid (opslag "
            "waarschijnlijk nog niet beschikbaar): " error.Message
        )
        return false
    }

    return UserStorageProbe_ResolveAfterCreate(probeDir)
}

; De probe-map is aantoonbaar schrijfbaar. Nu pas de echte beslissing nemen.
UserStorageProbe_ResolveAfterCreate(probeDir) {
    global UserDataDir, UserDataDirIsPreexisting

    ; Zelfde soort race als bij het telemetrie-installatie-ID
    ; (Telemetry_TryEnsureInstallationId): een tweede DocBot-instantie
    ; (dubbele autostart, of een handmatige start terwijl de eerste nog aan
    ; het proberen is) kan de echte map inmiddels al hebben aangemaakt, of
    ; die kan tijdens het aanmaken van de probe alsnog zijn verschenen
    ; (pure OneDrive-vertraging, geen eerste start). Vlak vóór gebruik nog
    ; eens controleren en de bestaande waarde laten winnen, in plaats van de
    ; eigen probe-map erover heen te claimen.
    if DirExist(UserDataDir) {
        try DirDelete(probeDir, true)
        UserDataDirIsPreexisting := true
        MigrateLegacyUserData()
        return true
    }

    ; De probe-map is écht schrijfbaar gebleken en UserDataDir bestaat nog
    ; steeds niet: hoge zekerheid dat dit een eerste start is. Hernoem de
    ; probe-map naar de echte plek in plaats van 'm weg te gooien en apart
    ; een nieuwe aan te maken.
    seedDir := GetUserDataSeedDirectory()
    copiedFromDir := ""

    try {
        if seedDir != "" && DirExist(seedDir) {
            ; Eerst leegmaken en opnieuw vullen via DirCopy (die de
            ; bestemming zelf aanmaakt) in plaats van in de al aangemaakte
            ; lege probe-map te kopiëren: zo blijft dit pad identiek aan het
            ; niet-probe-gedrag hierboven.
            DirDelete(probeDir, true)
            DirCopy(seedDir, probeDir, false)
            copiedFromDir := seedDir
        }

        DirMove(probeDir, UserDataDir)
    } catch as error {
        DebugLog(
            "✕",
            "Opslagfout",
            "Gebruikersmap kon niet worden voltooid vanuit de tijdelijke "
            "map: " error.Message
        )
        try DirDelete(probeDir, true)
        return false
    }

    UserDataDirIsPreexisting := false

    if copiedFromDir != ""
        RebaseCopiedHotstringPath(copiedFromDir)

    MigrateLegacyUserData()
    return true
}


RebaseCopiedHotstringPath(sourceDir) {
    global ConfigFile, UserDataDir

    if !FileExist(ConfigFile)
        return

    storedPath := Trim(
        IniRead(
            ConfigFile,
            "Hotstrings",
            "File",
            ""
        )
    )
    if storedPath = ""
        return

    normalizedStoredPath := StrReplace(storedPath, "/", "\")
    normalizedSourceDir := RTrim(
        StrReplace(sourceDir, "/", "\"),
        "\"
    )
    sourcePrefix := normalizedSourceDir "\"

    ; Alleen paden binnen het zojuist gekopieerde profiel worden omgezet.
    ; Een bewust gekozen extern bestand blijft als expliciete keuze intact.
    if SubStr(
        StrLower(normalizedStoredPath),
        1,
        StrLen(sourcePrefix)
    ) != StrLower(sourcePrefix)
        return

    relativePath := SubStr(
        normalizedStoredPath,
        StrLen(sourcePrefix) + 1
    )
    if relativePath = ""
        return

    IniWrite(
        UserDataDir "\" relativePath,
        ConfigFile,
        "Hotstrings",
        "File"
    )
}

LoadAppSettings() {
    global State, ConfigFile, UserDataDirIsPreexisting

    if !FileExist(ConfigFile) {
        ; Op een net gebootstrapte, nieuwe profielmap is een ontbrekend
        ; settings.ini gewoon een eerste start: de code-standaardwaarden in
        ; State blijven dan correct staan, zonder foutmelding of retry.
        ; Bestond de profielmap al, dan is een ontbrekend settings.ini
        ; verdacht (bijv. OneDrive dat de placeholder nog niet toont) en
        ; moet dit, net als de andere laders, opnieuw geprobeerd worden in
        ; plaats van stilzwijgend op standaardwaarden te blijven draaien.
        if !UserDataDirIsPreexisting
            return true
        ReportStorageError(
            "settings.ini kon niet worden gevonden, terwijl de gebruikersmap "
            "al bestaat.`n`n" ConfigFile,
            false
        )
        return false
    }

    try {
        State["AutoSave"] := ParseBooleanSetting(
            IniRead(ConfigFile, "Hotstrings", "AutoSave", State["AutoSave"])
        )
        State["HotstringFile"] := IniRead(
            ConfigFile,
            "Hotstrings",
            "File",
            State["HotstringFile"]
        )
        storedCallAction := Trim(
            IniRead(ConfigFile, "Features", "CallAction", "")
        )
        if storedCallAction != "" {
            State["CallAction"] := ParseCallActionSetting(
                storedCallAction,
                State["CallAction"]
            )
        } else {
            legacyAutoCall := ParseBooleanSetting(
                IniRead(ConfigFile, "Features", "AutoCall", 1)
            )
            legacyDirectCall := ParseBooleanSetting(
                IniRead(ConfigFile, "Features", "DirectCall", 0)
            )
            State["CallAction"] := !legacyAutoCall
                ? 0
                : (legacyDirectCall ? 2 : 1)
        }
        State["SmsCallActionTitle"] := ResolveSmsCallActionTitle(
            IniRead(
                ConfigFile,
                "Features",
                "SmsCallActionTitle",
                State["SmsCallActionTitle"]
            )
        )
        State["CallAction"] := NormalizeCallAction(State["CallAction"])
        State["TextReplacement"] := ParseBooleanSetting(
            IniRead(
                ConfigFile,
                "Features",
                "TextReplacement",
                State["TextReplacement"]
            )
        )
        return true
    } catch as error {
        ReportStorageError(
            "settings.ini kon niet worden geladen.`n`n" ConfigFile "`n`n"
            error.Message,
            false
        )
        return false
    }
}

SaveAppSettings() {
    global State, ConfigFile

    try {
        IniWrite(State["AutoSave"] ? 1 : 0, ConfigFile, "Hotstrings", "AutoSave")
        IniWrite(State["HotstringFile"], ConfigFile, "Hotstrings", "File")
        IniWrite(State["CallAction"], ConfigFile, "Features", "CallAction")
        IniWrite(State["SmsCallActionTitle"], ConfigFile, "Features", "SmsCallActionTitle")
        try IniDelete(ConfigFile, "Features", "AutoCall")
        try IniDelete(ConfigFile, "Features", "DirectCall")
        IniWrite(
            State["TextReplacement"] ? 1 : 0,
            ConfigFile,
            "Features",
            "TextReplacement"
        )
        return true
    } catch as error {
        ShowNotification(
            "De instellingen konden niet worden opgeslagen.`n" error.Message,
            5000,
            "error"
        )
        return false
    }
}

ParseBooleanSetting(value) {
    value := StrLower(Trim(value ""))
    return value = "1" || value = "true" || value = "yes" || value = "aan"
}

ParseCallActionSetting(value, fallback := 1) {
    value := Trim(value "")
    if !RegExMatch(value, "^[0-3]$")
        return fallback

    return Number(value)
}

SaveSettings(autoSaveCheck, filePathEdit, smsActionDropDown, smsDefaultTextEdit, pendingSmsDefaultTexts, smsDefaultTextUiState, *) {
    global State, SmsCallActions, DefaultSmsDefaultTextFile

    State["AutoSave"] := autoSaveCheck.Value = 1
    State["HotstringFile"] := Trim(filePathEdit.Value)
    State["SmsCallActionTitle"] := HasConfiguredSmsCallActions()
        ? ResolveSmsCallActionTitle(smsActionDropDown.Text)
        : ""

    if State["HotstringFile"] = "" {
        MsgBox("Kies eerst een JSON-bestand.", "DocBot", "Icon!")
        return
    }

    ; De op dit moment zichtbare standaardtekst is nog niet in
    ; pendingSmsDefaultTexts gezet (dat gebeurt pas bij het wisselen van
    ; SMS-pagina) — doe dat hier alsnog vóór het wegschrijven.
    currentTitle := smsDefaultTextUiState["LastTitle"]
    if currentTitle != ""
        pendingSmsDefaultTexts[StrLower(currentTitle)] := smsDefaultTextEdit.Value

    for _, action in SmsCallActions {
        if !action.Has("TextFieldId") || Trim(action["TextFieldId"]) = ""
            continue
        key := StrLower(action["Title"])
        if pendingSmsDefaultTexts.Has(key)
            SetSmsDefaultText(action["Title"], pendingSmsDefaultTexts[key])
    }

    settingsSaved := SaveAppSettings()
    dataSaved := !State["AutoSave"] || AutoSaveHotstrings()
    smsTextSaved := SaveSmsDefaultTextsToJson(DefaultSmsDefaultTextFile, false)

    BuildTrayMenu()

    if settingsSaved && dataSaved && smsTextSaved
        MsgBox("Instellingen opgeslagen.", "DocBot", "Iconi")
    else
        MsgBox(
            "Niet alles kon worden opgeslagen. Controleer het bestandspad en de schrijfrechten.",
            "DocBot",
            "Icon!"
        )
}

HandleAppExit(*) {
    global IPTPollRequest, UiBitmaps

    Telemetry_Shutdown()
    SetTimer ClipBoardPoller, 0
    SetTimer IPT_poller, 0
    SetTimer UpdateRegisterButtonState, 0
    SetTimer CheckSignalFile, 0

    ; Een eventueel nog lopende GetEvent-aanvraag afbreken; niet elk
    ; ComObject ondersteunt .abort(), dus stilletjes negeren indien niet.
    if IsObject(IPTPollRequest) {
        try IPTPollRequest.abort()
    }

    UnregisterRuntimeHotstrings()
    SaveAppSettings()
    AutoSaveHotstrings()

    DebugLog("i", "DocBot afgesloten", "Normale afsluiting.")
    ShutdownProblemReportLogging()
    ; Gebufferde standaardregels alsnog wegschrijven.
    FlushDebugLog()

    ; HBITMAP-handles van GDI+-cards en toggles zijn eigendom van DocBot.
    for _, hBitmap in UiBitmaps
        try DllCall("gdi32\DeleteObject", "ptr", hBitmap)
    UiBitmaps := []
}

; =============================================================================
; SYSTEEMVAK
; =============================================================================

BuildTrayMenu() {
    global State, IsDevMode, SpeedDialEntries, TraySpeedDialMaxEntries
    global ProblemReportSession, StorageAllReady

    A_TrayMenu.Delete()

    registeredLabel := Trim(State["IPT"]["UserTel"]) != ""
        ? "Geregistreerd nummer: " State["IPT"]["UserTel"]
        : "Geen nummer geregistreerd"

    A_TrayMenu.Add(registeredLabel, (*) => 0)
    A_TrayMenu.Disable(registeredLabel)

    A_TrayMenu.Add()

    A_TrayMenu.Add("DocBot", ShowMain)
    ; Menu.Default maakt het item vet en tot standaardactie (Win32
    ; MFS_DEFAULT) — de gedocumenteerde AHK v2-manier hiervoor, in
    ; tegenstelling tot een handmatige DllCall/struct-hack. Overlapt
    ; functioneel met het dubbelklikgedrag van het tray-icoon zelf
    ; (ToggleMainWindow via TrayIconMessage), wat geen probleem is.
    A_TrayMenu.Default := "DocBot"

    callActionMenu := Menu()
    callActionLabels := [
        "Niets doen",
        "Bellen na bevestiging",
        "Direct bellen"
    ]
    if HasConfiguredSmsCallActions()
        callActionLabels.Push("Bellen of sms kiezen")

    State["CallAction"] := NormalizeCallAction(State["CallAction"])
    for value, label in callActionLabels
        callActionMenu.Add(label, SetTrayCallAction.Bind(value - 1))
    callActionMenu.Check(callActionLabels[State["CallAction"] + 1])

    A_TrayMenu.Add("Belactie", callActionMenu)
    A_TrayMenu.Add("Tekstvervanging", ToggleTraySetting.Bind("TextReplacement"))

    if State["TextReplacement"]
        A_TrayMenu.Check("Tekstvervanging")

    if !StorageAllReady {
        ; Beide items schrijven rechtstreeks naar State/settings.ini
        ; (SetTrayCallAction()/ToggleTraySetting()), buiten het hoofdvenster
        ; om. Zolang niet alle opslag geladen is, zou een wijziging hier de
        ; dan pas net echt geladen waarde meteen weer overschrijven met een
        ; keuze gebaseerd op een nog niet bevestigde standaardwaarde.
        A_TrayMenu.Disable("Belactie")
        A_TrayMenu.Disable("Tekstvervanging")
    }

    ; Alleen als submenu-alternatief: platte lijst direct in het hoofdmenu,
    ; met een disabled sectiekopje erboven (zelfde patroon als het
    ; geregistreerd-nummer-label bovenaan). Streep + blok worden samen
    ; overgeslagen zonder entries.
    ;
    ; Zolang StorageAllReady nog false is, staat SpeedDialEntries nog op de
    ; code-standaardwaarden (DefaultSpeedDialEntries()) in plaats van de
    ; echte speeddial.json — en CallSpeedDialEntry() belt meteen echt via
    ; IPT_callNumber(). Dit blok blijft daarom net als "Belactie"/
    ; "Tekstvervanging" hierboven volledig weg tijdens degraded mode, in
    ; plaats van (mogelijk verouderde) nummers klikbaar te tonen — zie
    ; docs/DECISIONS.md D-064.
    if StorageAllReady {
        activeSpeedDials := []
        for _, entry in SpeedDialEntries {
            if entry["actief"]
                activeSpeedDials.Push(entry)
        }

        if activeSpeedDials.Length > 0 {
            A_TrayMenu.Add()
            A_TrayMenu.Add("Snelkiesnummers", (*) => 0)
            A_TrayMenu.Disable("Snelkiesnummers")

            Loop Min(activeSpeedDials.Length, TraySpeedDialMaxEntries) {
                entry := activeSpeedDials[A_Index]
                A_TrayMenu.Add(entry["naam"] . " (" . entry["nummer"] . ")", CallSpeedDialEntry.Bind(entry["nummer"]))
            }
            if activeSpeedDials.Length > TraySpeedDialMaxEntries
                A_TrayMenu.Add("Alle snelkiesnummers...", ShowSpeedDialsFromTray)
        }
    }

    A_TrayMenu.Add()
    if IsDevMode
        A_TrayMenu.Add("Debug-venster tonen", ShowDebugWindow)
    problemReportLabel := ProblemReportSession["ExtendedActive"]
        ? "Probleem melden... (logging actief)"
        : "Probleem melden..."
    A_TrayMenu.Add(problemReportLabel, ShowProblemReportWindow)

    A_TrayMenu.Add()
    A_TrayMenu.Add("Herladen", (*) => Reload())
    A_TrayMenu.Add("Afsluiten", (*) => ExitApp())

}

ShowSpeedDialsFromTray(*) {
    ShowPage("telefonie")
    ShowMain()
}

CallSpeedDialEntry(nummer, *) {
    IPT_callNumber(nummer)
}

SetTrayCallAction(value, *) {
    global State, CallActionSelector

    State["CallAction"] := NormalizeCallAction(value)
    if IsObject(CallActionSelector)
        CallActionSelector.Value := value

    SaveAppSettings()
    RefreshSidebarStatuses()
    BuildTrayMenu()
}

ToggleTraySetting(key, *) {
    global State, TextReplacementCheck

    State[key] := !State[key]

    if key = "TextReplacement" {
        TextReplacementCheck.Value := State[key]
        ReloadRuntimeHotstrings(true)
    }

    SaveAppSettings()
    RefreshSidebarStatuses()
    BuildTrayMenu()
}

ShowMain(*) {
    global MainGui

    MainGui.Show()
    WinActivate("ahk_id " MainGui.Hwnd)
}

TrayIconMessage(wParam, lParam, msg, hwnd) {
    ; 0x201 = WM_LBUTTONDOWN. Rechtsklikken blijft het contextmenu openen.
    if lParam = 0x201 {
        ToggleMainWindow()
        return true
    }
}

ToggleMainWindow(*) {
    global MainGui

    ; Controleer zichtbaarheid in plaats van focus. Een tray-klik neemt de focus
    ; namelijk zelf over voordat de callback wordt uitgevoerd.
    isVisible := DllCall(
        "IsWindowVisible",
        "ptr", MainGui.Hwnd,
        "int"
    )

    if isVisible {
        MainGui.Hide()
        return
    }

    MainGui.Show()
    WinActivate("ahk_id " MainGui.Hwnd)
}

MainGui_Close(GuiObj, *) {
    ; Verberg het venster en voorkom dat AHK het GUI-object vernietigt.
    GuiObj.Hide()
    return true
}

MainGui_Escape(GuiObj, *) {
    GuiObj.Hide()
}

HideMain(*) {
    global MainGui
    MainGui.Hide()
}

; =============================================================================
; AFRONDING
; =============================================================================

AddRound(control, radius := 12) {
    global RoundQueue
    RoundQueue.Push(Map("Control", control, "Radius", radius))
}

ApplyRoundedControls(visibleOnly := false) {
    global RoundQueue
    for _, item in RoundQueue {
        ctrl := item["Control"]
        if visibleOnly && !DllCall("IsWindowVisible", "ptr", ctrl.Hwnd, "int")
            continue
        try RoundControl(ctrl, item["Radius"])
    }
}

RoundControl(control, radius := 12) {
    ; SetWindowRgn shapes de hele vensterrechthoek van het control, niet
    ; alleen het clientgebied. GetClientRect sluit een scrollbalk echter per
    ; definitie uit (MSDN: "the client area... not including... scroll
    ; bars"), dus een regio op basis van GetClientRect viel eerder net te
    ; smal uit voor elk control met WS_VSCROLL (bodyEdit in de Help-
    ; accordeon, aboutEdit op de Over-pagina): de scrollbalkstrook viel
    ; buiten de regio en werd daardoor onzichtbaar geknipt, ook wanneer er
    ; wel degelijk meer te scrollen was. GetWindowRect neemt de scrollbalk
    ; wel mee.
    rect := Buffer(16, 0)

    if !DllCall("GetWindowRect", "ptr", control.Hwnd, "ptr", rect, "int")
        return

    width := NumGet(rect, 8, "int") - NumGet(rect, 0, "int")
    height := NumGet(rect, 12, "int") - NumGet(rect, 4, "int")

    if width <= 0 || height <= 0
        return

    region := DllCall("CreateRoundRectRgn", "int", 0, "int", 0, "int", width + 1, "int", height + 1, "int", radius, "int", radius, "ptr")
    DllCall("SetWindowRgn", "ptr", control.Hwnd, "ptr", region, "int", true)
}
