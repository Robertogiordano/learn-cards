# LearnCards

App iOS nativa (iPhone, iOS 17+) per memorizzare vocaboli tedeschi. L'interfaccia è in inglese, e in inglese sono anche le traduzioni, i temi, le categorie, le note sui verbi e i messaggi del coach.

- Fotografi una pagina di esercizi: un modello vision su OpenRouter estrae le parole, ognuna con una emoji per l'associazione visiva e un **tema** (Food, Home, Travel…). Il modello riusa i temi che hai già e ne crea di nuovi solo quando serve.
- Prima di salvare rivedi le parole: puoi correggerle, cambiare tema (anche a più parole insieme) e vedere i duplicati.
- Il vocabolario, raggruppato per tema, cresce nel tempo e resta solo sul telefono (SwiftData, nessun server).
- Ti alleni in tre aree, ciascuna con un calendario di ripasso separato (SM-2), filtrando per i temi che scegli:

| Area | Domanda | Risposta | Esercizi |
|---|---|---|---|
| Traduzione | table 🪑 | Tisch | scelta multipla, scrivi EN → DE, scrivi DE → EN, pronuncia |
| Articolo | Tisch | der Tisch / ein Tisch | scelta multipla (maskulin/feminin/neutral), scrivi, pronuncia |
| Plurale | der Tisch | die Tische | scelta multipla, scrivi, pronuncia |

- **Percorso** (scheda Study), pensato per un vocabolario che cresce:
  - **Continue your path**: una lezione sul tema in focus (quello importato più di recente, oppure il più debole), seguita da un **Bonus** che mescola tutto quello che hai già visto in ogni tema e area.
  - **Mappa dei temi**: per ogni tema una stella per area (Traduzione, Articolo, Plurale), accesa all'80%. Dentro il tema ogni tipo di esercizio (scelta multipla, scrittura, pronuncia…) ha la sua percentuale e quella dell'area è la loro media. Ogni risposta giusta conta, anche negli allenamenti extra: una vale metà parola, due di fila la parola intera, un errore la fa ripartire, più il badge "+N nuove". Nessun tema è bloccato e le parole aggiunte non azzerano i progressi.
  - Ogni parola passa da scelta multipla a scrittura a pronuncia man mano che la impari; un errore la riporta alla scelta multipla.
  - **Free practice** per scegliere a mano area, temi e tipo di esercizio.
  - **Word sets**: un pulsante crea un set casuale di 10, 20 o 30 parole, pescate da tutto il vocabolario preferendo quelle nuove o poco sapute. Il set poi resta fisso e si allena come un tema (aree, esercizi, percentuali, stelle); i set si possono rinominare o eliminare e sono inclusi nel backup.
    Un set si può creare anche nella revisione di un import di **Words** («Also create a word set»): entrano tutte le parole estratte (i doppioni con i loro progressi), con l'icona a pila se ne esclude qualcuna; nel vocabolario si salvano comunque solo le parole selezionate.
  - Ogni sessione (parole, frasi, verbi) prende prima i ripassi in scadenza, poi al massimo 4 novità, poi gli elementi più deboli nell'esercizio scelto, a rotazione: quelli già al 100% in quell'esercizio tornano solo quando non c'è altro. Una risposta sbagliata ritorna qualche domanda dopo, al massimo due volte per sessione.
- **Compound words** (scheda Study → More practice): le parole composte (Küche + Tür → die Küchentür) sono normali parole del vocabolario, nel tema "Compound words", che conoscono le loro parti. Nell'import il modello scompone i sostantivi composti, **risolve gli esercizi di abbinamento** (parola + parola, colonne da collegare) e aggiunge anche le parti come parole; nella revisione ogni parte mostra se è collegata (nel vocabolario o selezionata). Le parti si modificano anche a mano dalla scheda della parola. Giochi, ognuno con la sua percentuale:
  - **Match the pairs**: fino a 5 composte per round, prime parti a sinistra e seconde a destra da collegare;
  - **Complete the word**: «Küche + ___», 4 opzioni;
  - **Build from meaning**: dall'inglese, tocca le parti nell'ordine giusto tra 6–8 tasselli;
  - **Type the compound**: scrivi la parola con l'articolo (viene dall'ultima parte).

  «Automatico» va da abbinare/completare a comporre e scrivere; le composte entrano anche negli esercizi di traduzione, articolo e plurale, nel **Bonus** (un round di abbinamento con le composte più deboli, o due domande singole) e nella **lezione del giorno** (anche quella del coach, con il tipo «compounds»).

  Nella scheda di una parola, la sezione **Parts** suggerisce le parole del vocabolario mentre scrivi (si scelgono da un elenco a tendina) e il pulsante **Suggest parts** fa l'associazione da solo: prima cerca la divisione tra le tue parole (gestendo le lettere di collegamento -s-, -n-, -er-… e radici come Schreib- da schreiben), poi, se non la trova, chiede a OpenRouter.
- **Numeri** (scheda Study), su 4 livelli (0–20, 21–100, 101–1.000, fino a 1.000.000):
  - ascolta e scegli tra 4 opzioni ingannevoli (21 ↔ 12, 13 ↔ 30, ±1, ±10);
  - ascolta e scrivi le cifre (con riascolto lento);
  - leggi le cifre e scrivi il numero a lettere (*siebenundvierzig*; vale anche *hundert*/*einhundert*, *ss* per *ß*);
  - leggi le cifre e pronuncia il numero.

  Ogni esercizio ha la percentuale delle risposte giuste sulle ultime 20, i numeri sbagliati tornano più spesso e 3 domande sui numeri entrano in ogni Bonus.
- **Frasi** (sezione a parte): nella scheda Add scegli **Words | Phrases | Verbs** prima di caricare la foto, così ognuno usa il suo prompt. Per le frasi il modello estrae modi di dire, frasi utili e domande, **risolve gli esercizi a buchi** (es. "Wie heißt die Frage?": dalla risposta ricostruisce la domanda), aggiunge varianti corrette, traduzione inglese, nota per i modi di dire e una categoria (riusando le esistenti). Con **Frasi**, dalla stessa foto e in parallelo vengono estratte anche le **parole** e i **verbi** (i verbi solo nella loro sezione, e coniugati solo se nuovi); le revisioni si aprono una dopo l'altra e ognuna si salva o si annulla per conto suo. Si può disattivare in **Settings → Phrase import**; con **Words** o **Verbs** si estrae solo quel tipo. Le frasi sono centralizzate: niente doppioni, revisione prima del salvataggio, elenco e modifica nella scheda Vocabulary (**Words | Phrases | Verbs**). Esercizi:
  - ricomponi la frase con i tasselli;
  - traduci e scrivi;
  - domanda dalla risposta;
  - completa la parola mancante;
  - dettato (anche lento);
  - pronuncia.

  Ogni esercizio ha la sua percentuale; "Automatico" va dal ricomporre allo scrivere e dire la frase; 2 frasi già viste entrano in ogni Bonus.
- **Verbi** (sezione a parte): in Add scegli **Verbs**. L'estrazione va per gradi: prima il modello legge dalla foto solo gli infiniti, poi l'app scarta quelli già nel vocabolario e chiede la coniugazione (senza foto, quindi pochi token) solo per i verbi nuovi. Il prompt dedicato restituisce ogni verbo con il presente delle 6 persone (separabili con il prefisso in fondo, riflessivi con il pronome), il gruppo (regolari, cambio vocalico, irregolari, modali, separabili, riflessivi) e una nota su cosa fare attenzione. Esercizi:
  - scegli la forma tra 4 (con errori tipici come *fahrst*);
  - scrivi la forma;
  - tabella completa;
  - che persona è (le forme uguali, es. *macht* = er/ihr, valgono tutte);
  - pronuncia "du fährst";
  - giochi di traduzione come per le parole: scegli il verbo tedesco, scrivi EN → DE (con o senza «sich»), scrivi DE → EN, pronuncia l'infinito.

  Percentuale per esercizio e per gruppo (Traduzione / Coniugazione), filtro per gruppo, modalità automatica, 2 verbi già visti in ogni Bonus, elenco e modifica in Vocabulary (**Words | Phrases | Verbs**).
- **Obiettivo giornaliero e lezione del giorno** (in cima alla scheda Study):
  - scegli 5, 10, 15 o 20 minuti al giorno; conta il **tempo attivo** negli esercizi (pause lunghe escluse), con anello di avanzamento, **serie di giorni** (un giorno saltato a settimana è perdonato), **storico** a 7/30 giorni e **promemoria** locale solo nei giorni in cui l'obiettivo non è ancora raggiunto;
  - ogni giorno l'app prepara in locale una **lezione** della durata dell'obiettivo: i tuoi errori recenti (registrati con risposta data e risposta giusta), due temi in focus che ruotano, il ripasso in scadenza, qualche novità e un po' di numeri. Si riprende da dove l'hai lasciata e alla fine chiede "Too easy / Just right / Too hard" per regolare le lezioni successive;
  - **Ask the coach** (su richiesta, OpenRouter): scrivi cosa vuoi oggi ("I have a test on separable verbs tomorrow"); il coach riceve un riassunto dei tuoi progressi ed errori e assembla la lezione **solo con il tuo materiale**, con un breve messaggio sul perché.
- L'icona a forma di occhio in alto a destra di ogni card nasconde o mostra le emoji in tutti gli esercizi; la stessa scelta è in **Settings → Study**.
- La pronuncia usa il riconoscimento vocale Apple in tedesco, on-device.
- Nella scheda **Vocabulary** un solo campo di ricerca cerca insieme parole, frasi e verbi (tedesco, inglese, temi, varianti, forme coniugate; maiuscole, ä/ae/a e ß/ss non contano) e mostra i risultati divisi in **Words**, **Phrases** e **Verbs**.
- Puoi esportare e importare il vocabolario in JSON, con merge.

## Setup

Requisiti: Mac con Xcode 15.3 o superiore e [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen            # genera LearnCards.xcodeproj da project.yml
open LearnCards.xcodeproj
```

In Xcode, apri target LearnCards → Signing & Capabilities e scegli il tuo team (va bene un Apple ID gratuito). Poi collega l'iPhone ed esegui con ⌘R.

> Il file `.xcodeproj` è generato e non è versionato: dopo ogni `git pull` rilancia `xcodegen`. Il team va riselezionato, oppure puoi aggiungere `DEVELOPMENT_TEAM: <TEAM_ID>` in `project.yml`.

Al primo avvio:

1. Crea una API key su <https://openrouter.ai/keys> e caricaci qualche dollaro di credito.
2. In app vai su **Settings → OpenRouter**, incolla la key e premi Save API key. La key finisce nel Portachiavi.
3. Il modello predefinito è `google/gemini-2.5-flash` (circa mezzo centesimo a foto). Puoi cambiarlo con uno dei preset o con un qualsiasi id di openrouter.ai/models che accetti immagini.

## Test

La logica (verifica risposte, SRS, costruzione esercizi, parsing della risposta del modello, backup) sta nel package `Packages/LearnCore`, che dipende solo da Foundation:

```sh
cd Packages/LearnCore
swift test
```

## Struttura

```
project.yml              spec XcodeGen
Packages/LearnCore/      logica pura + test
App/
  LearnCardsApp.swift    entry point e tab
  Model/Word.swift       modello SwiftData
  Services/              OpenRouter, Keychain, speech, TTS, backup, impostazioni
  Views/                 Study, Vocabulary, Add, Settings
```

## Backup

Il vocabolario esiste solo su questo iPhone, quindi conviene fare un backup ogni tanto: **Settings → Export vocabulary** (su File, iCloud Drive, AirDrop...). Il file JSON contiene parole, temi, i calendari di ripasso delle tre aree e le serie di risposte giuste (per area e per tipo di esercizio) che muovono le percentuali del percorso, più frasi, verbi, lo storico degli esercizi sui numeri, il tempo di studio e gli errori recenti, ma non la API key. I backup della prima versione (schema 1) si importano ancora: le parole finiscono nel tema "Misc" (i vecchi temi "Varie" e la categoria "Frasi utili" vengono rinominati in "Misc" e "Useful phrases" al primo avvio).

L'import offre due modalità:

- **Merge**: per ogni parola tiene la versione modificata o ripassata più di recente.
- **Replace everything**: cancella il vocabolario attuale e lo rimpiazza con il backup.

## Icona

`design/AppIcon.svg` è il sorgente dell'icona: una pila di flashcard nei colori della bandiera tedesca con una "Ä". Il PNG 1024×1024 usato da Xcode è in `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`; se modifichi l'SVG, riesportalo a quella dimensione, senza trasparenza (il font è Inter Display Black).
