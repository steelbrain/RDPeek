import type { Dictionary } from "./en";

export const it: Dictionary = {
  meta: {
    title: "RDPeek – Desktop remoto per macOS",
    description:
      "Un client Desktop remoto per macOS, scritto in Swift. Connettiti a PC Windows e desktop Linux tramite RDP, con video decodificato in hardware, le abbreviazioni del Mac sul computer remoto e le password nel portachiavi. In otto lingue. Gratuito e open source.",
  },
  skipToContent: "Vai al contenuto",
  header: {
    navigation: "Sito",
    changelog: "Registro modifiche",
    github: "GitHub",
    download: "Scarica",
  },
  footer: {
    navigation: "Piè di pagina",
    languages: "Lingua",
    download: "Scarica",
    github: "GitHub",
    changelog: "Registro modifiche",
    rdpkit: "RDPKit",
    license: "Licenza MIT",
  },
  hero: {
    tagline:
      "Un client Desktop remoto per macOS, scritto in Swift. Si connette a PC Windows e a desktop Linux che eseguono un server RDP, come GNOME o xrdp.",
    download: "Scarica",
    source: "Codice sorgente su GitHub",
    homebrew: "Oppure installalo con <homebrew>Homebrew</homebrew>:",
    copy: "Copia",
    copied: "Copiato",
    requirements:
      "Richiede macOS 14 o versioni successive. In italiano e in <languages>altre sette lingue</languages>. Gratuito e open source con licenza MIT.",
  },
  pcs: {
    title: "I tuoi PC",
    paragraphs: [
      "Ogni PC che salvi ha un riquadro con un colore tutto suo, scelto quando lo aggiungi. Puoi cercare per nome, host o nome utente, ordinare per nome o per data dell’ultima connessione e aprire un PC facendo doppio clic, premendo il pulsante Riproduci che compare al passaggio del puntatore oppure premendo A capo.",
      "Per aggiungere un PC basta un nome host o un indirizzo IP. Il nome visualizzato, l’account e la scelta di condividere gli appunti o riprodurre l’audio del computer remoto sono facoltativi e puoi modificarli in seguito. Nell’app premi <kbd>⌘N</kbd>; in questa pagina usa il pannello qui sotto.",
    ],
  },
  sessions: {
    title: "Sessioni",
    paragraphs: [
      "Una finestra della sessione è il desktop remoto sotto una sottile barra del titolo. La barra del titolo mostra se sei connesso e contiene il menu ⋯: “Disconnetti”, gli interruttori per appunti e audio, la scelta dei monitor da mostrare, “Overlay prestazioni” e “Statistiche per nerd”.",
      "Il desktop remoto parte dalle dimensioni del tuo schermo e segue la finestra quando la ridimensioni, con supporto HiDPI. Un computer remoto con più monitor mantiene la propria disposizione e scegli tu quali monitor mostrare. Office Desktop, nella griglia qui sopra, ne ha due.",
      "“Risoluzione” stabilisce la nitidezza di un desktop che segue la finestra. “Qualità”, l’impostazione predefinita, richiede al server tutti i pixel della finestra. “Bilanciata” richiede fino a 1,5 volte le dimensioni della finestra in punti e “Veloce” le sue dimensioni in punti; in entrambi i casi RDPeek ingrandisce il desktop per adattarlo. Su un display Retina, ciò corrisponde a poco più della metà dei pixel con “Bilanciata” e a un quarto con “Veloce”, così il server ne ha meno da codificare e inviare.",
      "Puoi sceglierla per tutti i PC in Impostazioni, che trovi più sotto nella sezione Lingue, oppure per un singolo PC in “Opzioni” nelle sue impostazioni. Una modifica si applica a una sessione aperta senza riconnettersi, non appena il suo desktop segue la finestra. Su un display non Retina, o con un PC che non può ridimensionare il proprio desktop, le tre opzioni sono equivalenti.",
      "Il video arriva in H.264, nei formati AVC420 o AVC444, e viene decodificato in hardware da VideoToolbox. I fotogrammi vengono presentati tramite il display link, al ritmo dell’aggiornamento del tuo schermo.",
    ],
  },
  languages: {
    title: "Lingue",
    paragraphs: [
      "RDPeek è disponibile in cinese semplificato, francese, giapponese, inglese, italiano, portoghese (Brasile), russo e spagnolo. Segue la lingua del tuo Mac. “Lingua”, in Impostazioni, ne sceglie una solo per RDPeek, che compare quando RDPeek viene riaperto; una lingua impostata in seguito per RDPeek in Impostazioni di Sistema prende il suo posto. La finestra “Statistiche per nerd” rimane in inglese, tranne lo stato di una sessione e il motivo per cui è terminata.",
      "In Impostazioni trovi anche “Risoluzione” e i valori predefiniti per i PC che aggiungi. Nell’app premi <kbd>⌘,</kbd>.",
    ],
  },
  keyboard: {
    title: "Tastiera",
    intro:
      "Mentre una finestra della sessione ha il controllo della tastiera, le abbreviazioni con <kbd>⌘</kbd> o <kbd>⌃</kbd> vanno al computer remoto invece che al tuo Mac. Fai clic sul desktop remoto qui sopra e premi <kbd>⌘R</kbd>: il computer remoto riceve Win + R e apre la finestra di dialogo Esegui.",
    macColumn: "Sul tuo Mac",
    remoteColumn: "Sul computer remoto",
    keys: [
      { mac: "⌘ Comando", remote: "Tasto Windows" },
      { mac: "⌃ Controllo", remote: "Ctrl" },
      { mac: "⌥ Opzione sinistro", remote: "Alt" },
      {
        mac: "⌥ Opzione destro",
        remote: "Il carattere che digita sul tuo Mac, come @ con ⌥L su un layout tedesco, altrimenti Alt",
      },
    ],
    layout:
      "Al computer remoto viene comunicato il layout di tastiera del tuo Mac. I tasti che lì digitano lo stesso carattere vengono inviati come tasti, così i metodi di input sul computer remoto li ricevono, e tutto il resto viene inviato come testo. Quando la finestra non è più attiva, i tasti che stavi tenendo premuti vengono rilasciati sul computer remoto, così nessuno resta bloccato.",
    shortcutsTitle: "Abbreviazioni da tastiera in RDPeek",
    shortcutsNote:
      "<kbd>⌘?</kbd> apre “Aiuto RDPeek”, dove trovi le altre. Mentre una sessione ha il controllo della tastiera, anche le abbreviazioni ⌘ di RDPeek vanno al computer remoto, quindi i suoi comandi si trovano anche nel menu ⋯ e nel menu Sessione.",
  },
  clipboard: {
    title: "Appunti",
    paragraphs: [
      "Testo e file si copiano in entrambe le direzioni tra il tuo Mac e il computer remoto. La condivisione degli appunti si imposta per ogni PC, così puoi tenerla disattivata per un computer di cui non ti fidi.",
      "Con la condivisione attiva, gli appunti sono condivisi per tutta la sessione e “Sincronizza appunti ora” invia la tua ultima copia, se il computer remoto non ce l’ha ancora. Con la condivisione disattivata, “Condividi appunti per 30 secondi” la attiva giusto il tempo di trasferire qualcosa. Entrambi i comandi si trovano nel menu ⋯ della finestra della sessione qui sopra.",
    ],
  },
  security: {
    title: "Password e certificati",
    paragraphs: [
      "Le password vengono conservate nel tuo portachiavi, un elemento per account, host e porta. Una password viene rimossa quando elimini l’ultimo PC che la usa o smetti di ricordarla. Se preferisci non salvare una password, la finestra della sessione te la chiede quando ti connetti e RDPeek la tiene in memoria finché non esci dall’app. I PC salvati si trovano nelle preferenze dell’app e non contengono mai una password.",
      "Quando il tuo Mac non considera attendibile il certificato di un server, RDPeek si ferma prima di inviare qualsiasi credenziale e mostra un avviso come quello qui sotto. “Considera attendibile e connetti” associa l’impronta digitale SHA-256 del certificato a quell’host e a quella porta. Se in seguito il server presenta un certificato diverso che il tuo Mac non considera attendibile, la connessione si ferma di nuovo e segnala che il certificato è cambiato.",
      "Un server che esegue l’accesso con una versione obsoleta di Autenticazione a livello di rete, CredSSP senza l’aggiornamento di sicurezza del 2018, viene rifiutato prima dell’invio di qualsiasi password. “Connetti comunque” gli consente di eseguire l’accesso solo per quella connessione, ma non vale per un server a cui la sessione è stata trasferita, ad esempio da un bilanciatore di carico.",
    ],
  },
  source: {
    title: "Open source",
    paragraphs: [
      "RDPeek è gratuito e il suo codice sorgente è <github>su GitHub</github> con <license>licenza MIT</license>. Il Remote Desktop Protocol vero e proprio è gestito da <rdpkit>RDPKit</rdpkit>, una libreria RDP scritta interamente in Swift e basata sui framework Apple per contenuti multimediali, sicurezza e rete.",
      "Le modifiche di ogni versione sono descritte nel <changelog>registro delle modifiche</changelog>.",
    ],
  },
  demo: {
    grid: {
      caption:
        "Questa è una copia funzionante della finestra principale. Fai clic su un PC per selezionarlo e dargli un nuovo colore, fai doppio clic per connetterti oppure fai clic con il pulsante destro.",
      connecting: "Connessione a {name} in corso. La sua finestra della sessione è più in basso, nella sezione Sessioni.",
      deleted: "Hai eliminato “{name}”. La sua finestra della sessione, nella sezione Sessioni, resta aperta, come nell’app.",
      savedPCs: "PC salvati",
      actions: "Azioni per {name}",
      noResults: "Nessun risultato per “{query}”",
      noResultsHint: "Verifica che non ci siano errori di battitura o esegui una nuova ricerca.",
    },
    addPC: {
      caption: "Digita un host per vedere il riquadro assumerne il nome. “Salva” aggiunge il PC alla griglia in cima alla pagina.",
      added: "Hai aggiunto “{name}” alla griglia in cima alla pagina.",
      addedAndConnecting: "Hai aggiunto “{name}”. La connessione è in corso nella finestra della sessione qui sotto.",
    },
    sheet: {
      increaseTimeout: "Aumenta il timeout di connessione",
      decreaseTimeout: "Riduci il timeout di connessione",
    },
    session: {
      closed: "La finestra della sessione è chiusa.",
      openAnother: "Fai doppio clic su un PC in cima alla pagina per aprirne un’altra.",
      connectAgain: "Connettiti di nuovo a {name}",
      deviceDeleted: "{name} è stato eliminato dalla griglia. Come nell’app, la sua sessione continua, ma RDPeek non conserva alcuna password per questo PC.",
      closeWindow: "Chiudi la finestra della sessione",
      closeStats: "Chiudi “Statistiche per nerd”",
      desktop: "Desktop remoto di {name}. I tasti che premi qui vanno al computer remoto.",
      keysWaiting: "I tasti arrivano al desktop remoto dopo la connessione.",
      keysHint: "Fai clic sul desktop remoto e premi un’abbreviazione, ad esempio ⌘R, per vedere cosa riceve il computer remoto.",
      keysFocused: "Il desktop remoto ha il controllo della tastiera. Premi ⌘R o digita qualcosa.",
      keysPressed: "Hai premuto <kbd>{mac}</kbd> e {name} ha ricevuto <kbd>{remote}</kbd>",
      keysReleased: "La finestra non era più attiva mentre alcuni tasti erano premuti, quindi RDPeek li ha rilasciati sul computer remoto.",
    },
    certificate: {
      caption: "RDPeek si è connesso e ha ricevuto questo certificato, ma non ha inviato alcuna credenziale.",
      trusted: "Considerato attendibile: l’impronta digitale ora è associata a windows-laptop.local, porta 3389.",
      showAgain: "Mostra di nuovo l’avviso",
    },
    settings: {
      windowTitle: "Impostazioni RDPeek",
      increaseTimeout: "Aumenta il timeout di connessione predefinito",
      decreaseTimeout: "Riduci il timeout di connessione predefinito",
      readoutQuality:
        "Con “{mode}”, una finestra della sessione di {width} × {height} punti su un display Retina richiede al server un desktop di {requestedWidth} × {requestedHeight}: tutti i pixel della finestra.",
      readoutBalanced:
        "Con “{mode}”, una finestra della sessione di {width} × {height} punti su un display Retina richiede al server un desktop di {requestedWidth} × {requestedHeight}, pari al {percent}% dei pixel della finestra, e lo ingrandisce per adattarlo.",
      readoutFast:
        "Con “{mode}”, una finestra della sessione di {width} × {height} punti su un display Retina richiede al server un desktop di {requestedWidth} × {requestedHeight}, un quarto dei pixel della finestra, e lo ingrandisce per adattarlo.",
      reopenNote: "Nell’app, RDPeek ora si chiuderebbe e si riaprirebbe in {language}.",
    },
  },
};
