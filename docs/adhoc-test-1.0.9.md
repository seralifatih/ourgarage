# Ad hoc test — 1.0.9 (15), durum denetimi düzeltmeleri

iPad'de (iOS 15.x) elle yapılacak testler. Branch: `fix/state-audit-1.0.9`.
Kapsanan maddeler: #1, #2, #3, #4, #5, #6, #7, #12, #15 ve iPad yerleşimi.

Uygulama arayüzü İngilizce olduğu için ekran metinleri aynen, tırnak içinde
yazıldı. Her adımın yanına ✅ / ❌ koyup not düşebilirsin.

---

## 0. Hazırlık

### 0.1 iPad'i kaydet (bir kerelik)

1. iPad'in UDID'sini al. Örneğin Windows'ta Apple Devices uygulaması ya da
   iTunes → cihaz → seri numarasına tıklayınca UDID görünür.
2. developer.apple.com → Certificates, Identifiers & Profiles → Devices →
   "+" → iPad'i UDID ile ekle.
3. Kayıt, Ad Hoc build **başlamadan önce** yapılmış olmalı. Codemagic profili
   build sırasında kayıtlı cihazlarla oluşturur. Sonradan eklenen bir cihaz
   için yeni build gerekir.

### 0.2 Build ve kurulum

1. Codemagic → `ios-adhoc` ("iOS ad hoc → .ipa (manual)") workflow'unu
   `fix/state-audit-1.0.9` branch'inde elle başlat.
2. Build yeşil olmalı. Analyze ve testler bu workflow'da build'i durdurur.
   "Check export method is ad hoc" adımı `ad-hoc` ya da `release-testing`
   yazmalı.
3. Artefaktlardan `.ipa`'yı indir (başarı e-postasında da link var).
4. iPad'e kur. Mac yoksa en kolayı Diawi gibi bir OTA servisi: `.ipa`'yı yükle,
   verdiği linki iPad'de **Safari**'de aç, "Install". Mac varsa Apple
   Configurator ya da Finder ile sürükle-bırak.
5. Kurulum "Unable to install" ile bitiyorsa cihaz büyük olasılıkla profilde
   yok (bkz. 0.1).

**Dikkat:**
- Bu build **canlı Supabase'e** bağlanıyor (aynı `supabase` grubu). Household
  testlerinde gerçek veri yazılır.
- App Store'dan kurulu 1.0.9 varsa ad hoc build onun üzerine kurulur. Önceki
  veriler korunmayabilir, iPad'de önemli veri tutma.
- Ad hoc build satın almalarda **sandbox** kullanır. Gerçek kartından para
  çekilmez.

### 0.3 Sandbox hesabı

1. iPad: Ayarlar → App Store → en altta "SANDBOX HESABI" → sandbox tester ile
   giriş yap. App Store Connect → Users and Access → Sandbox'tan yeni tester
   oluşturabilirsin.
2. Lifetime bir non-consumable ürün. Bir kez alındıktan sonra aynı tester ile
   tekrar "satın alma" testi yapmak için App Store Connect'te o tester için
   **Clear Purchase History** yap ya da yeni tester kullan.

### 0.4 Temiz başlangıç

Testlerin çoğu "ücretsiz, hiç bildirim izni sorulmamış" durumdan başlar.
Uygulamayı silip yeniden kurmak hem veriyi hem iOS bildirim iznini sıfırlar.

---

## 1. iPad yerleşimi (tüm testler boyunca)

Her ekranda dikey **ve** yatay kontrol et. Mümkünse Split View'da (uygulama
ekranın yarısı/üçte biri) da bir tur dön.

| Ekran | Beklenen |
|---|---|
| Add vehicle / Edit vehicle | Form alanları ortalı, ~640 pt'den geniş değil. Telefonda olduğu gibi kenardan kenara uzanmıyor. |
| Add service / Edit service | Aynı |
| Add reminder / Edit reminder | Aynı. Edit'te sağ üstte çöp kutusu ikonu. |
| Reminders (araç → "Manage reminders") | Liste ve (varsa) bildirim banner'ı aynı ortalı kolonda |
| Update odometers | Alanlar ortalı kolonda |
| Araç detayı | Başlık, bölümler ve ayırıcı çizgiler ortalı kolonda |
| Settings | Satırlar ortalı kolonda. Yan boşluklarda parmakla kaydırınca liste yine kayıyor. |
| Paywall | İçerik ortalı, ~720 pt. İki plan kartı yan yana, fiyatlar taşmıyor. "Unlock" ve "Restore purchases" kaydırınca erişilebilir. |
| Odometer sheet, diyaloglar, snackbar'lar | Hiçbir metin kesilmiyor, taşma yok (sarı-siyah şerit yok) |

---

## 2. Maddeler

### #6 — Form hataları açılışta görünmüyor

1. Garaj boşken "Add vehicle".
   - **Beklenen:** Form kırmızı hata metni olmadan açılır. "Add vehicle"
     butonu pasif.
2. "Nickname"e bir harf yaz, sonra sil.
   - **Beklenen:** Yalnızca Nickname altında "Nickname is required" çıkar.
     "Current odometer" altında hata **yok** (dokunulmadı).
3. Nickname ve odometer'ı doldur.
   - **Beklenen:** Buton aktifleşir.
4. "Add reminder" (araç → Manage reminders → "+ Add reminder").
   - **Beklenen:** "Set an interval in months, distance, or both" açılışta
     görünmez, buton pasif. Months'a `6` yazınca buton aktifleşir.
5. "Add service" → Type: "Custom".
   - **Beklenen:** "Custom type" alanı belirir ama hata metni yok. Buton pasif,
     etiket yazınca aktif.

### #4 — Ücretsiz limit form açılmadan kontrol ediliyor

Ücretsiz kullanıcı (sandbox'ta satın alma yapılmamış), garajda 1 araç var.

1. Garaj listesinde "Add vehicle" (FAB).
   - **Beklenen:** Form değil, **doğrudan paywall** ("Unlock your whole
     garage") açılır.
2. Paywall'ı sol üstteki X ile kapat.
   - **Beklenen:** Garaj listesine dönülür, form açılmaz.
3. Tekrar "Add vehicle" → paywall → sandbox ile satın al (bkz. #12-A).
   - **Beklenen:** "Welcome to Premium" sonrası **"Add vehicle" formu
     kendiliğinden açılır**.
4. Garaj boşken (yeni kurulum) "Add vehicle".
   - **Beklenen:** Form doğrudan açılır, paywall yok.

### #1 — Yanlış kilometre düzeltilebiliyor

Bir araç oluştur: odometer `128500` km, varsayılan hatırlatmaları ekle (Oil
change 8000 km / 6 ay).

1. Araç detayı → "Update" → `1285000` → "Save".
   - **Beklenen:** Değer 1,285,000 olur, sheet kapanır, onay sorulmaz (artış).
2. Tekrar "Update" → `128500` → "Save".
   - **Beklenen:** "Correct a typo?" diyaloğu: "128,500 km is lower than the
     current reading, 1,285,000 km. …"
3. "Cancel".
   - **Beklenen:** Diyalog kapanır, sheet açık kalır, değer hâlâ 1,285,000.
4. Tekrar "Save" → "Correct reading".
   - **Beklenen:** Sheet kapanır, odometer 128,500 km. Hatırlatma durumları
     (Reminders bölümü ve garajdaki rozet) eski değere göre yeniden hesaplanır.
5. Bilinen sınır: düzeltme öncesinde yanlış değerle **servis kaydı**
   girildiyse o kaydın ve eşleşen hatırlatmanın "last done" kilometresi yanlış
   kalır. Kayıt ve hatırlatma formundan elle düzeltilmesi gerekir. Bunu
   gözlemle, hata olarak işaretleme.

### #5 — Hatırlatma silme ve geri alma

1. Araç → "Manage reminders" → bir hatırlatmaya dokun → sağ üstteki çöp
   kutusu ("Delete reminder").
   - **Beklenen:** Listeye dönülür, "Reminder deleted" snackbar'ı ve "Undo"
     görünür. Hatırlatma listeden kalkar.
2. "Undo".
   - **Beklenen:** Hatırlatma aynı ayarlarla geri gelir.
3. Tekrar sil, Undo'ya basma, snackbar'ın kaybolmasını bekle.
   - **Beklenen:** Silinmiş kalır, araç detayındaki Reminders bölümünden de
     kalkar.
4. "Add reminder" ekranında çöp kutusu **yok**.
5. (Household'daysan) Diğer cihazda silme ve Undo'nun senkronize olduğunu
   kontrol et.

### #7 — Servis kaydı sonrası geri bildirim

Aracın "Oil change" hatırlatması olsun.

1. "Add service record" → Type "Oil change" → "Add record".
   - **Beklenen:** Detay ekranında snackbar: "Service saved. Oil change
     reminder reset — next due <Ay Yıl>." (ya da "— next due in 8000 km.").
     Reminders bölümünde Oil change yeni tarihe/mesafeye geçer.
2. Hatırlatması olmayan bir tür ile kayıt ekle, örn. "Brakes".
   - **Beklenen:** Snackbar: "Service saved".
3. Geçmişten bir kayda dokun → bir alanı değiştir → "Save changes".
   - **Beklenen:** Snackbar: "Service record updated".

### #2 — Bildirim izni durumu

**A. Hiç sorulmamış (temiz kurulum)**

1. Settings.
   - **Beklenen:** "Notifications" satırı: "Off — reminders can't alert you"
     ve "Turn on" butonu (iOS henüz izin vermediği için kapalı sayılır).
2. "Turn on".
   - **Beklenen:** iOS'un kendi izin penceresi çıkar. "Allow" → satır "On"
     olur, buton kaybolur.
3. (Ayrı bir temiz kurulumda) "Turn on" → iOS penceresinde "Don't Allow".
   - **Beklenen:** iOS Ayarlar kendiliğinden açılmaz. Yalnızca "Open
     Settings" seçenekli snackbar çıkar.
4. Uygulamayı arka plana alıp geri getir.
   - **Beklenen:** Settings satırı ve (varsa) banner bir an bile kaybolup
     yeniden belirmez.

**B. Reddedilmiş**

1. Temiz kurulum → araç ekle → "Set up reminders?" → "Add reminders" →
   "Turn on reminders" → iOS penceresinde **"Don't Allow"**.
2. Settings.
   - **Beklenen:** "Off — reminders can't alert you" + "Turn on".
3. Araç → "Manage reminders".
   - **Beklenen:** Listenin üstünde banner: "Notifications are off, so these
     reminders can't alert you." + "Turn on" + X.
4. Banner'daki X.
   - **Beklenen:** Banner kaybolur. Başka ekrana gidip dönünce de görünmez.
5. Uygulamayı tamamen kapat (app switcher'dan yukarı kaydır), yeniden aç →
   Manage reminders.
   - **Beklenen:** Banner geri gelir (kapatma yalnızca o oturum için).
6. Banner'da ya da Settings'te "Turn on".
   - **Beklenen:** iOS izin penceresi **çıkmaz** (iOS bir kez sorar).
     iOS Ayarlar kendiliğinden **açılmaz**. Snackbar çıkar: "Notifications
     are off. You can turn them on in Settings." + "Open Settings".
7. "Open Settings".
   - **Beklenen:** iOS Ayarlar açılır. iOS 15.0–15.3'te uygulamanın ayar
     sayfası (en üstte "Bildirimler" satırı), 15.4+'ta doğrudan Bildirimler
     sayfası. iPad'in tam iOS sürümünü not et.
8. Ayarlar'da bildirimleri aç → uygulamaya geri dön.
   - **Beklenen:** Banner kaybolmuş, Settings satırı "On".

**C. Açıkken iOS Ayarlar'dan kapatma**

1. İzin açıkken uygulamayı arka plana al → iOS Ayarlar → OurGarage →
   Bildirimler → kapat → uygulamaya dön.
   - **Beklenen:** Settings satırı "Off …" ve banner görünür.

### #3 — Bildirim metni

Gece boyu bekleme gerektiren, isteğe bağlı bir test.

1. Bildirim izni açıkken bir hatırlatma ekle: Type "Custom" ("Ad hoc test"),
   Interval `1` month, "Last done date" = **bugünden 1 ay önce + 1 gün**
   (yarına denk gelsin).
2. Ertesi sabah 09:00'u bekle.
   - **Beklenen:** Bildirim "Blue Civic: Ad hoc test due", gövde
     **"Tap to log it."** ("or snooze" yok). Dokununca araç detayı açılır.

### #12 — Satın alma, Restore, iptal ve hatalar (sandbox)

Sandbox hesabıyla giriş yapılmış olmalı (0.3).

**A. Satın alma**

1. Settings → "OurGarage Premium" → paywall. "Lifetime" seçili → "Unlock".
2. Sandbox sayfasında satın almayı onayla.
   - **Beklenen:** "Welcome to Premium", paywall kapanır, Settings'te "Active".

**B. İptal**

1. (Premium değilken) paywall → "Unlock" → App Store sayfasında **Cancel**.
   - **Beklenen:** Hiçbir hata mesajı çıkmaz, paywall'da kalınır, "Unlock"
     tekrar basılabilir.

**C. Restore**

1. Satın almış sandbox hesabıyla: uygulamayı sil → yeniden kur → paywall →
   "Restore purchases".
   - **Beklenen:** "Purchases restored", paywall kapanır, Premium aktif.
2. Aynısını Settings → "Restore purchases" ile dene.
   - **Beklenen:** "Purchases restored".
3. Hiç satın almamış (ya da geçmişi temizlenmiş) tester ile Restore.
   - **Beklenen:** "No previous purchases found", paywall'da kalınır.

**D. Ağ hatası**

1. Paywall'ı **çevrimiçiyken** aç (fiyatlar görünsün), sonra Uçak Modu'nu aç
   → "Unlock".
   - **Beklenen:** App Store'un kendi uyarısı çıkabilir. Ardından
     uygulamada "Couldn't reach the App Store. Check your connection and try
     again." ve **"Message me"** butonlu snackbar.
2. "Message me".
   - **Beklenen:** Mail uygulaması açılır: alıcı destek adresi, konu
     "OurGarage purchase problem", gövdede `Error: <kod>`, uygulama ve iOS
     sürümü. (Mail hesabı yoksa "Could not open link".)
3. Uçak Modu açıkken Settings → "Restore purchases".
   - **Beklenen:** Hata mesajı + "Message me" (konu "OurGarage restore
     problem").
4. Uçak Modu açıkken paywall'ı **sıfırdan** aç.
   - **Beklenen:** "Purchases are unavailable right now." + "Try again" +
     "Message me". Uçak modunu kapatıp "Try again" → planlar görünür.

**E. Ask to Buy (beklemede satın alma)**

Sandbox'ta iOS 15 cihazında Ask to Buy tetiklenemiyor (Xcode StoreKit
testi gerekir). Bu yol widget testleriyle kapsanıyor
(`test/features/paywall/purchase_errors_test.dart`). Cihazda gerçek bir aile
hesabıyla denenirse beklenen: "Waiting for approval. Premium unlocks as soon
as the purchase is approved.", "Message me" yok, paywall'da kalınır.

### #15 — Yükleme hataları

Yerel veritabanı okuma hatası cihazda kendiliğinden tetiklenemiyor. Bu yol
testlerle kapsanıyor (`test/core/load_error_view_test.dart`). Cihazda yalnızca
şunu doğrula: normal kullanımda hiçbir ekranda İngilizce exception metni
(`Exception:`, `SqliteException`, `Bad state` vb.) görünmüyor. Görürsen ekran
görüntüsü al.

---

## 3. Gerileme kontrolü (kısa tur)

- [ ] Garaj listesi, araç kartı rozetleri, "Odometer may be out of date"
      ipucu eskisi gibi.
- [ ] Servis kaydını kaydırarak silme + "Undo" çalışıyor.
- [ ] Araç silme diyaloğu çalışıyor, listeye dönülüyor.
- [ ] Household: "Share with household" → giriş → yükleme → davet kodu
      paylaşımı. "Join a household" ile geçersiz kodda "That code doesn't
      match any invite."
- [ ] Export (Premium): CSV ve PDF paylaşım sayfası iPad'de bir popover
      olarak satırın yanında açılıyor.
- [ ] Settings → "Something wrong? Message me" eskisi gibi mail açıyor.

## 4. Sonuç

| Madde | Sonuç | Not |
|---|---|---|
| iPad yerleşimi | | |
| #6 | | |
| #4 | | |
| #1 | | |
| #5 | | |
| #7 | | |
| #2 A / B / C | | iOS sürümü: |
| #3 | | |
| #12 A / B / C / D | | |
| #15 | | |
| Gerileme | | |
