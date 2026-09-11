# Survivor Leveling & Advancement [B42]

Becerilerini geliştirerek puan kazan, sonra bu puanları istediğin becerilere harca. SLA, doğal beceri gelişimini koruyarak normal Beceriler paneline Hayatta Kalan Seviyesi ve Gelişim Puanları ekler. Bir sonraki kötü kararından sonra ilerlemenin bir kısmı kalsın mı? İsteğe bağlı seviye mirası, sonraki karakterinin Hayatta Kalan Seviyenin belirli bir yüzdesini ve harcayabileceği yeni puanları almasını sağlar.

Tek oyunculu, çok oyunculu, bölünmüş ekran ve kontrolcü desteği. Zorunlu bağımlılık yok.

## Gelişim nasıl çalışır?

Desteklenen becerilerde kazandığın XP, Hayatta Kalan Seviyeni de yükseltir. Her seviye bir Gelişim Puanı, yani AP verir. Becerilerin yanındaki **+** düğmeleriyle AP harcayabilirsin. Varsayılan olarak aynı anda üç gelişim yuvası kullanabilirsin. Geliştirdiğin beceriyi çalışıp atladığın XP'yi kazandıkça yuvaları boşaltırsın. Bu XP, becerinin sonraki seviyesine de sayılır.

Bir becerinin geçerli en yüksek seviyesine yapılan son gelişim, normalde 9'dan 10'a geçiş, ustalık sayılır. Ustalık 2 AP ve 2 boş Gelişim Yuvası gerektirir, ardından o becerinin tüm etkin yuvalarını temizler. Genel veya Beceri başına yuva sınırı 1 ise yalnızca 1 boş yuva gerekir, ancak bedel yine 2 AP'dir. Serbest modda yuva gerekmez, bedel 2 AP olarak kalır. Geçerli en yüksek seviyesine ulaşmış bir beceri ek Hayatta Kalan XP üretmez.

## Ölümden sonra ilerlemenin bir kısmını koru

Hayatta Kalan Seviyesi mirasını aç ve aynı dünyadaki sonraki karakterine ne kadarının geçeceğini seç. Örneğin, Hayatta Kalan Seviyesi 20 iken %50 mirasla ölürsen sonraki karakterin Hayatta Kalan Seviyesi 10 ve harcayabileceği 10 AP ile başlar. Eski beceri seviyeleri kopyalanmaz, dolayısıyla miras kalan puanları nereye harcayacağına sen karar verirsin. Miras isteğe bağlıdır ve varsayılan olarak kapalıdır.

## Ayarlar

- **Genel:** Tüm beceriler ayarlanabilir ortak bir Gelişim Yuvası havuzu kullanır. Varsayılan sınır toplam 3 etkin yuvadır.
- **Beceri başına:** Her becerinin ayrı, ayarlanabilir yuva sınırı vardır. Uyumlu özel beceriler için varsayılan değer ve temel oyun becerileri için isteğe bağlı ayrı ayarlar bulunur.
- **Serbest:** Gelişim Yuvası sınırlarını ve eksik XP'yi tamamlama kısıtlamalarını kaldırır.
- Beceri XP'sini değiştirmeden Hayatta Kalan XP hızını ayarla. Kondisyon, Güç, tek tek temel oyun becerileri ve uyumlu özel becerilerin katkıda bulunup bulunmayacağını seç.
- Mod seçeneklerinden daha yüksek kontrastlı gelişim işaretlerini veya dijital saatte 1. oyuncunun Hayatta Kalan XP yüzdesini açabilirsin.
- Project Zomboid dil ayarlarında bulunan tüm standart dilleri destekler. Tüm çeviriler tamamen yapay zekâ ile yapıldı. Yanlış veya anlaşılmaz bir metin fark edersen lütfen bildir.

**Not:** Mod değiştirmek kayıtlı ilerlemeyi sıfırlamaz. Serbest modda doğal yoldan kazanılan beceri XP'si, korunan mavi tamamlama ilerlemesine sayılmaya devam eder. Genel veya Beceri başına moda dönünce yalnızca kalan kısım geri yüklenir.

## SLA'yı eklemek veya kaldırmak

SLA mevcut kayıtlara eklenebilir veya kayıtlardan kaldırılabilir. Mevcut beceriler korunur ve geçmiş ilerleme geriye dönük Hayatta Kalan Seviyesi vermez. SLA'yı kapatmak arayüzünü gizler ancak AP ile kazanılan beceri seviyelerini korur. Yeniden açmak SLA durumunu geri yükler ve kapalıyken kazanılan desteklenen ilerlemeyi hesaba katar. Her mod listesi değişikliğinde olduğu gibi, önemsediğin dünyaların yedeğini almanı özellikle öneririm.

## Adanmış sunucular ve oyun barındırma

Yöneticiler mevcut çevrimiçi ve çevrimdışı profillere hayatta kalan XP veya tam seviyeler verebilir. Çevrimdışı ödüller hemen uygulanır. İlerlemeleri temizlemek AP iade etmeden veya beceri XP değiştirmeden yuvaları boşaltır. Çevrimdışı karakterlerde işlem yeniden bağlanana kadar bekler ve iptal edilebilir. Oyuncu istatistiklerinden beceri seviyesini değiştirmek o becerinin kaydını temizler.

SLA, Project Zomboid'in normal kayıt sistemini kullanır. Adanmış ve barındırılan sunucularda SaveWorldEveryMinutes ayarını aç ve sunucuyu normal şekilde kapat.

## Uyumluluk

- **Uyumsuz: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**
- **Şu anda desteklenmiyor: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) ve [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. Bu modlar SLA'nın dayandığı gelişim kurallarını doğrudan değiştirir.
- **Yükleme sırasına bağlı: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. SLA'nın mavi XP tamamlama metnini DST'nin genişletilmiş beceri ipuçlarına eklemek için SLA'yı Detailed Skill Tooltips'ten sonra yükle. SLA önce yüklenirse yalnızca bu metin değiştirilir. Hayatta Kalan Seviyesi gelişimi ve + düğmesi ipuçları çalışmaya devam eder.
- **Birlikte test edildi: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939) ve [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. Bu birleşim testlerde sorunsuz çalıştı, ancak her arayüz veya özel beceri moduyla uyumluluk garanti edilemez.
- Beceri XP işlemesini, sınırlarını veya eğrilerini, beceri panelini, oyuncu menülerini ya da dijital saati değiştiren modlar çakışabilir. Gerekli bağlantılar değiştirilirse SLA etkilenen entegrasyonu kapatır. Özel beceriler kullanılabilir bir XP eğrisi ve desteklenen XP olayları gerektirir. Becerileri doğrudan değiştiren veya bu olayları üretmeyen yollar hayatta kalan XP kazandırmaz.

## Yapay zekâ kullanımı

Bu projenin tüm kodu yapay zekâ kullanılarak yazıldı. İlk fikir, tasarım yönü, testler, hata ayıklama ve yayın kararları bana ait. SLA'nın amaçlandığı gibi çalışması için onu bizzat test ederek ve sorunları çözerek birçok saat harcadım. Yapay zekâ yardımıyla geliştirilen modları kullanmak istemiyorsan bunu anlıyor ve tercihine saygı duyuyorum.

## Destek

- [Ko-fi](https://ko-fi.com/skeptic043) bağışları isteğe bağlıdır. Hiçbir mod özelliği ödeme gerektirmez.

## Mod bilgileri

- Geliştirildiği/test edildiği sürüm: 42.20.4
- Zorunlu bağımlılıklar: Yok
- Lisans: MIT
- [Kaynak kodu ve sorun takibi](https://github.com/Skeptic043/survivor-leveling-and-advancement)
