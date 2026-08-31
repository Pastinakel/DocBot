DocBot
======

Overzicht
---------
DocBot is productiviteitssoftware voor medewerkers in een beheerde
bedrijfsomgeving. De software ondersteunt tekstinvoer door ingestelde
afkortingen (hotstrings) te vervangen en ondersteunt communicatie door
telefoonnummers op het Windows-klembord technisch te herkennen en te
normaliseren. Afhankelijk van de gebruikersinstelling kan DocBot een herkend
nummer doorgeven aan een geconfigureerde interne telefoniedienst of invullen
in een geconfigureerde SMS-webapplicatie. DocBot verzendt zelf geen
SMS-berichten. Alles draait via één GUI met sidebar-navigatie en een tray-icoon.

DocBot is ontstaan vanuit behoeften in een ziekenhuisomgeving en wordt daar
ook toegepast. De software heeft geen beoogd medisch doel: zij verricht geen
medische analyse van patiëntgegevens, trekt geen klinische conclusies en geeft
geen diagnose-, behandel-, doserings- of monitoringsadvies.

Deze README beschrijft de stabiele release 2.3 op `main`.

Bestanden
---------
- `DocBot.ahk` — stabiele release 2.3 met de huidige GUI,
  telefoniefunctionaliteit, hotstrings, snelkiesnummers en pakketbeheer.
- `packages/` — versieerbare ingebouwde hotstringpakketten plus manifest.
- `ThirdParty/ColorButton/` — custom-draw ondersteuning voor de moderne
  knoppen, inclusief de oorspronkelijke MIT-licentie.
- `ThirdParty/JXON/` — JSON-library van TheArkive voor het laden en opslaan
  van gebruikersgegevens, inclusief de oorspronkelijke MIT-licentie.
- `ThirdParty/UIA-v2/` — Windows UI Automation-library voor het betrouwbaar
  activeren van de geconfigureerde Edge-tab en invullen van het SMS-veld,
  inclusief de oorspronkelijke MIT-licentie.
- `LICENSE` — PolyForm Noncommercial-licentie van DocBot 2.2 en later.
- `AGENTS.md` en `CLAUDE.md` — project- en werkinstructies voor
  AI-assistenten.
- `docs/REGULATORY_ASSESSMENT.md` — voorlopige, versiegebonden beoordeling van
  DocBot als productiviteitssoftware die in zorgprocessen wordt toegepast en
  als mogelijke Medical Device Software, inclusief de relevantie van
  NEN 7510, IEC 62304, ISO 14971 en ISO 13485.
- `docs/INTENDED_PURPOSE.md` — goedgekeurde verklaring van het beoogde gebruik,
  de gebruikers, omgeving, invoer, uitvoer, autonome acties, beperkingen en
  uitgesloten medische toepassingen.
- `docs/DATA_PROTECTION.md` — technische beschrijving van persoonsgegevens-
  en gegevensstromen, met openstaande organisatorische invulpunten voor
  rollen, grondslagen, ontvangers, bewaartermijnen, autorisaties,
  transportbeveiliging en de DPIA-screening.

Er is geen apart bestand voor debug-logging in de repo: dat logbestand wordt
tijdens het draaien van het script aangemaakt op de gebruikerscomputer (zie
"Diagnostiek" hieronder).

Installatie
-----------
Laat `DocBot.ahk` en de map `ThirdParty/` in de oorspronkelijke structuur staan. Kopieer
`DocBot.local.example.ahk` naar `DocBot.local.ahk`, vul lokaal de
telefonieserver, endpointnamen, standaard-snelkiesnummers en
standaard-hotstrings in en compileer daarna `DocBot.ahk` met AutoHotkey v2.
Het echte lokale bestand staat in `.gitignore` en wordt niet naar GitHub
gestuurd. Ahk2Exe neemt het tijdens compilatie wel op in de executable. Het programma wordt alleen als gecompileerde executable aan
de eindgebruiker aangeboden zodat dit niet aangepast kan worden.
Bij de eerste start maakt het script zelf een gebruikersmap aan (zie hieronder) 
voor instellingen en hotstrings — daar is verder niets voor te installeren of 
te configureren.

`Build-EPD_Machine.bat` stelt eerst al zijn interactieve vragen — inclusief
die over de `packages`-submap hieronder — en doorloopt daarna zonder verdere
onderbrekingen het compileren en uitrollen. Bij elke vraag registreren `J`
of `j` direct Ja en `N` of `n` direct Nee, zonder dat Enter nodig is; Enter
zonder voorafgaande letter geldt als Ja. De batch compileert in de
bronmap eerst `DocBot.exe`. Direct daarna draait de batch automatisch
`DocBot.exe --selftest` tegen die zojuist gecompileerde executable en toont
de inhoud van `%TEMP%\docbot-selftest-results.txt` in de console — dit is de
betrouwbare uitvoer, niet de (typisch lege) stdout van een GUI-subsysteem-
executable (`docs/DECISIONS.md` D-053). Reageert de zelftest niet binnen
zestig seconden (bijvoorbeeld door een blokkerend dialoogvenster) of faalt
er een test, dan breekt de batch af zonder iets uit te rollen; zie
`tools/Invoke-WithTimeout.ps1` en `tests/README.md`. Slaagt de zelftest, dan
plaatst de batch vervolgens een kopie in de bovenliggende applicatiemap, met
de naam van die map. Wanneer het script een centrale
`-dev`-versie bevat en de batch vanuit een directe submap van `DocBot`
draait, kan optioneel ook `EPD_Machine.exe` in de naastgelegen
applicatiemap worden bijgewerkt. Voor
iedere gekozen doelmap plaatst de batch tijdelijk `ALL:update` in het
lokale `signal.txt`. Een actieve DocBot-instantie registreert vóór het
afsluiten een eenmalige taak in Windows Taakplanner. De batch probeert daarna
iedere seconde, maximaal vijfentwintig seconden lang, de executable te
verwijderen, te vervangen en byte-voor-byte te verifiëren. Na kopiëren of na
een fout wordt het updatesignaal altijd verwijderd. De geplande taak start
de beschikbare executable opnieuw met dezelfde vensterstatus — actief, op de
achtergrond of geminimaliseerd — en wordt na een geslaagde herstart door
DocBot weer verwijderd.

Voor iedere doelmap zorgt de batch na een geslaagde plaatsing van de
executable ook voor een gevulde `packages`-submap ernaast — dat is de map
waaruit de gecompileerde applicatie standaard leest (zie "Meegeleverde
hotstringpakketten" hieronder). Ontbreekt die submap nog, dan wordt hij
zonder te vragen gevuld vanuit de huidige checkout. Bestaat hij al, dan
vraagt de batch interactief of hij met de nieuwste versie uit de checkout
mag worden vervangen; bij "Nee" blijft een eventueel handmatig aangepaste
inhoud (bijvoorbeeld een pakket dat rechtstreeks op de doellocatie is
toegevoegd) ongemoeid (`docs/DECISIONS.md` D-052).

Functionaliteit — Hotstrings
-----------------------------
- Hotstrings worden opgeslagen als JSON. Standaardlocatie is
  `%MyDocuments%\DocBot\hotstrings.json`; instellingen (waaronder AutoSave en
  het gekozen hotstringbestand) staan in `%MyDocuments%\DocBot\settings.ini`.
  Keuzes voor meegeleverde pakketten staan afzonderlijk in
  `%MyDocuments%\DocBot\package-settings.json`.
- Gebruikersgegevens zijn per releasekanaal gescheiden: stabiele numerieke
  versies gebruiken `%MyDocuments%\DocBot`. Voor iedere niet-stabiele versie
  bepaalt de buildvorm het profiel, niet het prereleaselabel: een
  gecompileerde prerelease gebruikt `DocBot-test`, een niet-gecompileerde
  (rechtstreeks vanuit broncode gestarte) prerelease gebruikt `DocBot-dev`.
  Een ontbrekend testprofiel wordt vanuit main gekopieerd; een ontbrekend
  devprofiel bij voorkeur vanuit test en anders vanuit main. Opgeslagen
  interne hotstringpaden worden naar de doelmap omgezet voordat de normale
  datamodelmigraties draaien.
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
- Gebruik hotstrings voor generieke, herbruikbare tekst. Zet geen
  patiëntidentificerende of patiëntspecifieke gegevens in een hotstring —
  de volledige richtlijn, inclusief het onderscheid met generieke klinische
  formuleringen, staat in DocBot onder Help. DocBot controleert de inhoud
  van `hotstrings.json` niet automatisch op patiëntgegevens.

Meegeleverde hotstringpakketten
---------------------------------
De bronbestanden voor meegeleverde hotstrings staan als versieerbare JSON in
de map `packages`, met `manifest.json` als index. Momenteel bevat de
catalogus Nederlandse taal, Medisch algemeen, Controles, Veelgebruikte
spelfouten, Gynaecologie & obstetrie en Anesthesiologie & pijngeneeskunde,
samen 1.598 pakketitems.

Een `manifest.json`-vermelding bevat uitsluitend `id` en `file`: DocBot leest
verder niets anders uit het manifest. Alle inhoudelijke metadata — naam,
versie, beschrijving en optioneel `owner` (vrije tekst: wie dit pakket
aanmaakt of onderhoudt, zichtbaar in het venster **Pakketten** zodra een
item wordt bekeken) — staat uitsluitend in het pakketbestand zelf, nooit ook
in het manifest (`docs/DECISIONS.md` D-054).

Pakketten worden niet in de executable ingebakken en ook niet lokaal
gecached: DocBot leest ze bij iedere start rechtstreeks van de bron. Een
ongecompileerde ontwikkelversie leest daarvoor altijd de bronmap `packages`
naast `DocBot.ahk`. De gecompileerde applicatie leidt die locatie standaard
automatisch af: ook zij leest een map `packages` naast zichzelf
(`A_ScriptDir`), wat vanzelf naar de juiste netwerklocatie wijst wanneer
`DocBot.exe` rechtstreeks van daar wordt gestart (bijvoorbeeld door een
launcher als Ivanti die "vanaf de bron" start in plaats van een lokale
kopie te draaien) — `A_ScriptDir` wordt bij elke start naar het standaardlog
geschreven, al toont dat log het pad zelf nooit (zie hieronder). Start de
launcher toch een lokale kopie, dan is dat automatisch afgeleide pad niet
bruikbaar; `DocBot.local.ahk` kan dan `LocalConfig["Packages"]["ShareDir"]`
zetten als expliciete override naar het echte UNC-pad (`manifest.json` en
de pakketbestanden direct erin, geen submap). Een pakketbestand toevoegen,
wijzigen of verwijderen op de uiteindelijke bron is voor gebruikers direct
zichtbaar bij hun eerstvolgende DocBot-herstart, zonder dat `DocBot.ahk`
hoeft te worden aangepast of opnieuw gecompileerd. Is de bron niet
bereikbaar, dan laadt DocBot die sessie bewust gewoon geen pakketten in
plaats van de hele opstart te blokkeren; persoonlijke hotstrings blijven
altijd werken. Deze laag valideert manifest, schema, pakket-ID's en
dubbele triggers, en logt per pakketbestand of het laden is gelukt
(`docs/DECISIONS.md` D-046, D-048, D-049, D-052).

Het standaardlog schermt lokale en netwerkpaden altijd af (zie
"Probleem melden en diagnostiek" hieronder) — een gelogde pakketbron toont
dus alleen of het om een lokaal of een netwerkpad gaat, nooit het pad zelf.
Het echte pad staat wél gewoon op het scherm: in het venster **Pakketten**,
direct onder de titel, en in de melding wanneer er nul pakketten geladen
zijn (`docs/DECISIONS.md` D-050).

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
telefoon koppelen, bellen en SMS'jes versturen vanuit applicaties 
die telefoonnummers bevatten, bellen via snelkiesnummers en
hotstrings gebruiken. De instructies verwijzen expliciet naar de juiste
pagina's, knoppen en opties in DocBot; die interface-elementen zijn in de
uitleg vetgedrukt. Verwijzingen naar Overzicht, Telefonie en Hotstrings zijn
klikbaar en openen direct de betreffende pagina. Er kan steeds één onderwerp
tegelijk worden geopend. De
uitleg staat in een eigen verticaal scrollbaar tekstvlak, zodat langere
instructies binnen het vaste hoofdvenster leesbaar blijven.
De eerdere tekstfooter is vervangen door de knop **Probleem melden...**,
zonder de Help-layout of instructiekaarten in te korten.

Functionaliteit — Telefonie
-----------------------------
- DocBot houdt het Windows-klembord in de gaten en herkent automatisch
  Nederlandse telefoonnummers zodra ze gekopieerd worden.
- Bij een herkend nummer bepaalt **Belactie** wat DocBot doet:
  - **Niets doen** — het gekopieerde nummer wordt genegeerd;
  - **Bellen na bevestiging** — eerst verschijnt een bevestigingsdialoog;
  - **Direct bellen** — het nummer wordt zonder bevestiging gebeld;
  - **Bellen of sms kiezen** — bij een extern nummer verschijnt een keuze.
    Met links/rechts wordt **Annuleren**, **SMS** of **Bellen** geselecteerd;
    Enter bevestigt de blauwe keuze. Interne nummers worden in deze stand
    direct gebeld. Deze optie is alleen beschikbaar wanneer lokaal ten minste
    één SMS-actie is geconfigureerd.
- Komt er via het klembord een nieuw nummer binnen terwijl er nog een niet
  afgehandeld belvenster open staat (bevestiging, of de keuze
  bellen/sms), dan sluit DocBot dat oude venster automatisch — met een
  korte melding — en toont het venster voor het nieuwste nummer. Er staat
  zo nooit meer dan één klembord-belvenster tegelijk open, ook niet
  wanneer het nieuwe nummer een intern nummer is dat zonder eigen venster
  direct wordt gebeld.
- Onder **Instellingen > SMS actie** kiest de gebruiker welke lokaal
  geconfigureerde SMS-pagina wordt gebruikt. De dropdown toont de
  gebruikersvriendelijke `Title`; de technische `WindowTitle` wordt
  uitsluitend gebruikt om het juiste Edge-venster te herkennen. Eén
  `SmsCallAction`-map en een lijst met meerdere acties worden ondersteund.
- Bij **SMS** activeert DocBot eerst rechtstreeks het Edge-venster via
  `WindowTitle`. Staat de pagina als achtergrondtab open, dan selecteert
  DocBot hem via Windows UI Automation. Bestaat de tab nog niet, dan wordt de
  lokaal geconfigureerde URL geopend. Vervolgens wordt het 06-nummer via het
  UIA-`AutomationId` uit `FieldId` ingevuld; JavaScript is uitsluitend de
  fallback. SMS wordt alleen aangeboden voor een geldig Nederlands
  06-nummer en DocBot verstuurt het bericht niet zelf.
- Is voor de gekozen SMS-pagina ook `TextFieldId` geconfigureerd, dan kan de
  gebruiker onder **Instellingen > SMS actie** per SMS-pagina een
  meerregelige standaardtekst instellen (harde enters worden bewaard). Die
  tekst wordt na het telefoonnummer op dezelfde manier (UIA, met JavaScript
  als fallback) in het berichtveld van de pagina ingevuld. Dit is
  best-effort: lukt de tekstinvulling niet, dan blijft het al ingevulde
  telefoonnummer gewoon staan en meldt DocBot geen fout. Zonder
  `TextFieldId` blijft het standaardtekstveld uitgeschakeld voor die pagina.
  De standaardtekst wordt per gebruiker bewaard in `sms-default-texts.json`.
- Elke `SmsCallAction.Url` in `DocBot.local.ahk` moet met `https://`
  beginnen; `ValidateSmsCallActionItem()` weigert een `http://`-waarde al
  bij het opstarten.
- Het eigen toestelnummer wordt gekoppeld/geregistreerd bij de interne
  telefonieserver; de Verversen-knop op de Overzicht-pagina vraagt (met een
  ingebouwde afkoeltijd) een nieuw koppelnummer op. Zolang er nog geen
  toestel gekoppeld is, weigert DocBot te bellen en licht de hulptekst op
  de Overzicht-pagina toe wat de gebruiker moet doen.
- De GUI opent op Overzicht, met telefoonregistratie, de instelling Belactie
  en tekstvervanging. Telefonie bevat een onbeperkte lijst snelkiesnummers met
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
- In de huidige ziekenhuisconfiguratie werkt deze functionaliteit uitsluitend
  binnen het ziekenhuisnetwerk, omdat de geconfigureerde interne
  telefonieserver van buitenaf niet bereikbaar is.

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
- `Telephony.BaseUrl` in `DocBot.local.ahk` moet met `https://` beginnen;
  `ValidateLocalConfiguration()` weigert een `http://`-waarde al bij het
  opstarten (blokkerende foutmelding, geen stille HTTP-fallback).
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

Het doel is inzicht krijgen in het gebruik en de omvang van DocBot, zodat
systeembeheer de te verwachten belasting van de gebruikte telefonie- en
SMS-servers kan ramen en de benodigde capaciteit kan plannen. DocBot meet
hierbij geen verzonden SMS-berichten; een verwachting voor de SMS-server wordt
alleen afgeleid uit de omvang en activiteit van de installaties. De centrale
telemetrie is toegankelijk voor de leden van het RPA ontwikkel- en beheerteam.
Logregistraties ouder dan één jaar worden uit de centrale bestemming
verwijderd.

De telemetrie is vanaf het ontwerp opgezet met dataminimalisatie: de payload
gebruikt een willekeurig, pseudoniem installatie-ID in plaats van
rechtstreeks herleidbare gegevens. Tijdens de huidige opstartfase wordt de
Windows-gebruikersnaam daarnaast, als bewust tijdelijke aanvulling op dat
installatie-ID, gebruikt om een technisch signaal aan de getroffen gebruiker
te kunnen koppelen en gericht hulp te bieden. Voorbeelden zijn een
niet-geactiveerde telefoniefunctie en het onderzoek naar een eerder
wisselend installatie-ID wanneer DocBot startte voordat OneDrive was
gesynchroniseerd. De gebruikersnaam is niet bedoeld voor beoordeling van
prestaties, aanwezigheid of individueel werkgedrag. Na de opstartfase wordt
opnieuw beoordeeld of dit veld nog nodig is; het installatie-ID blijft dan
als het al aanwezige, minder identificerende kenmerk in de payload staan.

Bij het starten leest DocBot eerst het bestaande installatie-ID uit
`settings.ini`. Als dat ID beschikbaar is, wordt niets teruggeschreven en kan
telemetrie direct starten. Alleen wanneer het ID ontbreekt, maakt DocBot een
nieuw ID aan. Dat nieuwe ID wordt pas gebruikt nadat schrijven en teruglezen
zijn gelukt. Bij een tijdelijk niet-beschikbare OneDrive-map probeert DocBot
dit in totaal vijf keer tijdens de eerste minuten en daarna ieder uur opnieuw;
de overige functies van DocBot blijven intussen beschikbaar.

De drie cumulatieve gebruikstellers hieronder volgen dezelfde
lees-en-bevestig-voordat-er-geschreven-wordt-aanpak: bij een tijdelijk
niet-beschikbare opslag telt DocBot een actie tijdens die sessie gewoon
mee, maar schrijft dat aantal pas naar `settings.ini` zodra de echte,
eerder opgeslagen stand bevestigd is uitgelezen. Zo kan een sessie die met
een nog niet bevestigde tellerstand start nooit de eerder opgebouwde
telling overschrijven.

Iedere heartbeat bevat:

- een willekeurig, lokaal bewaard installatie-ID;
- de Windows-gebruikersnaam;
- de applicatienaam: `DocBot` of `EPD Machine`;
- de applicatieversie, starttijd en laatst-gezien-tijd;
- of een telefoon gekoppeld en tekstvervanging ingeschakeld is;
- het cumulatieve aantal gestarte belacties;
- het cumulatieve aantal uitgevoerde lange of meerregelige hotstrings;
- het cumulatieve aantal geslaagde sms-acties (`smsActions`): DocBot telt een
  sms-actie alleen als geslaagd zodra de sms-pagina of -tab daadwerkelijk is
  gevonden en het telefoonnummerveld is gevuld, nooit alleen omdat de
  sms-optie is aangeboden of gekozen. DocBot verstuurt de sms zelf niet en
  meet dus ook niet of de gebruiker de sms daadwerkelijk verzendt.

Korte hotstrings worden rechtstreeks door AutoHotkey uitgevoerd en tellen
niet mee in `hotstringActions`. De tellers worden lokaal in
`settings.ini` bewaard en zijn ook zichtbaar op de Overzicht-pagina.

DocBot verzendt bewust **geen** computernaam, gebelde telefoonnummers,
hotstringafkortingen, vervangteksten, pakketinhoud of klembordinhoud. Bij
toekomstige wijzigingen aan de telemetrie blijft deze melding aanwezig en
wordt zij aangepast aan de werkelijk verzonden gegevens.

Probleem melden en diagnostiek
------------------------------
De herkenbare gebruikersfunctie heet **Probleem melden...** en is bereikbaar
via het rechtermuisknopmenu van het DocBot-pictogram en via de knop onderaan
de Help-pagina. Beide ingangen openen exact hetzelfde probleemrapportagevenster.

DocBot houdt standaard uitsluitend een beperkte, lokaal opgeslagen en centraal
geschoonde log bij in `%LocalAppData%\DocBot\debug.log`. Volledige
telefoonnummers, klembordinhoud, volledige URL's, ruwe serverresponsen,
Windows-gebruikersnaam en computernaam worden daarin afgeschermd of niet
opgenomen. De precieze omvang van de standaardlogging blijft bewust beperkt
tot globale technische gebeurtenissen en foutcategorieën. Bij de eerste start
van deze versie verwijdert DocBot een eventueel ouder, nog niet centraal
geschoond debuglog, zodat historische URL's of responsinhoud niet alsnog in
een nieuw probleemrapport terechtkomen. Naast de bestaande omvangrotatie
(circa 2 MB naar `debug.log.oud`) verwijdert DocBot bij het opstarten en
daarna dagelijks automatisch alle logregels ouder dan zeven dagen, uit zowel
het actieve logbestand als `debug.log.oud`.

Voor problemen die opnieuw kunnen worden uitgevoerd kan de gebruiker in het
probleemrapportagevenster expliciet toestemming geven voor **uitgebreide
logging**. Uitgebreide logging staat standaard uit en wordt uitsluitend voor
de huidige DocBot-sessie ingeschakeld. Na toestemming bevat dit tijdelijke log
bewust ongeschoonde technische inhoud, waaronder volledige telefonie-URL's en
serverresponsen, volledige gebelde telefoonnummers en de afkorting en
vervangtekst van hotstrings die tijdens de sessie daadwerkelijk worden
uitgevoerd. Ook foutmeldingen en SMS/UIA-details kunnen volledige technische
waarden bevatten. De telemetrie-webhook blijft afgeschermd en het lokale
configuratiebestand zelf wordt nooit opgenomen.

Het venster mag tijdens het reproduceren worden gesloten: bij opnieuw openen
blijft duidelijk zichtbaar dat logging actief is en welke vervolgstappen nodig
zijn. Afsluiten of herstarten van DocBot stopt de uitgebreide logging
automatisch en verwijdert het tijdelijke uitgebreide logbestand.

Bij **Probleemrapport afronden** stopt DocBot eerst de uitgebreide logging en
zet daarna het probleemrapport, de beperkte standaardlog en — wanneer daarvoor
toestemming was gegeven — het tijdelijke uitgebreide log klaar als losse
bestanden (geen ZIP). `settings.ini`, `hotstrings.json`, lokale configuratie
en telemetrie-ID worden nooit als bestand toegevoegd. Gebruikte
hotstringinhoud kan na toestemming wel in het uitgebreide log staan, zoals
hierboven vermeld.

DocBot opent vervolgens een conceptbericht in Classic Outlook met het
diagnosepakket als losse bijlagen. Als Outlook nog niet actief is, start
DocBot Outlook en wacht het totdat de MAPI-sessie gereed is. De gebruiker
controleert het bericht en klikt zelf op **Verzenden**. Zodra DocBot heeft
geverifieerd dat Outlook alle bijlagen heeft overgenomen en het
conceptvenster staat, verwijdert DocBot de tijdelijke rapportmap automatisch
— de bestanden staan dan al in het conceptbericht zelf. Wanneer Classic
Outlook niet beschikbaar is, opent DocBot een nieuw e-mailbericht zonder
bijlage en toont de rapportmap in Verkenner, zodat de gebruiker de bestanden
handmatig kan toevoegen; DocBot laat de map in dat geval bewust staan en
vraagt expliciet (standaard "Nee") of hij meteen mag worden opgeruimd. Een
rapportmap die zo blijft staan — bijvoorbeeld omdat de gebruiker nog niet
klaar is — verwijdert DocBot uiterlijk na zeven dagen automatisch, op
dezelfde manier als de standaardlogretentie hierboven. Het
ontwikkelaarsdebugvenster blijft alleen zichtbaar voor het daarvoor
ingerichte Windows-account.

Regelgeving, informatiebeveiliging en patiëntveiligheid
-------------------------------------------------------
De actuele repositoryanalyse van de intended purpose, gegevensverwerking,
autonome acties, mogelijke kwalificatie als Medical Device Software en de
relevantie van NEN 7510, IEC 62304, ISO 14971 en ISO 13485 staat in
`docs/REGULATORY_ASSESSMENT.md`. De huidige beoordeling is dat DocBot
productiviteitssoftware is die in de huidige ziekenhuisomgeving
persoonsgegevens en potentieel gezondheidsinformatie verwerkt, maar op basis
van de intended purpose en huidige functie waarschijnlijk geen eigen medisch
doel heeft onder de MDR.

Deze beoordeling is voorlopig en geen juridisch of gecertificeerd
conformiteitsoordeel. Nieuwe patiëntspecifieke analyse, klinische aanbeveling,
alarmering, medicatie- of behandelbeslissing of aansturing van een medisch
hulpmiddel vereist vóór implementatie een nieuwe kwalificatie- en
risicoanalyse.

Changelog
---------

### 2.4 — In ontwikkeling
- Overzicht toont bij het opstarten soms een gele tip die wijst op een nog
  ongebruikte functie: telefonie koppelen, hotstrings aanmaken of sms
  versturen, plus een tip over het sluiten van DocBot naar het systeemvak
  (die laatste vervangt de vaste tekst die eerder altijd onderaan Overzicht
  stond). Per opstartsessie wordt willekeurig hooguit één tip getoond, en
  alleen als de bijbehorende teller nog op 0 staat (of, voor de
  systeemvak-tip, altijd) én de tip niet in de afgelopen 10 dagen al
  getoond is. De tip blijft zichtbaar tot de teller verandert of de
  gebruiker op het kruisje klikt, en verschijnt in totaal maximaal 5 keer
  per tip.
- DocBot herkent nu actief of Documents/OneDrive bij het opstarten (bijvoorbeeld
  via autostart, vóórdat OneDrive volledig gemount is) nog niet beschikbaar is,
  in plaats van dat één mislukte poging voor de rest van de sessie stilzwijgend
  op standaardwaarden blijft draaien. Instellingen, hotstrings, pakketkeuzes,
  snelkiesnummers en sms-standaardteksten worden op de achtergrond automatisch
  opnieuw geprobeerd totdat het lukt (`docs/DECISIONS.md` D-063). Zolang dat nog
  niet is gelukt, toont DocBot dit duidelijk: een blijvende melding in plaats
  van een vanzelf verdwijnende, en de bijbehorende functionaliteit (hotstrings,
  pakketbeheer, snelkiesnummers, sms-instellingen, en wat er met een herkend
  telefoonnummer gebeurt) is dan echt niet beschikbaar in plaats van
  onopgemerkt onjuist. Telefonie-koppeling zelf blijft altijd gewoon werken
  (`docs/DECISIONS.md` D-064). Ook het allereerste opstarten — wanneer de
  gebruikersmap nog moet worden aangemaakt — wordt niet langer verward met
  "opslag tijdelijk niet beschikbaar": DocBot test dit voortaan actief met een
  schrijfpoging in plaats van dat blind aan te nemen.
- Overzicht toont nu ook een derde gebruiksteller, "SMS-acties", naast
  "Belacties" en "Lange hotstrings" op de Gebruik-kaart. De teller telt
  alleen geslaagde sms-acties (de sms-pagina/-tab gevonden en het
  telefoonnummerveld gevuld), niet elke keer dat de sms-optie wordt
  aangeboden. De teller wordt ook meegestuurd in de telemetrie-heartbeat als
  `smsActions`, naast de bestaande `phoneActions`/`hotstringActions` — zie
  de sectie Telemetrie hierboven.
- Een gebundeld pakket hoeft geen `itemCount`-veld meer te bevatten dat
  precies overeenkomt met het aantal items. Dit optionele
  manifestveld moest tot nu toe handmatig in sync worden gehouden en kon een
  verder geldig pakket laten weigeren zodra dat vergeten werd; `items.Length`
  was al de enige echte bron van waarheid. De consistentiecontrole is uit
  `LoadBundledPackageFile()` verwijderd en het veld is uit alle meegeleverde
  `packages/*.json`-bestanden gehaald.
- `packages/anest.json` bevatte enkele meerregelige `replacement`-teksten met
  letterlijke regeleinden binnen een JSON-tekenreeks — geldig genoeg voor de
  lenient parser die DocBot gebruikt, maar geen geldige JSON volgens de spec
  en onleesbaar voor strikte JSON-tools. Die regeleinden zijn vervangen door
  `\n`-escapes; de daadwerkelijke vervangingstekst (en daarmee het
  DocBot-gedrag) is ongewijzigd.
- De opschoning van het standaardlog (`PruneExpiredDebugLogFile()`) herkent
  voortaan uitputtend welk formaat een regel heeft: het huidige formaat, het
  bekende oude formaat van vóór commit `5f72613`, of geen van beide. Een
  regel die bij geen enkel bekend formaat past, vervalt voortaan
  onvoorwaardelijk in plaats van voor altijd te worden bewaard — dit sluit
  het scenario waarbij een oudere of teruggezette build ooit niet-geschoonde
  inhoud onder een al geldig ogende "v2"-kopregel zou kunnen wegschrijven
  zonder dat een latere opstart dat opmerkt (`docs/DECISIONS.md` D-062).
- `DocBot.exe --selftest` schrijft `%TEMP%\docbot-selftest-results.txt`
  niet langer met een UTF-8 BOM. Die BOM veroorzaakte geen echte testfout
  (de 32/32-telling was altijd al correct), maar zorgde er wel voor dat de
  eerste regel van het bestand er in een console zonder UTF-8-codepage
  onleesbaar/verminkt uitzag zodra dat bestand met `type` werd getoond —
  onder meer nu `Build-EPD_Machine.bat` dat automatisch na het compileren
  doet.
- `DocBot.exe --selftest` dekt nu ook de telefoonnummernormalisatie
  (`NormalizePhoneNumber` en de interne/externe varianten,
  `NormalizeSmsPhoneNumber`): 4-cijferige interne nummers, externe
  NL-nummers in +31-/0031-/kale-0-vorm met spaties/streepjes genegeerd, de
  06-only-eis voor de SMS-variant, en te korte/ongeldige invoer.

### 2.3 — Huidige stabiele release
- DocBot probeert de gebruikersdatamap bij het opstarten niet langer lokaal
  te pinnen tegen OneDrive Files On-Demand (`MarkUserStorageAlwaysAvailable()`
  is verwijderd, samen met de aanroep ervan). Op een werkplek met
  applicatie-whitelisting blokkeerde het starten van het onderliggende
  externe proces (eerst via `cmd.exe`, daarna rechtstreeks via `attrib.exe`)
  zelf al, met een storend beveiligingsscherm bij elke start van DocBot tot
  gevolg — voor een best-effort optimalisatie die nooit noodzakelijk was
  voor de werking van DocBot (`docs/DECISIONS.md` D-058).
- Het venster-/tabselectiepad voor een SMS-actie (`RunSmsCallAction()`,
  `ActivateSmsEdgeWindowByTitle()`, `ActivateSmsEdgeTabByTitle()`,
  `OpenSmsPage()`) logt de belangrijkste beslispunten voortaan ook naar het
  standaardlog/ontwikkelaarsvenster, niet langer uitsluitend naar het
  uitgebreide log tijdens een toegestane sessie: welk pad (WinActivate,
  UIA-tabselectie of URL-fallback) is geprobeerd, per doorzocht Edge-venster
  of er een tab met de geconfigureerde `WindowTitle` is gevonden, en welk pad
  uiteindelijk de gebruikte tab leverde. Dit maakt zichtbaar waarom soms een
  nieuw Edge-venster/tab wordt geopend terwijl een passende tab al open leek
  te staan, zonder dat daarvoor eerst een uitgebreide-loggingsessie nodig is.
  Alleen een samenvatting is toegevoegd; de al bestaande gedetailleerde
  `ExtendedDebugLog()`-regels blijven ongewijzigd (`docs/TODO.md`, gefileerd
  vanuit `claude/sms-window-reopen-bug-mmx5ln`).
- `Build-EPD_Machine.bat` stelt al zijn interactieve vragen (EPD_Machine
  meekopiëren, een bestaande `packages`-submap overschrijven) nu vooraf,
  vóór het compileren begint, in plaats van verspreid tijdens het uitrollen.
  Enter zonder tekst registreert telkens Ja; alleen een expliciete "N" telt
  als Nee.
- Het gebruikersprofiel (`DocBot`/`DocBot-test`/`DocBot-dev`) voor
  niet-stabiele versies wordt nu bepaald door de buildvorm (`A_IsCompiled`)
  in plaats van door het prereleaselabel: een gecompileerde prerelease
  gebruikt `DocBot-test`, een niet-gecompileerde prerelease gebruikt
  `DocBot-dev`, ongeacht of het label `-dev`, `-rc` of een feature-/fixnaam
  is. Stable blijft altijd `DocBot` gebruiken (`docs/DECISIONS.md` D-056).
- Elke geconfigureerde SMS-pagina kan nu een optioneel tweede veld
  (`TextFieldId`) aanwijzen voor het berichtveld. Is dat ingesteld, dan kan
  de gebruiker onder **Instellingen > SMS actie** per SMS-pagina een
  meerregelige standaardtekst instellen (harde enters blijven behouden);
  DocBot vult die tekst na het telefoonnummer best-effort in hetzelfde
  berichtveld in. De standaardtekst wordt per gebruiker bewaard in het
  nieuwe `sms-default-texts.json`, met dezelfde schemaVersion-opzet als
  `speeddial.json` (`docs/MIGRATIONS.md`, `docs/DECISIONS.md` D-055).
- `manifest.json`-vermeldingen bevatten voortaan uitsluitend `id` en `file`;
  `name`, `version` en `description` stonden daar ongebruikt gedupliceerd
  (niets in de code las ze) en zijn verwijderd. Pakketbestanden ondersteunen
  nu ook een optioneel `owner`-veld (vrije tekst), zichtbaar in het venster
  **Pakketten** naast de pakketnaam zodra een item wordt bekeken
  (`docs/DECISIONS.md` D-054).
- Het laden van meegeleverde hotstringpakketten logt nu per bestand naar het
  standaardlog: welk bestand wordt geprobeerd, of dat lukt (met naam, versie
  en itemaantal) en zo niet, waarom. Eén ongeldig pakketbestand blokkeert
  niet langer het laden van de overige pakketten. `ReportStorageError()`
  schrijft elke opslagfout (pakketten, hotstrings, instellingen,
  snelkiesnummers) voortaan ook naar het standaardlog, ook wanneer alleen
  een tray-melding wordt getoond.
- Meegeleverde hotstringpakketten worden niet meer in de executable
  ingebakken. De ongecompileerde versie leest ze rechtstreeks uit de
  bronmap `packages`; de gecompileerde applicatie leest een map `packages`
  naast zichzelf (`A_ScriptDir`, bij elke start naar het standaardlog
  geschreven) en gebruikt die automatisch als de executable rechtstreeks
  vanaf de juiste netwerklocatie draait. Draait de executable via een
  lokale kopie (bijvoorbeeld door een launcher als Ivanti die niet "vanaf
  de bron" start), dan kan `LocalConfig["Packages"]["ShareDir"]` in
  `DocBot.local.ahk` het echte UNC-pad als expliciete override instellen.
  Een pakketbestand toevoegen, wijzigen of verwijderen op de uiteindelijke
  bron is zo zichtbaar bij de eerstvolgende DocBot-herstart, zonder
  wijziging aan of herbouw van `DocBot.ahk` (`docs/DECISIONS.md` D-048/
  D-049, die samen D-047 vervangen). Het standaardlog schermt dat pad zelf
  altijd af; het venster **Pakketten** toont het wél onafgeschermd, ook bij
  nul geladen pakketten (D-050).
- Het venster **Pakketten** kon vastlopen met een foutmelding
  ("Integer has no property named 'Value'") bij het sluiten van het venster
  terwijl de conflictstatus van een groot pakket nog werd berekend.
  `RefreshPackageManagerItemDetails()` controleert nu vlak vóór iedere
  schrijfactie opnieuw of de statusregel nog bestaat, in plaats van alleen
  bij binnenkomst (`docs/DECISIONS.md` D-051).
- `Build-EPD_Machine.bat` zorgt nu voor elke doelmap ook voor een gevulde
  `packages`-submap naast de geplaatste executable — de locatie waaruit de
  gecompileerde applicatie sinds D-049 standaard leest. Ontbreekt de submap,
  dan wordt hij gevuld vanuit de huidige checkout; bestaat hij al, dan
  vraagt de batch eerst of hij met de nieuwste versie mag worden vervangen
  (`docs/DECISIONS.md` D-052).
- Schemamigraties (hotstrings, snelkiesnummers, pakketten,
  pakketkeuzes) zijn gedocumenteerd in het nieuwe `docs/MIGRATIONS.md`, en
  de vijf schemaVersion-controles delen nu twee kleine gezamenlijke
  functies (`ReadSchemaVersion()`, `RejectNewerSchemaVersion()`) in plaats
  van vijfmaal losstaande code — dit wijzigt het gedrag niet, alleen de
  exacte bewoording van de zeldzame "bestand is nieuwer dan deze
  DocBot-versie"-foutmelding. Een nieuwe, standaard onzichtbare
  `--selftest`-opstartmodus (`DocBot.ahk --selftest`) draait losstaande
  zelftests voor deze migratielogica en is nu ook in de CI-syntaxcontrole
  opgenomen (`docs/DECISIONS.md` D-053).
- Nieuwe gebruikersinstructie voor veilige hotstring-inhoud: een vijfde
  Help-sectie ("Wat mag ik wel en niet in een hotstring zetten?") en een
  bijbehorende, altijd zichtbare hint op de Tekstvervanging-pagina. De
  kaarten op Hotstrings, Telefonie en Over sluiten daarbij nu onderaan op
  dezelfde hoogte af (`docs/DECISIONS.md` D-045).
- De verticale scrollbalk van een afgeronde tekstbox (zoals de Help-
  accordeontekst en het Over-scherm) werd altijd onzichtbaar afgeknipt,
  ook wanneer er wel degelijk meer te scrollen was. `RoundControl()`
  gebruikt nu `GetWindowRect` in plaats van `GetClientRect`, zodat de
  scrollbalk binnen de afgeronde regio valt (`docs/DECISIONS.md` D-045).
- De Help-link bij de hotstring-privacyhint op Tekstvervanging opent nu
  direct de bijbehorende, al opengeklapte accordeonsectie in plaats van
  alleen naar de Help-pagina te navigeren. Een klik of dubbelklik in een
  Help-accordeontekst laat ook geen blauwe tekstselectie meer achter — dat
  is nu, net als een klik op een link, een no-op in plaats van RichEdit's
  standaard selectiegedrag. Ook het openen van een sectie via die Help-link
  kon de hele hoofdtekst blauw geselecteerd tonen; elke sectie wist nu bij
  het openen expliciet zijn eigen selectie, met een korte herhaling om een
  laat binnenkomend bericht niet te laten winnen (`docs/DECISIONS.md`
  D-045).
- Telefonie en SMS vereisen nu een HTTPS-URL: `ValidateLocalConfiguration()`
  weigert een niet-HTTPS `Telephony.BaseUrl` en `ValidateSmsCallActionItem()`
  weigert een niet-HTTPS `SmsCallAction.Url`, beide al bij het opstarten
  (`docs/DECISIONS.md` D-043).
- Standaardlogregels ouder dan zeven dagen worden automatisch verwijderd (bij
  opstart en daarna dagelijks), uit zowel het actieve logbestand als
  `debug.log.oud`. De bestaande omvangrotatie (circa 2 MB) blijft ongewijzigd
  (`docs/DECISIONS.md` D-044).
- De tijdelijke probleemrapportmap in `%TEMP%` blijft niet langer onbeperkt
  staan: verwijderd na een geverifieerde Outlook-bijlage, expliciet
  (standaard "Nee") bij de handmatige fallback, en anders uiterlijk na zeven
  dagen automatisch opgeruimd (D-044). Een los uitgebreid-logbestand dat
  door een crash of geforceerd afsluiten wordt achtergelaten, ruimt DocBot
  op dezelfde manier uiterlijk na zeven dagen op.

### 2.2 — Vorige stabiele release
- Start van de volgende ontwikkelcyclus na de stabiele release van DocBot 2.1.
- Nieuwe gebruikersflow **Probleem melden...** via zowel het systeemvakmenu
  als een knop die de bestaande Help-footer vervangt. Beide openen dezelfde
  rapportsessie met een optionele probleembeschrijving.
- Uitgebreide SMS/UIA-logging staat standaard uit en vereist expliciete
  toestemming. Een actieve sessie blijft herkenbaar wanneer het venster wordt
  gesloten en opnieuw geopend, maar wordt bij afsluiten of herstarten van
  DocBot altijd beëindigd.
- Na expliciete toestemming bevat het uitgebreide log ook ongeschoonde
  telefonieresponsen, volledige gebelde nummers en daadwerkelijk gebruikte
  hotstringafkortingen en vervangteksten; het standaardlog blijft geschoond.
  De rood en vet benadrukte privacymelding staat inline met de waarschuwing,
  direct boven het toestemmingsvakje.
- Standaardlogging is beperkt en centraal geschoond; volledige
  telefoonnummers, klembordinhoud, volledige URL's, ruwe serverresponsen,
  gebruikersnaam en computernaam worden afgeschermd of niet opgenomen.
- Probleemrapporten starten Classic Outlook zo nodig, wachten tot Outlook
  gereed is en openen daarna een conceptmail met de rapportbestanden als
  losse bijlagen. Bij een Outlook-fout volgt een zichtbare handmatige
  fallback.
- Bij stoppen of afronden wordt de status van uitgebreide logging direct in
  het rapportagevenster bijgewerkt, ook wanneer Outlook niet beschikbaar is.
- Rapportbestanden worden los aan de mail gehangen in plaats van in een ZIP.
  De eerdere ZIP-opbouw via de Explorer-shellextensie "Compressed (zipped)
  Folders" bleek op sommige door group policy/EDR beheerde werkplekken
  onbetrouwbaar of volledig onbeschikbaar, waardoor probleemrapportage zelf
  faalde.
- De gebruikersmap wordt waar mogelijk met `attrib -U +P` als altijd lokaal
  beschikbaar gemarkeerd, zonder dat een mislukte pinactie de start blokkeert.
- DocBot voert bij het opstarten geen algemene schrijfbaarheidstest meer uit;
  iedere echte schrijfactie houdt zijn eigen gerichte foutafhandeling.
- Een bestaand telemetrie-installatie-ID wordt alleen gelezen en direct gebruikt.
  Alleen een ontbrekend nieuw ID wordt geschreven en pas na bevestigde opslag
  actief. Bij tijdelijke onbeschikbaarheid volgen vijf pogingen binnen de eerste
  minuten en daarna ieder uur een nieuwe poging.
- Externe libraries staan met hun oorspronkelijke MIT-licenties gegroepeerd
  onder `ThirdParty/`.
- Nieuwe vierstandeninstelling **Belactie** als vervanging voor AutoCall en
  DirectCall, inclusief een lokaal configureerbare keuze van de SMS-pagina.
  De SMS-keuze wordt alleen aangeboden als minimaal één geldige
  `SmsCallAction` aanwezig is; zichtbare namen komen uit `Title`.
- Geïntegreerde SMS-actie opent of activeert de geselecteerde Edge-pagina via
  snelle `WinActivate`-detectie met UI Automation als achtergrondtab-
  fallback, vult het geconfigureerde telefoonveld in en laat het uiteindelijke
  controleren en versturen bewust aan de gebruiker over. Het keuzescherm is
  volledig met links/rechts en Enter bedienbaar en toont geen overbodige
  succesmelding nadat het telefoonnummer zichtbaar is ingevuld. Een
  geforceerde repaint ná het tonen van de dialoog voorkomt dat de knoppen
  aanvankelijk nog met de native Windows-rand verschijnen.
- Fix: een nog niet afgehandeld belvenster kon door een volgende
  klemborddetectie onopgemerkt open blijven staan en later met een
  verouderd nummer terugkomen. DocBot sluit een dergelijk venster nu altijd
  automatisch (met melding) zodra een nieuw nummer wordt herkend, ook
  wanneer dat nieuwe nummer — zoals een intern nummer bij Belactie "Bellen
  of sms kiezen" — zonder eigen dialoog direct wordt gebeld.
- Het klembordnummer in de centrale telefoniestatus wordt nu direct
  geleegd na bellen, sms-actie, annuleren of sluiten van het venster, in
  plaats van te blijven staan tot het volgende nummer of het afsluiten van
  DocBot.
- Klikbare link naar de GitHub-pagina van DocBot
  (`https://github.com/Pastinakel/DocBot`) linksonder op het Over-scherm,
  op dezelfde hoogte als de knop "Probleem melden..." op de Help-pagina.

### 2.1 — Vorige stabiele release
- Nieuwe Help-pagina met vier uitklapbare, scrollbare instructiekaarten voor
  telefoonregistratie, bellen vanuit een EPD, snelkiesnummers en hotstrings.
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
  dial-actie met de vierstandenlogica van Belactie.
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

## License

DocBot 2.2 and later are available under the
[PolyForm Noncommercial License 1.0.0](LICENSE).

Noncommercial use, modification, and distribution are permitted under the
license terms. Commercial use requires a separate written license from the
copyright holder.

DocBot 2.1 was released separately under the MIT License and remains available
under those terms in tag `v2.1`.
