import type { Dictionary } from "./en";

/**
 * French. Words the app's UI shows are the app's own, from
 * Sources/Resources/Localizable.xcstrings. As there, a narrow no-break space
 * ( ) goes before : ; ? ! and inside « ».
 */
export const fr: Dictionary = {
  meta: {
    title: "RDPeek – Bureau à distance pour macOS",
    description:
      "Un client Bureau à distance pour macOS, écrit en Swift. Connectez-vous à des PC Windows et à des bureaux Linux via RDP, avec décodage vidéo matériel, les raccourcis de votre Mac sur l’ordinateur distant et les mots de passe dans le trousseau. En huit langues. Gratuit et open source.",
  },
  skipToContent: "Aller au contenu",
  header: {
    navigation: "Site",
    changelog: "Journal des modifications",
    github: "GitHub",
    download: "Télécharger",
  },
  footer: {
    navigation: "Pied de page",
    languages: "Langue",
    download: "Télécharger",
    github: "GitHub",
    changelog: "Journal des modifications",
    rdpkit: "RDPKit",
    license: "Licence MIT",
  },
  hero: {
    tagline:
      "Un client Bureau à distance pour macOS, écrit en Swift. Il se connecte aux PC Windows, ainsi qu’aux bureaux Linux qui exécutent un serveur RDP, comme GNOME ou xrdp.",
    download: "Télécharger",
    source: "Code source sur GitHub",
    homebrew: "Ou installez-le avec <homebrew>Homebrew</homebrew> :",
    copy: "Copier",
    copied: "Copié",
    requirements:
      "Nécessite macOS 14 ou version ultérieure. En français et en <languages>sept autres langues</languages>. Gratuit et open source sous licence MIT.",
  },
  pcs: {
    title: "Vos PC",
    paragraphs: [
      "Chaque PC que vous enregistrez reçoit une vignette d’une couleur qui lui est propre, choisie lorsque vous l’ajoutez. Recherchez par nom, hôte ou nom d’utilisateur, triez par nom ou par date de dernière connexion, et ouvrez un PC d’un double-clic, avec le bouton de lecture qui apparaît au survol, ou avec la touche Retour.",
      "Pour ajouter un PC, il suffit d’un nom d’hôte ou d’une adresse IP. Le nom affiché, le compte, ainsi que le partage du presse-papiers ou la lecture du son de l’ordinateur distant sont facultatifs, et vous pouvez les modifier plus tard. Dans l’app, appuyez sur <kbd>⌘N</kbd> ; ici, utilisez le formulaire ci-dessous.",
    ],
  },
  sessions: {
    title: "Sessions",
    paragraphs: [
      "Une fenêtre de session, c’est le bureau distant sous une fine barre de titre. Celle-ci indique si vous êtes connecté et contient le menu ⋯ : « Déconnecter », l’activation du presse-papiers et de l’audio, le choix des écrans à afficher, la superposition des performances et « Statistiques pour les geeks ».",
      "Le bureau distant démarre à la taille de votre écran et suit la fenêtre lorsque vous la redimensionnez, en tenant compte du HiDPI. Un ordinateur distant doté de plusieurs écrans conserve sa propre disposition, et vous choisissez lesquels afficher. Office Desktop, dans la grille ci-dessus, en a deux.",
      "« Résolution » détermine la netteté d’un bureau qui suit la fenêtre. « Qualité », le réglage par défaut, demande au serveur chaque pixel de la fenêtre. « Équilibré » demande jusqu’à 1,5 fois la taille de la fenêtre en points, et « Rapide » sa taille en points ; dans les deux cas, RDPeek agrandit l’image pour l’ajuster. Sur un écran Retina, cela représente un peu plus de la moitié des pixels avec « Équilibré » et un quart avec « Rapide » : le serveur en a donc moins à encoder et à envoyer.",
      "Choisissez-la pour tous les PC dans Réglages, présentés plus bas sous Langues, ou pour un seul PC sous « Options » dans ses réglages. Un changement s’applique à une session ouverte, sans reconnexion, dès que son bureau suit la fenêtre. Sur un écran non Retina, ou avec un PC qui ne peut pas redimensionner son bureau, les trois sont identiques.",
      "La vidéo arrive en H.264, au format AVC420 ou AVC444, et est décodée par le matériel via VideoToolbox. Les images sont présentées sur le display link, au rythme du rafraîchissement de votre écran.",
    ],
  },
  languages: {
    title: "Langues",
    paragraphs: [
      "RDPeek est disponible en anglais, chinois simplifié, espagnol, français, italien, japonais, portugais (Brésil) et russe. Il suit la langue de votre Mac. Dans Réglages, « Langue » en choisit une pour RDPeek uniquement, qui s’affiche une fois RDPeek rouvert ; une langue que vous définissez ensuite pour RDPeek dans Réglages Système la remplace. « Statistiques pour les geeks » reste en anglais, à l’exception de l’état d’une session et de la raison pour laquelle elle s’est terminée.",
      "La fenêtre Réglages contient aussi « Résolution » et les réglages par défaut des PC que vous ajoutez. Dans l’app, appuyez sur <kbd>⌘,</kbd>.",
    ],
  },
  keyboard: {
    title: "Clavier",
    intro:
      "Tant qu’une fenêtre de session reçoit votre clavier, les raccourcis avec <kbd>⌘</kbd> ou <kbd>⌃</kbd> sont envoyés à l’ordinateur distant au lieu de votre Mac. Cliquez sur le bureau distant ci-dessus et appuyez sur <kbd>⌘R</kbd> : l’ordinateur distant reçoit Win + R et ouvre sa boîte de dialogue Exécuter.",
    macColumn: "Sur votre Mac",
    remoteColumn: "Sur l’ordinateur distant",
    keys: [
      { mac: "⌘ Commande", remote: "Touche Windows" },
      { mac: "⌃ Contrôle", remote: "Ctrl" },
      { mac: "⌥ Option gauche", remote: "Alt" },
      {
        mac: "⌥ Option droite",
        remote: "Le caractère qu’elle produit sur votre Mac, comme @ avec ⌥L sur une disposition allemande, et Alt dans les autres cas",
      },
    ],
    layout:
      "L’ordinateur distant est informé de la disposition de clavier de votre Mac. Les touches qui y produisent le même caractère sont envoyées sous forme de touches, pour que les méthodes de saisie de l’ordinateur distant les voient, et tout le reste est envoyé sous forme de texte. Lorsque la fenêtre n’est plus active, les touches que vous mainteniez enfoncées sont relâchées sur l’ordinateur distant, pour qu’aucune ne reste bloquée.",
    shortcutsTitle: "Raccourcis dans RDPeek",
    shortcutsNote:
      "<kbd>⌘?</kbd> ouvre l’Aide RDPeek, qui présente les autres. Tant qu’une session reçoit votre clavier, les raccourcis ⌘ propres à RDPeek sont eux aussi envoyés à l’ordinateur distant ; ses commandes se trouvent donc également dans le menu ⋯ et le menu Session.",
  },
  clipboard: {
    title: "Presse-papiers",
    paragraphs: [
      "Le texte et les fichiers se copient dans les deux sens entre votre Mac et l’ordinateur distant. Le partage du presse-papiers se règle pour chaque PC ; vous pouvez donc le laisser désactivé pour une machine à laquelle vous ne faites pas confiance.",
      "Lorsque le partage est activé, le presse-papiers est partagé pendant toute la session, et « Synchroniser le presse-papiers maintenant » envoie ce que vous avez copié en dernier si l’ordinateur distant ne l’a pas encore reçu. Lorsqu’il est désactivé, « Partager le presse-papiers pendant 30 secondes » l’active juste le temps de transférer quelque chose. Ces deux commandes se trouvent dans le menu ⋯ de la fenêtre de session ci-dessus.",
    ],
  },
  security: {
    title: "Mots de passe et certificats",
    paragraphs: [
      "Les mots de passe sont conservés dans votre trousseau, un élément par compte, hôte et port. Chacun est supprimé lorsque vous supprimez le dernier PC qui l’utilise ou cessez de le mémoriser. Si vous préférez ne pas enregistrer de mot de passe, la fenêtre de session vous le demande lors de la connexion, et RDPeek le garde en mémoire jusqu’à ce que vous quittiez l’app. Les PC enregistrés sont stockés dans les préférences de l’app et ne contiennent jamais de mot de passe.",
      "Lorsque votre Mac ne fait pas confiance au certificat d’un serveur, RDPeek s’arrête avant l’envoi de tout identifiant et affiche un avertissement comme celui ci-dessous. « Faire confiance et se connecter » épingle l’empreinte SHA-256 du certificat pour cet hôte et ce port. Si le serveur présente plus tard un autre certificat auquel votre Mac ne fait pas confiance, la connexion s’arrête de nouveau et indique que le certificat a changé.",
      "Un serveur qui procède à l’identification avec une version obsolète de l’authentification au niveau du réseau, CredSSP sans la mise à jour de sécurité de 2018, est refusé avant l’envoi de tout mot de passe. « Se connecter quand même » lui permet de procéder à l’identification pour cette seule connexion, sauf sur un serveur auquel la session a été transmise, par exemple par un répartiteur de charge.",
    ],
  },
  source: {
    title: "Open source",
    paragraphs: [
      "RDPeek est gratuit, et son code source se trouve <github>sur GitHub</github> sous <license>licence MIT</license>. Le protocole Bureau à distance lui-même est pris en charge par <rdpkit>RDPKit</rdpkit>, une bibliothèque RDP entièrement écrite en Swift, qui repose sur les frameworks d’Apple pour les médias, la sécurité et le réseau.",
      "Les changements de chaque version figurent dans le <changelog>journal des modifications</changelog>.",
    ],
  },
  /** Captions and labels around the redrawn app UI, which run in the browser. */
  demo: {
    grid: {
      caption:
        "Voici une copie fonctionnelle de la fenêtre principale. Cliquez sur un PC pour le sélectionner et lui donner une nouvelle couleur, double-cliquez dessus pour vous connecter, ou cliquez dessus avec le bouton droit.",
      connecting: "Connexion à {name}. Sa fenêtre de session se trouve plus bas, dans Sessions.",
      deleted: "« {name} » a été supprimé. Sa fenêtre de session, sous Sessions, reste ouverte, comme dans l’app.",
      savedPCs: "PC enregistrés",
      actions: "Actions pour {name}",
      /** macOS's own words (ContentUnavailableView.search), with its no-break spaces ( ) in « ». */
      noResults: "Aucun résultat pour « {query} »",
      noResultsHint: "Vérifiez l’orthographe ou lancez une nouvelle recherche.",
    },
    addPC: {
      caption:
        "Saisissez un hôte pour voir la vignette prendre son nom. « Enregistrer » ajoute le PC à la grille en haut de la page.",
      added: "« {name} » a été ajouté à la grille en haut de la page.",
      addedAndConnecting: "« {name} » a été ajouté. Il se connecte dans la fenêtre de session ci-dessous.",
    },
    sheet: {
      increaseTimeout: "Augmenter le délai de connexion",
      decreaseTimeout: "Diminuer le délai de connexion",
    },
    session: {
      closed: "La fenêtre de session est fermée.",
      openAnother: "Double-cliquez sur un PC en haut de la page pour en ouvrir une autre.",
      connectAgain: "Se reconnecter à {name}",
      deviceDeleted:
        "{name} a été supprimé de la grille. Comme dans l’app, sa session continue, mais RDPeek ne conserve aucun mot de passe pour ce PC.",
      closeWindow: "Fermer la fenêtre de session",
      closeStats: "Fermer « Statistiques pour les geeks »",
      desktop:
        "Bureau distant de {name}. Les touches sur lesquelles vous appuyez ici sont envoyées à l’ordinateur distant.",
      keysWaiting: "Les touches parviennent au bureau distant une fois qu’il est connecté.",
      keysHint:
        "Cliquez sur le bureau distant et appuyez sur un raccourci, comme ⌘R, pour voir ce que reçoit l’ordinateur distant.",
      keysFocused: "Le bureau distant reçoit votre clavier. Appuyez sur ⌘R, ou tapez quelque chose.",
      keysPressed: "Vous avez appuyé sur <kbd>{mac}</kbd> et {name} a reçu <kbd>{remote}</kbd>",
      keysReleased:
        "La fenêtre n’est plus active alors que des touches étaient enfoncées ; RDPeek les a donc relâchées sur l’ordinateur distant.",
    },
    certificate: {
      caption: "RDPeek s’est connecté et a reçu ce certificat, mais n’a envoyé aucun identifiant.",
      trusted: "Confiance accordée : l’empreinte est désormais épinglée pour windows-laptop.local, port 3389.",
      showAgain: "Afficher de nouveau l’avertissement",
    },
    settings: {
      windowTitle: "Réglages RDPeek",
      increaseTimeout: "Augmenter le délai de connexion par défaut",
      decreaseTimeout: "Diminuer le délai de connexion par défaut",
      readoutQuality:
        "Avec « {mode} », une fenêtre de session de {width} × {height} points sur un écran Retina demande au serveur un bureau de {requestedWidth} × {requestedHeight} : chaque pixel de la fenêtre.",
      readoutBalanced:
        "Avec « {mode} », une fenêtre de session de {width} × {height} points sur un écran Retina demande au serveur un bureau de {requestedWidth} × {requestedHeight}, soit {percent} % des pixels de la fenêtre, et l’agrandit pour l’ajuster.",
      readoutFast:
        "Avec « {mode} », une fenêtre de session de {width} × {height} points sur un écran Retina demande au serveur un bureau de {requestedWidth} × {requestedHeight}, soit un quart des pixels de la fenêtre, et l’agrandit pour l’ajuster.",
      reopenNote: "Dans l’app, RDPeek se fermerait maintenant pour se rouvrir en {language}.",
    },
  },
};
