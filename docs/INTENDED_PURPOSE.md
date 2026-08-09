# DocBot — Intended purpose

_Status: goedgekeurd intern productbesluit._

_Vaststellingsdatum: 2026-08-09._

_Van toepassing op: DocBot `2.2-rc.3` en opvolgende versies totdat een
herbeoordeling tot een gewijzigde verklaring leidt._

## 1. Intended-purposeverklaring

DocBot is productiviteitssoftware voor medewerkers in een beheerde
bedrijfsomgeving. De software ondersteunt tekstinvoer door ingestelde
afkortingen (hotstrings) te vervangen en ondersteunt communicatie door
telefoonnummers op het Windows-klembord technisch te herkennen en te
normaliseren. Afhankelijk van de gebruikersinstelling kan DocBot een herkend
nummer doorgeven aan een geconfigureerde interne telefoniedienst of invullen
in een geconfigureerde SMS-webapplicatie. DocBot verzendt zelf geen
SMS-berichten.

DocBot is ontstaan vanuit behoeften in een ziekenhuisomgeving en wordt daar
ook toegepast. De software heeft geen beoogd medisch doel: zij verricht geen
medische analyse van patiëntgegevens, trekt geen klinische conclusies en geeft
geen diagnose-, behandel-, doserings- of monitoringsadvies.

## 2. Beoogde gebruikers

- Medewerkers die op een beheerde Windows-werkplek werken.
- Gebruikers die zelf verantwoordelijk blijven voor de gekozen hotstring, het
  telefoonnummer, de patiënt- of dossiercontext en het verzenden van een SMS.
- DocBot is niet bedoeld als zelfstandig patiëntproduct of voor zelfstandig
  gebruik door patiënten.

## 3. Gebruiksomgeving

- Een beheerde bedrijfsomgeving op Windows.
- De huidige toepassing vindt plaats in een ziekenhuisomgeving.
- Telefonie vereist in de huidige configuratie toegang tot het interne
  ziekenhuisnetwerk.
- Nummerherkenning is ingericht voor Nederlandse telefoonnummers en interne
  viercijferige nummers.

## 4. Invoer

DocBot verwerkt als functionele invoer:

- door de gebruiker geconfigureerde of geselecteerde hotstrings;
- ingeschakelde hotstrings uit meegeleverde pakketten;
- telefoonnummers die op het Windows-klembord worden geplaatst;
- snelkiesnummers en gebruikersinstellingen;
- gebruikerskeuzes zoals bevestigen, bellen of SMS kiezen;
- vrije tekst die de gebruiker aan een probleemrapport toevoegt.

In de huidige ziekenhuisomgeving kunnen telefoonnummers en probleemrapporten
persoonsgegevens en potentieel gezondheidsinformatie bevatten.
Hotstringinhoud kan persoonsgegevens van de medewerker bevatten, zoals een
naam, telefoonnummer of e-mailadres. Klinische hotstringtekst is bedoeld als
generieke, herbruikbare formulering en is niet aan één patiënt gebonden. De
afzonderlijke telemetriemelding in `README.md` bepaalt welke gegevens de
optionele telemetrie wel en niet verzendt.

## 5. Uitvoer en acties

DocBot kan:

- tekst in de actieve applicatie invoegen;
- een telefoonnummer aan een geconfigureerde interne telefoniedienst
  doorgeven;
- een telefoonnummer in een geconfigureerde SMS-webapplicatie invullen;
- statusmeldingen, bevestigingsvensters en gebruikerskeuzes tonen;
- lokale instellingen, hotstrings, pakketkeuzes en snelkiesnummers opslaan;
- optionele telemetrie verzenden zoals beschreven in `README.md`;
- diagnostische logs en, op initiatief van de gebruiker, een probleemrapport
  maken.

DocBot verzendt een SMS-bericht of probleemrapport niet zelfstandig. De
gebruiker controleert en verzendt deze zelf.

## 6. Autonome acties

DocBot voert de volgende technische of instellingsafhankelijke acties uit
zonder voor iedere tussenstap afzonderlijk toestemming te vragen:

- wijzigingen van het Windows-klembord bewaken;
- telefoonnummers technisch herkennen en normaliseren;
- bij de instelling `Direct bellen` een herkend nummer zonder aanvullende
  bevestiging aan de telefoniedienst doorgeven;
- een ingevoerde hotstringtrigger automatisch vervangen;
- afhankelijk van de gekozen SMS-actie een Edge-venster of -tab selecteren en
  daar het telefoonnummer invullen;
- telefonieserverevents verwerken en de gebruikersinterface bijwerken;
- lokaal geconfigureerde telemetrie volgens het beschreven interval
  verzenden;
- op een gericht beheersignaal afsluiten, herladen of een updatepad starten.

Deze acties zijn technisch, administratief of communicatief. DocBot neemt geen
medische beslissing en verzendt geen SMS-bericht zelfstandig.

## 7. Beperkingen en gebruikersverantwoordelijkheid

- DocBot controleert niet of de juiste patiënt, het juiste dossier, de juiste
  applicatie of het juiste invoerveld actief is.
- De gebruiker controleert de tekst en context vóór definitieve vastlegging.
- De gebruiker controleert het telefoonnummer en een eventueel SMS-bericht.
- De gebruiker verzendt het SMS-bericht zelf.
- Herkenning van een telefoonnummer bewijst niet dat het nummer bij de bedoelde
  persoon hoort.
- Meegeleverde medische teksten zijn vaste teksthulpmiddelen en geen klinische
  aanbevelingen. De gebruiker bepaalt of en waar een tekst passend is.
- DocBot garandeert geen klinische juistheid of patiëntveiligheid.
- Telefonie en SMS-integraties zijn afhankelijk van lokaal geconfigureerde
  externe diensten, de bereikbaarheid daarvan en de beheerde werkplekomgeving.
- Hotstringuitvoer gaat naar de applicatie en het veld die op dat moment actief
  zijn.

## 8. Uitgesloten medische toepassingen

DocBot is niet bedoeld voor:

- diagnose, preventie, voorspelling of prognose van ziekte;
- klinische monitoring of alarmering;
- triage of patiëntspecifieke risicoberekening;
- behandelkeuze of behandeladvies;
- medicatie- of doseringsadvies;
- automatisch bepalen welke medische conclusie in een dossier wordt
  vastgelegd;
- aansturing of beïnvloeding van een medisch hulpmiddel;
- zelfstandig verzenden van patiëntcommunicatie;
- het waarborgen van klinische juistheid, medische besluitvorming of
  patiëntveiligheid.

## 9. Goedkeuring en betekenis

| Onderdeel | Vastlegging |
| --- | --- |
| Status | Goedgekeurd |
| Goedgekeurd door | Projecteigenaar DocBot |
| Rol | Productverantwoordelijke |
| Datum | 2026-08-09 |
| Van toepassing op | `2.2-rc.3` en opvolgende versies tot herbeoordeling |
| Repositorybesluit | `docs/DECISIONS.md`, D-039 |

Deze goedkeuring is een intern productbesluit waarmee het beoogde gebruik en
de grenzen van DocBot worden vastgesteld. Zij is geen juridisch advies,
formele MDR-kwalificatie of gecertificeerd conformiteitsoordeel.

## 10. Consistent beheer

Deze verklaring is de primaire repositorybron voor de intended purpose van
DocBot. De README, gebruikersinterface, Help, distributie-informatie,
trainingsmaterialen, externe claims en regulatoire beoordeling moeten hiermee
in overeenstemming blijven.

De feitelijke persoonsgegevensstromen en DPIA-screening worden beheerd in
`docs/DATA_PROTECTION.md` en moeten eveneens met deze verklaring overeenkomen.

Een wijziging van alleen redactie of toelichting die het beoogde gebruik niet
verruimt, kan via het normale wijzigingsproces worden goedgekeurd. Een
inhoudelijke verruiming vereist vooraf herbeoordeling van de kwalificatie,
risico's, gegevensverwerking en toepasselijke normen.

## 11. Herbeoordelingstriggers

Deze verklaring en de kwalificatie in `docs/REGULATORY_ASSESSMENT.md` moeten
minimaal bij iedere voorgenomen hoofdrelease worden gecontroleerd en vóór
ontwerp of introductie opnieuw worden beoordeeld als DocBot:

- patiëntgegevens gebruikt voor diagnose, risicoscore, prognose, triage of
  behandelkeuze;
- klinische scores, waarschuwingen, conclusies of aanbevelingen genereert;
- medicatie, dosering of controletermijnen aanbeveelt;
- automatisch bepaalt welke medische inhoud in een dossier komt;
- patiëntcommunicatie zelfstandig gaat verzenden;
- nieuwe categorieën persoonsgegevens verwerkt of logging/telemetrie
  wezenlijk verruimt;
- een medisch hulpmiddel bestuurt of de werking ervan beïnvloedt;
- extern wordt gepresenteerd als software die klinische juistheid,
  patiëntveiligheid of medische besluitvorming waarborgt;
- wordt opgesplitst in modules waarvan één een zelfstandig medisch doel kan
  hebben.

Bij herbeoordeling worden minimaal datum, versie, wijziging, beoordelaars,
uitkomst en eventuele nieuwe beheersmaatregelen vastgelegd.
