# Survivor Leveling & Advancement [B42]

Verdien punten door je vaardigheden te ontwikkelen en besteed ze aan vaardigheden naar keuze. SLA voegt een overlevingsniveau en verbeteringspunten toe aan het gewone vaardighedenpaneel, met behoud van natuurlijke vaardigheidsgroei. Wil je dat een deel van je voortgang je volgende slechte beslissing overleeft? Met optionele niveauovererving behoudt je volgende personage een percentage van je overlevingsniveau en krijgt het nieuwe punten om te besteden.

Ondersteunt singleplayer, multiplayer, gesplitst scherm en controllers. Geen verplichte afhankelijkheden.

## Zo werken verbeteringen

XP uit ondersteunde vaardigheden verhoogt ook je overlevingsniveau. Elk overlevingsniveau geeft één verbeteringspunt, of AP. Besteed AP met de **+**-knoppen naast je vaardigheden. Standaard kun je drie verbeteringsplaatsen tegelijk bezetten. Oefen een verbeterde vaardigheid om de overgeslagen XP in te halen en haar plaatsen vrij te maken. Die XP telt ook mee voor het volgende vaardigheidsniveau.

De laatste verbetering tot het effectieve maximum van een vaardigheid, meestal van niveau 9 naar 10, geldt als volledige beheersing. Dit kost 2 AP en vereist 2 vrije verbeteringsplaatsen. Daarna worden alle actieve plaatsen van die vaardigheid vrijgemaakt. Staat de limiet voor Gedeeld of Per vaardigheid op 1, dan is slechts 1 vrije plaats nodig, maar blijft de prijs 2 AP. Vrij vereist geen plaatsen en kost nog steeds 2 AP. Een vaardigheid op haar effectieve maximum levert geen extra overlevings-XP op.

## Behoud voortgang na de dood

Schakel overerving van het overlevingsniveau in en bepaal hoeveel je volgende personage in dezelfde wereld krijgt. Sterf je bijvoorbeeld op overlevingsniveau 20 met 50% overerving, dan krijgt je volgende personage overlevingsniveau 10 en 10 AP. De oude vaardigheidsniveaus worden niet gekopieerd, zodat je zelf kiest waar je de geërfde punten besteedt. Overerving is optioneel en standaard uitgeschakeld.

## Instellingen

- **Gedeeld:** Alle vaardigheden delen één instelbare voorraad verbeteringsplaatsen, standaard met een limiet van 3 actieve plaatsen in totaal.
- **Per vaardigheid:** Elke vaardigheid heeft een eigen instelbare limiet, met een standaardwaarde voor compatibele modvaardigheden en optionele afwijkingen voor basisvaardigheden.
- **Vrij:** Verwijdert plaatslimieten en beperkingen voor het inhalen van XP.
- Pas de snelheid van overlevings-XP aan zonder vaardigheids-XP te wijzigen. Kies of conditie, kracht, afzonderlijke basisvaardigheden en compatibele modvaardigheden meetellen.
- Schakel in de modopties verbeteringsmarkeringen met meer contrast in, of toon het overlevings-XP-percentage van speler 1 op het digitale horloge.
- Ondersteunt alle standaardtalen in de taalinstellingen van Project Zomboid. Alle vertalingen zijn volledig door AI gemaakt. Meld onjuiste of onduidelijke tekst gerust.

**Let op:** Een andere modus kiezen wist de bijgehouden voortgang niet. Natuurlijke vaardigheids-XP die je in Vrij verdient, vermindert nog steeds het bewaarde blauwe inhaalwerk. Terugschakelen naar Gedeeld of Per vaardigheid herstelt alleen wat nog over is.

## SLA toevoegen of verwijderen

Je kunt SLA aan bestaande saves toevoegen of eruit verwijderen. Bestaande vaardigheden blijven behouden en eerdere voortgang geeft geen overlevingsniveaus met terugwerkende kracht. Uitschakelen verbergt de interface, maar behoudt vaardigheidsniveaus die met AP zijn verkregen. Opnieuw inschakelen herstelt de SLA-status en verwerkt ondersteunde voortgang uit de periode zonder SLA. Zoals bij elke wijziging van je modlijst raad ik sterk aan een back-up te maken van lopende werelden die je wilt behouden.

## Dedicated servers en hosting

Beheerders kunnen overlevings-XP of hele niveaus toekennen aan bestaande online- en offlineprofielen. Offline toekenningen gelden direct. Verbeteringen wissen maakt plaatsen vrij zonder AP terug te geven of vaardigheids-XP te veranderen. Bij offline personages wacht deze opdracht tot ze weer verbinden en kan hij tot dan worden geannuleerd. Een vaardigheidsniveau aanpassen via spelerstatistieken wist de administratie van die vaardigheid.

SLA gebruikt de normale saves van Project Zomboid. Schakel SaveWorldEveryMinutes in op gehoste en dedicated servers en sluit de server normaal af.

## Compatibiliteit

- **Niet compatibel: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**
- **Momenteel niet ondersteund: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) en [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. Deze mods vervangen rechtstreeks groeiregels waarvan SLA afhankelijk is.
- **Afhankelijk van laadvolgorde: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Laad SLA na Detailed Skill Tooltips om SLA's blauwe inhaaltekst aan de uitgebreide vaardigheidstooltips van DST toe te voegen. Laadt SLA eerst, dan wordt alleen die tekst vervangen. De groei van het overlevingsniveau en de tooltips van de +knoppen blijven werken.
- **Samen getest: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939) en [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. Deze combinatie werkte probleemloos tijdens tests. Compatibiliteit met elke interface- of vaardigheidsmod is echter niet gegarandeerd.
- Mods die de verwerking van vaardigheids-XP, maxima of curves, het vaardighedenpaneel, spelermenu's of digitale horloges vervangen, kunnen conflicten veroorzaken. SLA schakelt de betrokken integratie uit als noodzakelijke koppelingen worden vervangen. Compatibele modvaardigheden vereisen een bruikbare XP-curve en ondersteunde XP-gebeurtenissen. Rechtstreekse vaardigheidswijzigingen of groei zonder zulke gebeurtenissen leveren geen overlevings-XP op.

## Gebruik van AI

Alle code in dit project is met AI geschreven. Het oorspronkelijke concept, de ontwerprichting, het testen, de foutopsporing en de beslissingen over uitgaven zijn van mij. Ik heb SLA vele uren zelf getest en problemen opgelost om te zorgen dat het werkt zoals bedoeld. Gebruik je liever geen mods die met AI-hulp zijn ontwikkeld, dan begrijp en respecteer ik die keuze.

## Steun

- Donaties via [Ko-fi](https://ko-fi.com/skeptic043) zijn vrijwillig. Geen enkele modfunctie vereist betaling.

## Modinformatie

- Ontwikkeld/getest op versie: 42.20.4
- Verplichte afhankelijkheden: Geen
- Licentie: MIT
- [Broncode en problemen melden](https://github.com/Skeptic043/survivor-leveling-and-advancement)
