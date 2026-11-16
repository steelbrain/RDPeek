import type { Dictionary } from "./en";

export const es: Dictionary = {
  meta: {
    title: "RDPeek – Escritorio remoto para macOS",
    description:
      "Un cliente de Escritorio remoto para macOS, escrito en Swift. Conéctate por RDP a PC con Windows y escritorios Linux, con vídeo decodificado por hardware, las funciones rápidas de tu Mac en el equipo remoto y las contraseñas en el llavero. En ocho idiomas. Gratuito y de código abierto.",
  },
  skipToContent: "Saltar al contenido",
  header: {
    navigation: "Sitio",
    changelog: "Registro de cambios",
    github: "GitHub",
    download: "Descargar",
  },
  footer: {
    navigation: "Pie de página",
    languages: "Idioma",
    download: "Descargar",
    github: "GitHub",
    changelog: "Registro de cambios",
    rdpkit: "RDPKit",
    license: "Licencia MIT",
  },
  hero: {
    tagline:
      "Un cliente de Escritorio remoto para macOS, escrito en Swift. Se conecta a PC con Windows y a escritorios Linux que ejecutan un servidor RDP, como GNOME o xrdp.",
    download: "Descargar",
    source: "Código fuente en GitHub",
    homebrew: "O instálalo con <homebrew>Homebrew</homebrew>:",
    copy: "Copiar",
    copied: "Copiado",
    requirements:
      "Requiere macOS 14 o posterior. En español y en <languages>otros siete idiomas</languages>. Gratuito y de código abierto, con la licencia MIT.",
  },
  pcs: {
    title: "Tus PC",
    paragraphs: [
      "Cada PC que guardas tiene una tarjeta con un color propio, elegido al añadirlo. Busca por nombre, host o nombre de usuario, ordena por nombre o por la última vez que te conectaste, y abre un PC con un doble clic, con el botón de reproducción que aparece al situar el puntero encima o con Retorno.",
      "Para añadir un PC basta con un nombre de host o una dirección IP. El nombre visible, la cuenta y si se comparte el portapapeles o se reproduce el sonido del ordenador remoto son opcionales, y puedes cambiarlos más tarde. En la app, pulsa <kbd>⌘N</kbd>; aquí, usa la hoja de abajo.",
    ],
  },
  sessions: {
    title: "Sesiones",
    paragraphs: [
      "Una ventana de sesión es el escritorio remoto bajo una barra de título fina. La barra de título muestra si estás conectado y contiene el menú ⋯: “Desconectar”, los interruptores del portapapeles y del audio, qué pantallas mostrar, una superposición de rendimiento y “Estadísticas para nerds”.",
      "El escritorio remoto, compatible con HiDPI, empieza con el tamaño de tu pantalla y sigue la ventana cuando cambias su tamaño. Un ordenador remoto con varias pantallas conserva su propia disposición, y tú eliges cuáles mostrar. Office Desktop, en la cuadrícula de arriba, tiene dos.",
      "“Resolución” define la nitidez de un escritorio que sigue la ventana. “Calidad”, la opción por omisión, solicita al servidor todos los píxeles de la ventana. “Equilibrada” solicita hasta 1,5 veces el tamaño de la ventana en puntos, y “Rápida”, su tamaño en puntos; en ambos casos, RDPeek lo amplía para ajustarlo. En una pantalla Retina, eso supone algo más de la mitad de los píxeles con “Equilibrada” y una cuarta parte con “Rápida”, así que el servidor tiene menos que codificar y enviar.",
      "Elígela para todos los PC en Ajustes, que se muestran más abajo, en la sección Idiomas, o para un solo PC en “Opciones”, en sus ajustes. Un cambio llega a una sesión abierta sin volver a conectar en cuanto su escritorio sigue la ventana. En una pantalla que no es Retina, o con un PC que no puede cambiar el tamaño de su escritorio, las tres opciones son iguales.",
      "El vídeo llega como H.264, en AVC420 o AVC444, y VideoToolbox lo decodifica por hardware. Los fotogramas se presentan con el display link, al ritmo de la frecuencia de actualización de tu pantalla.",
    ],
  },
  languages: {
    title: "Idiomas",
    paragraphs: [
      "RDPeek está en chino simplificado, español, francés, inglés, italiano, japonés, portugués (Brasil) y ruso. Sigue el idioma de tu Mac. “Idioma”, en Ajustes, elige uno solo para RDPeek, que se muestra cuando RDPeek se vuelve a abrir; un idioma que definas después para RDPeek en Ajustes del Sistema lo sustituye. “Estadísticas para nerds” se mantiene en inglés, salvo el estado de una sesión y el motivo por el que finalizó.",
      "Ajustes también contiene “Resolución” y los valores por omisión para los PC que añadas. En la app, pulsa <kbd>⌘,</kbd>.",
    ],
  },
  keyboard: {
    title: "Teclado",
    intro:
      "Mientras una ventana de sesión tiene el control de tu teclado, las funciones rápidas con <kbd>⌘</kbd> o <kbd>⌃</kbd> van al ordenador remoto en lugar de a tu Mac. Haz clic en el escritorio remoto de arriba y pulsa <kbd>⌘R</kbd>: el ordenador remoto recibe Win + R y abre su cuadro de diálogo Ejecutar.",
    macColumn: "En tu Mac",
    remoteColumn: "En el ordenador remoto",
    keys: [
      { mac: "⌘ Comando", remote: "Tecla Windows" },
      { mac: "⌃ Control", remote: "Ctrl" },
      { mac: "⌥ Opción izquierda", remote: "Alt" },
      {
        mac: "⌥ Opción derecha",
        remote: "El carácter que escribe en tu Mac, como @ con ⌥L en una distribución alemana, y Alt en los demás casos",
      },
    ],
    layout:
      "Al ordenador remoto se le indica la distribución de teclado de tu Mac. Las teclas que allí escriben el mismo carácter se envían como teclas, para que los métodos de entrada del ordenador remoto las vean, y todo lo demás se envía como texto. Cuando la ventana pierde el foco, las teclas que mantenías pulsadas se sueltan en el ordenador remoto, para que ninguna se quede atascada.",
    shortcutsTitle: "Funciones rápidas de RDPeek",
    shortcutsNote:
      "<kbd>⌘?</kbd> abre la “Ayuda de RDPeek”, donde están las demás. Mientras una sesión tiene el control de tu teclado, las propias funciones rápidas con ⌘ de RDPeek también van al ordenador remoto, así que sus comandos también están en el menú ⋯ y en el menú “Sesión”.",
  },
  clipboard: {
    title: "Portapapeles",
    paragraphs: [
      "El texto y los archivos se copian en ambos sentidos entre tu Mac y el ordenador remoto. El uso compartido del portapapeles se define para cada PC, así que puedes mantenerlo desactivado en un equipo en el que no confíes.",
      "Con el uso compartido activado, el portapapeles se comparte durante toda la sesión, y “Sincronizar portapapeles ahora” envía lo último que has copiado si el ordenador remoto aún no lo tiene. Con él desactivado, “Compartir portapapeles durante 30 segundos” lo activa el tiempo justo para pasar algo al otro lado. Ambos están en el menú ⋯ de la ventana de sesión de arriba.",
    ],
  },
  security: {
    title: "Contraseñas y certificados",
    paragraphs: [
      "Las contraseñas se guardan en tu llavero, un ítem por cuenta, host y puerto, y cada una se elimina cuando eliminas el último PC que la usa o dejas de recordarla. Si prefieres no guardar una contraseña, la ventana de sesión te la pide al conectarte, y RDPeek la conserva en la memoria hasta que sales de la app. Los PC guardados se almacenan en las preferencias de la app y nunca incluyen una contraseña.",
      "Cuando tu Mac no confía en el certificado de un servidor, RDPeek se detiene antes de enviar ninguna credencial y muestra un aviso como el de abajo. “Confiar y conectar” fija la huella digital SHA-256 del certificado para ese host y puerto. Si más adelante el servidor muestra otro certificado en el que tu Mac no confía, la conexión vuelve a detenerse e indica que el certificado ha cambiado.",
      "Un servidor que usa para el inicio de sesión una versión obsoleta de la autenticación a nivel de red, CredSSP sin la actualización de seguridad de 2018, se rechaza antes de que se envíe ninguna contraseña. “Conectar de todos modos” le permite iniciar sesión solo para esa conexión, salvo en un servidor al que se haya transferido la sesión, por ejemplo, mediante un equilibrador de carga.",
    ],
  },
  source: {
    title: "Código abierto",
    paragraphs: [
      "RDPeek es gratuito, y su código fuente está <github>en GitHub</github> con la <license>licencia MIT</license>. Del propio protocolo de Escritorio remoto se encarga <rdpkit>RDPKit</rdpkit>, una biblioteca RDP en Swift puro basada en los frameworks de multimedia, seguridad y red de Apple.",
      "Los cambios de cada versión están en el <changelog>registro de cambios</changelog>.",
    ],
  },
  demo: {
    grid: {
      caption:
        "Esta es una copia funcional de la ventana principal. Haz clic en un PC para seleccionarlo y darle un color nuevo, haz doble clic en él para conectarte o haz clic en él con el botón derecho.",
      connecting: "Conectando con {name}. Su ventana de sesión está en Sesiones, más abajo.",
      deleted: "Se ha eliminado “{name}”. Su ventana de sesión, en Sesiones, sigue abierta, como en la app.",
      savedPCs: "PC guardados",
      actions: "Acciones de {name}",
      noResults: "No hay resultados para “{query}”",
      noResultsHint: "Comprueba la ortografía o prueba con una nueva búsqueda.",
    },
    addPC: {
      caption:
        "Escribe un host para ver cómo la tarjeta toma su nombre. “Guardar” añade el PC a la cuadrícula de la parte superior de la página.",
      added: "Se ha añadido “{name}” a la cuadrícula de la parte superior de la página.",
      addedAndConnecting: "Se ha añadido “{name}”. Se está conectando en la ventana de sesión de abajo.",
    },
    sheet: {
      increaseTimeout: "Aumentar el tiempo de espera de conexión",
      decreaseTimeout: "Reducir el tiempo de espera de conexión",
    },
    session: {
      closed: "La ventana de sesión está cerrada.",
      openAnother: "Haz doble clic en un PC de la parte superior de la página para abrir otra.",
      connectAgain: "Volver a conectar con {name}",
      deviceDeleted:
        "{name} se ha eliminado de la cuadrícula. Como en la app, su sesión continúa, pero RDPeek no conserva ninguna contraseña para él.",
      closeWindow: "Cerrar la ventana de sesión",
      closeStats: "Cerrar “Estadísticas para nerds”",
      desktop: "Escritorio remoto de {name}. Las teclas que pulses aquí van al ordenador remoto.",
      keysWaiting: "Las teclas llegarán al escritorio remoto en cuanto se conecte.",
      keysHint:
        "Haz clic en el escritorio remoto y pulsa una función rápida, como ⌘R, para ver qué recibe el ordenador remoto.",
      keysFocused: "El escritorio remoto tiene el control de tu teclado. Pulsa ⌘R o escribe algo.",
      keysPressed: "Has pulsado <kbd>{mac}</kbd> y {name} ha recibido <kbd>{remote}</kbd>",
      keysReleased:
        "La ventana ha perdido el foco con teclas pulsadas, así que RDPeek las ha soltado en el ordenador remoto.",
    },
    certificate: {
      caption: "RDPeek se ha conectado y ha recibido este certificado, pero no ha enviado ninguna credencial.",
      trusted: "De confianza: la huella digital ya está fijada para windows-laptop.local, puerto 3389.",
      showAgain: "Volver a mostrar el aviso",
    },
    settings: {
      windowTitle: "Ajustes de RDPeek",
      increaseTimeout: "Aumentar el tiempo de espera de conexión por omisión",
      decreaseTimeout: "Reducir el tiempo de espera de conexión por omisión",
      readoutQuality:
        "Con “{mode}”, una ventana de sesión de {width} × {height} puntos en una pantalla Retina solicita al servidor un escritorio de {requestedWidth} × {requestedHeight}: todos los píxeles de la ventana.",
      readoutBalanced:
        "Con “{mode}”, una ventana de sesión de {width} × {height} puntos en una pantalla Retina solicita al servidor un escritorio de {requestedWidth} × {requestedHeight}, el {percent}% de los píxeles de la ventana, y lo amplía para ajustarlo.",
      readoutFast:
        "Con “{mode}”, una ventana de sesión de {width} × {height} puntos en una pantalla Retina solicita al servidor un escritorio de {requestedWidth} × {requestedHeight}, una cuarta parte de los píxeles de la ventana, y lo amplía para ajustarlo.",
      reopenNote: "En la app, RDPeek se cerraría ahora y se volvería a abrir en {language}.",
    },
  },
};
