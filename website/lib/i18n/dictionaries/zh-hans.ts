import type { Dictionary } from "./en";

export const zhHans: Dictionary = {
  meta: {
    title: "RDPeek – 适用于 macOS 的远程桌面",
    description:
      "一款用 Swift 编写的 macOS 远程桌面客户端。通过 RDP 连接 Windows 电脑和 Linux 桌面：视频由硬件解码，Mac 的快捷键可在远程计算机上使用，密码存储在钥匙串中。支持八种语言，免费开源。",
  },
  skipToContent: "跳至内容",
  header: {
    navigation: "网站",
    changelog: "更新日志",
    github: "GitHub",
    download: "下载",
  },
  footer: {
    navigation: "页脚",
    languages: "语言",
    download: "下载",
    github: "GitHub",
    changelog: "更新日志",
    rdpkit: "RDPKit",
    license: "MIT 许可证",
  },
  hero: {
    tagline:
      "一款用 Swift 编写的 macOS 远程桌面客户端。它可以连接 Windows 电脑，也可以连接运行 RDP 服务器（例如 GNOME 或 xrdp）的 Linux 桌面。",
    download: "下载",
    source: "GitHub 上的源代码",
    homebrew: "也可以使用 <homebrew>Homebrew</homebrew> 安装：",
    copy: "拷贝",
    copied: "已拷贝",
    requirements:
      "需要 macOS 14 或更高版本。支持简体中文和<languages>其他七种语言</languages>。免费开源，采用 MIT 许可证。",
  },
  pcs: {
    title: "你的电脑",
    paragraphs: [
      "你存储的每台电脑都有一张卡片，颜色各不相同，在添加电脑时选定。你可以按名称、主机或用户名搜索，按名称或上次连接时间排序；要打开电脑，可以连按卡片、点按悬停时出现的播放按钮，或按下 Return 键。",
      "添加电脑只需要主机名或 IP 地址。显示名称、账户，以及是否共享剪贴板或播放远程计算机的声音，都是可选的，以后也可以更改。在 App 中，按下 <kbd>⌘N</kbd>；在这里，请使用下方的表单。",
    ],
  },
  sessions: {
    title: "会话",
    paragraphs: [
      "会话窗口就是远程桌面，上方有一条窄窄的标题栏。标题栏显示你是否已连接，并包含 ⋯ 菜单：“断开连接”、剪贴板和音频开关、要显示哪些显示器、性能叠加层，以及“详细统计信息”。",
      "远程桌面一开始与你的屏幕大小相同，并在你调整窗口大小时跟随窗口，支持 HiDPI。有多台显示器的远程计算机会保留自己的布局，由你选择显示其中哪些。上方网格中的 Office Desktop 就有两台。",
      "“分辨率”决定跟随窗口的桌面有多清晰。“高质量”（默认值）会向服务器请求窗口的每一个像素。“均衡”最多请求窗口以点为单位的尺寸的 1.5 倍，“快速”则请求窗口以点为单位的尺寸；无论哪种，RDPeek 都会将其放大以适合窗口。在 Retina 显示屏上，“均衡”的像素数略多于一半，“快速”为四分之一，因此服务器需要编码和发送的像素更少。",
      "你可以在“设置”中为所有电脑选择（“设置”窗口见下方“语言”部分），也可以在某台电脑设置的“选项”下单独为它选择。更改会在已打开会话的桌面跟随窗口时应用到该会话，无需重新连接。在非 Retina 显示屏上，或者对于无法调整桌面大小的电脑，这三个选项效果相同。",
      "视频以 H.264（AVC420 或 AVC444）格式传输，并由 VideoToolbox 进行硬件解码。帧按显示链接（display link）呈现，与屏幕刷新保持同步。",
    ],
  },
  languages: {
    title: "语言",
    paragraphs: [
      "RDPeek 提供英语、简体中文、法语、意大利语、日语、葡萄牙语（巴西）、俄语和西班牙语版本，并跟随你的 Mac 的语言。“设置”中的“语言”可以只为 RDPeek 选择一种语言，RDPeek 重新打开后才会显示；之后你在“系统设置”中为 RDPeek 设定的语言会取而代之。“详细统计信息”保持英文显示，但会话的状态及其结束原因除外。",
      "“设置”中还有“分辨率”以及新添加电脑的默认设置。在 App 中，按下 <kbd>⌘,</kbd> 即可打开。",
    ],
  },
  keyboard: {
    title: "键盘",
    intro:
      "当会话窗口接收你的键盘输入时，带 <kbd>⌘</kbd> 或 <kbd>⌃</kbd> 的快捷键会发送到远程计算机，而不是你的 Mac。点按上方的远程桌面并按下 <kbd>⌘R</kbd>：远程计算机会收到 Win + R，并打开“运行”对话框。",
    macColumn: "在你的 Mac 上",
    remoteColumn: "在远程计算机上",
    keys: [
      { mac: "⌘ Command 键", remote: "Windows 键" },
      { mac: "⌃ Control 键", remote: "Ctrl" },
      { mac: "左侧 ⌥ Option 键", remote: "Alt" },
      {
        mac: "右侧 ⌥ Option 键",
        remote: "它在你的 Mac 上输入的字符（例如在德语键盘布局中按 ⌥L 输入的 @），其他情况下为 Alt",
      },
    ],
    layout:
      "远程计算机会获知你的 Mac 的键盘布局。在远程计算机上能输入相同字符的按键会作为按键发送，以便远程计算机上的输入法能够识别，其他内容则作为文本发送。当窗口失去焦点时，你按住的按键会在远程计算机上松开，因此不会有按键卡住。",
    shortcutsTitle: "RDPeek 中的快捷键",
    shortcutsNote:
      "按下 <kbd>⌘?</kbd> 会打开“RDPeek 帮助”，其中列出了其余快捷键。当会话接收你的键盘输入时，RDPeek 自己的 ⌘ 快捷键也会发送到远程计算机，因此它的命令也位于 ⋯ 菜单和“会话”菜单中。",
  },
  clipboard: {
    title: "剪贴板",
    paragraphs: [
      "文本和文件可以在你的 Mac 与远程计算机之间双向拷贝。剪贴板共享按电脑单独设置，因此对于你不信任的机器，可以保持关闭。",
      "共享打开时，剪贴板在整个会话期间共享；如果远程计算机还没有你最近拷贝的内容，“立即同步剪贴板”会将其发送过去。共享关闭时，“共享剪贴板 30 秒”会暂时打开共享，时长刚好够你传送内容。这两项都位于上方会话窗口的 ⋯ 菜单中。",
    ],
  },
  security: {
    title: "密码和证书",
    paragraphs: [
      "密码保存在你的钥匙串中，每个账户、主机和端口的组合对应一个项目；当你删除使用该密码的最后一台电脑，或关闭“在钥匙串中记住密码”时，密码会被移除。如果你不想存储密码，会话窗口会在你连接时要求输入，RDPeek 会将其保留在内存中，直到你退出。已存储的电脑位于 App 的偏好设置中，且从不包含密码。",
      "当你的 Mac 不信任服务器的证书时，RDPeek 会在发送任何凭证之前停止，并显示类似下方的警告。“信任并连接”会将该证书的 SHA-256 指纹固定到该主机和端口。如果服务器之后出示了你的 Mac 不信任的其他证书，连接会再次停止，并提示证书已更改。",
      "使用过时版本的网络级别身份验证（未安装 2018 年安全更新的 CredSSP）登录的服务器，会在发送任何密码之前被拒绝。“仍然连接”可让它仅在该次连接中登录，但会话被转交到的服务器（例如由负载均衡器转交）除外。",
    ],
  },
  source: {
    title: "开源",
    paragraphs: [
      "RDPeek 是免费的，其源代码依据 <license>MIT 许可证</license>发布在 <github>GitHub 上</github>。远程桌面协议本身由 <rdpkit>RDPKit</rdpkit> 处理，这是一个纯 Swift 编写的 RDP 库，构建于 Apple 的媒体、安全和网络框架之上。",
      "每个版本的更改内容见<changelog>更新日志</changelog>。",
    ],
  },
  demo: {
    grid: {
      caption:
        "这是主窗口的可操作副本。点按一台电脑可选中它并为它换一种颜色，连按可连接，也可以右键点按它。",
      connecting: "正在连接到“{name}”。它的会话窗口在下方的“会话”部分。",
      deleted: "已删除“{name}”。与在 App 中一样，它在“会话”部分中的会话窗口会保持打开。",
      savedPCs: "已存储的电脑",
      actions: "“{name}”的操作",
      noResults: "未找到“{query}”的相关结果",
      noResultsHint: "检查拼写或尝试新搜索词。",
    },
    addPC: {
      caption: "输入主机，即可看到卡片使用它的名称。“存储”会将这台电脑添加到页面顶部的网格中。",
      added: "已将“{name}”添加到页面顶部的网格中。",
      addedAndConnecting: "已添加“{name}”。它正在下方的会话窗口中连接。",
    },
    sheet: {
      increaseTimeout: "增加连接超时时间",
      decreaseTimeout: "减少连接超时时间",
    },
    session: {
      closed: "会话窗口已关闭。",
      openAnother: "连按页面顶部的一台电脑，即可打开另一个会话窗口。",
      connectAgain: "再次连接到“{name}”",
      deviceDeleted: "“{name}”已从网格中删除。与在 App 中一样，它的会话会继续，但 RDPeek 不会为它保留任何密码。",
      closeWindow: "关闭会话窗口",
      closeStats: "关闭“详细统计信息”",
      desktop: "“{name}”的远程桌面。你在这里按下的按键会发送到远程计算机。",
      keysWaiting: "远程桌面连接后，按键才会发送到远程桌面。",
      keysHint: "点按远程桌面并按下快捷键（例如 ⌘R），即可看到远程计算机收到的内容。",
      keysFocused: "远程桌面正在接收你的键盘输入。请按下 ⌘R，或输入一些内容。",
      keysPressed: "你按下了 <kbd>{mac}</kbd>，“{name}”收到了 <kbd>{remote}</kbd>",
      keysReleased: "窗口在按键按住时失去了焦点，因此 RDPeek 在远程计算机上松开了这些按键。",
    },
    certificate: {
      caption: "RDPeek 已连接并收到此证书，但尚未发送任何凭证。",
      trusted: "已信任：该指纹现已固定到 windows-laptop.local，端口 3389。",
      showAgain: "再次显示警告",
    },
    settings: {
      windowTitle: "RDPeek设置",
      increaseTimeout: "增加默认连接超时时间",
      decreaseTimeout: "减少默认连接超时时间",
      readoutQuality:
        "选择“{mode}”时，Retina 显示屏上 {width} × {height} 点的会话窗口会向服务器请求 {requestedWidth} × {requestedHeight} 的桌面：即窗口的每一个像素。",
      readoutBalanced:
        "选择“{mode}”时，Retina 显示屏上 {width} × {height} 点的会话窗口会向服务器请求 {requestedWidth} × {requestedHeight} 的桌面，即窗口像素的 {percent}%，并将其放大以适合窗口。",
      readoutFast:
        "选择“{mode}”时，Retina 显示屏上 {width} × {height} 点的会话窗口会向服务器请求 {requestedWidth} × {requestedHeight} 的桌面，即窗口像素的四分之一，并将其放大以适合窗口。",
      reopenNote: "在 App 中，RDPeek 此时会退出，然后以“{language}”重新打开。",
    },
  },
};
