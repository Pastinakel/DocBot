DocBot
======

Overzicht
---------
DocBot is een AutoHotkey v2-hulpmiddel voor medewerkers met twee hoofdfuncties:
(a) tekstvervanging via hotstrings, en (b) bellen via de interne IP-telefonie
van het ziekenhuis, inclusief automatische detectie van telefoonnummers op
het klembord. Alles draait via één GUI met sidebar-navigatie en een
tray-icoon.

Deze README beschrijft DocBot 2.1 op de `main`-branch. Versie 2.1 is de
huidige stabiele productieversie; nieuwe functionaliteit wordt eerst via
`develop`, afzonderlijke featurebranches en het testprofiel beproefd.

Bestanden
---------
- `DocBot.ahk` — stabiele versie 2.1 met de huidige GUI,
  telefoniefunctionaliteit, hotstrings, snelkiesnummers en pakketbeheer.
- `packages/` — versieerbare ingebouwde hotstringpakketten plus manifest.
- `ColorButton.ahk` — custom-draw ondersteuning voor de moderne knoppen.
- `JXON.ahk` — JSON-library van TheArkive, gebruikt voor het laden en
  opslaan van gebruikersgegevens.
- `LICENSE-JXON.md` — MIT-licentie van de JXON-library.
- `LICENSE` — MIT-licentie van DocBot.
- `AGENTS.md` en `CLAUDE.md` — project- en werkinstructies voor
  AI-assistenten.

De verwijderde legacybron blijft beschikbaar in de Git-geschiedenis en op
de vaste archieftak `archive/legacy-v2-final`; hij maakt geen deel meer uit
van de actieve ontwikkel- en distributiebestanden.

Er is geen apart bestand voor debug-logging in de repo: dat logbestand wordt
tijdens het draaien van het script aangemaakt op de gebruikerscomputer (zie
"Diagnostiek" hieronder).

Installatie
-----------
Laat `DocBot.ahk` en `JXON.ahk` in dezelfde map staan. Kopieer
`DocBot.local.example.ahk` naar `DocBot.local.ahk`, vul lokaal de
telefonieserver, endpointnamen, standaard-snelkiesnummers en
standaard-hotstrings in en compileer daarna `DocBot.ahk` met AutoHotkey v2.
Het echte lokale bestand staat in `.gitignore` en wordt niet naar GitHub
gestuurd. Ahk2Exe neemt het tijdens compilatie wel op in de executable. Het programma wordt alleen als gecompileerde executable aan
de eindgebruiker aangeboden zodat dit niet aangepast kan worden.
Bij de eerste start maakt het script zelf een gebruikersmap aan (zie hieronder) 
voor instellingen en hotstrings — daar is verder niets voor te installeren of 
te configureren.

`Build-EPD_Machine.bat` compileert in de bronmap eerst `DocBot.exe` en
plaatst vervolgens een kopie in de bovenliggende applicatiemap, met de naam
van die map. Wanneer het script een centrale `-dev`-versie bevat en de
batch vanuit een directe submap van `DocBot` draait, kan optioneel ook
`EPD_Machine.exe` in de naastgelegen applicatiemap worden bijgewerkt. Voor
iedere gekozen doelmap plaatst de batch tijdelijk `ALL:update` in het
lokale `signal.txt`. Een actieve DocBot-instantie registreert vóór het
afsluiten een eenmalige taak in Windows Taakplanner. De batch probeert daarna
iedere seconde, maximaal vijfentwintig seconden lang, de executable te
verwijderen, te vervangen en byte-voor-byte te verifiëren. Na kopiëren of na
een fout wordt het updatesignaal altijd verwijderd. De geplande taak start
de beschikbare executable opnieuw met dezelfde vensterstatus — actief, op de
achtergrond of geminimaliseerd — en wordt na een geslaagde herstart door
DocBot weer verwijderd.

Functionaliteit — Hotstrings
-----------------------------
- Hotstrings worden opgeslagen als JSON. Standaardlocatie is
  `%MyDocuments%\DocBot\hotstrings.json`; instellingen (waaronder AutoSave en
  het gekozen hotstringbestand) staan in `%MyDocuments%\DocBot\settings.ini`.
  Keuzes voor meegeleverde pakketten staan afzonderlijk in
  `%MyDocuments%\DocBot\package-settings.json`.
- Gebruikersgegevens zijn per releasekanaal gescheiden: stabiele numerieke
  versies gebruiken `%MyDocuments%\DocBot`, centrale `-dev`-versies
  gebruiken `DocBot-test` en feature- of fixversies met een ander
  prereleaselabel gebruiken `DocBot-dev`. Een ontbrekend testprofiel wordt
  vanuit main gekopieerd; een ontbrekend devprofiel bij voorkeur vanuit test
  en anders vanuit main. Opgeslagen interne hotstringpaden worden naar de
  doelmap omgezet voordat de normale datamodelmigraties draaien.
- Het bewerkformulier toont vervangingen standaard op één regel en kan
  worden uitgeklapt naar drie regels. Een geladen meerregelige vervanging
  klapt automatisch uit. Het JSON-model houdt één veld `Replacement`; een
  apart datatype voor lange of meerregelige teksten is niet nodig.
- DocBot kiest de uitvoermethode automatisch: korte enkelregelige tekst gaat
  via de gewone hotstringvervanging, lange teksten (vanaf 200 tekens) en
  meerregelige teksten via een callback met `SendText()`, en teksten met
  AutoHotkey-opdrachten zoals `{Tab}` of `{Left}` blijven in toetsenmodus.
  Hotstringvervangingen gebruiken het Windows-klembord nooit. Regeleinden
  worden door de callback afzonderlijk als `{Enter}` uitgevoerd; het
  klembord blijft uitsluitend beschikbaar voor de telefonienummerdetectie.
- Vervangteksten ondersteunen dynamische codes die pas bij gebruik worden
  ingevuld: `{{datum}}` wordt de actuele datum in de vorm `dd-MM-jjjj` en
  `{{tijd}}` de actuele tijd in de vorm `uu:mm`. Een persoonlijke
  hotstring `gg` met vervangtekst
  `NF: Geen gehoor op {{datum}} {{tijd}}` levert bijvoorbeeld
  `NF: Geen gehoor op 23-07-2026 14:35` op.
- Nieuwe profielen kunnen lokaal geconfigureerde standaard-hotstrings
  bevatten. Bij de schema-5-migratie worden deze alleen toegevoegd als de
  afkorting nog niet bestaat; persoonlijke varianten worden nooit gewijzigd.
  De daadwerkelijke waarden staan uitsluitend in `DocBot.local.ahk`.
- Wanneer "Automatisch opslaan" aan staat, wordt het ingestelde JSON-bestand
  bij het starten geladen; toevoegen, wijzigen of verwijderen van een
  hotstring slaat de lijst direct weer op.
- Bestaat het JSON-bestand nog niet, dan wordt het automatisch aangemaakt.
- Bij opslaan wordt van het bestaande JSON-bestand eerst een `.bak`-backup
  gemaakt, en wordt de nieuwe inhoud eerst naar een `.tmp`-bestand
  geschreven en gecontroleerd voordat die het bestaande bestand vervangt
  (atomair schrijven).
- De legacy-`.txt`-importer zet oude `{Enter}`-codes om naar echte
  regeleinden. Escapes voor losse leestekens, zoals `{;}`, `{)}` en
  `{+}`, worden gewone tekens; echte toetsopdrachten zoals `{Tab}` en
  `{Left}` blijven behouden.
- Handmatig laden en opslaan vanaf een zelfgekozen pad blijft beschikbaar
  onder Instellingen.
- Bij de eerste start migreert het script eenmalig een eventueel bestaand
  `DocBot.ini` en `hotstrings.json` naast het script (oude locatie) naar de
  nieuwe gebruikersmap, zonder bestaande nieuwe bestanden te overschrijven.

Meegeleverde hotstringpakketten
---------------------------------
De bronbestanden voor meegeleverde hotstrings staan als versieerbare JSON in
de map `packages`, met `manifest.json` als index. Momenteel bevat de
catalogus Nederlandse taal, Medisch algemeen, Controles, Veelgebruikte
spelfouten en Gynaecologie & obstetrie, samen 1.596 pakketitems.

Bij compilatie neemt Ahk2Exe de bestanden via `FileInstall` op in de
executable. De gecompileerde applicatie pakt ze uit naar
`%LocalAppData%\DocBot\packages`. Een ongecompileerde ontwikkelversie
kopieert dezelfde bronbestanden naar
`%LocalAppData%\DocBot-dev\packages`, zodat tests de productiecache nooit
overschrijven. Deze laag valideert manifest, schema, pakket-ID's,
itemaantallen en dubbele triggers.

Pakketkeuzes worden apart en atomisch opgeslagen in
`package-settings.json`. Dat bestand bevat uitsluitend ingeschakelde
pakketten, uitgeschakelde pakketitems en expliciete conflictoplossingen; nooit
de tekstinhoud zelf. Persoonlijke hotstrings hebben standaard voorrang. Als
een pakketitem wordt bewerkt of bewust wordt bewaard, maakt DocBot een
volledige persoonlijke kopie in `hotstrings.json`, inclusief stabiele ID en
herkomstmetadata. Daardoor blijft die kopie bestaan wanneer een pakketitem in
een latere release verandert of verdwijnt. Verouderde pakketverwijzingen en
conflictkeuzes worden bij het laden automatisch verwijderd.

Via de knop **Pakketten** op de pagina Tekstvervanging kan de gebruiker de
pakketten en hun volledige inhoud bekijken. Pakketten en losse items kunnen
worden in- of uitgeschakeld. De beheerweergave markeert conflicten met
persoonlijke hotstrings of andere actieve pakketten; bij een persoonlijk
conflict kan de gebruiker de voorrang wisselen. Een pakketitem kan bovendien
als volledige persoonlijke hotstring worden bewaard.

De statuskolom gebruikt steeds dezelfde betekenis:

- **Inactief** — het pakket of het afzonderlijke item staat uit.
- **Overruled** — een persoonlijke hotstring heeft voorrang.
- **Voorrang** — dit pakketitem heeft voorrang op een persoonlijke hotstring.
- **Conflict** — dezelfde afkorting staat in een ander actief pakket.
- **Actief** — het pakketitem wordt normaal gebruikt.

Help in DocBot
---------------
DocBot bevat een aparte Help-pagina met vier uitklapbare onderwerpen:
telefoon koppelen, bellen vanuit HiX, bellen via snelkiesnummers en
hotstrings gebruiken. De instructies verwijzen expliciet naar de juiste
pagina's, knoppen en opties in DocBot; die interface-elementen zijn in de
uitleg vetgedrukt. Verwijzingen naar Overzicht, Telefonie en Hotstrings zijn
klikbaar en openen direct de betreffende pagina. Er kan steeds één onderwerp
tegelijk worden geopend. De
uitleg staat in een eigen verticaal scrollbaar tekstvlak, zodat langere
instructies binnen het vaste hoofdvenster leesbaar blijven.

Functionaliteit — Telefonie
-----------------------------
- DocBot houdt het Windows-klembord in de gaten en herkent automatisch
  Nederlandse telefoonnummers zodra ze gekopieerd worden.
- Bij een herkend nummer kan DocBot, afhankelijk van de instellingen:
  - **AutoCall**: automatische detectie aan/uit — staat dit uit, dan
    gebeurt er niets met een gekopieerd nummer.
  - **DirectCall**: bepaalt wat er gebeurt zodra AutoCall actief is. Staat
    DirectCall uit, dan verschijnt eerst een bevestigingsdialoog met het
    gevonden nummer; staat DirectCall aan, dan wordt direct gebeld zonder
    bevestiging.
- Het eigen toestelnummer wordt gekoppeld/geregistreerd bij de interne
  telefonieserver; de Verversen-knop op de Overzicht-pagina vraagt (met een
  ingebouwde afkoeltijd) een nieuw koppelnummer op. Zolang er nog geen
  toestel gekoppeld is, weigert DocBot te bellen en licht de hulptekst op
  de Overzicht-pagina toe wat de gebruiker moet doen.
- De GUI opent op Overzicht, met telefoonregistratie, AutoCall/DirectCall en
  tekstvervanging. Telefonie bevat een onbeperkte lijst snelkiesnummers met
  een inline bewerkingspaneel. Snelkiesnummers kunnen actief of inactief
  worden gemaakt; alleen actieve nummers verschijnen in het traymenu en
  kunnen worden gebeld. De eerste tien actieve nummers staan als snelle
  acties in het traymenu en bij meer entries opent "Alle
  snelkiesnummers..." de volledige lijst. Hotstrings staan op
  Tekstvervanging en opslag/import onder Instellingen.
- Nieuwe profielen kunnen lokaal geconfigureerde standaard-snelkiesnummers
  bevatten. Schema 3 vult deze bij bestaande opslag één keer aan, behalve
  wanneer dezelfde naam of hetzelfde nummer al aanwezig is. De daadwerkelijke
  waarden staan uitsluitend in `DocBot.local.ahk`.
- Bestaande snelkiesbestanden uit schema 1 worden bij het laden automatisch
  naar schema 2 gemigreerd. Ontbreekt het veld `actief`, dan blijft het
  nummer standaard actief. Ook de oude bestandsnaam
  `snelkiesnummers.json` wordt vanuit de gebruikers- of programmamap
  veilig overgenomen; de bestaande atomaire opslag en `.bak`-back-up
  blijven daarbij van toepassing.
- Deze functionaliteit werkt uitsluitend binnen het ziekenhuisnetwerk, omdat
  er verbinding wordt gemaakt met een interne telefonieserver die van
  buitenaf niet bereikbaar is.

Technische achtergrond — IP-telefonie API
-------------------------------------------
Onderstaande is bedoeld voor toekomstig onderhoud (een opvolger, of een
volgende sessie die niet bij de oorspronkelijke implementatie was).

- De integratie praat met de interne telefonieserver via drie endpoints:
  `registratie-endpoint` (registratie/koppelverzoek), `event-endpoint`
  (long-polling voor events) en `bel-endpoint` (daadwerkelijk bellen).
  Server-URL en endpointnamen staan uitsluitend in `DocBot.local.ahk`;
  niet-gevoelige technische instellingen staan in `IPTConfig`.
- Alle aanroepen zijn POST met een lege body; parameters gaan in de
  querystring.
- `event-endpoint` is een long-poll: de server houdt de aanvraag open totdat
  er een event is. De client plant pas een nieuwe aanvraag zodra de vorige
  is afgerond (`IPT_poller()` / `IPT_PollResponse()`), niet via een vaste
  interval-timer.
- Responses zijn XML met een `Name`-attribuut dat het event-type aangeeft:
  `NULL` (keep-alive), `StopEventLoop`, `SetUpperText` (bevat het
  koppelnummer) en `ShowAlert`.
- De lopende telefoniestatus (toestelnummer, koppelnummer, klembordnummer,
  poll-status) staat in de globale `State["IPT"]`-map.
- `IPT_callNumber()` is de centrale plek waar elke belpoging doorheen gaat
  (klembord-detectie, handmatig bellen, koppelgesprek); een belpoging wordt
  geweigerd zolang er geen toestel gekoppeld is, met uitzondering van het
  koppelgesprek zelf.
- Zie `IPT_register()`, `IPT_poller()`/`IPT_PollResponse()` en
  `IPT_callNumber()` in `DocBot.ahk` voor de implementatie zelf.

Telemetrie
----------
Als telemetrie lokaal is ingeschakeld, stuurt DocBot een statusbericht naar
een Power Automate Teams-webhook. De webhook-URL staat uitsluitend in het
niet door Git gevolgde `DocBot.local.ahk`. De eerste heartbeat wordt tien
seconden na het starten verzonden en daarna iedere vijftien minuten.

Iedere heartbeat bevat:

- een willekeurig, lokaal bewaard installatie-ID;
- de Windows-gebruikersnaam;
- de applicatienaam: `DocBot` of `EPD Machine`;
- de applicatieversie, starttijd en laatst-gezien-tijd;
- of een telefoon gekoppeld en tekstvervanging ingeschakeld is;
- het cumulatieve aantal gestarte belacties;
- het cumulatieve aantal uitgevoerde lange of meerregelige hotstrings.

Korte hotstrings worden rechtstreeks door AutoHotkey uitgevoerd en tellen
niet mee in `hotstringActions`. De tellers worden lokaal in
`settings.ini` bewaard en zijn ook zichtbaar op de Overzicht-pagina.

DocBot verzendt bewust **geen** computernaam, gebelde telefoonnummers,
hotstringafkortingen, vervangteksten, pakketinhoud of klembordinhoud. Bij
toekomstige wijzigingen aan de telemetrie blijft deze melding aanwezig en
wordt zij aangepast aan de werkelijk verzonden gegevens.

Diagnostiek
-----------
Er is een stille achtergrond-logfunctie voor troubleshooting van de
telefonie-integratie. Deze loopt altijd mee en schrijft naar
`%LocalAppData%\DocBot\debug.log`. Daarnaast is er een los debugvenster met
live logweergave, alleen zichtbaar voor de CMIO (gekoppeld aan het
Windows-account), en een "Diagnostische gegevens verzenden"-knop waarmee
gewone gebruikers het logbestand als bijlage in een conceptmail kunnen
laten klaarzetten — zonder dat zij de inhoud zelf hoeven in te zien.

Changelog
---------

### 2.1 — Huidige stabiele release
- Nieuwe Help-pagina met vier uitklapbare, scrollbare instructiekaarten voor
  telefoonregistratie, bellen vanuit HiX, snelkiesnummers en hotstrings.
- Optionele Power Automate-heartbeat voor centraal inzicht in actieve
  installaties en telefonie-/hotstringstatus, zonder computernaam of
  inhoudelijke gebruikersgegevens; configuratie en webhook blijven lokaal.
- Meegeleverde, gecompileerde hotstringpakketten met pakket- en itemkeuze,
  persoonlijke kopieën en expliciete conflictvoorkeuren.
- Pakketbeheer met sorteerbare lijsten, stabiele item-ID's en onderscheidende
  statussen voor actieve, uitgeschakelde en conflicterende items.
- Conflictstatussen worden vooraf geïndexeerd en de pakketlijst wordt als
  visuele batch gevuld, zodat ook pakketten met circa 1.400 items snel openen
  en veilig tijdens het laden kunnen worden gesloten.
- Gescheiden gebruikersprofielen voor `DocBot`, `DocBot-test` en
  `DocBot-dev`, inclusief veilige eenmalige kopieerketen en padmigratie.
- Compacte en uitklapbare editor voor enkel- en meerregelige
  vervangteksten, met automatische keuze tussen directe hotstringuitvoer,
  klembordvrije `SendText()`-uitvoer en toetsenmodus.
- Het klembord is volledig uit hotstringvervangingen verwijderd, zodat
  bestaande gekopieerde inhoud nooit als vervangtekst kan worden ingevoegd.
- Dynamische vervangcodes `{{datum}}` en `{{tijd}}` worden pas bij
  gebruik van een hotstring ingevuld, zodat persoonlijke teksten altijd de
  actuele datum en tijd kunnen opnemen.
- Legacy-import verbeterd: `{Enter}` wordt een echt regeleinde en
  accolade-escapes voor leestekens worden als gewone tekens opgeslagen.
- De buildbatch sluit actieve clients via een tijdelijk updatesignaal
  gecontroleerd af, vervangt en verifieert de executable en laat ze daarna
  via een eenmalige Windows Taakplanner-taak automatisch opnieuw starten.
  De actieve, achtergrond- of geminimaliseerde vensterstatus blijft daarbij
  behouden en het updatesignaal wordt na iedere uitrol opgeruimd.
- Interne telefonieadressen, endpointnamen en lokale standaarditems staan
  buiten Git in `DocBot.local.ahk`; de repository bevat uitsluitend een
  veilige, uitgecommentarieerde voorbeeldconfiguratie.
- Lokaal configureerbare standaarditems worden eenmalig toegevoegd zonder
  bestaande gebruikersvarianten te overschrijven.
- De ongebruikte legacybron is uit de actieve tak verwijderd en blijft
  beschikbaar via de Git-geschiedenis en `archive/legacy-v2-final`.

### 2.0.1 — Vorige stabiele release
- Pagina-indeling vernieuwd met Overzicht en afzonderlijke pagina's voor
  Telefonie, Hotstrings, Instellingen en Over.
- Consistente inline editors en moderne afgeronde kaarten, knoppen en toggles.
- Onbeperkte snelkiesnummers met actief/inactief-status en automatische
  migratie van oudere snelkiesbestanden.

### 2.0.0 — Eerste stabiele release
- Eerste productieversie van de vernieuwde DocBot-interface en
  telefonie-integratie.
- Snelkiesvolgorde via omhoog/omlaag, betrouwbaardere schermredraw en
  verbeteringen aan bevestigings- en instellingenschermen.

### 2.0.0-beta — Ontwikkelgeschiedenis

In de repo staan geen `v2.0.0-beta.N`-tags; de onderverdeling hieronder volgt
de opeenvolgende `AppVersion`-waarden die daadwerkelijk in de code hebben
gestaan (gereconstrueerd uit `git log`). Het Over-scherm leest uitsluitend
deze Changelog-sectie uit de meegecompileerde README, zodat er nog maar één
versiegeschiedenis wordt onderhouden.

#### 2.0.0-beta.2
- Bugfix: het Afsluiten-icoon (⏻, Segoe UI Symbol) rendert niet op sommige
  door IT beheerde Windows-images, omdat die glyph niet in elke
  Segoe UI Symbol-subset zit — vervangen door dezelfde MDL2-glyph die
  Windows zelf gebruikt in Instellingen en het Start-menu, en die daardoor
  vrijwel gegarandeerd aanwezig is.
- Bugfix: `TrayTip()`-meldingen kwamen op sommige zakelijk beheerde
  werkplekken niet in beeld doordat group policy het Windows-
  notificatiesysteem beperkt, zonder dat AutoHotkey daar een foutmelding
  van terugkrijgt. Alle `TrayTip()`-aanroepen zijn vervangen door een
  eigen, altijd-zichtbaar meldingsvenstertje rechtsonder boven de
  taakbalk, dat buiten dat notificatiesysteem om werkt en geen
  focus van het actieve venster afneemt.
- Bugfix: de Verversen-knop kwam bij het opstarten van de app meteen op
  afkoeltijd te staan, terwijl de automatische koppelnummer-aanvraag tijdens
  opstarten geen cooldown hoort te triggeren.
- Signal.txt-mechanisme voor op afstand gecoördineerd afsluiten/herladen:
  een periodiek gepolld bestand naast de executable op de centrale
  netwerklocatie, met targeting per computernaam of gebruikersnaam (of
  "ALL") en een optioneel eigen bericht per commando
  (`<doel>:<commando>:<bericht>`), voor shutdown- en reload-commando's
  apart.
- Over-scherm: versiegeschiedenis uitgebreid met de beta.2-regel.

#### 2.0.0-beta.1
- Basisstructuur voor de telefonie-integratie: `IPTConfig` en
  `State["IPT"]`.
- Registratie en polling bij de telefonieserver (`IPT_register`,
  `IPT_poller`), klembordmonitoring voor automatische nummerherkenning, en
  dial-actie met AutoCall/DirectCall-beslislogica.
- Eigen bevestigingsdialoog voor bellen, opstart- en afsluitkoppeling van de
  telefonie-integratie, Verversen-knop met afkoeltijd en aftellende
  countdown-tekst.
- Protocolcorrectie: GET vervangen door POST voor alle IPT-endpoints,
  gescheiden requests/callbacks via eigen globals, aaneengeschakelde
  poll-lus i.p.v. vaste interval-timer, echte XML-parsing van de
  `GetEvent`-respons, ERROR-detectie op de respons van `bel-endpoint`.
- Diagnostiek toegevoegd: achtergrondlogging, debugvenster, "diagnose
  verzenden".
- Bugfixes na eerste live-test: AHK v2-waarschuwing opgelost
  (`A_LocalAppData` bestaat niet als ingebouwde variabele, vervangen door
  `EnvGet("LocalAppData")`), poll-keten herstart bij Verversen na een
  eerdere `StopEventLoop`, GUI-tekstvelden en tray-menu verversen bij elk
  inkomend event, verlopen koppelnummer wordt gewist i.p.v. te blijven
  staan, autoscroll-lock in het debugvenster, onafhankelijke 1-seconde
  timer voor de Verversen-knop-countdown.
- Bellen zonder gekoppeld toestel voorkomen: `IPT_callNumber()` weigert nu
  een belpoging zolang er geen toestel gekoppeld is (met uitzondering van
  het koppelgesprek zelf), met een duidelijke melding i.p.v. een stille of
  onvoorspelbare belpoging; de hulptekst op de Telefonie-pagina legt nu
  ook uit wat de gebruiker moet doen.
- Snelkiesnummers toegevoegd: oorspronkelijk tot 10 entries (naam + nummer),
  opgeslagen in `speeddial.json` volgens hetzelfde atomaire
  laad-/opslagpatroon als hotstrings. In de 2.0.1-ontwikkeling is de harde
  grens verwijderd en het losse invoegvenster vervangen door een inline
  bewerkingspaneel; het traymenu toont alleen de eerste tien entries.
- Telefoonnummervalidatie losgetrokken tot een gedeelde
  `NormalizePhoneNumber()`, met een apart, expliciet pad voor interne
  4-cijferige nummers naast het bestaande externe-nummerpad: intern
  gedetecteerde klembordnummers vragen altijd om bevestiging (ongeacht
  DirectCall), omdat een los 4-cijferig getal een hogere kans op een
  fout-positief heeft dan een volledig extern nummer. Later verder
  aangescherpt tot uitsluitend NL-nationale nummers, met tolerantie voor
  spaties/streepjes/haakjes bij handmatige invoer en een duidelijkere
  foutmelding die ook de interne 4-cijferige optie noemt.
- Belopties-kaart compacter: AutoCall en DirectCall naast elkaar i.p.v.
  onder elkaar, met de toelichting als kleine tekst naast de checkbox.
- Snelkiesnummer-invoegvenster verbreed, met Naam en Nummer naast elkaar
  i.p.v. onder elkaar; de "+ Nieuw"-knop is later verplaatst van de
  rechterbovenhoek van de kaart naar de knoppenrij (rechts uitgelijnd
  t.o.v. Bellen/Wijzig/Verwijder), en de kaart zelf is vergroot zodat de
  lijst merkbaar meer rijen toont zonder te scrollen.
- Traymenu heringericht: "DocBot" (vet, standaardactie via `Menu.Default`)
  vervangt "DocBot openen"; Instellingen, Vervanglijst en Over zijn
  verwijderd uit het traymenu (alleen nog bereikbaar via het
  hoofdvenster); snelkiesnummers staan niet langer in een submenu maar als
  platte lijst met een sectiekopje, en verschijnen alleen als er entries
  zijn.
- Sidebar: "Afsluiten"-knop onderaan, visueel afwijkend (kleur, icoon,
  scheidingslijn) van de vier paginaknoppen erboven, die na bevestiging
  de hele applicatie inclusief tray-icoon sluit — een bewust andere actie
  dan het kruisje rechtsboven, dat alleen naar de tray verbergt.
- Over-pagina gevuld met inhoudelijke tekst (doel, doelgroep,
  auteursregel) via `BuildAboutText()`, aangevuld met een
  versiegeschiedenis die uitsluitend versies bevat die daadwerkelijk als
  `AppVersion` in de code hebben gestaan.
- Bugfix: de registratiehulptekst op de Telefonie-pagina werd afgekapt
  doordat het label maar op één regel hoogte was ingesteld terwijl de
  langste van de drie mogelijke teksten niet op één regel past.

#### 0.2
Eerste versie van de herschreven, niet-monolithische DocBot:
- Volledige GUI herbouwd: sidebar-navigatie, cards, tray-menu, consistente
  styling met afgeronde hoeken.
- JXON-library geïntegreerd; JSON-opslag en automatisch laden/opslaan van
  hotstrings, met `.bak`-backup en atomair schrijven via `.tmp`.
- Nog zonder telefonie.

*Noot: een deel van de commits in de git-geschiedenis heeft generieke
berichten ("Add files via upload", "Create README.md", "Update DocBot.ahk").
De bijbehorende inhoud is voor deze changelog rechtstreeks uit de diffs
gehaald in plaats van uit de commit message zelf. De oude bestandsnaam-
labels uit eerdere versies van deze changelog (v4.2, v4.5) waren interne
tussenstappen tijdens de refactor, geen aparte productversies — die
geschiedenis valt nu onder v2.0.0-beta hierboven.*
