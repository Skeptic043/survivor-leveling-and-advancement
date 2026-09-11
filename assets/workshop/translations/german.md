# Survivor Leveling & Advancement [B42]

Steigere Fertigkeiten, verdiene Punkte und gib sie für Fertigkeiten deiner Wahl aus. SLA ergänzt das Fertigkeitenfenster um ein Überlebendenlevel und Aufstiegspunkte und erhält die natürliche Entwicklung. Mit optionaler Levelvererbung erhält dein nächster Charakter einen Prozentsatz deines Überlebendenlevels und neue Punkte.

Unterstützt Einzelspieler, Mehrspieler, geteilten Bildschirm und Controller. Keine erforderlichen Abhängigkeiten.

## So funktioniert der Aufstieg

XP aus unterstützten Fertigkeiten erhöhen auch dein Überlebendenlevel. Jedes Level gibt dir einen Aufstiegspunkt, kurz AP. Gib AP über die **+**-Schaltflächen neben deinen Fertigkeiten aus. Standardmäßig können drei Aufstiegsplätze gleichzeitig belegt sein. Wenn du eine gesteigerte Fertigkeit übst und die übersprungenen XP nachholst, werden ihre Plätze frei. Diese XP zählen auch für das nächste Fertigkeitslevel.

Der letzte Aufstieg bis zum tatsächlichen Maximum einer Fertigkeit, normalerweise von Level 9 auf 10, gilt als Meisterung. Er kostet 2 AP und benötigt 2 freie Aufstiegsplätze. Danach werden alle aktiven Plätze dieser Fertigkeit freigegeben. Ist das globale oder individuelle Platzlimit auf 1 gesetzt, wird nur 1 freier Platz benötigt. Die Kosten bleiben bei 2 AP. Im freien Modus werden keine Plätze benötigt, die Kosten betragen weiterhin 2 AP. Eine Fertigkeit auf ihrem tatsächlichen Maximum erzeugt keine zusätzlichen Überlebenden-XP.

## Behalte Fortschritt nach dem Tod

Aktiviere die Vererbung des Überlebendenlevels und wähle, wie viel an deinen nächsten Charakter in derselben Welt übergeht. Stirbst du zum Beispiel mit Überlebendenlevel 20 und 50% Vererbung, erhält dein nächster Charakter Überlebendenlevel 10 und 10 AP zum Verteilen. Die alten Fertigkeitslevel werden nicht kopiert. Du entscheidest selbst, wohin die geerbten Punkte gehen. Die Vererbung ist optional und standardmäßig ausgeschaltet.

## Einstellungen

- **Global:** Alle Fertigkeiten teilen sich einen einstellbaren Vorrat an Aufstiegsplätzen. Das Standardlimit beträgt insgesamt 3 aktive Plätze.
- **Pro Fertigkeit:** Jede Fertigkeit erhält ein eigenes einstellbares Limit. Es gibt einen Standardwert für kompatible zusätzliche Fertigkeiten und optionale Einzelwerte für die Fertigkeiten des Grundspiels.
- **Frei:** Entfernt die Limits für Aufstiegsplätze und die Einschränkungen beim Nachholen von XP.
- Passe die Geschwindigkeit der Überlebenden-XP an, ohne die Fertigkeits-XP zu ändern. Wähle, ob Fitness, Stärke, einzelne Fertigkeiten des Grundspiels und kompatible zusätzliche Fertigkeiten beitragen.
- In den Modoptionen kannst du kontrastreichere Aufstiegsmarkierungen oder den Überlebenden-XP-Prozentwert von Spieler 1 auf der Digitaluhr einschalten.
- Unterstützt alle regulären Sprachen in den Spracheinstellungen von Project Zomboid. Alle Übersetzungen wurden vollständig mit KI erstellt. Bitte melde falsche oder unverständliche Texte, wenn dir welche auffallen.

**Hinweis:** Ein Moduswechsel setzt den erfassten Fortschritt nicht zurück. Natürlich verdiente Fertigkeits-XP zählen im freien Modus weiterhin zum gespeicherten blauen Nachholfortschritt. Beim Wechsel zurück zu Global oder Pro Fertigkeit wird nur der noch offene Teil wiederhergestellt.

## SLA hinzufügen oder entfernen

SLA kann zu bestehenden Spielständen hinzugefügt und daraus entfernt werden. Vorhandene Fertigkeiten bleiben erhalten. Vergangener Fortschritt gibt keine rückwirkenden Überlebendenlevel. Das Deaktivieren von SLA blendet die Oberfläche aus, lässt mit AP erworbene Fertigkeitslevel aber bestehen. Beim erneuten Aktivieren wird der SLA-Zustand wiederhergestellt und unterstützter Fortschritt aus der Zwischenzeit berücksichtigt. Wie bei jeder Änderung der Modliste empfehle ich dringend, wichtige Welten vorher zu sichern.

## Dedizierte Server und Hosting

Admins können bestehenden Online- und Offline-Profilen Überlebenden-XP oder ganze Level geben. Offline-Vergaben wirken sofort. Fortschritte löschen gibt Plätze frei, ohne AP zu erstatten oder Fertigkeits-XP zu ändern. Bei Offline-Charakteren bleibt die Aktion bis zur Rückkehr ausstehend und abbrechbar. Eine Leveländerung über die Spielerstatistik löscht die Fortschrittsabrechnung dieser Fertigkeit.

SLA verwendet die normalen Speicherungen von Project Zomboid. Aktiviere auf dedizierten und gehosteten Servern SaveWorldEveryMinutes und beende den Server regulär.

## Kompatibilität

- **Inkompatibel: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**
- **Derzeit nicht unterstützt: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) und [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. Diese Mods ersetzen direkt Entwicklungsregeln, auf die SLA angewiesen ist.
- **Von der Ladereihenfolge abhängig: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Lade SLA nach Detailed Skill Tooltips, um SLAs blauen Nachholtext an die erweiterten Fertigkeitshinweise von DST anzuhängen. Wird SLA zuerst geladen, wird nur dieser Text ersetzt. Überlebendenfortschritt und die Hinweise der +-Schaltflächen funktionieren weiterhin.
- **Zusammen getestet: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939) und [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. Diese Kombination funktionierte in den Tests problemlos. Kompatibilität mit jeder Oberflächen- oder Fertigkeitsmod lässt sich jedoch nicht garantieren.
- Mods, die XP-Verarbeitung, Fertigkeitsgrenzen oder XP-Kurven, das Fertigkeitenfenster, Spielermenüs oder die Digitaluhr ersetzen, können Konflikte verursachen. Werden benötigte Einbindungen ersetzt, deaktiviert SLA die betroffene Integration. Angepasste Fertigkeiten brauchen eine nutzbare XP-Kurve und unterstützte XP-Ereignisse. Direkte Fertigkeitsänderungen oder Entwicklung ohne solche Ereignisse erzeugen keine Überlebenden-XP.

## KI-Nutzung

Der gesamte Code wurde mit KI geschrieben. Konzept, Design, Tests, Fehlersuche und Veröffentlichungsentscheidungen stammen von mir. Ich habe SLA viele Stunden selbst getestet und Probleme behoben. Wenn du keine mit KI entwickelten Mods nutzen möchtest, verstehe und respektiere ich das.

## Unterstützung

- Spenden über [Ko-fi](https://ko-fi.com/skeptic043) sind freiwillig. Keine Modfunktion ist hinter einer Bezahlschranke gesperrt.

## Modinformationen

- Entwickelt/getestet auf Version: 42.20.4
- Erforderliche Abhängigkeiten: Keine
- Lizenz: MIT
- [Quellcode und Fehlermeldungen](https://github.com/Skeptic043/survivor-leveling-and-advancement)
