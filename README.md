# LearnCards

App iOS nativa (iPhone, iOS 17+) per memorizzare vocaboli tedeschi.

- Fotografi una pagina di esercizi: un modello vision su OpenRouter estrae le parole, ciascuna con una emoji per l'associazione visiva.
- Prima di salvarle le rivedi e correggi; i duplicati vengono segnalati.
- Il vocabolario cresce nel tempo e gira solo sul telefono (SwiftData, nessun server).
- Gli esercizi sono quattro: scelta multipla EN → DE, scrittura EN → DE, scrittura DE → EN e pronuncia EN → DE (riconoscimento vocale Apple on-device).
- Ci sono tre livelli globali: 1 traduzione, 2 articolo + parola, 3 articolo + parola + plurale.
- Il ripasso usa la spaced repetition (SM-2).
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

Il vocabolario esiste solo su questo iPhone, quindi conviene fare un backup ogni tanto: **Impostazioni → Esporta vocabolario** (su File, iCloud Drive, AirDrop...). Il file JSON contiene parole e progressi di ripasso, ma non la API key.

L'import offre due modalità:

- **Unisci**: per ogni parola tiene la versione modificata o ripassata più di recente.
- **Sostituisci tutto**: cancella il vocabolario attuale e lo rimpiazza con il backup.
