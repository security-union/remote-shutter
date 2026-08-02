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
      "mac2": ["Hands full?", "Camera handled."],
      "mac3": ["Direct the shot", "from the big screen."],
      "mac1": ["See everything.", "Control everything."]
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
      "mac2": ["Hænderne fulde?", "Kameraet klarer det."],
      "mac3": ["Instruér billedet", "fra den store skærm."],
      "mac1": ["Se alt.", "Styr alt."]
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
      "mac2": ["Hände voll?", "Die Kamera läuft."],
      "mac3": ["Führ Regie", "vom großen Bildschirm."],
      "mac1": ["Alles sehen.", "Alles steuern."]
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
      "mac2": ["¿Manos ocupadas?", "La cámara se encarga."],
      "mac3": ["Dirige la toma", "desde la pantalla grande."],
      "mac1": ["Ve todo.", "Controla todo."]
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
      "mac2": ["Les mains prises ?", "La caméra s'en charge."],
      "mac3": ["Dirigez la scène", "depuis le grand écran."],
      "mac1": ["Voyez tout.", "Contrôlez tout."]
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
      "mac2": ["Mani occupate?", "Ci pensa la fotocamera."],
      "mac3": ["Dirigi la scena", "dal grande schermo."],
      "mac1": ["Vedi tutto.", "Controlli tutto."]
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
      "mac2": ["手がふさがっていても、", "カメラはおまかせ。"],
      "mac3": ["大画面で", "撮影を演出。"],
      "mac1": ["すべて見える。", "すべて操作できる。"]
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
      "mac2": ["손이 바빠도", "카메라는 알아서."],
      "mac3": ["큰 화면에서", "촬영을 연출하세요."],
      "mac1": ["모두 보고,", "모두 제어하세요."]
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
      "mac2": ["Mãos ocupadas?", "A câmera resolve."],
      "mac3": ["Dirija a cena", "pela tela grande."],
      "mac1": ["Veja tudo.", "Controle tudo."]
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
      "mac2": ["腾不开手？", "相机替你搞定。"],
      "mac3": ["在大屏幕上", "把控画面。"],
      "mac1": ["尽收眼底。", "尽在掌控。"]
    },
    labels: {
      "CAMERA": "相机", "REMOTE": "遥控器",
      "PHOTO & VIDEO": "照片和视频", "TIMER": "定时器",
      "ZOOM & LENS": "变焦和镜头", "FLASH & TORCH": "闪光灯和手电筒",
      "CAMERA PICKER": "相机选择", "LIVE PREVIEW": "实时预览", "PRO CAMERA": "专业相机"
    }
  },
  "hi": {
    sublines: { "0": "इंटरनेट की ज़रूरत नहीं — AirDrop जैसा पीयर-टू-पीयर।", "1": "रियर कैमरे से लिया। किसी भी सेल्फी से तेज़।", "mac0": "प्रो कैमरे, वेबकैम, यहाँ तक कि Continuity Camera — सीधे आपके फ़ोन पर लाइव।" },
    headlines: {
      "0": ["एक फ़ोन है कैमरा।", "दूसरा है रिमोट।"],
      "1": ["सब फ़्रेम में।", "आप भी।"],
      "2": ["सब कुछ देखें।", "सब कुछ कंट्रोल करें।"],
      "3": ["पास जाएँ।", "बिना पास गए।"],
      "4": ["नया: शटर दबाएँ", "अपनी कलाई से।"],
      "5": ["न इंटरनेट। न अकाउंट।", "बस कनेक्ट करें।"],
      "mac0": ["आपका Mac कैमरा है।", "आपका iPhone रिमोट है।"],
      "mac1": ["सब कुछ देखें।", "सब कुछ कंट्रोल करें।"],
      "mac2": ["हाथ भरे हैं?", "कैमरा संभल गया।"],
      "mac3": ["बड़ी स्क्रीन से", "शॉट डायरेक्ट करें।"]
    },
    labels: {
      "CAMERA": "कैमरा", "REMOTE": "रिमोट", "PRO CAMERA": "प्रो कैमरा",
      "PHOTO & VIDEO": "फ़ोटो और वीडियो", "TIMER": "टाइमर",
      "ZOOM & LENS": "ज़ूम और लेंस", "FLASH & TORCH": "फ़्लैश और टॉर्च",
      "LIVE PREVIEW": "लाइव प्रीव्यू"
    }
  },
  "vi": {
    sublines: { "0": "Không cần internet — ngang hàng, như AirDrop.", "1": "Chụp bằng camera sau. Sắc nét hơn mọi ảnh selfie.", "mac0": "Máy ảnh chuyên nghiệp, webcam, cả Continuity Camera — truyền trực tiếp về điện thoại." },
    headlines: {
      "0": ["Một máy là máy ảnh.", "Máy kia là điều khiển."],
      "1": ["Mọi người vào khung.", "Kể cả bạn."],
      "2": ["Thấy mọi thứ.", "Điều khiển mọi thứ."],
      "3": ["Lại gần.", "Mà không cần đến gần."],
      "4": ["MỚI: Bấm màn trập", "từ cổ tay bạn."],
      "5": ["Không internet. Không tài khoản.", "Chỉ việc kết nối."],
      "mac0": ["Mac là máy ảnh.", "iPhone là điều khiển."],
      "mac1": ["Thấy mọi thứ.", "Điều khiển mọi thứ."],
      "mac2": ["Bận tay?", "Máy ảnh lo rồi."],
      "mac3": ["Đạo diễn khung hình", "từ màn hình lớn."]
    },
    labels: {
      "CAMERA": "MÁY ẢNH", "REMOTE": "ĐIỀU KHIỂN", "PRO CAMERA": "MÁY ẢNH PRO",
      "PHOTO & VIDEO": "ẢNH & VIDEO", "TIMER": "HẸN GIỜ",
      "ZOOM & LENS": "THU PHÓNG & ỐNG KÍNH", "FLASH & TORCH": "ĐÈN FLASH & ĐÈN PIN",
      "LIVE PREVIEW": "XEM TRỰC TIẾP"
    }
  },
  "ms": {
    sublines: { "0": "Tiada internet perlu — peer-to-peer, seperti AirDrop.", "1": "Dirakam dengan kamera belakang. Lebih tajam daripada swafoto.", "mac0": "Kamera pro, webcam, malah Continuity Camera — langsung ke telefon anda." },
    headlines: {
      "0": ["Satu telefon jadi kamera.", "Satu lagi jadi kawalan."],
      "1": ["Semua masuk gambar.", "Termasuk anda."],
      "2": ["Lihat segalanya.", "Kawal segalanya."],
      "3": ["Semakin dekat.", "Tanpa mendekat."],
      "4": ["BAHARU: Cetuskan pengatup", "dari pergelangan tangan."],
      "5": ["Tiada internet. Tiada akaun.", "Cuma sambung."],
      "mac0": ["Mac anda ialah kamera.", "iPhone anda alat kawalan."],
      "mac1": ["Lihat segalanya.", "Kawal segalanya."],
      "mac2": ["Tangan penuh?", "Kamera diuruskan."],
      "mac3": ["Arahkan penggambaran", "dari skrin besar."]
    },
    labels: {
      "CAMERA": "KAMERA", "REMOTE": "KAWALAN JAUH", "PRO CAMERA": "KAMERA PRO",
      "PHOTO & VIDEO": "FOTO & VIDEO", "TIMER": "PEMASA",
      "ZOOM & LENS": "ZUM & KANTA", "FLASH & TORCH": "DENYAR & SULUH",
      "LIVE PREVIEW": "PRATONTON LANGSUNG"
    }
  },
  "tr": {
    sublines: { "0": "İnternet gerekmez — AirDrop gibi eşler arası.", "1": "Arka kamerayla çekildi. Her selfie'den keskin.", "mac0": "Profesyonel kameralar, web kameraları, hatta Continuity Camera — telefonunuzda canlı." },
    headlines: {
      "0": ["Bir telefon kamera olur.", "Diğeri kumanda."],
      "1": ["Herkes karede.", "Sen de dahil."],
      "2": ["Her şeyi gör.", "Her şeyi kontrol et."],
      "3": ["Yaklaş.", "Yaklaşmadan."],
      "4": ["YENİ: Deklanşörü", "bileğinden tetikle."],
      "5": ["İnternet yok. Hesap yok.", "Sadece bağlan."],
      "mac0": ["Mac'iniz kamera.", "iPhone'unuz kumanda."],
      "mac1": ["Her şeyi gör.", "Her şeyi kontrol et."],
      "mac2": ["Elleriniz dolu mu?", "Kamera halleder."],
      "mac3": ["Çekimi büyük ekrandan", "yönetin."]
    },
    labels: {
      "CAMERA": "KAMERA", "REMOTE": "KUMANDA", "PRO CAMERA": "PRO KAMERA",
      "PHOTO & VIDEO": "FOTOĞRAF VE VİDEO", "TIMER": "ZAMANLAYICI",
      "ZOOM & LENS": "ZOOM VE OBJEKTİF", "FLASH & TORCH": "FLAŞ VE EL FENERİ",
      "LIVE PREVIEW": "CANLI ÖNİZLEME"
    }
  },
  "ru": {
    sublines: { "0": "Интернет не нужен — peer-to-peer, как AirDrop.", "1": "Снято на основную камеру. Чётче любого селфи.", "mac0": "Проф. камеры, веб-камеры, даже Continuity Camera — прямо на телефон." },
    headlines: {
      "0": ["Один телефон — камера.", "Другой — пульт."],
      "1": ["Все в кадре.", "И вы тоже."],
      "2": ["Всё видно.", "Всё под контролем."],
      "3": ["Снимайте вблизи.", "Не приближаясь."],
      "4": ["НОВОЕ: спуск затвора", "прямо с запястья."],
      "5": ["Без интернета. Без аккаунта.", "Просто подключитесь."],
      "mac0": ["Ваш Mac — камера.", "Ваш iPhone — пульт."],
      "mac1": ["Всё видно.", "Всё под контролем."],
      "mac2": ["Руки заняты?", "Камера справится."],
      "mac3": ["Управляйте съёмкой", "с большого экрана."]
    },
    labels: {
      "CAMERA": "КАМЕРА", "REMOTE": "ПУЛЬТ", "PRO CAMERA": "ПРОФ. КАМЕРА",
      "PHOTO & VIDEO": "ФОТО И ВИДЕО", "TIMER": "ТАЙМЕР",
      "ZOOM & LENS": "ЗУМ И ОБЪЕКТИВ", "FLASH & TORCH": "ВСПЫШКА И ФОНАРИК",
      "LIVE PREVIEW": "ЖИВОЙ ПРОСМОТР"
    }
  }
};
