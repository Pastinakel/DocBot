# DocBot — Regulatory and standards assessment

_Status: voorlopige repositoryanalyse, geen juridisch advies of formeel conformiteitsoordeel._

_Beoordelingsdatum: 2026-08-14._

_Onderzochte basis: branch `release/2.2-finalize` (bestemd voor `main`),
`AppVersion = 2.2` (stabiele release). Deze update volgt op de vorige
beoordeling (commit `76fe6a0`, `2.2-rc.3`) en verwerkt de sindsdien in PR #23
doorgevoerde functionele wijziging aan het telefonie-bevestigingsvenster en
de klembordstatus (zie §5.4 en §7). De overige wijzigingen sinds
`2.2-rc.3` (o.a. een klikbare GitHub-link op het Over-scherm) zijn
regulatoir niet relevant._

## 1. Doel en status

Dit document legt de beoordeling vast of DocBot:

1. software is;
2. bij de huidige zorgtoepassing gezondheidsinformatie verwerkt;
3. mogelijk Medical Device Software (MDSW) is onder Verordening (EU) 2017/745 (MDR).

Het beschrijft daarnaast de mogelijke relevantie van NEN 7510, IEC 62304,
ISO 14971 en ISO 13485. De beoordeling is gebaseerd op de repository, niet
alleen op de README. De hoofdbron, telemetriemodule, pakketinhoud,
lokale-configuratietemplate, het buildscript en de duurzame projectdocumentatie
zijn onderzocht.

Dit is een momentopname. De uiteindelijke juridische kwalificatie hangt ook af
van informatie buiten de repository, waaronder labels, gebruiksinstructies,
trainingsmateriaal, promotionele claims, lokale configuratie en het door de
fabrikant beoogde gebruik.

## 2. Samenvatting

| Niveau | Beoordeling | Hoofdreden |
| --- | --- | --- |
| Software | Ja, zonder twijfel | DocBot verwerkt invoer, bewaart toestand, genereert uitvoer, communiceert over het netwerk en stuurt andere applicaties aan. |
| Toepassing binnen zorgprocessen | Ja | DocBot wordt toegepast in een ziekenhuisomgeving en kan daar patiënttelefoonnummers verwerken, klinische tekst in een EPD invoegen en gevoelige diagnostische logs verzamelen. |
| MDSW onder de goedgekeurde intended purpose | Waarschijnlijk niet | De goedgekeurde verklaring sluit een medisch doel uit en de aangetroffen functies analyseren geen patiëntspecifieke medische gegevens en geven geen diagnose, prognose, monitoring, behandelkeuze of doseringsadvies. De beslisregels zijn technisch en administratief. |

DocBot heeft wel reële informatiebeveiligings- en patiëntveiligheidsrisico's.
Het ontbreken van MDSW-kwalificatie neemt die risico's niet weg.

## 3. Onderzochte repositorybasis

De beoordeling steunt onder meer op:

- `README.md`: productbeschrijving, installatie, functionele uitleg,
  telemetrie en diagnostiek;
- `docs/INTENDED_PURPOSE.md`: goedgekeurde verklaring van het beoogde gebruik,
  de grenzen en de uitgesloten medische toepassingen;
- `docs/DATA_PROTECTION.md`: technische gegevensstromen en openstaande
  organisatorische beoordeling van rollen, grondslagen, ontvangers,
  bewaartermijnen, autorisaties, transportbeveiliging en DPIA-noodzaak;
- `DocBot.ahk`: feitelijke hotstring-, telefonie-, SMS-, opslag-, logging-,
  rapportage- en updatefunctionaliteit;
- `Telemetry.ahk`: telemetrieconfiguratie, lokale tellers en payload;
- `packages/*.json`: meegeleverde medische en algemene hotstringinhoud;
- `DocBot.local.example.ahk`: structuur van lokale telefonie-, SMS- en
  telemetrieconfiguratie;
- `Build-EPD_Machine.bat`: compilatie en centraal updateproces;
- `docs/PROJECT_CONTEXT.md`, `docs/ARCHITECTURE.md`, `docs/DECISIONS.md` en
  `docs/TODO.md`: requirements, ontwerpkeuzes, ontwikkelstatus en bekende
  validatiehiaten;
- `.github/pull_request_template.md`: huidige wijzigingscontroles.

Niet in Git opgenomen `DocBot.local.ahk`, productie-endpoints, beheerbeleid,
trainingsmateriaal, externe productclaims en de feitelijke ziekenhuisomgeving
vallen buiten de onderzochte repositorybasis.

## 4. Intended purpose

### 4.1 Aangetroffen productdoel

De primaire verklaring staat in `docs/INTENDED_PURPOSE.md`, heeft de status
van goedgekeurd intern productbesluit en wordt in `README.md` en
`docs/PROJECT_CONTEXT.md` weerspiegeld. DocBot is productiviteitssoftware voor
medewerkers in een beheerde bedrijfsomgeving. De software ondersteunt
tekstinvoer door ingestelde afkortingen (hotstrings) te vervangen en
ondersteunt communicatie door telefoonnummers op het Windows-klembord
technisch te herkennen en te normaliseren. Afhankelijk van de
gebruikersinstelling kan DocBot een herkend nummer doorgeven aan een
geconfigureerde interne telefoniedienst of invullen in een geconfigureerde
SMS-webapplicatie. DocBot verzendt zelf geen SMS-berichten. De beoogde
gebruikers zijn medewerkers op een beheerde Windows-werkplek; DocBot is geen
zelfstandig patiëntproduct.

DocBot is ontstaan vanuit behoeften in een ziekenhuisomgeving en wordt daar
ook toegepast. De software heeft geen beoogd medisch doel: zij verricht geen
medische analyse van patiëntgegevens, trekt geen klinische conclusies en geeft
geen diagnose-, behandel-, doserings- of monitoringsadvies. De gebruiker blijft
verantwoordelijk voor de gekozen hotstring, het telefoonnummer, de
patiënt-/dossiercontext en het verzenden van SMS en probleemrapport.
Aanvullende functies zijn snelkiezen, pakketbeheer, telemetrie,
probleemrapportage en gecontroleerd afsluiten, herstarten en updaten.

### 4.2 Niet aangetroffen als productdoel

In de repository is geen intended purpose aangetroffen voor:

- diagnose, preventie, voorspelling of prognose van ziekte;
- bewaking van fysiologische of pathologische processen;
- patiëntspecifieke risicoberekening of triage;
- keuze of aanbeveling van behandeling of medicatiedosering;
- klinische alarmering op basis van patiëntparameters;
- aansturing of beïnvloeding van een medisch hulpmiddel.

De intended-purposeverklaring legt gebruikers, omgeving, invoer, uitvoer,
autonome technische acties, beperkingen, gebruikersverantwoordelijkheid en
uitgesloten medische toepassingen vast. Zij geldt voor `2.2-rc.3` en
opvolgende versies totdat een herbeoordeling tot een gewijzigde verklaring
leidt. De regulatoire kwalificatie blijft voorlopig: zij is gebaseerd op
documentatie én implementatie en is geen extern juridisch of gecertificeerd
oordeel.

## 5. Feitelijke functionaliteit

### 5.1 Softwaregedrag

DocBot is een blijvende AutoHotkey v2-desktopapplicatie met GUI en tray-menu.
De software:

- valideert lokale configuratie en initialiseert opslag, packages,
  instellingen, hotstrings, telemetrie en logging (`DocBot.ahk:15-25` en
  `DocBot.ahk:230-275`);
- registreert dynamische hotstrings en voert tekst uit in de actieve
  applicatie (`DocBot.ahk:5234-5424`);
- controleert het Windows-klembord iedere 100 ms op telefoonnummers
  (`DocBot.ahk:3608-3629`);
- communiceert via POST met registratie-, event- en bel-endpoints van de
  interne telefonieserver (`DocBot.ahk:1979-2177`);
- automatiseert Edge om een telefoonnummer in een SMS-pagina te plaatsen
  (`DocBot.ahk:4000-4281`);
- kan na een gericht signaalbestand afsluiten, herladen of een updatepad
  starten (`DocBot.ahk:2206-2397`).

Dit is ondubbelzinnig software: een samenstel van instructies dat invoer
verwerkt en uitvoer en acties produceert.

### 5.2 Hotstrings

Een gebruiker maakt of bewerkt een afkorting en vervangtekst
(`DocBot.ahk:5161-5205`). DocBot bouwt daaruit de effectieve hotstrings en
registreert die dynamisch (`DocBot.ahk:5234-5283`). De software kiest daarna
een technische uitvoermethode:

- normale vervanging voor korte enkelregelige tekst;
- `SendText()` voor lange of meerregelige tekst;
- toetsenmodus voor opdrachten zoals `{Tab}` of `{Left}`;
- vervanging van datum- en tijdcodes.

Deze regels staan in `DocBot.ahk:5309-5424`. DocBot leest hiervoor geen
patiëntdossier en leidt geen klinische conclusie af. De gebruiker kiest de
hotstring; DocBot voert de bijbehorende vaste of door de gebruiker gemaakte
tekst uit in het actieve venster.

### 5.3 Medische pakketinhoud

De meegeleverde pakketten bevatten teksten met medische betekenis. Voorbeelden:

- `packages/medisch-algemeen.json:31-35`: "geen duidelijke afwijkingen";
- `packages/medisch-algemeen.json:73-77`: een vaste verklaring over
  procedures, risico's en verkregen toestemming;
- `packages/controles.json:15-92`: vaste controletermijnen;
- `packages/gyn-obst.json:38-76`: termen als zwangerschapshypertensie,
  pre-eclampsie, HELLP en eclampsie.

Deze inhoud kan de betekenis van een medisch dossier beïnvloeden. De software
bepaalt echter niet of de patiënt een afwijking heeft, of toestemming werkelijk
is verkregen of welke controletermijn passend is. Die selectie blijft bij de
gebruiker. Dit lijkt functioneel meer op tekstverwerking of documentatiemacro's
dan op patiëntspecifieke clinical decision support.

De teksten in de pakketbestanden en persoonlijke `hotstrings.json` zijn
bedoeld als generieke, herbruikbare formuleringen en zijn zonder koppeling aan
een identificeerbare patiënt niet op zichzelf patiënt- of
gezondheidsgegevens. Zodra de gebruiker zo'n tekst in een patiëntdossier
plaatst, wordt de resulterende dossierinhoud wel onderdeel van de
patiëntgebonden zorgdocumentatie. Patiëntidentificerende of patiëntspecifieke
inhoud hoort niet in `hotstrings.json`; een technische inhoudscontrole
ontbreekt en een gebruikersinstructie staat nog als vervolgactie open.

### 5.4 Telefonie en SMS

`IPT_callNumber()` is het centrale belpad. Het controleert onder meer of een
toestel is gekoppeld en verzendt het nummer naar de telefonieserver
(`DocBot.ahk:1979-2021`).

Het klembordpad normaliseert Nederlandse externe en interne nummers met
technische regexregels (`DocBot.ahk:3639-3675`). Afhankelijk van de instelling
kan DocBot niets doen, bevestiging vragen, direct bellen of bij een extern
nummer een keuze tussen annuleren, SMS of bellen tonen
(`DocBot.ahk:3678-3771`). Bij direct bellen kan een herkend klembordnummer
zonder nieuwe bevestiging worden gebeld. Dat is autonoom operationeel gedrag,
maar geen medische beslissing.

Sinds PR #23 (`2.2-rc.4`) sluit een nieuwe klemborddetectie een nog niet
bevestigd bel- of sms-keuzevenster van een eerder nummer automatisch en
vervangt dat door het venster voor het nieuwe nummer, met een zichtbare
melding (`CloseExistingPhoneActionDialog()`, `DocBot.ahk:3899-3914`). Er kan
zo nooit meer dan één, altijd het meest recente, te bevestigen nummer
tegelijk openstaan; DocBot belt hierbij zelf niets — bevestigen blijft aan de
gebruiker. Het herkende nummer wordt bovendien direct uit de centrale
`State["IPT"]`-status gewist zodra de actuele actie is overgedragen, afgerond
of geannuleerd (`SetClipBoardNumber()`/`ClearClipBoardNumber()`,
`DocBot.ahk:3563-3578`; zie ook `docs/DATA_PROTECTION.md` §3.1). Beide
wijzigingen beperken hoe lang en hoeveel klembordnummers intern zichtbaar
blijven en veranderen geen belbeslissing; ze zijn geen nieuwe autonome
medische actie.

Bij SMS activeert DocBot een geconfigureerde Edge-pagina en vult het nummer in.
DocBot verzendt de SMS niet zelfstandig; controle en verzending blijven bij de
gebruiker (`README.md:192-216` en beslissing D-021). De huidige
SMS-webapplicatie wordt geleverd als Enovation Funatic. De exacte
contractpartij binnen Enovation Group, AVG-rol, verwerkersovereenkomst,
subverwerkers, hostinglocaties en feitelijke serverbewaring moeten nog aan de
overeenkomst en productieomgeving worden getoetst.

### 5.5 Diagnostiek en telemetrie

De standaardlog wordt centraal geschoond. De redactie maskeert onder andere
paden, gebruiker/computer, URL's, telefoonnummers en gestructureerde inhoud
(`DocBot.ahk:2533-2588`). Na expliciete toestemming kan een tijdelijk
uitgebreid log exacte URL's, serverresponsen, volledige telefoonnummers en
uitgevoerde hotstringafkortingen en -teksten bevatten
(`DocBot.ahk:3054-3101` en `DocBot.ahk:5397-5404`). Bij afsluiten wordt dit
tijdelijke log verwijderd (`DocBot.ahk:3175-3189`).

Een probleemrapport kan vrije tekst, de standaardlog en na toestemming de
uitgebreide log bevatten. DocBot maakt vervolgens een Outlook-concept met de
rapportbestanden als losse bijlagen (geen ZIP, zie `docs/DECISIONS.md`
D-041); de gebruiker verzendt het bericht zelf.

In de huidige opstartfase is de enige ontwikkelaar de enige ontvanger van een
verzonden probleemrapport. De ontwikkelaar gebruikt hiervoor een door de
organisatie beheerd Outlook-account en een speciale diagnostiekmap waarin
berichten ouder dan zeven dagen automatisch worden verwijderd. Er is geen
waarnemer of vervanger bij afwezigheid. Langere retentie in herstelvoorzieningen
of back-ups volgt het organisatorische Microsoft-/mailboxbeleid. De lokale
standaardlog wordt nog alleen op bestandsgrootte geroteerd; automatische
verwijdering van logregels ouder dan zeven dagen is een openstaande technische
actie. Ook automatische verwijdering van de tijdelijke probleemrapportmap na
veilige overdracht of annulering staat nog open.

De optionele telemetrie bevat onder meer een installatie-ID,
Windows-gebruikersnaam, applicatieversie, tijden, functionele status en
gebruikstellers (`Telemetry.ahk:294-353`). De code en telemetriemelding in
`README.md:272-322` beogen geen telefoonnummers, hotstringinhoud of
klembordinhoud te verzenden. Het vastgelegde doel is inzicht in gebruik en
omvang voor capaciteitsplanning van telefonie- en SMS-diensten. Het
willekeurige installatie-ID is als pseudoniem, minder identificerend
kenmerk vanaf het ontwerp onderdeel van de payload — dit is geen mechanisme
dat nog gebouwd moet worden. Tijdens de opstartfase ondersteunt de
Windows-gebruikersnaam daarnaast, bovenop dat installatie-ID, gerichte hulp
bij technische problemen, zoals niet-geactiveerde telefonie of een eerder
wisselend installatie-ID bij nog niet gesynchroniseerde OneDrive-opslag. De
gebruikersnaam is niet bedoeld voor beoordeling van prestaties, aanwezigheid
of werkgedrag en moet na de opstartfase opnieuw op noodzakelijkheid worden
beoordeeld; bij verwijdering blijft het al aanwezige installatie-ID
functioneren als het minder identificerende kenmerk. Leden van het RPA
ontwikkel- en beheerteam hebben toegang tot de centrale bestemming; centrale
registraties ouder dan één jaar worden verwijderd.

## 6. Persoonsgegevens en gezondheidsinformatie

| Gegeven | Bron en verwerking | Opslag of overdracht | Beoordeling |
| --- | --- | --- | --- |
| Patiënttelefoonnummer | Onder andere uit een EPD gekopieerd, via het klembord herkend en genormaliseerd | Tijdelijk in geheugen; bij bellen naar de telefonieserver; bij SMS in Edge | Persoonsgegeven en door patiënt-/zorgcontext mogelijk onderdeel van gezondheidsinformatie |
| Hotstringafkorting en vervangtekst | Door gebruiker gekozen of gemaakt; ingevoegd in actieve applicatie | Persoonlijke hotstrings in lokale JSON; gebruikte tekst kan na toestemming in uitgebreide log staan | Kan persoonsgegevens van de medewerker bevatten; klinische tekst is bedoeld als generieke formulering en is zonder patiëntkoppeling geen patiënt- of gezondheidsgegeven |
| Probleembeschrijving | Vrije invoer door gebruiker | In rapportbestand (los, geen ZIP); daarna eventueel per e-mail | Kan onbedoeld patiënt- of gezondheidsinformatie bevatten |
| Ruwe telefonierespons en URL | Interne telefonieserver en aanvraagpad | Alleen in uitgebreide log na toestemming | Kan nummer, servergegevens of gevoelige context bevatten |
| Snelkiesnaam en nummer | Standaard of door gebruiker ingevoerd | Lokale JSON | Persoons- of organisatiedata, afhankelijk van invoer |
| Telemetrie-identificatie en gebruik | DocBot-installatie en Windows-account | Lokale INI en optionele HTTPS-webhook; centrale registraties maximaal één jaar | Medewerker-/installatiegegevens voor capaciteitsplanning en tijdelijk gerichte ondersteuning; geen patiëntinhoud beoogd |

DocBot leest geen patiëntdossier als gegevensbron uit en bewaart geen gestructureerde
diagnoses, uitslagen of medicatielijst als eigen patiëntendatabase. Het staat
wel in de gegevensstroom van zorgdocumentatie en patiëntcommunicatie. Daarom
is het software die persoonsgegevens en potentieel gezondheidsinformatie
verwerkt.

Lokale instellingen en inhoud worden als INI/JSON opgeslagen onder Documents;
logs staan onder LocalAppData (`DocBot.ahk:34-49`). In de applicatiecode is
geen eigen versleuteling of expliciete inrichting van bestands-ACL's
aangetroffen. Bescherming berust mede op Windows, het gebruikersprofiel en de
beheerde werkplekomgeving.

In de huidige inzet staat de map Documents en daarmee de persistente
DocBot-gebruikersopslag in de organisatorische OneDrive-omgeving. De
organisatie bepaalt grotendeels bewaartermijnen, back-ups, beheerderstoegang
en definitieve profielverwijdering. Bij uitdiensttreding wordt de toegang van
de medewerker via het organisatorische accountbeheer geblokkeerd; dat betekent
niet noodzakelijk dat actieve bestanden, herstelkopieën en back-ups direct
worden gewist.

`docs/DATA_PROTECTION.md` legt inmiddels ook vast dat snelkiesinhoud wordt
begrensd door normaal telefoongebruik en organisatiebeleid, dat Funatic van
Enovation de SMS-leverancier is, dat het RPA ontwikkel- en beheerteam toegang
heeft tot telemetrie en dat datalekken via het algemene organisatieproces door
de CISO worden afgehandeld. Exacte AVG-grondslagen, contractketens,
productie-TLS, een aantal concrete verwijdertermijnen en het formele
DPIA-besluit blijven organisatorisch open.

Deze concretere gegevensbeschermingsfeiten veranderen de voorlopige
MDSW-conclusie niet: zij verduidelijken gegevensstromen, ontvangers en
beheersmaatregelen, maar voegen geen patiëntspecifieke medische analyse of
medisch productdoel toe. De eventuele eigen regulatoire kwalificatie van de
Funatic-dienst valt buiten deze beoordeling en wordt niet door de beperkte
nummerinvulling aan DocBot toegerekend.

## 7. Beslisregels en autonome acties

| Regel of actie | Betekenis | Medische betekenis |
| --- | --- | --- |
| Telefoonnummer herkennen en normaliseren | Technische regex- en formatteringsregel | Nee |
| Niets doen, bevestigen, direct bellen of keuze tonen | Instellingsafhankelijke communicatieregel | Nee |
| Hotstringconflicten en pakketprioriteit oplossen | Bepaalt welke vaste tekst aan een gekozen trigger is gekoppeld | Niet op zichzelf; de tekst kan klinisch relevant zijn |
| Uitvoermethode voor hotstring kiezen | Normale tekst, `SendText()` of toetsenmodus | Nee |
| Datum en tijd vervangen | Tekstgeneratie | Nee |
| Telefonieserverevents verwerken | Operationele status en meldingen | Nee |
| Edge-tab activeren en SMS-veld vullen | Communicatieondersteuning | Nee |
| Afsluiten, herladen of updatepad starten | Applicatiebeheer | Nee |
| Nog niet bevestigd bel-/sms-keuzevenster sluiten en vervangen bij een nieuw klembordnummer | Voorkomt dat een verouderd venster later per ongeluk voor het verkeerde nummer wordt bevestigd; er staat nooit meer dan één venster tegelijk open | Nee |
| Klembordnummer direct uit de centrale status wissen na overdracht, afronding of annulering | Begrenst hoe lang een herkend nummer intern zichtbaar blijft | Nee |

DocBot bevat geen regels die patiëntkenmerken omzet in een
diagnose, prognose, behandeladvies, dosering, klinische score of medisch alarm.

## 8. MDR- en MDSW-beoordeling

### 8.1 Toetsingskader

Artikel 2(1) MDR omvat software alleen als medisch hulpmiddel wanneer de
fabrikant die specifiek bestemt voor een medisch doel, zoals diagnose,
preventie, monitoring, voorspelling, prognose of behandeling. Overweging 19
maakt duidelijk dat software voor algemene doeleinden, ook wanneer zij in de
zorg wordt gebruikt, geen medisch hulpmiddel is.

Artikel 2(12) bepaalt dat de intended purpose mede wordt vastgesteld uit
labels, gebruiksinstructies, verkoop- en promotiemateriaal en verklaringen van
de fabrikant. Zie de officiële
[Verordening (EU) 2017/745](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32017R0745).

De niet-bindende Europese leidraad
[MDCG 2019-11 rev.1, juni 2025](https://health.ec.europa.eu/document/download/b45335c5-1679-4c71-a91c-fc7a4d37f12b_en?filename=mdcg_2019_11_en.pdf)
benadrukt onder meer dat niet alle software in een zorgomgeving MDSW is,
algemene communicatie en tekstverwerking gewoonlijk geen eigen medisch doel
hebben, en alleen mogelijke patiëntschade door een fout geen zelfstandig
kwalificatiecriterium is. Patiëntspecifieke analyse voor diagnose of therapie
kan daarentegen wel een MDSW-module vormen.

### 8.2 Toepassing op DocBot

Op basis van de huidige repository en goedgekeurde intended purpose
kwalificeert DocBot **waarschijnlijk niet als MDSW**, omdat de software:

- geen patiëntparameters of dossiergegevens medisch analyseert;
- geen diagnose, prognose of behandelvoorstel berekent;
- geen patiëntspecifieke klinische alarmen genereert;
- geen medicatie of dosering aanbeveelt;
- geen medisch hulpmiddel bestuurt of beïnvloedt;
- voor hotstrings technische tekstverwerkingsregels toepast;
- voor telefonie technische communicatieregels toepast;
- de selectie van klinisch betekenisvolle standaardtekst aan de gebruiker laat.

Een fout kan niettemin patiëntschade veroorzaken, bijvoorbeeld als vaste tekst
in het verkeerde dossier terechtkomt. Dat vraagt om risicobeheersing, maar
verandert de huidige productiviteits- en communicatiefunctie niet automatisch
in een eigen medisch doel.

### 8.3 Herbeoordelingstriggers

Deze kwalificatie moet vóór ontwerp of introductie opnieuw worden beoordeeld
als DocBot:

- patiëntgegevens gebruikt om een diagnose, risicoscore, prognose, triage of
  behandelkeuze voor te stellen;
- automatisch bepaalt welke medische conclusie in een dossier komt;
- medicatie, dosering of controletermijn aanbeveelt;
- patiëntparameters bewaakt of klinische alarmen genereert;
- patiëntcommunicatie zelfstandig gaat verzenden;
- nieuwe categorieën persoonsgegevens verwerkt of logging/telemetrie
  wezenlijk verruimt;
- een medisch hulpmiddel bestuurt of de werking ervan beïnvloedt;
- extern wordt gepresenteerd als software die klinische juistheid,
  patiëntveiligheid of medische besluitvorming waarborgt;
- wordt opgesplitst in modules waarvan één een zelfstandig medisch doel heeft.

Pas nadat een functie als MDSW kwalificeert, is classificatie volgens Annex
VIII, Rule 11 aan de orde. De klasse hangt dan af van het concrete medische
doel en de mogelijke gevolgen van de informatie of beslissingen.

Bij uitsluitend intern gebruik kan artikel 5(5) MDR mogelijk relevant zijn.
De in-house-route vereist onder voorwaarden onder meer een passend
kwaliteitsmanagementsysteem, technische documentatie, naleving van de algemene
veiligheids- en prestatie-eisen en een onderbouwing van de interne behoefte.
Intern gebruik is daarom geen automatische vrijstelling.

## 9. Relevantie van normen

### 9.1 NEN 7510 — nu al hoog relevant

[NEN 7510-1:2024](https://www.nen.nl/nen-7510-1-2024-nl-331311) en
[NEN 7510-2:2024+A1:2026](https://www.nen.nl/nen-7510-2-2024-a1-2026-nl-350012)
zijn gericht op informatiebeveiliging in de zorg. De relevantie hangt niet af
van MDSW-kwalificatie. Omdat DocBot in ziekenhuisprocessen staat en
persoonsgegevens en mogelijk gezondheidsinformatie verwerkt, hoort het binnen
de scope en risicoanalyse van het informatiebeveiligingsmanagementsysteem van
de zorgorganisatie.

Voor DocBot zijn in elk geval relevant:

- scope, eigenaarschap, classificatie en risicoanalyse;
- toegangsbeheer en least privilege;
- vertrouwelijkheid en integriteit van telefoon-, hotstring- en loggegevens;
- beveiliging van netwerkverkeer en lokale opslag;
- veilige ontwikkeling, wijziging, testen en vrijgave;
- logging, monitoring, incident- en kwetsbaarheidsbeheer;
- leveranciers- en third-partybeheer;
- bewaartermijnen, veilige verwijdering, continuïteit en herstel;
- gecontroleerde overdracht van probleemrapporten.

De inmiddels vastgelegde OneDrive-opslag en organisatorische blokkering van
accounts bij uitdiensttreding, beperkte diagnostiekontvanger, Outlook-retentie,
telemetrietoegang en -retentie en CISO-afhandeling van datalekken zijn relevante
organisatorische maatregelen. Zij moeten nog worden gekoppeld aan formeel
beleid, controlebewijs, eigenaarschap en waar nodig de NEN 7510-risicoanalyse.

NEN 7510-conformiteit is een eigenschap van een organisatorisch beheersysteem,
niet van alleen een broncodebestand of losse applicatie.

### 9.2 IEC 62304 — voorwaardelijk

[IEC 62304:2006+A1:2015](https://webstore.iec.ch/en/publication/22794)
beschrijft levenscyclusprocessen voor medical-device-software. De norm wordt
rechtstreeks relevant wanneer DocBot zelf MDSW wordt of onderdeel van een
medisch hulpmiddel is.

Dan zijn onder meer nodig: softwareveiligheidsclassificatie; ontwikkel- en
onderhoudsplannen; requirements en architectuur; traceerbaarheid van eis naar
ontwerp, risico en verificatie; unit-, integratie- en systeemtesten;
configuratie-, release- en wijzigingsbeheer; software-risicomanagement; en
formele probleemafhandeling.

De huidige repository vormt daarvoor nog geen volledig bewijs. Er is geen
conventionele geautomatiseerde testsuite. `docs/ARCHITECTURE.md:480-493`
beschrijft broninspectie en handmatige validatie op Windows en het interne
netwerk; gerichte tests en technische privacymaatregelen staan nog open in
`docs/TODO.md`.

Wanneer DocBot geen MDSW is, is IEC 62304 niet automatisch de toepasselijke
productlevenscyclusnorm. De werkwijze kan wel vrijwillig worden gebruikt om de
kwaliteit en patiëntveiligheid te versterken.

### 9.3 ISO 14971 — conditioneel en als goede praktijk relevant

[ISO 14971:2019](https://www.iso.org/standard/72704.html) beschrijft
risicomanagement voor medische hulpmiddelen over de levenscyclus. Bij MDSW is
deze norm rechtstreeks relevant. Zonder MDSW is een vergelijkbare systematische
risicoanalyse nog steeds verstandig vanwege voorzienbare patiëntveiligheids-
en informatiebeveiligingsrisico's.

Voorbeelden zijn invoer in het verkeerde patiëntdossier, een onjuiste medische
verklaring, bellen van een verkeerd nummer, onbevoegde ontvangst van een
uitgebreide log, invullen van de verkeerde Edge-tab, pakketfouten en
onverwachte onbeschikbaarheid door update- of signaalfunctionaliteit.

Er zijn beheersmaatregelen aanwezig, zoals nummernormalisatie,
bevestigingsmodi, handmatige SMS-verzending, standaardlogredactie, expliciete
toestemming voor uitgebreide logging, verwijdering van tijdelijke logs en
atomische JSON-writes. De intended purpose legt bovendien expliciet vast dat
de gebruiker tekst, nummer, patiënt-/dossiercontext en verzending controleert.
Er is geen formeel risicodossier aangetroffen dat
gevaren, oorzaken, beheersmaatregelen, verificatie en restrisico's traceerbaar
verbindt.

### 9.4 ISO 13485 — bij een medische-hulpmiddelrol of bewuste QMS-keuze

[ISO 13485:2016](https://www.iso.org/standard/59752.html) is een
kwaliteitsmanagementnorm voor organisaties die medische hulpmiddelen
ontwerpen, produceren of onderhouden. Zij is niet alleen door gebruik in een
ziekenhuis automatisch van toepassing op DocBot.

De norm wordt relevant als DocBot als medisch hulpmiddel wordt aangeboden, de
ontwikkelende organisatie als fabrikant optreedt, een in-house-medical-device-
route wordt gebruikt of de organisatie vrijwillig een vergelijkbaar
ontwerpbeheersysteem verlangt. Dan zijn onder meer ontwerpbeheersing,
document- en recordcontrole, leveranciersbeheer, verificatie en validatie,
wijzigingsbeheer, klachten, CAPA, vrijgave en post-productiefeedback relevant.

De huidige branch-, versie- en PR-regels zijn nuttige technische controles,
maar vormen op zichzelf geen ISO 13485-kwaliteitsmanagementsysteem.

## 10. Positieve beheersmaatregelen

- De intended purpose is als intern productbesluit goedgekeurd en beschrijft
  gebruikers, omgeving, invoer, uitvoer, autonome acties, beperkingen en
  uitgesloten medische toepassingen.
- Alle normale belacties lopen door één centraal belpad.
- Bellen wordt geblokkeerd zolang geen toestel gekoppeld is, behalve voor het
  koppelgesprek.
- Er bestaan bevestigings- en keuzevarianten naast direct bellen.
- DocBot verstuurt een SMS niet zelfstandig.
- Standaardlogs worden centraal geredigeerd.
- Ongeredigeerde logging vereist expliciete toestemming en is tijdelijk.
- Persoonlijke JSON-opslag gebruikt backup, tijdelijk bestand en validatie.
- Gebruikersprofielen zijn per releasekanaal gescheiden.
- Persistente gebruikersgegevens staan in de huidige inzet in de
  organisatorische OneDrive-omgeving; accounttoegang wordt bij
  uitdiensttreding geblokkeerd.
- Probleemrapporten worden door de gebruiker verzonden naar de enige
  ontwikkelaar; de speciale Outlook-map verwijdert berichten ouder dan zeven
  dagen automatisch.
- Telemetrie is beperkt tot de beschreven payload, optioneel geconfigureerd
  en vereist HTTPS; toegang is beperkt tot het RPA ontwikkel- en beheerteam en
  centrale registraties ouder dan één jaar worden verwijderd.
- Datalekken vallen onder het algemene incidentproces van de organisatie en
  worden door de CISO afgehandeld.
- De buildhelper verifieert na vervanging de bytes van de executable.

Deze maatregelen verminderen risico's, maar zijn geen zelfstandig bewijs van
conformiteit met een norm of de MDR.

## 11. Belangrijkste hiaten

1. Er is geen formele MDR-kwalificatie buiten deze voorlopige analyse.
2. Er is geen traceerbaar informatiebeveiligings- en
   patiëntveiligheidsrisicodossier aangetroffen.
3. Klinische pakketinhoud heeft in de repository geen zichtbare klinische
   eigenaar, bron, vierogenbeoordeling of formele inhoudelijke vrijgave.
4. Tekst wordt naar de actieve applicatie gestuurd zonder aantoonbare
   patiënt-, applicatie- of veldcontrole.
5. Direct bellen kan na klemborddetectie zonder nieuwe bevestiging plaatsvinden.
6. De voorbeeldconfiguratie gebruikt HTTPS voor telefonie en SMS, maar
   `ValidateLocalConfiguration()` controleert voor deze URL's alleen of een
   waarde is ingevuld. Een lokale `http://`-configuratie wordt dus nog niet
   technisch geweigerd en de feitelijke productiebeveiliging is niet uit de
   repository vast te stellen.
7. Lokale INI/JSON/logbestanden hebben geen applicatie-eigen versleuteling of
   zichtbare ACL-inrichting; de feitelijke bescherming berust op Windows,
   OneDrive en organisatorisch werkplekbeheer en moet aantoonbaar worden
   gekoppeld aan beleid en controles.
8. Voor centrale update-/signaalopdrachten is geen cryptografische
   authenticatie in de clientcode aangetroffen.
9. Er ontbreekt een geautomatiseerde regressie-, integratie- en
   veiligheidstestsuite.
10. Definitieve AVG-grondslagen, formele rollen, contract-/verwerkersketens,
    productiehosting en -TLS, enkele concrete back-up-/verwijdertermijnen en
    het DPIA-besluit zijn nog niet organisatorisch vastgesteld of als bewijs
    aan de repository gekoppeld.
11. De lokale standaardlog verwijdert nog niet automatisch regels ouder dan
    zeven dagen en de tijdelijke probleemrapportmap wordt na overdracht of
    annulering nog niet automatisch opgeruimd.
12. De Windows-gebruikersnaam in telemetrie heeft een tijdelijk supportdoel
    tijdens de opstartfase, maar er is nog geen objectief eindcriterium of
    vastgelegde herbeoordelingsdatum voor verwijdering vastgesteld. Het
    installatie-ID fungeert al als het minder identificerende alternatief in
    de payload; er is dus geen nieuw pseudonimiseringsmechanisme nodig, enkel
    een besluit over het moment van verwijderen van de gebruikersnaam.
13. De gebruikersinstructie die patiëntidentificerende en patiëntspecifieke
    inhoud in persoonlijke hotstrings uitsluit, moet nog worden opgesteld en
    beheerd.

## 12. Aanbevolen vervolgacties

1. Beheer de vastgelegde intended purpose consistent in de README,
   gebruikersinterface, projectdocumentatie, distributie en externe claims.
2. Laat de MDR-kwalificatie beoordelen door de verantwoordelijke voor medische
   hulpmiddelen of een daarvoor gekwalificeerde specialist.
3. Neem DocBot expliciet op in de NEN 7510-scope, gegevensclassificatie en
   risicoanalyse van de zorgorganisatie.
4. Rond de resterende organisatorische onderdelen in
   `docs/DATA_PROTECTION.md` af: laat met name rollen en AVG-grondslagen,
   contractketens, productiehosting/TLS, concrete resttermijnen,
   autorisatie-eigenaarschap en bezwaar-/inzageprocessen goedkeuren en laat de
   verwerkingsverantwoordelijke en FG het DPIA-besluit vastleggen.
5. Maak een traceerbare patiëntveiligheids- en informatiebeveiligingsanalyse,
   ook zolang DocBot geen MDSW is.
6. Breng klinische standaardteksten onder inhoudelijk eigenaarschap,
   vierogencontrole, versiebeheer en regressietests.
7. Onderzoek doelapplicatie-/venstercontrole, extra bevestiging bij risicovolle
   acties en waar mogelijk een controle van de juiste patiëntcontext.
8. Implementeer de zeven-dagenverwijdering voor lokale standaardlogregels en
   ruim tijdelijke probleemrapportmappen veilig op na overdracht of
   annulering.
9. Stel de gebruikersinstructie voor veilige, niet-patiëntspecifieke
   hotstringinhoud op en wijs een eigenaar voor klinische pakketinhoud aan.
10. Definieer het einde van de telemetrie-opstartfase en herbeoordeel dan de
   noodzaak van de Windows-gebruikersnaam, met het oog op verwijdering uit de
   payload — het installatie-ID is al aanwezig als minder identificerend
   alternatief, dus hoeft niet apart te worden ontwikkeld.
11. Bouw requirements, traceerbaarheid, automatische tests,
   verificatieresultaten en gecontroleerde release-evidence op.
12. Herbeoordeel dit document bij iedere trigger uit paragraaf 8.3 en minstens
   bij iedere voorgenomen hoofdrelease.

## 13. Beheer van deze beoordeling

Bij een update moeten minimaal worden vastgelegd:

- datum, onderzochte branch, commit en `AppVersion`;
- wijziging in intended purpose of externe claims;
- nieuwe invoer, gegevenscategorieën, beslisregels en autonome acties;
- gewijzigde integraties of medische pakketinhoud;
- effect op MDSW-kwalificatie, Rule 11 en relevante normen;
- naam of rol van de inhoudelijk beoordelaar en eventuele formele goedkeuring.

Een wijziging aan klinische beslislogica, patiëntspecifieke analyse,
medicatie- of behandeladvies, klinische alarmering of aansturing van een
medisch hulpmiddel mag niet alleen als gewone feature worden behandeld. Vóór
implementatie is een nieuwe kwalificatie- en risicoanalyse nodig.
