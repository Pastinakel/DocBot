# DocBot – werkinstructies voor Claude

## Project

Dit project gebruikt **AutoHotkey v2** (niet v1; de syntax verschilt fors).

DocBot is een AutoHotkey v2-hulpmiddel voor medewerkers met twee hoofdfuncties:

- tekstvervanging via hotstrings;
- bellen via de interne IP-telefonie van het ziekenhuis, met automatische detectie van telefoonnummers op het klembord.

`DocBot.ahk` is de nieuwe, gerefactorde versie met een interface met sidebar-navigatie, cards en een tray-menu.

## Bestanden

- `DocBot.ahk` — huidig hoofdscript; werk hieraan voor hotstrings, telefonie en de interface.
- `ThirdParty/JXON/JXON.ahk` — JSON-library (TheArkive, MIT), gebruikt voor hotstring-opslag.
- `ThirdParty/ColorButton/ColorButton.ahk` — knopbibliotheek (Nikola Perovic, MIT).
- `ThirdParty/UIA-v2/UIA.ahk` — UI Automation-library voor interactie met Edge.
- `ThirdParty/<library>/LICENSE` — oorspronkelijke licentie van de betreffende externe library.
- `tests/SelfTests.ahk` — opt-in zelftests voor pure migratielogica, gestart met `DocBot.ahk --selftest`; zie `tests/README.md` en `docs/DECISIONS.md` D-053.
- `docs/MIGRATIONS.md` — register per opslagformaat: welke schemaversie welk veld/standaardwaarde toevoegde.
- `README.md` — volledige documentatie over installatie, functionaliteit, telefonie, diagnostiek en wijzigingen.
- Voeg verwijderde legacybestanden niet opnieuw toe aan actieve branches.

Plaats meegeleverde externe libraries altijd in een eigen map onder
`ThirdParty/`, met hun oorspronkelijke licentiebestand in dezelfde map.
Pas bij een verplaatsing zowel alle `#Include`-paden als de bestandenlijst
in `README.md`, `AGENTS.md` en `CLAUDE.md` aan.

## Projectdocumentatie

De map `docs/` bevat duurzame projectkennis die niet uit losse chats of
agentgeheugen mag worden afgeleid. Gebruik `CLAUDE.md` als navigatiekaart en
lees vóór uitvoering de documenten die voor de taak relevant zijn:

1. Lees `docs/PROJECT_CONTEXT.md` voor productcontext, requirements, bekende
   bugs en de actuele ontwikkel- en releasestatus.
2. Lees `docs/INTENDED_PURPOSE.md` vóór wijzigingen aan het beoogde gebruik,
   gebruikers, gebruiksomgeving, invoer, uitvoer, autonome acties, beperkingen
   of uitgesloten medische toepassingen.
3. Lees `docs/DATA_PROTECTION.md` vóór wijzigingen aan persoonsgegevens,
   gegevensstromen, ontvangers, bewaartermijnen, autorisaties,
   transportbeveiliging of DPIA-relevante functionaliteit.
4. Lees `docs/ARCHITECTURE.md` voordat je architectuur, opslag, dataflows,
   componentgrenzen of integraties wijzigt.
5. Lees `docs/DECISIONS.md` voordat je een bestaande ontwerpkeuze vervangt,
   terugdraait of opnieuw bespreekt.
6. Lees `docs/TODO.md` bij werk aan openstaande taken, releaseplanning of
   bekende vervolgacties.
7. Lees `docs/REGULATORY_ASSESSMENT.md` vóór wijzigingen aan de intended
   purpose, patiëntgegevens, klinische pakketinhoud, beslislogica, autonome
   acties, logging/telemetrie of integraties die de MDR-kwalificatie,
   patiëntveiligheid of NEN 7510-scope kunnen beïnvloeden.

Behandel deze documenten als duurzame projectcontext, maar controleer vóór
implementatie altijd of statusgegevens nog overeenkomen met de actuele code,
branches en pull requests. Werk de relevante `docs/`-bestanden bij wanneer een
wijziging hun inhoud achterhaald maakt.

## Hotstringmodel en uitvoer

- Persoonlijke hotstrings gebruiken één `Replacement`-veld. Introduceer geen
  apart datatype voor enkelregelige, meerregelige of lange teksten.
- Kies de uitvoer automatisch: korte enkelregelige tekst via de normale
  hotstringvervanging, lange of meerregelige tekst via een callback met
  `SendText()` en teksten met toetsopdrachten zoals `{Tab}` of `{Left}`
  via toetsenmodus.
- Gebruik het Windows-klembord nooit voor hotstringvervangingen. DocBot leest
  het klembord uitsluitend voor de telefoniefunctie. Meerregelige callbacks
  versturen gewone tekst met `SendText()` en voeren regeleinden afzonderlijk
  als `{Enter}` uit.
- Nieuwe standaarditems worden via een eenmalige schema-upgrade toegevoegd.
  Controleer op de functionele sleutel (hotstringafkorting; snelkiesnaam of
  nummer), overschrijf nooit gebruikersgegevens en voeg verwijderde defaults
  na de migratie niet bij iedere start opnieuw toe.
- De pakketstatussen heten: `Inactief`, `Overruled`, `Voorrang`,
  `Conflict` en `Actief`, met de betekenis uit de README.

## Changelog en Over-scherm

- Onderhoud de versiegeschiedenis uitsluitend onder `Changelog` in
  `README.md`. Voeg geen handmatige versieregels meer toe aan
  `BuildAboutText()`; het Over-scherm leest en vereenvoudigt deze sectie.
- Houd de changelog aflopend: nieuwste release bovenaan en de oudste onderaan.
- Houd ieder changelog-item beknopt: richt op ongeveer 50 woorden, en ga tot
  maximaal 100 woorden alleen als dat echt nodig is, afhankelijk van hoe
  uitgebreid het item daadwerkelijk is. Beschrijf wat er veranderde en
  waarom het relevant is voor de gebruiker; verwijs niet naar
  implementatiedetails, bestandsnamen of interne discussie die daar niet
  voor nodig zijn.
- `README.md` wordt via `FileInstall` in gecompileerde builds opgenomen.

## Transparantie over telemetrie

- Iedere actieve branch en release moet in `README.md` een duidelijk
  herkenbare sectie `Telemetrie` behouden. Deze melding is bedoeld voor
  eindgebruikers en mag niet stilzwijgend worden verwijderd, verborgen of
  afgezwakt.
- De melding noemt begrijpelijk en volledig welke gegevens worden verzonden,
  met welk doel en interval, en welke gevoelige inhoud uitdrukkelijk niet
  wordt verzameld.
- Iedere wijziging aan `Telemetry.ahk`, de telemetrieconfiguratie, het
  verzendinterval of de payload moet in dezelfde wijzigingsreeks worden
  verwerkt in de README-melding. De documentatie moet overeenkomen met de
  daadwerkelijk verzonden payload.
- Nieuwe telemetrievelden of een verruiming van de verzameling vereisen
  expliciete toestemming van de projecteigenaar en moeten vóór een release
  zichtbaar in de README worden beschreven.

## Distributie

Het script wordt gecompileerd en uitsluitend als executable aan eindgebruikers aangeboden. Wijzigingen horen daarom altijd in de `.ahk`-bronbestanden in deze repository. Compileren en uitleveren gebeurt daarna apart door de gebruiker.

## Opslag op de gebruikerscomputer

Deze bestanden staan niet in de repository:

- Hotstrings: `%MyDocuments%\DocBot\hotstrings.json`
- Instellingen: `%MyDocuments%\DocBot\settings.ini`
- Pakketstatussen: `%MyDocuments%\DocBot\package-settings.json`
- Snelkiesnummers: `%MyDocuments%\DocBot\speeddial.json`
- SMS-standaardtekst per pagina: `%MyDocuments%\DocBot\sms-default-texts.json`
- Debug-log: `%LocalAppData%\DocBot\debug.log`

## Gebruikersprofielen per releasekanaal

DocBot gebruikt bewust drie gescheiden mappen onder `A_MyDocuments`. Stable
heeft voorrang; voor elke niet-stabiele versie kiest de buildvorm
(`A_IsCompiled`), niet het prereleaselabel, tussen `DocBot-test` en
`DocBot-dev`:

- een versie met uitsluitend cijfers en punten, bijvoorbeeld `2.2`, gebruikt
  altijd `DocBot` (main/stable), ongeacht of die build gecompileerd is;
- iedere niet-stabiele, gecompileerde versie — bijvoorbeeld `2.3-dev.15`,
  `2.3-rc.1` of `2.3-multiline.1` — gebruikt `DocBot-test`: een gecompileerde
  prerelease test de opleverbare vorm en deelt daarom het centrale
  testprofiel, ongeacht welke branch de build maakte;
- iedere niet-stabiele, niet-gecompileerde versie (rechtstreeks vanuit
  broncode gestart) gebruikt `DocBot-dev`: dat is broncode-ontwikkeling en
  blijft geïsoleerd van het gedeelde testprofiel.

Als `DocBot-test` nog niet bestaat, wordt die eenmalig vanuit `DocBot`
gekopieerd. Als `DocBot-dev` nog niet bestaat, wordt die bij voorkeur vanuit
`DocBot-test` gekopieerd en anders vanuit `DocBot`. Na het kopiëren lopen
de normale datamodelmigraties. Bestaande doelmappen worden nooit opnieuw
overschreven.

## Telefonie

Telefonie werkt uitsluitend binnen het ziekenhuisnetwerk. De interne telefonieserver is van buitenaf niet bereikbaar.

Endpoints:

- `registratie-endpoint` — registratie;
- `event-endpoint` — long-poll voor events;
- `bel-endpoint` — bellen.

Alle aanroepen zijn POST. De configuratie staat in `IPTConfig`; de live status staat in `State["IPT"]`. Beide staan bovenaan `DocBot.ahk`.

`Telephony.BaseUrl` en elke `SmsCallAction.Url` in `DocBot.local.ahk` moeten met `https://` beginnen. `ValidateLocalConfiguration()` respectievelijk `ValidateSmsCallActionItem()` weigeren een `http://`-waarde al bij het opstarten (zie `docs/DECISIONS.md` D-043); voeg hier geen stille HTTP-fallback of certificaatomzeiling aan toe.

## AutoHotkey v2 en globale variabelen

AHK v2 voert top-level statements in bestandsvolgorde uit. Functiedefinities worden daarbij overgeslagen, maar een `global X := ...`-initialisatie die pas na een aanroep staat waarin `X` wordt gebruikt, is op dat moment nog niet uitgevoerd.

Alle globale declaraties die vóór of tijdens het opbouwen van de GUI nodig zijn, moeten daarom in het bestaande globals-blok bovenaan het bestand staan, vóór het auto-execute-gedeelte. Dit geldt ook voor waarden die direct of indirect vanuit `BuildMainGui()` worden gelezen, zoals:

- `RoundQueue`;
- `RoundedRadii`;
- `ControlHomePos`;
- `GdipToken`.

Plaats zulke globals niet verderop in een functionele sectie zoals “AFRONDING”.

## Branch-workflow

`main` is exact gelijk aan wat als executable bij de eindgebruiker draait. Normaal werk begint altijd vanaf een actuele `develop`, niet vanaf `main`.

Begin een lokale werksessie met:

```bash
git fetch --prune
git checkout develop
git pull origin develop
git checkout -b claude/<omschrijving>
```

Controleer met `git status` en `git branch -vv` of de huidige branch nog op de remote bestaat. Merge afgerond werk in `develop`, niet in `main`.

Werk alleen rechtstreeks vanaf `main` wanneer de gebruiker expliciet zegt dat het om een hotfix voor de gedeployde versie gaat. Merge zo’n fix daarna ook naar `develop`, zodat die branch niet achterloopt.

Wijzig develop en main nooit rechtstreeks. Maak altijd een pull request vanuit een feature-, fix- of releasebranch. Merge pas nadat de gebruiker daar expliciet opdracht voor geeft.

### Lokale werkwijze

Gebruik voor bronbewerking een lokale git-clone, niet de GitHub-webeditor/
-connector en niet een tijdelijke, zichzelf-verwijderende GitHub Actions-
workflow als editing-workaround (zie `docs/DECISIONS.md` D-036). Gebruik
GitHub-tooling voor pull requests, reviews en kleinere metadata-acties; val
alleen op een workflow-as-editor-truc terug als normale git-/
connectormethoden echt niet beschikbaar zijn.

Controleer `git status` vóór iedere `git pull` of branchwissel. Commit of
stash bewuste lokale wijzigingen eerst; laat een `pull` nooit lokale
wijzigingen stilzwijgend overschrijven.

Controleer vóór iedere commit expliciet: het branchtype en de bijbehorende
`AppVersion`-teller; of `DocBot.ahk` is gewijzigd en zo ja of `AppVersion` in
dezelfde commit is aangepast; of de README/changelog moet worden bijgewerkt;
en of de telemetriedocumentatie moet worden bijgewerkt.

Git-bewerking (clonen, branchen, committen, pushen) kan vanaf een Mac,
maar functionele AutoHotkey v2-validatie vereist Windows. Behandel "de
patch is bewerkt en gepusht" nooit als bewijs dat DocBot ook daadwerkelijk
is gevalideerd (zie `docs/DECISIONS.md` D-037).

### Versienummers per branch

Gebruik in de huidige ontwikkelcyclus deze versies:

```text
main:              2.3
develop:           2.4-dev.N
features/fixes:    2.4-<korte-branchnaam>.N
release candidate: 2.4-rc.N
release:           2.4
```

Dezelfde structuur geldt voor latere releases: `main` bevat altijd de laatst
uitgebrachte stabiele versie; `develop` gebruikt de volgende beoogde release
met `-dev.N`; iedere feature- of fixbranch gebruikt een korte
branchspecifieke prerelease-naam met een eigen lokale teller; een releasebranch
gebruikt `-rc.N`; bij de stabiele release vervalt de prerelease-suffix.

Maak een releasecandidate vanaf een actuele `develop` op een branch zoals
`release/2.4-rc.1`. Voeg daar uitsluitend bugfixes, documentatie en
releasevoorbereidingen aan toe. Nieuwe functionaliteit wacht op de volgende
ontwikkelcyclus. Iedere commit op de releasebranch die `DocBot.ahk` wijzigt,
verhoogt `rc.N` met één.

Voorbeelden zijn `2.4-dev.7`, `2.4-ronde-kaarten.3`,
`2.4-import.5` en `2.4-rc.1`. Houd branchspecifieke prerelease-namen
geschikt voor SemVer: uitsluitend ASCII-letters, cijfers en koppeltekens.

Iedere commit die `DocBot.ahk` wijzigt, moet in dezelfde commit ook
`global AppVersion` aanpassen:

- op `develop`: verhoog uitsluitend de centrale `dev.N`-teller met één;
- op een feature- of fixbranch: verhoog uitsluitend de lokale teller;
- op een releasebranch: verhoog uitsluitend de centrale `rc.N`-teller;
- op `main`: gebruik uitsluitend een stabiele releaseversie, behalve bij een
  expliciet gevraagde hotfixvoorbereiding.

De teller van een zijbranch bepaalt nooit de teller van `develop`. Bij het
mergen naar `develop` moet de zijbranchversie worden vervangen door de
actuele `develop`-versie met een nieuw, hoger centraal `dev.N`. Een merge
mag het nummer nooit verlagen. Een commit die `DocBot.ahk` niet wijzigt,
wijzigt ook `AppVersion` niet.

Een wijziging van alleen een prerelease-teller of prerelease-naam is geen
stabiele release: maak daarvoor geen stabiele changelogsectie en geen
releasetag.

## Releases, versiegeschiedenis en tags

De releasebranch wordt via een pull request naar `main` gemerged. Zet
`AppVersion` pas voor de definitieve releasecommit van `2.4-rc.N` naar
de stabiele versie `2.4`.

Bij een stabiele release moet in dezelfde commit-cyclus:

1. De sectie `Changelog` in `README.md` worden afgerond. Dit is de enige
   bron voor de versiegeschiedenis; het Over-scherm leest deze sectie
   automatisch in. Onderhoud `BuildAboutText()` niet handmatig.
2. Een annotated tag met `v`-prefix worden aangemaakt op de stabiele
   versiecommit, bijvoorbeeld:
   ```bash
   git tag -a v2.3 -m "2.3"
   ```
3. De tag worden gepusht:
   ```bash
   git push origin --tags
   ```
4. Releasefixes uit de releasebranch ook via een pull request in `develop`
   opnemen en daar de volgende ontwikkelversie starten.

Ontwikkel-, feature-, fix- en RC-versies krijgen geen stabiele releasetag.
Meld het expliciet als een tag niet naar `origin` kan worden gepusht. Een
tag telt pas als gereed wanneer die op `origin` zichtbaar is.

### Verantwoording bij versie- en tagwijzigingen

Benoem bij iedere wijziging van `global AppVersion` expliciet, in dezelfde
boodschap aan de gebruiker, op welk branchtype dit gebeurt (main, develop,
releasebranch of feature-/fixbranch) en welke tellerregel daarbij hoort — dus
niet alleen de nieuwe versiestring tonen. Een feature- of fixbranch die via
een pull request naar een releasebranch gaat, is en blijft een feature-/
fixbranch voor deze regel, ook als de gebruiker toestemming heeft gegeven om
"op" of "voor" die releasebranch te werken: dat is geen toestemming om de
gedeelde `rc.N`- of `dev.N`-teller van de doelbranch te gebruiken.

Behandel het aanmaken en pushen van een tag niet als vanzelfsprekend
onderdeel van een reeds goedgekeurde taak. Vraag daar apart expliciete
toestemming voor, ook wanneer de gebruiker net al voor de rest van het werk
"ga door" heeft gezegd — een tag is, net als een force-push, moeilijker
terug te draaien dan een gewone commit.

## Lokale configuratie

Interne telefonieadressen, endpointnamen, standaard-snelkiesnummers en
standaard-hotstrings staan uitsluitend in `DocBot.local.ahk`. Hetzelfde
geldt voor het optionele UNC-pad van de netwerkshare met meegeleverde
hotstringpakketten (`LocalConfig["Packages"]["ShareDir"]`): de
gecompileerde applicatie leidt die locatie standaard automatisch af uit
`A_ScriptDir` (de map naast de draaiende executable) en heeft dit veld dus
alleen nodig als expliciete override, bijvoorbeeld wanneer een launcher een
lokale kopie van de executable start in plaats van rechtstreeks vanaf de
netwerklocatie. `DocBot.local.ahk` wordt door Git genegeerd en mag nooit
worden gecommit. Gebruik `DocBot.local.example.ahk` als veilige
structuurtemplate zonder echte waarden. Ahk2Exe neemt de lokale include
tijdens compilatie op.
