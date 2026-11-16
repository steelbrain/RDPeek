import type { Dictionary } from "./en";

export const ptBr: Dictionary = {
  meta: {
    title: "RDPeek – Área de Trabalho Remota para macOS",
    description:
      "Um cliente de Área de Trabalho Remota para macOS, escrito em Swift. Conecte-se a PCs com Windows e a áreas de trabalho Linux por RDP, com vídeo decodificado por hardware, os atalhos do seu Mac no computador remoto e senhas nas Chaves. Em oito idiomas. Gratuito e de código aberto.",
  },
  skipToContent: "Pular para o conteúdo",
  header: {
    navigation: "Site",
    changelog: "Registro de alterações",
    github: "GitHub",
    download: "Baixar",
  },
  footer: {
    navigation: "Rodapé",
    languages: "Idioma",
    download: "Baixar",
    github: "GitHub",
    changelog: "Registro de alterações",
    rdpkit: "RDPKit",
    license: "Licença MIT",
  },
  hero: {
    tagline:
      "Um cliente de Área de Trabalho Remota para macOS, escrito em Swift. Ele se conecta a PCs com Windows e a áreas de trabalho Linux que executam um servidor RDP, como o GNOME ou o xrdp.",
    download: "Baixar",
    source: "Código-fonte no GitHub",
    homebrew: "Ou instale com o <homebrew>Homebrew</homebrew>:",
    copy: "Copiar",
    copied: "Copiado",
    requirements:
      "Requer o macOS 14 ou posterior. Disponível em português e em <languages>mais sete idiomas</languages>. Gratuito e de código aberto, sob a licença MIT.",
  },
  pcs: {
    title: "Seus PCs",
    paragraphs: [
      "Cada PC que você salva ganha um cartão com uma cor própria, escolhida quando você o adiciona. Busque por nome, host ou nome de usuário, ordene por nome ou pela última conexão, e abra um PC com um clique duplo, com o botão de reprodução que aparece ao passar o ponteiro sobre ele ou com a tecla Return.",
      "Para adicionar um PC, basta o nome do host ou um endereço IP. O nome de exibição, a conta e as opções de compartilhar a área de transferência ou reproduzir o som do computador remoto são opcionais, e você pode alterá-los depois. No app, pressione <kbd>⌘N</kbd>; aqui, use o formulário abaixo.",
    ],
  },
  sessions: {
    title: "Sessões",
    paragraphs: [
      "Uma janela de sessão é a área de trabalho remota sob uma barra de título fina. A barra de título mostra se você está conectado e contém o menu ⋯: Desconectar, as opções de área de transferência e de áudio, quais monitores mostrar, a sobreposição de desempenho e Estatísticas para Nerds.",
      "A área de trabalho remota começa com o tamanho da sua tela e acompanha a janela quando você a redimensiona, com suporte a HiDPI. Um computador remoto com vários monitores mantém a própria disposição, e você escolhe quais deles mostrar. O Office Desktop, na grade acima, tem dois.",
      "Resolução define a nitidez de uma área de trabalho que acompanha a janela. Qualidade, o padrão, pede ao servidor todos os pixels da janela. Equilibrada pede até 1,5 vez o tamanho da janela em pontos, e Rápida, o tamanho dela em pontos; o RDPeek amplia qualquer uma das duas para caber. Em uma tela Retina, isso dá pouco mais da metade dos pixels com Equilibrada e um quarto com Rápida, e assim o servidor tem menos pixels para codificar e enviar.",
      "Escolha a resolução para todos os PCs nos Ajustes, que aparecem na seção Idiomas mais abaixo, ou para um único PC em Opções, nos ajustes dele. Uma alteração chega a uma sessão aberta, sem reconectar, assim que a área de trabalho dela acompanha a janela. Em uma tela que não é Retina, ou com um PC que não consegue redimensionar a área de trabalho, as três são iguais.",
      "O vídeo chega em H.264, no formato AVC420 ou AVC444, e é decodificado em hardware pelo VideoToolbox. Os quadros são apresentados pelo display link, no ritmo da taxa de atualização da sua tela.",
    ],
  },
  languages: {
    title: "Idiomas",
    paragraphs: [
      "O RDPeek está em chinês simplificado, espanhol, francês, inglês, italiano, japonês, português (Brasil) e russo. Ele segue o idioma do seu Mac. A opção Idioma, nos Ajustes, escolhe um idioma só para o RDPeek, que aparece quando o RDPeek é aberto novamente; um idioma que você definir depois para o RDPeek nos Ajustes do Sistema passa a valer no lugar dele. A janela Estatísticas para Nerds fica em inglês, exceto o status de uma sessão e o motivo pelo qual ela terminou.",
      "Os Ajustes também contêm a Resolução e os padrões para os PCs que você adicionar. No app, pressione <kbd>⌘,</kbd>.",
    ],
  },
  keyboard: {
    title: "Teclado",
    intro:
      "Enquanto uma janela de sessão estiver com o seu teclado, os atalhos com <kbd>⌘</kbd> ou <kbd>⌃</kbd> vão para o computador remoto em vez do seu Mac. Clique na área de trabalho remota acima e pressione <kbd>⌘R</kbd>: o computador remoto recebe Win + R e abre a caixa de diálogo Executar.",
    macColumn: "No seu Mac",
    remoteColumn: "No computador remoto",
    keys: [
      { mac: "⌘ Comando", remote: "Tecla Windows" },
      { mac: "⌃ Controle", remote: "Ctrl" },
      { mac: "⌥ Opção esquerda", remote: "Alt" },
      {
        mac: "⌥ Opção direita",
        remote: "O caractere que ela digita no seu Mac, como @ com ⌥L em um layout alemão, e Alt nos demais casos",
      },
    ],
    layout:
      "O computador remoto é informado sobre o layout de teclado do seu Mac. As teclas que digitam o mesmo caractere lá são enviadas como teclas, para que os métodos de entrada do computador remoto as vejam, e o restante é enviado como texto. Quando a janela perde o foco, as teclas que você estava segurando são soltas no computador remoto, para que nenhuma fique presa.",
    shortcutsTitle: "Atalhos no RDPeek",
    shortcutsNote:
      "<kbd>⌘?</kbd> abre a Ajuda, com os demais atalhos. Enquanto uma sessão estiver com o seu teclado, os atalhos ⌘ do próprio RDPeek também vão para o computador remoto; por isso, os comandos dele também estão no menu ⋯ e no menu Sessão.",
  },
  clipboard: {
    title: "Área de transferência",
    paragraphs: [
      "Textos e arquivos são copiados nos dois sentidos entre o seu Mac e o computador remoto. O compartilhamento da área de transferência é definido para cada PC, então você pode mantê-lo desativado para uma máquina em que não confia.",
      "Com o compartilhamento ativado, a área de transferência é compartilhada durante toda a sessão, e Sincronizar Área de Transferência Agora envia a sua cópia mais recente se o computador remoto ainda não a tiver. Com ele desativado, Compartilhar Área de Transferência por 30 Segundos o ativa só pelo tempo suficiente para passar algo para o outro lado. Os dois comandos estão no menu ⋯ da janela de sessão acima.",
    ],
  },
  security: {
    title: "Senhas e certificados",
    paragraphs: [
      "As senhas ficam guardadas nas suas Chaves, um item por conta, host e porta, e cada uma é removida quando você apaga o último PC que a usa ou deixa de lembrá-la. Se preferir não salvar uma senha, a janela da sessão a pede quando você se conecta, e o RDPeek a mantém na memória até você encerrar o app. Os PCs salvos ficam nas preferências do app e nunca incluem uma senha.",
      "Quando o seu Mac não confia no certificado de um servidor, o RDPeek para antes de enviar qualquer credencial e mostra um aviso como o que está abaixo. Confiar e Conectar fixa a impressão digital SHA-256 do certificado para esse host e porta. Se depois o servidor mostrar um certificado diferente em que o seu Mac não confia, a conexão para de novo e avisa que o certificado mudou.",
      "Um servidor cujo início de sessão usa uma versão desatualizada da Autenticação no Nível da Rede, o CredSSP sem a atualização de segurança de 2018, é recusado antes que qualquer senha seja enviada. Conectar Mesmo Assim permite esse início de sessão apenas nessa conexão, exceto em um servidor para o qual a sessão foi repassada, por exemplo, por um balanceador de carga.",
    ],
  },
  source: {
    title: "Código aberto",
    paragraphs: [
      "O RDPeek é gratuito, e o código-fonte dele está <github>no GitHub</github>, sob a <license>licença MIT</license>. O Remote Desktop Protocol em si fica a cargo do <rdpkit>RDPKit</rdpkit>, uma biblioteca RDP escrita inteiramente em Swift e construída sobre os frameworks de mídia, segurança e rede da Apple.",
      "O que mudou em cada versão está no <changelog>registro de alterações</changelog>.",
    ],
  },
  demo: {
    grid: {
      caption:
        "Esta é uma cópia funcional da janela principal. Clique em um PC para selecioná-lo e dar a ele uma nova cor, clique duas vezes nele para conectar ou clique nele com o botão direito.",
      connecting: "Conectando a {name}. A janela da sessão dele está em Sessões, mais abaixo.",
      deleted: "“{name}” foi apagado. A janela da sessão dele, em Sessões, continua aberta, como no app.",
      savedPCs: "PCs salvos",
      actions: "Ações de {name}",
      noResults: "Nenhum Resultado para “{query}”",
      noResultsHint: "Verifique a ortografia ou tente uma nova busca.",
    },
    addPC: {
      caption: "Digite um host para ver o cartão assumir o nome dele. Salvar adiciona o PC à grade no topo da página.",
      added: "“{name}” foi adicionado à grade no topo da página.",
      addedAndConnecting: "“{name}” foi adicionado e está se conectando na janela da sessão abaixo.",
    },
    sheet: {
      increaseTimeout: "Aumentar o tempo limite de conexão",
      decreaseTimeout: "Diminuir o tempo limite de conexão",
    },
    session: {
      closed: "A janela da sessão está fechada.",
      openAnother: "Clique duas vezes em um PC no topo da página para abrir outra.",
      connectAgain: "Conectar a {name} novamente",
      deviceDeleted: "{name} foi apagado da grade. Como no app, a sessão dele continua, mas o RDPeek não guarda nenhuma senha para ele.",
      closeWindow: "Fechar a janela da sessão",
      closeStats: "Fechar Estatísticas para Nerds",
      desktop: "Área de trabalho remota de {name}. As teclas que você pressionar aqui vão para o computador remoto.",
      keysWaiting: "As teclas chegam à área de trabalho remota quando ela estiver conectada.",
      keysHint: "Clique na área de trabalho remota e pressione um atalho, como ⌘R, para ver o que o computador remoto recebe.",
      keysFocused: "A área de trabalho remota está com o seu teclado. Pressione ⌘R ou digite algo.",
      keysPressed: "Você pressionou <kbd>{mac}</kbd> e {name} recebeu <kbd>{remote}</kbd>",
      keysReleased: "A janela perdeu o foco com teclas pressionadas, então o RDPeek as soltou no computador remoto.",
    },
    certificate: {
      caption: "O RDPeek se conectou e recebeu este certificado, mas não enviou nenhuma credencial.",
      trusted: "Confiável: a impressão digital agora está fixada para windows-laptop.local, porta 3389.",
      showAgain: "Mostrar o aviso novamente",
    },
    settings: {
      windowTitle: "Ajustes de RDPeek",
      increaseTimeout: "Aumentar o tempo limite de conexão padrão",
      decreaseTimeout: "Diminuir o tempo limite de conexão padrão",
      readoutQuality:
        "Com a opção {mode}, uma janela de sessão de {width} × {height} pontos em uma tela Retina pede ao servidor uma área de trabalho de {requestedWidth} × {requestedHeight}: todos os pixels da janela.",
      readoutBalanced:
        "Com a opção {mode}, uma janela de sessão de {width} × {height} pontos em uma tela Retina pede ao servidor uma área de trabalho de {requestedWidth} × {requestedHeight}, {percent}% dos pixels da janela, e a amplia para caber.",
      readoutFast:
        "Com a opção {mode}, uma janela de sessão de {width} × {height} pontos em uma tela Retina pede ao servidor uma área de trabalho de {requestedWidth} × {requestedHeight}, um quarto dos pixels da janela, e a amplia para caber.",
      reopenNote: "No app, o RDPeek seria encerrado agora e aberto novamente em {language}.",
    },
  },
};
