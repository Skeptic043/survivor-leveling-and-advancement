# Survivor Leveling & Advancement [B42]

Guadagna punti sviluppando le abilità e spendili in quelle che preferisci. SLA aggiunge il livello del sopravvissuto e i punti avanzamento al normale pannello Abilità, mantenendo la progressione naturale. Vuoi che parte dei progressi sopravviva alla tua prossima pessima decisione? L'eredità dei livelli, facoltativa, permette al prossimo personaggio di conservare una percentuale del tuo livello del sopravvissuto, con nuovi punti da spendere.

Supporta giocatore singolo, multigiocatore, schermo condiviso e controller. Nessuna dipendenza obbligatoria.

## Come funziona l'avanzamento

Gli XP ottenuti nelle abilità supportate aumentano anche il livello del sopravvissuto. Ogni livello assegna un punto avanzamento, o AP. Spendi AP con i pulsanti **+** accanto alle abilità. Per impostazione predefinita puoi occupare tre slot di avanzamento contemporaneamente. Allenare un'abilità avanzata libera i suoi slot quando recuperi gli XP saltati. Questi XP contribuiscono anche al livello successivo dell'abilità.

L'ultimo avanzamento fino al massimo effettivo dell'abilità, normalmente dal livello 9 al 10, equivale a padroneggiarla. Costa 2 AP e richiede 2 slot di avanzamento liberi, poi libera tutti gli slot attivi di quell'abilità. Se il limite Globale o Per abilità è 1, basta 1 slot libero, ma il costo rimane 2 AP. La modalità Libera non richiede slot e mantiene il costo di 2 AP. Un'abilità al massimo effettivo non genera altri XP del sopravvissuto.

## Conserva parte dei progressi dopo la morte

Attiva l'eredità del livello del sopravvissuto e scegli quanto passa al prossimo personaggio nello stesso mondo. Per esempio, morendo al livello del sopravvissuto 20 con eredità al 50%, il prossimo personaggio riceve livello del sopravvissuto 10 e 10 AP. I vecchi livelli delle abilità non vengono copiati, quindi puoi scegliere dove investire i punti ereditati. L'eredità è facoltativa e disattivata per impostazione predefinita.

## Impostazioni

- **Globale:** Tutte le abilità condividono un insieme configurabile di slot di avanzamento, con un limite predefinito di 3 slot attivi totali.
- **Per abilità:** Ogni abilità ha un limite configurabile, con un valore predefinito per le abilità personalizzate compatibili e modifiche individuali facoltative per quelle del gioco base.
- **Libera:** Rimuove i limiti degli slot e le restrizioni di recupero degli XP saltati.
- Regola la velocità degli XP del sopravvissuto senza cambiare gli XP delle abilità. Scegli se contribuiscono forma fisica, forza, singole abilità del gioco base e abilità personalizzate compatibili.
- Nelle opzioni mod puoi attivare indicatori di avanzamento a maggiore contrasto o la percentuale di XP del sopravvissuto del giocatore 1 sull'orologio digitale.
- Supporta tutte le lingue standard nelle impostazioni linguistiche di Project Zomboid. Tutte le traduzioni sono state realizzate interamente con IA. Segnala eventuali testi errati o poco chiari.

**Nota:** Cambiare modalità non azzera i progressi registrati. Gli XP naturali delle abilità ottenuti in modalità Libera continuano a ridurre il recupero blu conservato. Tornando a Globale o Per abilità, viene ripristinata solo la parte ancora da recuperare.

## Aggiungere o rimuovere SLA

Puoi aggiungere SLA ai salvataggi esistenti o rimuoverlo. Le abilità vengono conservate e i progressi precedenti non assegnano livelli del sopravvissuto retroattivi. Disattivarlo nasconde l'interfaccia ma mantiene i livelli delle abilità ottenuti con AP. Riattivarlo ripristina lo stato di SLA e tiene conto della progressione supportata ottenuta durante la sua assenza. Come per qualsiasi modifica alla lista dei mod, consiglio vivamente un backup dei mondi in corso a cui tieni.

## Server dedicati e hosting

Gli amministratori possono assegnare XP del sopravvissuto o livelli interi a profili esistenti online e offline. Le assegnazioni offline hanno effetto immediato. Cancella avanzamenti libera gli slot senza rimborsare AP né modificare gli XP delle abilità. Per i personaggi offline, la cancellazione resta in attesa ed è annullabile fino alla riconnessione. Modificare un livello nelle statistiche del giocatore cancella la contabilità di quell'abilità.

SLA usa i normali salvataggi di Project Zomboid. Sui server ospitati e dedicati, attiva SaveWorldEveryMinutes e arresta il server normalmente.

## Compatibilità

- **Incompatibile: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**
- **Attualmente non supportati: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) e [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. Questi mod sostituiscono direttamente regole di progressione da cui SLA dipende.
- **Dipende dall'ordine di caricamento: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Carica SLA dopo Detailed Skill Tooltips per aggiungere il testo di recupero blu di SLA alle descrizioni estese di DST. Se SLA viene caricato prima, viene sostituito solo quel testo. La progressione del livello del sopravvissuto e le descrizioni dei pulsanti + continuano a funzionare.
- **Testati insieme: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939) e [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. Questa combinazione ha funzionato senza problemi nei test, ma non è possibile garantire la compatibilità con ogni mod di interfaccia o abilità personalizzate.
- I mod che sostituiscono gestione degli XP, massimi o curve delle abilità, pannello Abilità, menu del giocatore o orologio digitale possono causare conflitti. SLA disattiva l'integrazione interessata se i suoi collegamenti necessari vengono sostituiti. Le abilità personalizzate compatibili richiedono una curva XP utilizzabile ed eventi XP supportati. Impostazioni dirette delle abilità o progressioni senza tali eventi non generano XP del sopravvissuto.

## Uso dell'IA

Tutto il codice del progetto è stato scritto con IA. Il concetto originale, la direzione del design, i test, la ricerca dei problemi e le decisioni di pubblicazione sono miei. Ho dedicato molte ore a testare personalmente SLA e risolvere problemi per assicurarmi che funzioni come previsto. Se preferisci non usare mod sviluppati con l'aiuto dell'IA, capisco e rispetto la tua scelta.

## Sostegno

- Le donazioni su [Ko-fi](https://ko-fi.com/skeptic043) sono facoltative. Nessuna funzionalità del mod richiede un pagamento.

## Informazioni sul mod

- Sviluppato/testato sulla versione: 42.20.4
- Dipendenze obbligatorie: Nessuna
- Licenza: MIT
- [Codice sorgente e segnalazione problemi](https://github.com/Skeptic043/survivor-leveling-and-advancement)
