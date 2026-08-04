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
- `README.md` — volledige documentatie over installatie, functionaliteit, telefonie, diagnostiek en wijzigingen.
- Voeg verwijderde legacybestanden niet opnieuw toe aan actieve branches.

Plaats meegeleverde externe libraries altijd in een eigen map onder
`ThirdParty/`, met hun oorspronkelijke licentiebestand in dezelfde map.
Pas bij een verplaatsing zowel alle `#Include`-paden als de bestandenlijst
in `README.md`, `AGENTS.md` en `CLAUDE.md` aan.

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
- Debug-log: `%LocalAppData%\DocBot\debug.log`

## Gebruikersprofielen per releasekanaal

DocBot gebruikt bewust drie gescheiden mappen onder `A_MyDocuments`. De
versiestring bepaalt het profiel:

- een versie met uitsluitend cijfers en punten, bijvoorbeeld `2.1`, gebruikt
  `DocBot` (main/stable);
- `-dev` of `-rc` direct achter het numerieke versienummer, bijvoorbeeld
  `2.1-dev.15` of `2.1-rc.1`, gebruikt `DocBot-test` (centrale
  ontwikkel-, test- en releasecandidateversies);
- iedere andere prerelease met letters, bijvoorbeeld
  `2.1-multiline.1` of `2.1-bugs-pakketview.2`, gebruikt `DocBot-dev`
  (feature- en fixbranches).

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

### Versienummers per branch

Gebruik in de huidige ontwikkelcyclus deze versies:

```text
main:              2.1
develop:           2.2-dev.N
features/fixes:    2.2-<korte-branchnaam>.N
release candidate: 2.2-rc.N
release:           2.2
```

Dezelfde structuur geldt voor latere releases: `main` bevat altijd de laatst
uitgebrachte stabiele versie; `develop` gebruikt de volgende beoogde release
met `-dev.N`; iedere feature- of fixbranch gebruikt een korte
branchspecifieke prerelease-naam met een eigen lokale teller; een releasebranch
gebruikt `-rc.N`; bij de stabiele release vervalt de prerelease-suffix.

Maak een releasecandidate vanaf een actuele `develop` op een branch zoals
`release/2.2-rc.1`. Voeg daar uitsluitend bugfixes, documentatie en
releasevoorbereidingen aan toe. Nieuwe functionaliteit wacht op de volgende
ontwikkelcyclus. Iedere commit op de releasebranch die `DocBot.ahk` wijzigt,
verhoogt `rc.N` met één.

Voorbeelden zijn `2.2-dev.7`, `2.2-ronde-kaarten.3`,
`2.2-import.5` en `2.2-rc.1`. Houd branchspecifieke prerelease-namen
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
`AppVersion` pas voor de definitieve releasecommit van `2.2-rc.N` naar
de stabiele versie `2.2`.

Bij een stabiele release moet in dezelfde commit-cyclus:

1. De sectie `Changelog` in `README.md` worden afgerond. Dit is de enige
   bron voor de versiegeschiedenis; het Over-scherm leest deze sectie
   automatisch in. Onderhoud `BuildAboutText()` niet handmatig.
2. Een annotated tag met `v`-prefix worden aangemaakt op de stabiele
   versiecommit, bijvoorbeeld:
   ```bash
   git tag -a v2.1 -m "2.1"
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


## Lokale configuratie

Interne telefonieadressen, endpointnamen, standaard-snelkiesnummers en
standaard-hotstrings staan uitsluitend in `DocBot.local.ahk`. Dit bestand
wordt door Git genegeerd en mag nooit worden gecommit. Gebruik
`DocBot.local.example.ahk` als veilige structuurtemplate zonder echte
waarden. Ahk2Exe neemt de lokale include tijdens compilatie op.


## Release bijwerkacties

Bij release 2.2 moet de releasebranch met een mergecommit naar `main` worden
gemerged en moet `main` daarna terug naar `develop`; hiermee wordt de sinds
release 2.1 afwijkende commitgeschiedenis definitief gesynchroniseerd.
