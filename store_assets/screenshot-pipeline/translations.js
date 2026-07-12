// Static screenshot translations — one entry per App Store locale.
// Rendering is fully deterministic: `node render.mjs --locale it` uses this
// table, no AI/API calls involved. Keys: headlines h0..h5 (slot base ids,
// banner uses h0), labels keyed by the English callout string.
window.I18N = {
  "en-US": {
    sublines: { "0": 'No internet needed — peer-to-peer, like AirDrop.', "1": 'Shot on the rear camera. Sharper than any selfie.', "mac0": 'Pro cameras, webcams, even Continuity Camera — live to your phone.' },
    headlines: {
      "0": ["One phone is the camera.", "The other is the remote."],
      "1": ["Everyone's in the shot.", "Including you."],
      "2": ["See everything.", "Control everything."],
      "3": ["Get close.", "Without getting close."],
      "4": ["NEW: Fire the shutter", "from your wrist."],
      "5": ["No internet. No account.", "Just connect."],
      "mac0": ["Your Mac is the camera.", "Your iPhone is the remote."],
      "mac2": ["Every camera on your Mac.", "One tap away."],
      "mac3": ["Direct the shot", "from the big screen."]
    },
    labels: {}
  },
  "da": {
    sublines: { "0": 'Kræver ingen internet — peer-to-peer, ligesom AirDrop.', "1": 'Taget med bagkameraet. Skarpere end nogen selfie.', "mac0": 'Prokameraer, webcams, endda Continuity Camera — live på din telefon.' },
    headlines: {
      "0": ["Én telefon er kameraet.", "Den anden er fjernbetjeningen."],
      "1": ["Alle er med på billedet.", "Også dig."],
      "2": ["Se alt.", "Styr alt."],
      "3": ["Kom tæt på.", "Uden at komme tæt på."],
      "4": ["NYT: Udløs kameraet", "fra dit håndled."],
      "5": ["Intet internet. Ingen konto.", "Bare forbind."],
      "mac0": ["Din Mac er kameraet.", "Din iPhone er fjernbetjeningen."],
      "mac2": ["Alle kameraer på din Mac.", "Ét tryk væk."],
      "mac3": ["Instruér billedet", "fra den store skærm."]
    },
    labels: {
      "CAMERA": "KAMERA", "REMOTE": "FJERNBETJENING",
      "PHOTO & VIDEO": "FOTO & VIDEO", "TIMER": "TIMER",
      "ZOOM & LENS": "ZOOM & LINSE", "FLASH & TORCH": "BLITZ & LYS",
      "CAMERA PICKER": "KAMERAVALG", "LIVE PREVIEW": "LIVE-VISNING", "PRO CAMERA": "PROKAMERA"
    }
  },
  "de-DE": {
    sublines: { "0": 'Kein Internet nötig — Peer-to-Peer, wie AirDrop.', "1": 'Mit der Rückkamera. Schärfer als jedes Selfie.', "mac0": 'Profikameras, Webcams, sogar Continuity Camera — live auf dein Handy.' },
    headlines: {
      "0": ["Ein Telefon ist die Kamera.", "Das andere die Fernbedienung."],
      "1": ["Alle sind auf dem Foto.", "Auch du."],
      "2": ["Alles sehen.", "Alles steuern."],
      "3": ["Ganz nah dran.", "Ohne nah zu sein."],
      "4": ["NEU: Auslösen", "direkt vom Handgelenk."],
      "5": ["Kein Internet. Kein Konto.", "Einfach verbinden."],
      "mac0": ["Dein Mac ist die Kamera.", "Dein iPhone die Fernbedienung."],
      "mac2": ["Jede Kamera an deinem Mac.", "Ein Tipp genügt."],
      "mac3": ["Führ Regie", "vom großen Bildschirm."]
    },
    labels: {
      "CAMERA": "KAMERA", "REMOTE": "FERNBEDIENUNG",
      "PHOTO & VIDEO": "FOTO & VIDEO", "TIMER": "TIMER",
      "ZOOM & LENS": "ZOOM & OBJEKTIV", "FLASH & TORCH": "BLITZ & LICHT",
      "CAMERA PICKER": "KAMERA-AUSWAHL", "LIVE PREVIEW": "LIVE-VORSCHAU", "PRO CAMERA": "PROFIKAMERA"
    }
  },
  "es-MX": {
    sublines: { "0": 'Sin internet — tecnología P2P, como AirDrop.', "1": 'Con la cámara trasera. Más nítida que cualquier selfie.', "mac0": 'Cámaras pro, webcams y hasta Continuity Camera — en vivo en tu teléfono.' },
    headlines: {
      "0": ["Un teléfono es la cámara.", "El otro es el control."],
      "1": ["Todos salen en la foto.", "Tú también."],
      "2": ["Ve todo.", "Controla todo."],
      "3": ["Acércate.", "Sin acercarte."],
      "4": ["NUEVO: Dispara", "desde tu muñeca."],
      "5": ["Sin internet. Sin cuenta.", "Solo conéctate."],
      "mac0": ["Tu Mac es la cámara.", "Tu iPhone es el control."],
      "mac2": ["Cada cámara de tu Mac.", "A un toque."],
      "mac3": ["Dirige la toma", "desde la pantalla grande."]
    },
    labels: {
      "CAMERA": "CÁMARA", "REMOTE": "CONTROL",
      "PHOTO & VIDEO": "FOTO Y VIDEO", "TIMER": "TEMPORIZADOR",
      "ZOOM & LENS": "ZOOM Y LENTE", "FLASH & TORCH": "FLASH Y LINTERNA",
      "CAMERA PICKER": "SELECTOR DE CÁMARA", "LIVE PREVIEW": "VISTA EN VIVO", "PRO CAMERA": "CÁMARA PRO"
    }
  },
  "fr-FR": {
    sublines: { "0": 'Sans internet — pair-à-pair, comme AirDrop.', "1": "Avec la caméra arrière. Plus net qu'un selfie.", "mac0": "Caméras pro, webcams, même Continuity Camera — en direct sur votre téléphone." },
    headlines: {
      "0": ["Un téléphone est l'appareil photo.", "L'autre est la télécommande."],
      "1": ["Tout le monde sur la photo.", "Vous aussi."],
      "2": ["Voyez tout.", "Contrôlez tout."],
      "3": ["Approchez-vous.", "Sans vous approcher."],
      "4": ["NOUVEAU : Déclenchez", "depuis votre poignet."],
      "5": ["Pas d'internet. Pas de compte.", "Connectez, c'est tout."],
      "mac0": ["Votre Mac est l'appareil photo.", "Votre iPhone, la télécommande."],
      "mac2": ["Chaque caméra de votre Mac.", "En un toucher."],
      "mac3": ["Dirigez la scène", "depuis le grand écran."]
    },
    labels: {
      "CAMERA": "CAMÉRA", "REMOTE": "TÉLÉCOMMANDE",
      "PHOTO & VIDEO": "PHOTO & VIDÉO", "TIMER": "RETARDATEUR",
      "ZOOM & LENS": "ZOOM & OBJECTIF", "FLASH & TORCH": "FLASH & TORCHE",
      "CAMERA PICKER": "SÉLECTEUR DE CAMÉRA", "LIVE PREVIEW": "APERÇU EN DIRECT", "PRO CAMERA": "CAMÉRA PRO"
    }
  },
  "it": {
    sublines: { "0": 'Senza internet — peer-to-peer, come AirDrop.', "1": 'Con la fotocamera posteriore. Più nitida di un selfie.', "mac0": 'Fotocamere pro, webcam e persino Continuity Camera — live sul telefono.' },
    headlines: {
      "0": ["Un telefono è la fotocamera.", "L'altro è il telecomando."],
      "1": ["Tutti in foto.", "Anche tu."],
      "2": ["Vedi tutto.", "Controlli tutto."],
      "3": ["Avvicinati.", "Senza avvicinarti."],
      "4": ["NOVITÀ: Scatta", "dal tuo polso."],
      "5": ["Niente internet. Nessun account.", "Basta connettersi."],
      "mac0": ["Il tuo Mac è la fotocamera.", "Il tuo iPhone è il telecomando."],
      "mac2": ["Ogni fotocamera del tuo Mac.", "A un tocco."],
      "mac3": ["Dirigi la scena", "dal grande schermo."]
    },
    labels: {
      "CAMERA": "FOTOCAMERA", "REMOTE": "TELECOMANDO",
      "PHOTO & VIDEO": "FOTO E VIDEO", "TIMER": "TIMER",
      "ZOOM & LENS": "ZOOM E OBIETTIVO", "FLASH & TORCH": "FLASH E TORCIA",
      "CAMERA PICKER": "SELEZIONE FOTOCAMERA", "LIVE PREVIEW": "ANTEPRIMA LIVE", "PRO CAMERA": "FOTOCAMERA PRO"
    }
  },
  "ja": {
    sublines: { "0": 'インターネット不要 — AirDropのようなP2P接続。', "1": '背面カメラで撮影。セルフィーよりずっと高精細。', "mac0": 'プロ用カメラもウェブカメラも、連係カメラも — iPhoneにライブで。' },
    headlines: {
      "0": ["1台はカメラに。", "もう1台はリモコンに。"],
      "1": ["全員が写真に。", "あなたも一緒に。"],
      "2": ["すべて見える。", "すべて操作できる。"],
      "3": ["近づかずに、", "もっと近くへ。"],
      "4": ["新機能: 手首から", "シャッターを切る。"],
      "5": ["ネット不要。アカウント不要。", "つなぐだけ。"],
      "mac0": ["Macがカメラに。", "iPhoneがリモコンに。"],
      "mac2": ["Macのすべてのカメラを。", "ワンタップで。"],
      "mac3": ["大画面で", "撮影を演出。"]
    },
    labels: {
      "CAMERA": "カメラ", "REMOTE": "リモコン",
      "PHOTO & VIDEO": "写真＆ビデオ", "TIMER": "タイマー",
      "ZOOM & LENS": "ズーム＆レンズ", "FLASH & TORCH": "フラッシュ＆ライト",
      "CAMERA PICKER": "カメラ選択", "LIVE PREVIEW": "ライブプレビュー", "PRO CAMERA": "プロ用カメラ"
    }
  },
  "ko": {
    sublines: { "0": '인터넷 불필요 — AirDrop 같은 P2P 연결.', "1": '후면 카메라로 촬영. 셀피보다 선명하게.', "mac0": '프로 카메라, 웹캠, 연속성 카메라까지 — iPhone에 실시간으로.' },
    headlines: {
      "0": ["한 대는 카메라,", "다른 한 대는 리모컨."],
      "1": ["모두가 사진 속에.", "당신도 함께."],
      "2": ["모두 보고,", "모두 제어하세요."],
      "3": ["가까이,", "다가가지 않고도."],
      "4": ["NEW: 손목에서", "셔터를 누르세요."],
      "5": ["인터넷 불필요. 계정 불필요.", "연결만 하세요."],
      "mac0": ["Mac이 카메라,", "iPhone이 리모컨."],
      "mac2": ["Mac의 모든 카메라를,", "한 번의 탭으로."],
      "mac3": ["큰 화면에서", "촬영을 연출하세요."]
    },
    labels: {
      "CAMERA": "카메라", "REMOTE": "리모컨",
      "PHOTO & VIDEO": "사진·비디오", "TIMER": "타이머",
      "ZOOM & LENS": "줌·렌즈", "FLASH & TORCH": "플래시·손전등",
      "CAMERA PICKER": "카메라 선택", "LIVE PREVIEW": "실시간 미리보기", "PRO CAMERA": "프로 카메라"
    }
  },
  "pt-BR": {
    sublines: { "0": 'Sem internet — ponto a ponto, como o AirDrop.', "1": 'Com a câmera traseira. Mais nítida que qualquer selfie.', "mac0": 'Câmeras pro, webcams e até Continuity Camera — ao vivo no seu celular.' },
    headlines: {
      "0": ["Um celular é a câmera.", "O outro é o controle."],
      "1": ["Todos na foto.", "Incluindo você."],
      "2": ["Veja tudo.", "Controle tudo."],
      "3": ["Chegue perto.", "Sem chegar perto."],
      "4": ["NOVO: Dispare", "do seu pulso."],
      "5": ["Sem internet. Sem conta.", "É só conectar."],
      "mac0": ["Seu Mac é a câmera.", "Seu iPhone é o controle."],
      "mac2": ["Cada câmera do seu Mac.", "A um toque."],
      "mac3": ["Dirija a cena", "pela tela grande."]
    },
    labels: {
      "CAMERA": "CÂMERA", "REMOTE": "CONTROLE",
      "PHOTO & VIDEO": "FOTO E VÍDEO", "TIMER": "TEMPORIZADOR",
      "ZOOM & LENS": "ZOOM E LENTE", "FLASH & TORCH": "FLASH E LANTERNA",
      "CAMERA PICKER": "SELETOR DE CÂMERA", "LIVE PREVIEW": "PRÉVIA AO VIVO", "PRO CAMERA": "CÂMERA PRO"
    }
  },
  "zh-Hans": {
    sublines: { "0": '无需网络 — 点对点连接，就像隔空投送。', "1": '使用后置摄像头拍摄，比自拍更清晰。', "mac0": '专业相机、网络摄像头，甚至接续互通相机——实时传到你的手机。' },
    headlines: {
      "0": ["一台是相机。", "另一台是遥控器。"],
      "1": ["每个人都入镜。", "包括你。"],
      "2": ["尽收眼底。", "尽在掌控。"],
      "3": ["靠得更近，", "无需走近。"],
      "4": ["新功能：抬腕", "即可拍摄。"],
      "5": ["无需网络。无需账户。", "连接即用。"],
      "mac0": ["Mac 就是相机。", "iPhone 就是遥控器。"],
      "mac2": ["Mac 上的每个相机，", "一键切换。"],
      "mac3": ["在大屏幕上", "把控画面。"]
    },
    labels: {
      "CAMERA": "相机", "REMOTE": "遥控器",
      "PHOTO & VIDEO": "照片和视频", "TIMER": "定时器",
      "ZOOM & LENS": "变焦和镜头", "FLASH & TORCH": "闪光灯和手电筒",
      "CAMERA PICKER": "相机选择", "LIVE PREVIEW": "实时预览", "PRO CAMERA": "专业相机"
    }
  }
};
