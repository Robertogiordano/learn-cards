# LearnCards

App iOS nativa (iPhone, iOS 17+) per memorizzare vocaboli tedeschi.

- Fotografi una pagina di esercizi: un modello vision su OpenRouter estrae le parole, ognuna con una emoji per l'associazione visiva e un **tema** (Cibo, Casa, Viaggi…). Il modello riusa i temi che hai già e ne crea di nuovi solo quando serve.
- Prima di salvare rivedi le parole: puoi correggerle, cambiare tema (anche a più parole insieme) e vedere i duplicati.
- Il vocabolario, raggruppato per tema, cresce nel tempo e resta solo sul telefono (SwiftData, nessun server).
- Ti alleni in tre aree, ciascuna con un calendario di ripasso separato (SM-2), filtrando per i temi che scegli:

| Area | Domanda | Risposta | Esercizi |
|---|---|---|---|
| Traduzione | table 🪑 | Tisch | scelta multipla, scrivi EN → DE, scrivi DE → EN, pronuncia |
| Articolo | Tisch | der Tisch / ein Tisch | scelta multipla (maskulin/feminin/neutral), scrivi, pronuncia |
| Plurale | der Tisch | die Tische | scelta multipla, scrivi, pronuncia |

- **Percorso** (scheda Studia), pensato per un vocabolario che cresce:
  - **Continua il percorso**: una lezione sul tema in focus (quello importato più di recente, oppure il più debole), seguita da un **Bonus** che mescola tutto quello che hai già visto in ogni tema e area.
  - **Mappa dei temi**: per ogni tema una stella per area (Traduzione, Articolo, Plurale), accesa all'80%. Dentro il tema ogni tipo di esercizio (scelta multipla, scrittura, pronuncia…) ha la sua percentuale e quella dell'area è la loro media. Ogni risposta giusta conta, anche negli allenamenti extra: una vale metà parola, due di fila la parola intera, un errore la fa ripartire, più il badge "+N nuove". Nessun tema è bloccato e le parole aggiunte non azzerano i progressi.
  - Ogni parola passa da scelta multipla a scrittura a pronuncia man mano che la impari; un errore la riporta alla scelta multipla.
  - **Allenamento libero** per scegliere a mano area, temi e tipo di esercizio.
- **Numeri** (scheda Studia), su 4 livelli (0–20, 21–100, 101–1.000, fino a 1.000.000):
  - ascolta e scegli tra 4 opzioni ingannevoli (21 ↔ 12, 13 ↔ 30, ±1, ±10);
  - ascolta e scrivi le cifre (con riascolto lento);
  - leggi le cifre e scrivi il numero a lettere (*siebenundvierzig*; vale anche *hundert*/*einhundert*, *ss* per *ß*);
  - leggi le cifre e pronuncia il numero.

  Ogni esercizio ha la percentuale delle risposte giuste sulle ultime 20, i numeri sbagliati tornano più spesso e 3 domande sui numeri entrano in ogni Bonus.
- **Frasi** (sezione a parte): nella scheda Aggiungi scegli **Parole | Frasi** prima di caricare la foto, così ognuno usa il suo prompt. Per le frasi il modello estrae modi di dire, frasi utili e domande, **risolve gli esercizi a buchi** (es. "Wie heißt die Frage?": dalla risposta ricostruisce la domanda), aggiunge varianti corrette, traduzione inglese, nota per i modi di dire e una categoria (riusando le esistenti). Le frasi sono centralizzate: niente doppioni, revisione prima del salvataggio, elenco e modifica nella scheda Vocabolario (**Parole | Frasi**). Esercizi:
  - ricomponi la frase con i tasselli;
  - traduci e scrivi;
  - domanda dalla risposta;
  - completa la parola mancante;
  - dettato (anche lento);
  - pronuncia.

  Ogni esercizio ha la sua percentuale; "Automatico" va dal ricomporre allo scrivere e dire la frase; 2 frasi già viste entrano in ogni Bonus.
- **Verbi** (sezione a parte): in Aggiungi scegli **Verbi**; il prompt dedicato estrae ogni verbo con il presente delle 6 persone (separabili con il prefisso in fondo, riflessivi con il pronome), il gruppo (regolari, cambio vocalico, irregolari, modali, separabili, riflessivi) e una nota su cosa fare attenzione. Esercizi:
  - scegli la forma tra 4 (con errori tipici come *fahrst*);
  - scrivi la forma;
  - tabella completa;
  - che persona è (le forme uguali, es. *macht* = er/ihr, valgono tutte);
  - pronuncia "du fährst";
  - giochi di traduzione come per le parole: scegli il verbo tedesco, scrivi EN → DE (con o senza «sich»), scrivi DE → EN, pronuncia l'infinito.

  Percentuale per esercizio e per gruppo (Traduzione / Coniugazione), filtro per gruppo, modalità automatica, 2 verbi già visti in ogni Bonus, elenco e modifica in Vocabolario (**Parole | Frasi | Verbi**).
- La pronuncia usa il riconoscimento vocale Apple in tedesco, on-device.
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
2. In app vai su **Impostazioni → OpenRouter**, incolla la key e premi Salva. La key finisce nel Portachiavi.
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
  Views/                 Studia, Vocabolario, Aggiungi, Impostazioni
```

## Backup

Il vocabolario esiste solo su questo iPhone, quindi conviene fare un backup ogni tanto: **Impostazioni → Esporta vocabolario** (su File, iCloud Drive, AirDrop...). Il file JSON contiene parole, temi, i calendari di ripasso delle tre aree e le serie di risposte giuste (per area e per tipo di esercizio) che muovono le percentuali del percorso, più frasi, verbi e lo storico degli esercizi sui numeri, ma non la API key. I backup della prima versione (schema 1) si importano ancora: le parole finiscono nel tema "Varie".

L'import offre due modalità:

- **Unisci**: per ogni parola tiene la versione modificata o ripassata più di recente.
- **Sostituisci tutto**: cancella il vocabolario attuale e lo rimpiazza con il backup.

## Icona

`design/AppIcon.svg` è il sorgente dell'icona: una pila di flashcard nei colori della bandiera tedesca con una "Ä". Il PNG 1024×1024 usato da Xcode è in `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`; se modifichi l'SVG, riesportalo a quella dimensione, senza trasparenza (il font è Inter Display Black).
