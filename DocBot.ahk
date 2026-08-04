#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent true
#Include ThirdParty\JXON\JXON.ahk
#Include ThirdParty\ColorButton\ColorButton.ahk
#Include Telemetry.ahk
#Include ThirdParty\UIA-v2\UIA.ahk
#Include ThirdParty\UIA-v2\UIA_Browser.ahk

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

global AppVersion := "2.2-dev.4"

; Toegang tot het debugvenster is gekoppeld aan het Windows-account, niet
; aan een instelling die iedereen zelf kan aanzetten.
global IsDevMode := (A_UserName = "n.feenstra")
global StartupWindowState := GetRequestedStartupWindowState()

; Gebruikersgegevens staan buiten de programmamap en zijn bewust per
; releasekanaal gescheiden. Stable gebruikt DocBot, de centrale develop-
; versies met -dev of -rc gebruiken DocBot-test en feature-/fixbranches
; gebruiken DocBot-dev. Een prereleasebuild kan zo nooit productiedata migreren.
global AppDataFolderName := "DocBot"
global UserDataProfile := GetUserDataProfile(AppVersion)
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

global MainGui := 0
global Pages := Map("overzicht", [], "telefonie", [], "tekstvervanging", [], "instellingen", [], "help", [], "over", [])
global CurrentPage := ""
global HelpSections := []
global HelpOpenSection := 1
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

; Achtergrondlogging (zie DIAGNOSTIEK & LOGGING) — begrensd en gebufferd,
; zodat er al diagnostische data is zodra iemand een probleem meldt.
global DebugLogBuffer := ""
global DebugFlushPending := false
global DebugWindow := 0
global DebugLogEdit := 0
global DebugAutoScroll := true

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

InitializeUserStorage()
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
InitializeBundledPackages()
LoadAppSettings()
InitializeHotstringStorage()
InitializePackageSettings()
InitializeSpeedDialStorage()
ReloadRuntimeHotstrings()
Telemetry_Initialize(ConfigFile, AppVersion, GetTelemetryStatus)

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
    global OverviewPhoneActionsText, OverviewLongHotstringActionsText
    global HotLV, HotSearch, HotTriggerEdit, HotEnabledCheck
    global HotReplacementSingleGroup, HotReplacementMultiGroup
    global HotReplacementExpandButton, HotReplacementCollapseButton
    global HotEditorCompactCard, HotEditorExpandedCard, HotSaveButton
    global SidebarPhoneDot, SidebarPhoneText, SidebarTextDot, SidebarTextText
    global SpeedDialLV, SpeedDialEnabledCheck, SpeedDialNameEdit, SpeedDialNumberEdit

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
    phoneUsageIcon := AddCardLabel("overzicht", 270, 568, 36, 34, Chr(0xE717), "s20 c" C["Primary"], "Center")
    phoneUsageIcon.SetFont("s20 c" C["Primary"], "Segoe MDL2 Assets")
    AddCardLabel("overzicht", 320, 562, 160, 18, "Belacties", "s9 c" C["Muted"])
    OverviewPhoneActionsText := AddCardLabel("overzicht", 320, 582, 160, 34, Telemetry_GetPhoneActions(), "s22 bold c" C["Text"])
    hotstringUsageIcon := AddCardLabel("overzicht", 600, 568, 36, 34, Chr(0xE8FD), "s20 c" C["Primary"], "Center")
    hotstringUsageIcon.SetFont("s20 c" C["Primary"], "Segoe MDL2 Assets")
    AddCardLabel("overzicht", 650, 562, 220, 18, "Lange hotstrings", "s9 c" C["Muted"])
    OverviewLongHotstringActionsText := AddCardLabel("overzicht", 650, 582, 160, 34, Telemetry_GetLongHotstringActions(), "s22 bold c" C["Text"])
    AddCardLabel("overzicht", 650, 614, 280, 18, "Lange en meerregelige vervangingen", "s8 c" C["Muted"])

    overviewFooter := MainGui.AddText("x236 y672 w736 h18 Right Background" C["Window"], "Sluiten verbergt DocBot in het systeemvak")
    overviewFooter.SetFont("s8 c" C["Muted"], "Segoe UI")
    AddPageControl("overzicht", overviewFooter)

    ; -------------------------------------------------------------------------
    ; PAGINA: TELEFONIE
    ; -------------------------------------------------------------------------

    AddPageHeader("telefonie", "Telefonie", "Bel en beheer je snelkiesnummers.")

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

    phoneFooter := MainGui.AddText("x236 y672 w736 h18 Right Background" C["Window"], "Sluiten verbergt DocBot in het systeemvak")
    phoneFooter.SetFont("s8 c" C["Muted"], "Segoe UI")
    AddPageControl("telefonie", phoneFooter)

    ; -------------------------------------------------------------------------
    ; PAGINA: TEKSTVERVANGING
    ; -------------------------------------------------------------------------

    AddPageHeader("tekstvervanging", "Tekstvervanging", "Beheer de hotstrings van DocBot.")

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

    HotEditorCompactCard := AddCard("tekstvervanging", 236, 452, 736, 196)
    HotEditorExpandedCard := AddCard("tekstvervanging", 236, 452, 736, 230)
    AddCardLabel("tekstvervanging", 260, 472, 220, 22, "Hotstring bewerken", "s12 bold c" C["Text"])
    AddFlatButton("tekstvervanging", 588, 464, 220, 34, "⚙  Geavanceerde opties...", ShowAdvancedHotstringOptions, false)
    HotEnabledCheck := MainGui.AddCheckbox("x840 y472 w100 h22 Background" C["Card"], "Actief")
    HotEnabledCheck.Value := 1
    AddPageControl("tekstvervanging", HotEnabledCheck)
    AddCardLabel("tekstvervanging", 260, 512, 100, 20, "Afkorting", "s10 c" C["Text"])
    HotTriggerEdit := AddRoundedEdit("tekstvervanging", 370, 504, 586, 34, "")
    AddCardLabel("tekstvervanging", 260, 552, 100, 20, "Vervanging", "s10 c" C["Text"])
    HotReplacementSingleGroup := AddRoundedEditGroup("tekstvervanging", 370, 544, 538, 34, "", false, 8)
    HotReplacementMultiGroup := AddRoundedEditGroup("tekstvervanging", 370, 544, 538, 70, "", true, 6)
    HotReplacementSingleGroup["Edit"].OnEvent("Change", UpdateHotReplacementDraft)
    HotReplacementMultiGroup["Edit"].OnEvent("Change", UpdateHotReplacementDraft)
    ; Deze twee eenvoudige klikcontrols worden door Windows betrouwbaarder
    ; opnieuw getekend na hide/show dan twee overlappende custom-draw buttons.
    HotReplacementExpandButton := MainGui.AddText(
        "x920 y544 w36 h34 Center 0x200 Background" C["Button"],
        Chr(0xE740)
    )
    HotReplacementExpandButton.SetFont("s12 c" C["Text"], "Segoe MDL2 Assets")
    AddRound(HotReplacementExpandButton, 10)
    AddPageControl("tekstvervanging", HotReplacementExpandButton)
    HotReplacementExpandButton.OnEvent(
        "Click", ToggleHotReplacementEditor.Bind(true)
    )

    HotReplacementCollapseButton := MainGui.AddText(
        "x920 y544 w36 h34 Center 0x200 Background" C["Button"],
        Chr(0xE73F)
    )
    HotReplacementCollapseButton.SetFont("s12 c" C["Text"], "Segoe MDL2 Assets")
    AddRound(HotReplacementCollapseButton, 10)
    AddPageControl("tekstvervanging", HotReplacementCollapseButton)
    HotReplacementCollapseButton.OnEvent(
        "Click", ToggleHotReplacementEditor.Bind(false)
    )
    HotSaveButton := AddFlatButton("tekstvervanging", 808, 590, 148, 36, "💾  Opslaan", SaveHotstringFromForm, true)
    ApplyHotReplacementEditorState()

    ; -------------------------------------------------------------------------
    ; PAGINA: INSTELLINGEN
    ; -------------------------------------------------------------------------

    AddPageHeader("instellingen", "Instellingen", "Beheer de opslag, import en SMS-integratie.")

    AddCard("instellingen", 236, 92, 736, 194)
    AddCardLabel("instellingen", 260, 114, 250, 24, "Hotstringbestand", "s14 bold c" C["Text"])

    autoSaveCheck := MainGui.AddCheckbox("x260 y152 w340 h22 Background" C["Card"], "Hotstrings automatisch opslaan en laden")
    autoSaveCheck.Value := State["AutoSave"]
    AddPageControl("instellingen", autoSaveCheck)

    filePathEdit := AddRoundedEdit("instellingen", 260, 188, 520, 36, State["HotstringFile"])
    AddFlatButton("instellingen", 792, 188, 172, 36, "📁  Bladeren", BrowseHotstringFile.Bind(filePathEdit), false)
    AddFlatButton("instellingen", 260, 230, 220, 36, "↥  Oud .txt importeren", ImportLegacyHotstrings, false)
    AddFlatButton("instellingen", 692, 230, 132, 36, "📂  Laden", ManualLoadHotstrings.Bind(filePathEdit), false)
    AddFlatButton("instellingen", 832, 230, 132, 36, "💾  Opslaan", ManualSaveHotstrings.Bind(filePathEdit), true)

    AddCard("instellingen", 236, 304, 736, 202)
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

    AddCardLabel(
        "instellingen",
        260, 430, 688, 20,
        "Deze pagina wordt gebruikt bij de belactie 'Bellen of sms kiezen'.",
        "s9 c" C["Muted"]
    )
    smsAvailabilityText := smsActionTitles.Length = 1
        ? "1 SMS-pagina beschikbaar via lokale configuratie."
        : smsActionTitles.Length " SMS-pagina's beschikbaar via lokale configuratie."
    if smsActionTitles.Length = 0
        smsAvailabilityText := "Geen SMS-pagina beschikbaar; de bijbehorende belactie is uitgeschakeld."
    AddCardLabel("instellingen", 260, 462, 688, 20, smsAvailabilityText, "s9 c" C["Muted"])

    AddFlatButton(
        "instellingen",
        824, 526, 140, 38,
        "Opslaan",
        SaveSettings.Bind(autoSaveCheck, filePathEdit, smsActionDropDown),
        true,
        C["Window"]
    )

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
    AddHelpAccordionSection(
        "Hoe bel ik vanuit HiX?",
        "Kies bij Belactie op de pagina Overzicht wat DocBot met een herkend nummer moet doen."
        "`r`n`r`nKlik linksboven in HiX op het pijltje naast het telefoonnummer van de patiënt. "
        "Klik vervolgens op het getoonde telefoonnummer. DocBot herkent het nummer en voert de gekozen belactie uit."
        "`r`n`r`nJe kunt kiezen voor niets doen, bellen na bevestiging, direct bellen of bij externe nummers kiezen tussen bellen en sms. "
        "Interne nummers worden bij die laatste keuze direct gebeld."
        "`r`n`r`nBij een extern Nederlands 06-nummer opent SMS de onder Instellingen gekozen pagina en vult DocBot het telefoonnummer in."
        "`r`n`r`nSoms toont HiX na het kopiëren van het nummer een foutmelding. "
        "Deze melding kun je negeren zonder HiX af te sluiten.",
        ["Belactie", "Overzicht", "niets doen", "bellen na bevestiging", "direct bellen", "bellen en sms", "Interne nummers", "Instellingen", "SMS"],
        Map("Overzicht", "overzicht")
    )
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
    RefreshHelpAccordion()

    helpFooter := MainGui.AddText(
        "x236 y672 w736 h18 Right Background" C["Window"],
        "Sluiten verbergt DocBot in het systeemvak"
    )
    helpFooter.SetFont("s8 c" C["Muted"], "Segoe UI")
    AddPageControl("help", helpFooter)

    ; -------------------------------------------------------------------------
    ; PAGINA: OVER
    ; -------------------------------------------------------------------------

    AddPageHeader("over", "Over", "Informatie over DocBot.")

    AddCard("over", 236, 92, 736, 500)

    aboutShell := MainGui.AddText("x260 y116 w688 h452 Background" C["Border"], "")
    AddRound(aboutShell, 12)
    AddPageControl("over", aboutShell)

    aboutEdit := MainGui.AddEdit(
        "x262 y118 w684 h448 ReadOnly VScroll Multi -E0x200 BackgroundFFFFFF",
        BuildAboutText()
    )
    aboutEdit.SetFont("s10 c" C["Text"], "Segoe UI")
    AddRound(aboutEdit, 10)
    AddPageControl("over", aboutEdit)

    RefreshRegistrationTexts()
    RefreshHotstringList()
    RefreshSpeedDialList()
    ShowPage("overzicht")

    MainGui.OnEvent("Close", MainGui_Close)
    MainGui.OnEvent("Escape", MainGui_Escape)
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
    ; afgeronde hoeken ook na paginawisselingen stabiel blijven.
    collapsedCard := AddCard("help", 236, 104, 720, 64)
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
        throw Error("De navigatielinks in Help konden niet worden geactiveerd.")
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
    static WM_NCDESTROY := 0x0082
    static EM_CHARFROMPOS := 0x00D7

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
    }

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

RefreshHelpAccordion() {
    global HelpSections, HelpOpenSection

    y := 104
    gap := 12
    collapsedHeight := 64
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
        } else {
            section["Body"].Opt("+Hidden")
        }

        y += (isOpen ? expandedHeight : collapsedHeight) + gap
    }
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

SetCueText(editCtrl, text) {
    ; EM_SETCUEBANNER = 0x1501
    SendMessage(0x1501, 0, StrPtr(text), editCtrl)
}

ShowPage(pageKey, *) {
    global Pages, CurrentPage, NavButtons, NavBars, C

    CurrentPage := pageKey

    for key, controls in Pages {
        visible := key = pageKey
        for _, ctrl in controls
            ctrl.Opt(visible ? "-Hidden" : "+Hidden")
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
    else if pageKey = "overzicht"
        UpdateRegisterButtonState()
    else if pageKey = "help"
        RefreshHelpAccordion()

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
    text .= "DocBot is een tool die telefoonnummers kan kiezen via de interne IP-telefonie en teksten kan vervangen via hotstrings, geschreven om het werken met digitale hulpmiddelen in de werkplek van het Meander wat makkelijker te maken.`r`n`r`n"
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
    global State, SidebarPhoneDot, SidebarPhoneText, SidebarTextDot, SidebarTextText, C

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
    global OverviewPhoneActionsText, OverviewLongHotstringActionsText

    if IsObject(OverviewPhoneActionsText)
        OverviewPhoneActionsText.Value := Telemetry_GetPhoneActions()
    if IsObject(OverviewLongHotstringActionsText)
        OverviewLongHotstringActionsText.Value := Telemetry_GetLongHotstringActions()
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
; DIAGNOSTIEK & LOGGING
; =============================================================================

; Stille achtergrondlogging: verzamelt regels in het geheugen en schrijft ze
; periodiek in één keer weg, i.p.v. een losse FileAppend per regel.
DebugLog(richting, label, tekst) {
    global DebugLogBuffer, DebugFlushPending, DebugLogEdit, DebugAutoScroll

    tijd := FormatTime(A_Now, "HH:mm:ss") . "." . A_MSec
    regel := tijd . " " . richting . " " . label . "`r`n" . tekst . "`r`n───`r`n"

    DebugLogBuffer .= regel

    if !DebugFlushPending {
        DebugFlushPending := true
        SetTimer FlushDebugLog, -2000   ; verzamel 2 seconden, dan in één keer wegschrijven
    }

    if IsObject(DebugLogEdit) {
        DebugLogEdit.Value .= regel
        ; venster begrenzen: bij te veel regels de oudste helft afknippen
        if StrLen(DebugLogEdit.Value) > 500000 {
            volledigeTekst := DebugLogEdit.Value
            DebugLogEdit.Value := SubStr(volledigeTekst, StrLen(volledigeTekst) // 2)
        }
        if DebugAutoScroll
            SendMessage(0x115, 7, 0, DebugLogEdit)  ; WM_VSCROLL, SB_BOTTOM — automeescrollen
    }
}

FlushDebugLog() {
    global DebugLogBuffer, DebugFlushPending

    ; %LocalAppData% i.p.v. A_MyDocuments: dat laatste is bij deze gebruiker
    ; OneDrive-gesynchroniseerd en een puur lokaal, wegwerpbaar logbestand
    ; hoort daar niet elke schrijfactie de sync te triggeren.
    ; (A_LocalAppData bestaat niet als ingebouwde AHK-variabele; vandaar EnvGet.)
    logDir := EnvGet("LocalAppData") . "\DocBot"
    logPath := logDir . "\debug.log"

    if !DirExist(logDir)
        DirCreate(logDir)

    if FileExist(logPath) && FileGetSize(logPath) > 2000000  ; 2MB
        FileMove(logPath, logPath . ".oud", true)  ; simpele rotatie, 1 backup

    FileAppend(DebugLogBuffer, logPath, "UTF-8")
    DebugLogBuffer := ""
    DebugFlushPending := false
}

; Live debugvenster — alleen bereikbaar via het systeemvakmenu als IsDevMode.
ShowDebugWindow(*) {
    global DebugWindow, DebugLogEdit, DebugAutoScroll

    if IsObject(DebugWindow) {
        DebugWindow.Show()
        return
    }

    DebugWindow := Gui("+Resize", "DocBot - Telefonie debug")
    DebugLogEdit := DebugWindow.AddEdit("w700 h400 ReadOnly VScroll +Wrap", "")
    DebugLogEdit.SetFont("s9", "Consolas")

    clearBtn := DebugWindow.AddButton("w100", "Wissen")
    clearBtn.OnEvent("Click", (*) => DebugLogEdit.Value := "")

    autoScrollCheck := DebugWindow.AddCheckbox("x+10 y+0 Checked", "Automatisch meescrollen")
    autoScrollCheck.OnEvent("Click", (*) => DebugAutoScroll := autoScrollCheck.Value)

    DebugWindow.OnEvent("Close", (*) => (DebugWindow := 0, DebugLogEdit := 0))
    DebugWindow.Show()
}

; Bouwt een diagnosepakket met uitsluitend het logbestand en zet een
; conceptmail klaar — de gebruiker hoeft zelf niets in te kunnen zien.
SendDiagnostics(*) {
    zipPath := A_Temp . "\DocBot_diagnose_" . FormatTime(A_Now, "yyyyMMdd_HHmmss") . ".zip"
    logPath := EnvGet("LocalAppData") . "\DocBot\debug.log"

    if !FileExist(logPath) {
        MsgBox("Er is nog geen logbestand. Vraag de gebruiker het probleem eerst nogmaals te laten optreden.", "DocBot")
        return
    }

    ; Alleen het logbestand meenemen — NOOIT settings.ini of credential-gerelateerde
    ; bestanden, want daar kunnen wachtwoorden in staan
    Compress(logPath, zipPath)

    try {
        outlook := ComObject("Outlook.Application")
        fullName := outlook.Session.CurrentUser.Name
        mail := outlook.CreateItem(0)
        mail.To := "n.feenstra@meandermc.nl"
        mail.Subject := "DocBot probleem - " . A_UserName . " - versie: " . AppVersion
        mail.Body := "Hoi Nico, `r`n`r`nIk heb het volgende probleem met " . A_ScriptName . ":`r`n`r`nAutomatisch gegenereerd diagnosepakket is bijgevoegd.`r`n`r`nMet vriendelijke groeten,`r`n`r`n" . fullName
        mail.Attachments.Add(zipPath)
        mail.Display()  ; toont als concept, gebruiker moet zelf op Verzenden klikken
    } catch {
        Run("explorer.exe /select," . zipPath)  ; fallback: gebruiker mailt/teamst het zelf
    }
}

; Zet sourcePath in een nieuw zip-archief via de Shell-namespace, zonder
; externe afhankelijkheden (Msxml2/COM en Explorer zijn altijd aanwezig).
Compress(sourcePath, zipPath) {
    if FileExist(zipPath)
        FileDelete(zipPath)

    ; Minimale lege ZIP-structuur (End Of Central Directory record), zodat
    ; de Shell-namespace het bestand als zip-archief herkent.
    header := Buffer(22, 0)
    NumPut("UChar", 0x50, header, 0)
    NumPut("UChar", 0x4B, header, 1)
    NumPut("UChar", 0x05, header, 2)
    NumPut("UChar", 0x06, header, 3)

    file := FileOpen(zipPath, "w")
    file.RawWrite(header)
    file.Close()

    shell := ComObject("Shell.Application")
    zipFolder := shell.NameSpace(zipPath)
    zipFolder.CopyHere(sourcePath)

    ; Wachten tot de Shell het bestand daadwerkelijk heeft toegevoegd.
    Loop 50 {
        if zipFolder.Items().Count > 0
            break
        Sleep(200)
    }
}

ClipBoardPoller() {
    global State
    static lastSeq := DllCall("GetClipboardSequenceNumber")  ; voorkomt dat de klembordinhoud bij opstarten al wordt opgepakt

    seq := DllCall("GetClipboardSequenceNumber")
    if seq = lastSeq
        return

    lastSeq := seq

    externalTel := NormalizePhoneNumberExternal(A_ClipBoard)
    if externalTel != "" {
        State["IPT"]["ClipBoardNumber"] := externalTel
        HandleClipboardNumberDetected()
        return
    }

    internalTel := NormalizePhoneNumberInternal(A_ClipBoard)
    if internalTel != "" {
        State["IPT"]["ClipBoardNumber"] := internalTel
        HandleInternalClipboardNumberDetected()
    }
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

    action := State["CallAction"]
    switch action {
        case 0:
            return
        case 1:
            ShowCallConfirmationDialog()
        case 2:
            IPT_callNumber(State["IPT"]["ClipBoardNumber"])
        case 3:
            ShowCallOrSmsChoiceDialog()
    }
}

; Een intern 4-cijferig nummer volgt dezelfde Belactie, behalve bij de
; keuze bellen/sms: SMS is alleen beschikbaar voor externe nummers en
; daarom wordt een intern nummer in stand 3 direct gebeld.
HandleInternalClipboardNumberDetected() {
    global State

    action := State["CallAction"]
    switch action {
        case 0:
            return
        case 1:
            ShowCallConfirmationDialog()
        case 2, 3:
            IPT_callNumber(State["IPT"]["ClipBoardNumber"])
    }
}

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

ClosePhoneActionDialog(dialog, *) {
    global PhoneActionDialogState

    if IsObject(PhoneActionDialogState)
        && PhoneActionDialogState["DialogHwnd"] = dialog.Hwnd {
        PhoneActionDialogState := 0
    }

    try dialog.Destroy()
}

ExecutePhoneActionCallChoice(dialog, number, *) {
    ClosePhoneActionDialog(dialog)
    IPT_callNumber(number)
}

StartSmsCallAction(dialog, number, *) {
    ClosePhoneActionDialog(dialog)

    smsNumber := NormalizeSmsPhoneNumber(number)
    if smsNumber = "" {
        ShowNotification(
            "SMS versturen is alleen mogelijk naar een Nederlands 06-nummer.",
            4500,
            "warning"
        )
        DebugLog(
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
        DebugLog("✕", "SMS actie geweigerd", "Geen geselecteerde SmsCallAction gevonden.")
        return
    }

    try {
        ; Succes is direct zichtbaar doordat Edge met het ingevulde veld op de
        ; voorgrond staat. Toon alleen nog een melding als de actie mislukt.
        if !RunSmsCallAction(smsConfig, smsNumber) {
            ShowNotification(
                "De SMS-pagina of het telefoonveld kon niet worden gevonden.",
                5000,
                "error"
            )
        }
    } catch as smsError {
        DebugLog("✕", "SMS actie", smsError.Message)
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

    DebugLog(
        "→",
        "SMS actie",
        "Start voor '" smsConfig["Title"] "' met nummer "
            MaskSmsPhoneNumber(number) ". Eerst WinActivate(WindowTitle), daarna UIA."
    )

    try {
        edge := ActivateSmsEdgeWindowByTitle(smsConfig["WindowTitle"])

        if !IsObject(edge)
            edge := ActivateSmsEdgeTabByTitle(smsConfig["WindowTitle"])

        if !IsObject(edge)
            edge := OpenSmsPage(smsConfig["Url"], smsConfig["WindowTitle"])

        if !IsObject(edge) {
            DebugLog(
                "✕",
                "SMS vensterselectie",
                "WinActivate, UIA-tabselectie en URL-fallback vonden geen bruikbare Edge-tab."
            )
            return false
        }

        if FillSmsPhoneFieldWithUIA(edge, smsConfig["FieldId"], number) {
            DebugLog(
                "✓",
                "SMS veldinvulling",
                "AutomationId '" smsConfig["FieldId"] "' via UI Automation ingevuld."
            )
            return true
        }

        DebugLog(
            "→",
            "SMS veldinvulling",
            "UIA Edit-element niet gevonden; JavaScriptfallback wordt uitgevoerd."
        )
        return FillSmsDomFieldWithJavaScript(
            edge,
            smsConfig["FieldId"],
            number
        )
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
            "Titelmatch werd niet binnen 1 seconde actief."
        )
        return 0
    }

    try {
        edge := UIA_Browser(hwnd)
        DebugLog(
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
        edgeWindows.Length " bruikbare Edge-browservenster(s) gevonden; "
            "TabExist wordt per venster uitgevoerd."
    )

    for index, hwnd in edgeWindows {
        try {
            if WinGetMinMax("ahk_id " hwnd) = -1
                WinRestore("ahk_id " hwnd)

            edge := UIA_Browser(hwnd)
            tab := edge.TabExist(targetTitle, 2, false)
            if !tab
                continue

            edge.SelectTab(tab)
            WinActivate("ahk_id " hwnd)
            if WinWaitActive("ahk_id " hwnd, , 2) {
                DebugLog(
                    "✓",
                    "SMS UIA-tabselectie",
                    "Tab gevonden in Edge-browservenster " index
                        " en geactiveerd in " (A_TickCount - startedAt) " ms."
                )
                return edge
            }
        } catch as windowError {
            DebugLog(
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
            " bruikbare Edge-browservenster(s), duur "
            (A_TickCount - startedAt) " ms."
    )
    return 0
}

OpenSmsPage(url, targetTitle) {
    DebugLog(
        "→",
        "SMS URL-fallback",
        "Geen bestaande tab gevonden; de lokaal geconfigureerde pagina wordt in Edge geopend."
    )

    try Run('msedge.exe "' url '"')
    catch as runError {
        DebugLog("✕", "SMS URL-fallback", "Edge starten mislukte: " runError.Message)
        return 0
    }

    ; Bewust uitsluitend WindowTitle gebruiken. De POC heeft aangetoond dat
    ; een samengestelde query met ahk_exe in deze werkomgeving niet betrouwbaar is.
    hwnd := WinWaitActive(targetTitle, , 10)
    if !hwnd {
        DebugLog(
            "✕",
            "SMS URL-fallback",
            "De geconfigureerde WindowTitle werd niet binnen 10 seconden actief."
        )
        return 0
    }

    try {
        edge := UIA_Browser(hwnd)
        DebugLog("✓", "SMS URL-fallback", "Nieuwe Edge-tab actief en UIA_Browser gekoppeld.")
        return edge
    } catch as browserError {
        DebugLog(
            "✕",
            "SMS URL-fallback",
            "UIA_Browser koppelen aan de nieuwe tab mislukte: " browserError.Message
        )
        return 0
    }
}

FillSmsPhoneFieldWithUIA(edge, fieldId, value, timeoutMs := 5000) {
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
            DebugLog(
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

    DebugLog(
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

    js := "(()=>{"
        . "const e=document.getElementById('" escapedFieldId "');"
        . "if(!e){throw new Error('DocBot: SMS-veld niet gevonden');}"
        . "const s=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;"
        . "s.call(e,'" escapedValue "');"
        . "e.dispatchEvent(new Event('input',{bubbles:true}));"
        . "e.dispatchEvent(new Event('change',{bubbles:true}));"
        . "e.focus();"
        . "return true;"
        . "})()"

    try {
        edge.JSExecute(js)
        DebugLog(
            "✓",
            "SMS JavaScriptfallback",
            "Veld '" fieldId "' ingevuld; input- en change-events verstuurd."
        )
        return true
    } catch as jsError {
        DebugLog("✕", "SMS JavaScriptfallback", jsError.Message)
        return false
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
    global MainGui, C, BundledPackages
    global PackageManagerGui, PackageManagerPackageLV, PackageManagerItemLV
    global PackageManagerStatusText

    if BundledPackages.Count = 0 {
        MsgBox(
            "Er zijn geen meegeleverde hotstringpakketten beschikbaar.",
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

    intro := PackageManagerGui.AddText(
        "x24 y54 w852 h28 Background" C["Window"],
        "Kies links een pakket en bekijk rechts eerst de inhoud en eventuele conflicten."
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

    if !IsObject(PackageManagerStatusText)
        return

    selected := GetSelectedPackageManagerItem()
    if !IsObject(selected) {
        PackageManagerStatusText.Value := "Selecteer een pakketitem."
        return
    }

    packageId := selected["PackageId"]
    itemId := selected["ItemId"]
    package := BundledPackages[packageId]
    packageItem := FindBundledPackageItem(packageId, itemId)
    conflict := FindPackageItemConflict(packageId, itemId)

    status := GetPackageItemStatus(packageId, itemId)
    detail := package["name"] " · " status

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
    global CurrentPage, HotReplacementExpanded, HotReplacementSingleGroup, HotReplacementMultiGroup
    global HotReplacementExpandButton, HotReplacementCollapseButton, HotEditorCompactCard, HotEditorExpandedCard, HotSaveButton
    if !IsObject(HotReplacementSingleGroup)
        return
    visible := CurrentPage = "tekstvervanging"
    SetControlGroupVisible(HotReplacementSingleGroup, visible && !HotReplacementExpanded)
    SetControlGroupVisible(HotReplacementMultiGroup, visible && HotReplacementExpanded)
    HotEditorCompactCard.Opt(visible && !HotReplacementExpanded ? "-Hidden" : "+Hidden")
    HotEditorExpandedCard.Opt(visible && HotReplacementExpanded ? "-Hidden" : "+Hidden")
    HotReplacementExpandButton.Opt(visible && !HotReplacementExpanded ? "-Hidden" : "+Hidden")
    HotReplacementCollapseButton.Opt(visible && HotReplacementExpanded ? "-Hidden" : "+Hidden")
    HotSaveButton.Move(808, HotReplacementExpanded ? 626 : 590, 148, 36)
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
    global RuntimeHotstrings, State

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
                callback := SendHotstringText.Bind(replacement)
                Hotstring(hotstringSpec, callback, true)
                RuntimeHotstrings[hotstringSpec] := callback
            } else if mode = "dynamic-text" {
                callback := SendDynamicHotstringText.Bind(replacement)
                Hotstring(hotstringSpec, callback, true)
                RuntimeHotstrings[hotstringSpec] := callback
            } else if mode = "dynamic-keys" {
                callback := SendDynamicHotstringKeys.Bind(replacement)
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

SendHotstringText(replacement, *) {
    Telemetry_RecordLongHotstring()
    RefreshUsageStatistics()
    SendPlainHotstringText(replacement)
}

SendDynamicHotstringText(replacement, *) {
    expanded := ExpandDynamicHotstringCodes(replacement)

    if IsLongOrMultilineHotstring(expanded) {
        Telemetry_RecordLongHotstring()
        RefreshUsageStatistics()
    }

    SendPlainHotstringText(expanded)
}

SendDynamicHotstringKeys(replacement, *) {
    Send(ExpandDynamicHotstringCodes(replacement))
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

GetBundledPackageDirectory() {
    localAppData := EnvGet("LocalAppData")
    if localAppData = ""
        throw Error("De Windows-map LocalAppData kon niet worden gevonden.")

    ; Ongecompileerde tests blijven strikt gescheiden van de productcache.
    cacheName := A_IsCompiled ? "DocBot" : "DocBot-dev"
    packageDir := localAppData "\\" cacheName "\\packages"

    if !DirExist(packageDir)
        DirCreate(packageDir)

    InstallBundledPackageFiles(packageDir)
    return packageDir
}

InstallBundledPackageFiles(packageDir) {
    packageFiles := [
        "manifest.json",
        "nl-taal.json",
        "medisch-algemeen.json",
        "controles.json",
        "spelfouten-wikipedia.json",
        "gyn-obst.json"
    ]

    if A_IsCompiled {
        ; De bronpaden van FileInstall moeten letterlijk in het script staan,
        ; zodat Ahk2Exe alle pakketten in de executable kan opnemen.
        FileInstall "packages\manifest.json", packageDir "\manifest.json", true
        FileInstall "packages\nl-taal.json", packageDir "\nl-taal.json", true
        FileInstall "packages\medisch-algemeen.json", packageDir "\medisch-algemeen.json", true
        FileInstall "packages\controles.json", packageDir "\controles.json", true
        FileInstall "packages\spelfouten-wikipedia.json", packageDir "\spelfouten-wikipedia.json", true
        FileInstall "packages\gyn-obst.json", packageDir "\gyn-obst.json", true
        return
    }

    ; Tijdens ontwikkeling worden de bronbestanden naar een aparte cache
    ; gekopieerd. Daardoor raakt een test nooit de productiecache.
    for _, fileName in packageFiles {
        FileCopy(
            A_ScriptDir "\packages\" fileName,
            packageDir "\" fileName,
            true
        )
    }
}

InitializeBundledPackages() {
    global BundledPackageDir, BundledPackages, BundledPackageSchemaVersion

    try {
        BundledPackageDir := GetBundledPackageDirectory()
        manifestPath := BundledPackageDir "\manifest.json"
        manifest := LoadBundledJsonFile(manifestPath)

        if !(manifest is Map)
            throw Error("Het pakketmanifest moet een JSON-object zijn.")

        schemaVersion := manifest.Has("schemaVersion")
            ? (manifest["schemaVersion"] + 0)
            : 1

        if schemaVersion > BundledPackageSchemaVersion {
            throw Error(
                Format(
                    "Het pakketmanifest gebruikt schemaVersion {1}, maar deze DocBot-versie ondersteunt maximaal versie {2}.",
                    schemaVersion,
                    BundledPackageSchemaVersion
                )
            )
        }

        if !manifest.Has("packages") || !(manifest["packages"] is Array)
            throw Error("Het veld 'packages' ontbreekt in het pakketmanifest.")

        loadedPackages := Map()

        for _, packageEntry in manifest["packages"] {
            if !(packageEntry is Map)
                throw Error("Een pakketvermelding in het manifest is ongeldig.")

            if !packageEntry.Has("id") || !packageEntry.Has("file")
                throw Error("Een pakketvermelding mist 'id' of 'file'.")

            packageId := Trim(packageEntry["id"])
            fileName := Trim(packageEntry["file"])
            package := LoadBundledPackageFile(BundledPackageDir "\\" fileName)

            if package["id"] != packageId {
                throw Error(
                    Format(
                        "Pakket-id '{1}' komt niet overeen met manifest-id '{2}'.",
                        package["id"],
                        packageId
                    )
                )
            }

            if loadedPackages.Has(packageId)
                throw Error("Dubbel pakket-id in manifest: " packageId)

            loadedPackages[packageId] := package
        }

        BundledPackages := loadedPackages
        return true
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

    schemaVersion := package.Has("schemaVersion")
        ? (package["schemaVersion"] + 0)
        : 1

    if schemaVersion > BundledPackageSchemaVersion {
        throw Error(
            Format(
                "Pakket {1} gebruikt schemaVersion {2}, maximaal ondersteund is {3}.",
                path,
                schemaVersion,
                BundledPackageSchemaVersion
            )
        )
    }

    for _, requiredField in ["id", "name", "version", "items"] {
        if !package.Has(requiredField)
            throw Error("Pakket mist verplicht veld '" requiredField "': " path)
    }

    if !(package["items"] is Array)
        throw Error("Het veld 'items' moet een lijst zijn: " path)

    seenIds := Map()
    seenTriggers := Map()

    for index, item in package["items"] {
        if !(item is Map)
            throw Error("Ongeldig pakketitem op positie " index ": " path)

        for _, requiredField in ["id", "trigger", "replacement"] {
            if !item.Has(requiredField)
                throw Error("Pakketitem " index " mist veld '" requiredField "'.")
        }

        itemId := Trim(item["id"])
        trigger := StrLower(Trim(item["trigger"]))
        replacement := item["replacement"] ""

        if itemId = "" || trigger = "" || replacement = ""
            throw Error("Pakketitem " index " bevat een lege id, trigger of vervanging.")

        if seenIds.Has(itemId)
            throw Error("Dubbel item-id in pakket: " itemId)
        if seenTriggers.Has(trigger)
            throw Error("Dubbele afkorting in pakket: " trigger)

        seenIds[itemId] := true
        seenTriggers[trigger] := true
    }

    if package.Has("itemCount") && (package["itemCount"] + 0) != package["items"].Length {
        throw Error(
            Format(
                "Pakket {1} vermeldt {2} items, maar bevat er {3}.",
                package["id"],
                package["itemCount"],
                package["items"].Length
            )
        )
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
        LoadPackageSettingsFromJson(DefaultPackageSettingsFile)
    else {
        PackageSettings := DefaultPackageSettings()
        SavePackageSettingsToJson(DefaultPackageSettingsFile)
    }
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

    schemaVersion := document.Has("schemaVersion")
        ? (document["schemaVersion"] + 0)
        : 1
    if schemaVersion > PackageSettingsSchemaVersion
        throw Error("Deze versie van package-settings.json wordt nog niet ondersteund.")

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
        return

    path := Trim(State["HotstringFile"])
    if path = ""
        return

    if FileExist(path) {
        LoadHotstringsFromJson(path, false)
        return
    }

    ; Bij de eerste start wordt het standaardmodel direct aangemaakt.
    SaveHotstringsToJson(path, false)
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

        schemaVersion := document.Has("schemaVersion")
            ? (document["schemaVersion"] + 0)
            : 1

        if schemaVersion > HotstringSchemaVersion {
            throw Error(
                Format(
                    "Dit bestand gebruikt schemaVersion {1}, maar deze DocBot-versie ondersteunt maximaal versie {2}.",
                    schemaVersion,
                    HotstringSchemaVersion
                )
            )
        }

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

    if FileExist(DefaultSpeedDialFile) {
        LoadSpeedDialFromJson(DefaultSpeedDialFile, false)
        return
    }

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
        if FileExist(DefaultSpeedDialFile) {
            LoadSpeedDialFromJson(DefaultSpeedDialFile, false)
            return
        }
    }

    ; Bij de eerste start wordt een lege lijst direct aangemaakt.
    SaveSpeedDialToJson(DefaultSpeedDialFile, false)
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

        schemaVersion := document.Has("schemaVersion")
            ? (document["schemaVersion"] + 0)
            : 1

        if schemaVersion > SpeedDialSchemaVersion {
            throw Error(
                Format(
                    "Dit bestand gebruikt schemaVersion {1}, maar deze DocBot-versie ondersteunt maximaal versie {2}.",
                    schemaVersion,
                    SpeedDialSchemaVersion
                )
            )
        }

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

    Telemetry_ValidateConfiguration(LocalConfig)
    ValidateSmsCallActionsConfiguration(LocalConfig)

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

NormalizeCallAction(value, fallback := 1) {
    value := ParseCallActionSetting(value, fallback)
    return value = 3 && !HasConfiguredSmsCallActions() ? fallback : value
}

GetUserDataProfile(appVersion) {
    normalizedVersion := StrLower(Trim(appVersion))

    ; Een stabiele SemVer bestaat hier uitsluitend uit cijfers en punten.
    if RegExMatch(normalizedVersion, "^\d+(?:\.\d+)*$")
        return "main"

    ; -dev en -rc direct achter het numerieke versienummer gebruiken het
    ; testkanaal. Bijvoorbeeld: 2.1-dev, 2.1-dev.15 en 2.1-rc.1.
    if RegExMatch(normalizedVersion, "^\d+(?:\.\d+)*-(?:dev|rc)(?:\.\d+|\d+)?$")
        return "test"

    ; Iedere andere prerelease/build met letters is een feature- of fixbuild.
    ; Ook een onverwachte niet-stabiele notatie valt uit veiligheid in dev,
    ; zodat zo'n build nooit de productiegegevens gebruikt.
    return "dev"
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

InitializeUserStorage() {
    global UserDataDir, ConfigFile, DefaultHotstringFile

    copiedFromDir := ""

    try {
        if !DirExist(UserDataDir) {
            seedDir := GetUserDataSeedDirectory()

            ; Test start eenmalig vanuit main. Dev start bij voorkeur vanuit
            ; test en valt terug op main als er nog geen testprofiel bestaat.
            if seedDir != "" && DirExist(seedDir) {
                DirCopy(seedDir, UserDataDir, false)
                copiedFromDir := seedDir
            } else {
                DirCreate(UserDataDir)
            }
        }

        if copiedFromDir != ""
            RebaseCopiedHotstringPath(copiedFromDir)
    } catch as error {
        MsgBox(
            "De gebruikersmap kon niet worden voorbereid.`n`n"
            UserDataDir "`n`n" error.Message,
            "DocBot",
            "Icon!"
        )
        ExitApp()
    }

    ; Eenmalige, voorzichtige migratie vanaf oudere versies die hun bestanden
    ; naast het script bewaarden. Bestaande bestanden in de gebruikersmap
    ; worden nooit overschreven.
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


; Controleer na het voorbereiden van de gebruikersmap of de map zelf en alle
; bestaande, door DocBot beheerde gegevensbestanden daadwerkelijk schrijfbaar
; zijn. De echte schrijfacties houden daarnaast hun eigen foutafhandeling.
ValidateUserStorageAccess() {
    global UserDataDir, ConfigFile, DefaultHotstringFile
    global DefaultPackageSettingsFile, DefaultSpeedDialFile

    AssertUserStorageDirectoryWritable(UserDataDir)

    managedFiles := [
        ConfigFile,
        DefaultHotstringFile,
        DefaultPackageSettingsFile,
        DefaultSpeedDialFile
    ]

    for _, path in managedFiles {
        if FileExist(path)
            AssertUserStorageFileWritable(path)
    }
}

AssertUserStorageDirectoryWritable(directory) {
    if !DirExist(directory) {
        throw Error(
            "De gebruikersmap bestaat niet.`n`n"
            . directory
        )
    }

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
    } catch as caughtError {
        if IsObject(probeFile)
            try probeFile.Close()
        if FileExist(probePath)
            try FileDelete(probePath)

        throw Error(
            "DocBot kan niet schrijven in de gebruikersmap.`n`n"
            . directory
            . "`n`n"
            . caughtError.Message
        )
    }
}

AssertUserStorageFileWritable(path) {
    file := 0

    try {
        attributes := FileGetAttrib(path)

        if InStr(attributes, "D") {
            throw Error(
                "DocBot verwachtte een bestand, maar vond een map.`n`n"
                . path
            )
        }

        if InStr(attributes, "R") {
            throw Error(
                "Dit DocBot-bestand is alleen-lezen.`n`n"
                . path
            )
        }

        file := FileOpen(path, "rw")
        if !IsObject(file)
            throw Error("Het bestand kon niet voor lezen en schrijven worden geopend.")

        file.Close()
        file := 0
    } catch as caughtError {
        if IsObject(file)
            try file.Close()

        if InStr(caughtError.Message, path)
            throw caughtError

        throw Error(
            "DocBot kan dit bestand niet wijzigen.`n`n"
            . path
            . "`n`n"
            . caughtError.Message
        )
    }
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
    global State, ConfigFile

    if !FileExist(ConfigFile)
        return

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

SaveSettings(autoSaveCheck, filePathEdit, smsActionDropDown, *) {
    global State

    State["AutoSave"] := autoSaveCheck.Value = 1
    State["HotstringFile"] := Trim(filePathEdit.Value)
    State["SmsCallActionTitle"] := HasConfiguredSmsCallActions()
        ? ResolveSmsCallActionTitle(smsActionDropDown.Text)
        : ""

    if State["HotstringFile"] = "" {
        MsgBox("Kies eerst een JSON-bestand.", "DocBot", "Icon!")
        return
    }

    settingsSaved := SaveAppSettings()
    dataSaved := !State["AutoSave"] || AutoSaveHotstrings()

    BuildTrayMenu()

    if settingsSaved && dataSaved
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

    ; Gebufferde logregels alsnog wegschrijven, anders gaan ze verloren.
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

    ; Alleen als submenu-alternatief: platte lijst direct in het hoofdmenu,
    ; met een disabled sectiekopje erboven (zelfde patroon als het
    ; geregistreerd-nummer-label bovenaan). Streep + blok worden samen
    ; overgeslagen zonder entries.
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

    A_TrayMenu.Add()
    if IsDevMode
        A_TrayMenu.Add("Debug-venster tonen", ShowDebugWindow)
    A_TrayMenu.Add("Probleem melden...", SendDiagnostics)

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
    rect := Buffer(16, 0)

    if !DllCall("GetClientRect", "ptr", control.Hwnd, "ptr", rect, "int")
        return

    width := NumGet(rect, 8, "int")
    height := NumGet(rect, 12, "int")

    if width <= 0 || height <= 0
        return

    region := DllCall("CreateRoundRectRgn", "int", 0, "int", 0, "int", width + 1, "int", height + 1, "int", radius, "int", radius, "ptr")
    DllCall("SetWindowRgn", "ptr", control.Hwnd, "ptr", region, "int", true)
}
