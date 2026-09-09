# OurGarage — App Store Submission Checklist

Not: İlk gerçek build Codemagic üzerinden başarıyla TestFlight'a yüklendi (bkz. bölüm 6 ve "Telefon/tablet gelince" bölümü). Test cihazı olarak elde bulunan iPad mini 4 (A1538), donanımsal olarak iOS 15.8.x'te kilitli — Xcode 26 ile derlenen build'ler bu cihazda TestFlight tarafından "iOS 16 gerekli" denilerek reddediliyor (Apple'ın Xcode 26 SDK zorunluluğuyla gelen, projeden bağımsız bir platform kısıtlaması). Fonksiyonel doğrulama şimdilik MacinCloud'daki iOS Simulator üzerinden yapılıyor; gerçek cihaz testi iOS 16+ çalıştırabilen bir cihaz bulununca tamamlanacak.

Proje bilgileri (referans):
- Bundle ID: `com.ourgarage.ourgarage`
- App adı (kod içi): `OurGarage`

---

## 1. Screenshot'lar (simülatörden, release modda)

- [x] Debug banner kapatıldı — [lib/app.dart](lib/app.dart) içine `debugShowCheckedModeBanner: false` eklendi. Artık release build'e ek olarak debug modda bile banner çıkmaz.
- [x] App icon 1024×1024, RGB (alfa kanalsız) — [assets/icon/icon.png](assets/icon/icon.png) zaten bu gereksinimi karşılıyor, ekstra işlem gerekmedi.

**Release/simulator build almak için (sen çalıştıracaksın):**
```powershell
flutter build ios --release --simulator
```

**Gerekli boyutlar (Apple zorunlu tutuyor):**
- 6.9" (iPhone 16 Pro Max / 15 Pro Max) — zorunlu
- 6.5" (iPhone 11 Pro Max / XS Max) — zorunlu (bazı hesaplarda hâlâ isteniyor, kontrol et)
- İsteğe bağlı: iPad 13" — iPad desteklemiyorsan atla

Xcode Simulator → Device menüsünden ilgili cihazı seç → uygulamayı çalıştır → ⌘S.

**Hangi ekranlardan alınmalı (5 screenshot, App Store bu sırayla gösterir — ilk ikisi en kritik, mağaza sayfasında kesilmeden görünür):**
1. Ana ekran — birden fazla araç listesi (family-sharing farkını hemen göstersin, en az 2 araç + "shared" rozeti varsa o görünsün)
2. Bir aracın servis geçmişi / detay ekranı
3. Yeni hatırlatma ekleme ekranı
4. Aile paylaşımı / household davet ekranı (asıl farklılaştırma burada — atlama)
5. Ana ekran veya bildirim örneği (hatırlatma push'u)

Marketing metni/overlay eklemek istersen (ör. "Şimdi tüm aile" gibi) Figma'da veya basit bir Canva şablonuyla üstüne bindirebilirsin — zorunlu değil ama dönüşümü artırır.

- [x] Screenshot'ları çek (cihaz/simülatör gerekiyor — sende)

---

## 2. App Store Connect kaydı

### 2.1 Yeni app oluşturma

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → giriş yap.
2. Üst menüden **My Apps** → sol üstteki **+** butonuna tıkla → **New App**.
3. Açılan formda:
   - **Platforms**: `iOS` kutucuğunu işaretle.
   - **Name**: `OurGarage: Car Maintenance` (bölüm 3'teki App Name).
   - **Primary Language**: `English (U.S.)`.
   - **Bundle ID**: dropdown'dan `com.ourgarage.ourgarage` seç. Listede görünmüyorsa önce [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers) üzerinden bu Bundle ID'yi bir **App ID** olarak register etmen gerekir (Identifiers → + → App IDs → App → Bundle ID: Explicit → `com.ourgarage.ourgarage`).
   - **SKU**: `ourgarage-ios-2026` (bkz. aşağıdaki not).
   - **User Access**: `Full Access` (varsayılan bırakılabilir).
4. **Create** butonuna tıkla.

- [x] SKU belirle: `ourgarage-ios-2026` (yalnızca App Store Connect içinde kullanılan, kullanıcıya görünmeyen bir iç kod — yukarıdaki formda giriliyor, ayrı bir yerde tekrar ayarlamana gerek yok)
- [x] Primary language: English (US) — hedef pazar EN (yukarıdaki formda ayarlandı)
- [x] Kategori: App oluşturduktan sonra sol menüden **App Information** sayfasına git → **Category** bölümünde **Primary**: `Utilities`, **Secondary** (opsiyonel): `Lifestyle` seç → sağ üstten **Save**.

---

## 3. Listing metni

Bu metinler App Store Connect'te: sol menü → **App Store** sekmesi altında ilgili dil sürümüne tıklayınca (veya **Distribution** → sürüm sayfası) açılan formlara giriliyor. Aşağıdaki 4 alan aynı sayfada, üst üste sıralı şekilde bulunur.

**App Name (30 karakter sınırı):**
`OurGarage: Car Maintenance`

**Subtitle (30 karakter):**
`Family Car Care & Reminders` — "family" kelimesi farklılaştırmayı ilk satırda taşıyor.

**Promotional Text (170 karakter, opsiyonel ama önerilir — App Description'ın üstünde görünür, build submit edilmeden değiştirilebilir):**
`Track every vehicle your family drives in one shared garage. Get reminders before service is due, and share the history with your whole household.`

**Keywords (100 karakter, virgülle ayrılmış, boşluk yok):**
ASO actor datasındaki opportunity skoru yüksek terimleri buraya koy — elimde tam liste yok, actor çıktısını kontrol edip şunun etrafında şekillendir:
`car maintenance,oil change,vehicle log,service reminder,family car,auto tracker,car care`
(App Name/Subtitle'da geçen kelimeleri keyword alanına tekrar koyma, indexleme onları zaten kapsıyor — yer israfı olur.)

**Description taslağı:**
```
The only car maintenance app built for the whole household.

Track every vehicle your family drives — not just your own — in one shared
garage. Get reminders before oil changes, inspections, and tune-ups are
due, and keep a full service history for every car.

FAMILY SHARING
Invite your household. Everyone sees the same reminders, the same
history, no more "did you get the oil changed?" texts.

MULTI-VEHICLE
Track unlimited cars, trucks, and motorcycles in one place.

SERVICE HISTORY
Log every repair and service with cost, mileage, and notes — searchable
whenever you need it (insurance claims, resale, warranty).

SMART REMINDERS
Mileage- or date-based reminders that actually fit how you drive.

Free to start with one vehicle. Upgrade for unlimited vehicles and
family sharing.

OURGARAGE PREMIUM
- Lifetime — $9.99 one-time purchase, unlocks unlimited vehicles and
  household sharing forever.
- Annual — $4.99/year, auto-renewing subscription with the same features.
  Payment is charged to your Apple ID at confirmation. Subscriptions
  automatically renew unless auto-renew is turned off at least 24 hours
  before the end of the current period. Manage or cancel anytime in
  Settings > [your name] > Subscriptions.

Terms of Use (EULA): https://seralifatih.github.io/ourgarage/ourgarage/terms/
Privacy Policy: https://seralifatih.github.io/ourgarage/ourgarage/privacy/
```

**Guideline 3.1.2(c) reddi buradan geliyordu — düzeltildi:** Apple, uygulama içindeki Terms/Privacy linklerini yeterli görmüyor, App Store **metadata**'sında (Description veya EULA alanı) da fonksiyonel bir link istiyor. Yukarıdaki "OURGARAGE PREMIUM" bloğu + linkler artık Description'ın sonunda — Description alanını güncellerken bunu da ekle.

**What's New (ilk sürüm için):**
`Welcome to OurGarage — track and share your family's vehicle maintenance in one place.`

**Giriş adımları:**
1. Sol menüden version'a tıkla (ör. `1.0 Prepare for Submission`).
2. **Promotional Text**, **Description**, **Keywords**, **What's New** alanlarını yukarıdaki metinlerle doldur.
3. **App Name** ve **Subtitle** alanları aynı sayfanın üst kısmında (bazı hesaplarda **App Information** sayfasında) — orada doldur.
4. Sağ üstten **Save**.

- [x] Yukarıdaki metinleri ilgili alanlara gir

---

## 4. Görsel varlıklar

- [x] App icon (1024×1024, alfa kanalsız) — [assets/icon/icon.png](assets/icon/icon.png) hazır ve `flutter_launcher_icons` ile platform ikonlarına uygulandı (önceki adımda).
- [ ] Screenshot'lar (yukarıdaki 5 görsel × gerekli boyutlar) — cihaz/simülatör gerektiriyor, bölüm 1'e bak.
- [ ] Opsiyonel: App Preview video (atlanabilir, ilk sürümde gerekli değil)

**Screenshot yükleme (görseller hazır olduğunda):**
1. Version sayfasında aşağı kaydır → **App Previews and Screenshots** bölümü.
2. Cihaz boyutunu seçen sekmeler var (`6.9" Display`, `6.5" Display` vb.) — her sekme için ayrı yükleme gerekiyor.
3. İlgili sekmede **+** ya da sürükle-bırak alanına 5 screenshot'ı sırayla yükle (App Store'da gösterilecek sıra = yükleme sırası).
4. Diğer zorunlu boyut sekmesine geç, aynı 5 görseli (o boyutta export edilmiş haliyle) tekrar yükle.
5. **Save**.

---

## 5. Privacy / Legal

Not: [lib/services/auth_service.dart](lib/services/auth_service.dart) ve household paylaşım ekranı üzerinden kod tarafında **Sign in with Apple** kullanıldığı doğrulandı — App Privacy formunda bunu işaretlemen doğru olur. Supabase Auth → Providers → Apple entegrasyonu da tamamlandı (Client ID: `com.ourgarage.ourgarage`, native id-token akışı); Apple Developer'da App ID üzerinde Sign in with Apple capability'si açık.

- [x] Privacy Policy URL (Supabase + RevenueCat kullanıldığı için: hangi veri toplanıyor — email/Sign in with Apple bilgisi, household üyelik verisi, satın alma durumu — bunları açıkça yaz). Bu bir web sayfası olmalı (basit bir statik sayfa yeterli, App Store Connect kendi barındırmıyor).
- [x] Support URL (basit bir sayfa/e-posta yeterli)

**App Privacy (Nutrition Label) formu — adım adım:**
1. Sol menüden **App Privacy** sekmesine tıkla.
2. **Get Started** (ilk kez dolduruyorsan).
3. "Do you collect data from this app?" → **Yes**.
4. Veri kategorilerini tek tek işaretle:
   - **Contact Info** → **Email Address**: kullanım amacı olarak yalnızca `App Functionality` ve `Account Creation` seç, "Linked to user" işaretle (Supabase auth email'e bağlı çalışıyor). **`Analytics` veya `Third-Party Advertising` amaçlarını İŞARETLEME.**
   - **Identifiers** → **User ID**: yalnızca `App Functionality`, "Linked to user" işaretli. **`Analytics`/`Third-Party Advertising` işaretleme.**
   - **Purchases** → **Purchase History**: yalnızca `App Functionality` seç. **`Analytics` seçme** — uygulamada hiçbir analytics/ads SDK yok (`store/privacy_nutrition_label.md`'de doğrulandı), bu amacı işaretlemek App Store Connect'in "Used for Tracking = Yes" varsaymasına yol açar.
   - Household/veri paylaşımı ile ilgili ek bir "User Content" kategorisi eklemek istersen (araç/servis kayıtları), `App Functionality` amacıyla ekleyebilirsin — zorunlu değil ama şeffaflık için önerilir.
5. Free/local-only kullanım senaryosu (hesap açmadan kullanan biri) varsa, formun altındaki açıklama kutusunda bunu ayrı belirtebilirsin: "Data collection only applies to users who create an account or make a purchase."
6. **"Do you use this data to track the user?" sorusuna → NO.** Uygulama hiçbir veriyi reklam amacıyla üçüncü taraflarla paylaşmıyor, hiçbir data broker'a satmıyor, ATT prompt'u da yok (`NSUserTrackingUsageDescription` Info.plist'te yok). Bu soru "Yes" gelmişse, formu geri açıp düzelt — **Guideline 5.1.2(i) reddinin kaynağı tam olarak bu.**
7. Her kategori için **Save**, sonra sayfa sonunda **Publish**.

**Guideline 5.1.2(i) reddi — App Tracking Transparency:** Apple, App Privacy formunda User ID/Purchase History/Email için "tracking" amacı işaretli olduğunu, ama uygulamanın ATT izni istemediğini tespit etti. Uygulama gerçekte hiçbir kullanıcıyı takip etmiyor (analytics/ads SDK'sı yok) — çözüm ATT eklemek değil, **App Privacy formundaki yanlış cevabı düzeltmek**: yukarıdaki 4 ve 6. adımları tekrar kontrol et, her veri tipi için Analytics/Advertising amaçlarının kapalı olduğundan ve "track the user" sorusunun "No" olduğundan emin ol, sonra Resolution Center'daki mesaja bu düzeltmeyi belirterek Reply'la (Apple'ın kendi mesajındaki 3 seçenekten "app does not track" seçeneği bizim durumumuz).

**Age Rating anketi:**
1. Sol menüden **Age Rating** sekmesine git (bazı hesaplarda **App Information** içinde).
2. Şiddet/yetişkin içerik/kumar vb. sorulara uygulamanın içeriğine göre `None` seçerek ilerle.
3. Uygulamada bu tarz içerik olmadığı için sonuç muhtemelen **4+** çıkacak.
4. **Save/Next** ile onayla.

**Export Compliance sorusu:**
- Bu soru genelde **her build'i yüklerken** (TestFlight/submission adımında) veya version sayfasında karşına çıkar: "Does your app use encryption?"
- Supabase/HTTPS gibi standart, platform-sağlanan şifreleme dışında özel bir kriptografi algoritması **yazmadıysanız** → **Yes** (uses encryption) → **Uses only standard/exempt encryption (HTTPS)** seçeneğini işaretle. Bu durumda ek dokümantasyon (ITSAPP) genelde istenmez ve "Exempt" statüsü otomatik onaylanır.
- Emin değilsen Apple'ın resmi rehberine bak: [Export Compliance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).

---

## 6. Fiyatlandırma / IAP (RevenueCat tarafı)

**App Store Connect'te In-App Purchase ürünleri oluşturma:**
1. Sol menüden **Monetization** → **In-App Purchases** (veya **Subscriptions**, yıllık ürün için).
2. Tek seferlik "lifetime unlock" ürünü için:
   - **In-App Purchases** → **+** → **Non-Consumable** seç.
   - **Reference Name**: `Lifetime Unlock` (iç kullanım, kullanıcı görmez).
   - **Product ID**: kod tarafındaki `AppConstants.lifetimeProductId` ile birebir aynı olmalı — gerçekte kullanılan: `ourgarage_lifetime`.
   - **Price**: **Price Schedule** üzerinden $9.99'a en yakın fiyat tier'ını seç.
   - **Display Name** / **Description**: kullanıcıya App Store'da görünecek başlık/açıklama (ör. "Lifetime Unlock" / "Unlock unlimited vehicles and family sharing, forever.").
   - Bir **screenshot** yüklemen istenir (satın alma ekranının görseli, App Review için) — uygulamanın paywall ekranından bir screenshot yeterli.
   - **Save** → sonra **Submit for Review** (ürün, app'in kendisiyle birlikte veya ayrı review'a girebilir).
3. Yıllık $4.99 ürünü için:
   - **Subscriptions** → önce bir **Subscription Group** oluştur (ör. `OurGarage Plus`).
   - Grup içinde **+** → yeni subscription: **Reference Name**: `Annual Plan`, **Product ID**: ör. `ourgarage_annual`, **Duration**: `1 Year`, **Price**: $4.99 tier.
   - Aynı şekilde Display Name/Description/screenshot doldur → **Save**.

- [x] App Store Connect'te In-App Purchase ürünleri tanımlandı: `ourgarage_lifetime` (Non-Consumable, $9.99) + `ourgarage_annual` (Auto-Renewable Subscription, $4.99/yıl). Her ikisi için Review Information ekran görüntüsü de yüklendi, ikisi de "Ready to Submit" durumunda — **ama bu, Submit for Review'a basılmış olmakla aynı şey değil**, aşağıdaki bulgu bunu netleştirdi.

**BULGU (2026-08-20, Mac'te simülatörde `flutter run` ile test edildi):** Paywall ekranı "Purchases are unavailable right now" hatası veriyor. RevenueCat SDK log'u:
```
getOfferings failed: CONFIGURATION_ERROR (code 23)
"None of the products registered in the RevenueCat dashboard could be fetched from App Store Connect
(or the StoreKit Configuration file if one is being used)."
More info: https://rev.cat/why-are-offerings-empty
```
Kod tarafı doğru — `lib/core/constants.dart` içindeki product ID'ler (`ourgarage_lifetime`, `ourgarage_annual`) ve entitlement (`premium`) RevenueCat dashboard'daki isimlerle eşleşiyor, bu kaynaklı değil. `.storekit` local config de bu testte devrede değildi (`flutter run` Xcode Run action'ı kullanmıyor, gerçek App Store Connect'e gitti).

~~En olası neden: bu checklist'teki "Submit for Review" adımı IAP ürünleri için henüz yapılmamış olabilir...~~ **DÜZELTME (2026-09-09):** Bu varsayım yanlıştı. App Review'ın kendi mesajı açıkça şunu söylüyor: *"Apple reviews In-App Purchase products in the sandbox and the In-App Purchase products do not need prior approval to function in review."* Yani IAP'lerin önceden ayrı submit edilmiş/onaylanmış olması gerekmiyor — StoreKit sandbox'ta zaten çalışması bekleniyor.

- [x] App Store Connect → Monetization → In-App Purchases: her iki ürünün durumunu kontrol et, "Ready to Submit" veya sonrası bir durumda değilse tamamla ve **Submit for Review**'a bas
- [x] Agreements, Tax, and Banking → Paid Apps sözleşmesinin imzalı/aktif olduğunu doğrula (imzalı değilse IAP hiç fetch edilemez) — **doğrulandı: Active/imzalı.**
- [x] RevenueCat dashboard'daki App Store Connect app bağlantısının bundle ID'sinin (`com.ourgarage.ourgarage`) doğru olduğunu doğrula
- [x] Yukarıdakiler düzeltildikten sonra simülatörde tekrar test et: `flutter run --dart-define-from-file=dart_defines.json -d "iPhone 16 Pro"` → paywall'a git → gerçek fiyatlar ($9.99 / $4.99) görünmeli

**İKİNCİ SUBMISSION SONUCU (2026-09-09) — 3 ayrı red geldi, hepsi çözülebilir:**

1. **Guideline 2.1(b) — Paywall'da hata mesajı (App Review'ın kendi cihazında, iPad Air 11" M3, iPadOS 26.6).** Bizim `CONFIGURATION_ERROR` bulgumuzla aynı belirti. Review ekibinin notuna göre IAP'lerin önceden onaylanmasına gerek yok — yani sorun muhtemelen StoreKit/RevenueCat senkronizasyon gecikmesiydi (Apple'ın kendi review altyapısı da bazen ilk birkaç günde metadata'yı geç çekebiliyor), ya da aşağıdaki 3.1.2(c) ve 5.1.2(i) düzeltmeleriyle birlikte yeniden submit edilince kendiliğinden düzelecek. Yeniden submit etmeden önce sandbox test hesabıyla gerçek satın alma denemesi yapmak (aşağıdaki Sandbox bölümü) bunu doğrulayacak.

2. **Guideline 3.1.2(c) — Metadata'da fonksiyonel EULA linki eksik.** Uygulama içindeki Terms/Privacy linkleri (paywall'daki `_LegalLinks`) yeterli değil — Apple, App Store **Description** veya **EULA alanının kendisinde** de bir link istiyor. **Çözüldü:** yukarıdaki Description taslağına "OURGARAGE PREMIUM" bloğu ve Terms/Privacy linkleri eklendi — Description'ı App Store Connect'te güncellerken bu bloğu da dahil et.

3. **Guideline 5.1.2(i) — App Tracking Transparency.** App Privacy formunda User ID/Purchase History/Email için muhtemelen `Analytics` amacı işaretliydi, bu da App Store Connect'in "Used for Tracking = Yes" varsaymasına yol açtı — ama uygulamada gerçekten hiçbir tracking/analytics/ads SDK'sı yok. **Çözüm, kodda değil App Privacy formunda:** aşağıdaki "App Privacy formu" adımlarını tekrar gözden geçir, her veri tipinde Analytics/Advertising amaçlarının KAPALI olduğundan ve "track the user" sorusunun **No** olduğundan emin ol.

- [ ] Description'ı yukarıdaki güncellenmiş taslakla (OURGARAGE PREMIUM bloğu + linkler dahil) App Store Connect'e gir
- [ ] App Privacy formunu aç, Analytics/Advertising amaçlarının hiçbir veri tipinde işaretli olmadığını doğrula, "track the user" sorusunu No yap, Publish et
- [ ] Resolution Center'daki mesaja Reply: 3 maddeye de değinerek ne düzeltildiğini yaz, gerekiyorsa yeni bir ekran kaydı ekle
- [ ] Yeniden submit et

**RevenueCat eşleştirmesi:**
1. [app.revenuecat.com](https://app.revenuecat.com) → ilgili proje → sol menü **Products**.
2. **+ New** → App Store Connect'te oluşturduğun `Product ID`'yi birebir aynı şekilde gir (`ourgarage_lifetime`, `ourgarage_annual`).
3. **Entitlements** sekmesinde bu ürünü ilgili entitlement'a bağla (uygulama kodundaki `purchases_flutter` entegrasyonunun kontrol ettiği entitlement ID ile eşleşmeli — kod tarafında hangi entitlement kullanıldığını sen biliyorsun, RevenueCat dashboard'daki isimle birebir aynı olmalı).
4. **Offerings** sekmesinde bu ürünleri bir offering/paywall'a ekle (varsayılan offering'e ekli değilse paywall'da görünmez).

- [x] RevenueCat dashboard'da ürünler App Store Connect ürünleriyle eşleştirildi: `premium` entitlement'ı oluşturuldu, her iki ürün de ona bağlandı; `sale` adında bir offering oluşturuldu (tek offering olduğu için otomatik "Current"), içine `Lifetime`/`Annual` paketleri eklendi. RevenueCat public SDK key (`appl_...`) `dart_defines.json` ve Codemagic `revenuecat` env grubuna girildi.

**Sandbox test hesabı:**
1. App Store Connect → sağ üstteki hesap/organizasyon menüsünden (veya sol alt) **Users and Access** → üstteki sekmelerden **Sandbox Testers**.
2. **+** → yeni bir test Apple ID oluştur (gerçek bir email olmak zorunda değil, Apple'ın kabul ettiği herhangi bir format + benzersiz olmalı, ör. `ourgarage.sandbox1@icloud.com` gibi bir isim — gerçekten var olan bir Apple ID ile çakışmasın).
3. Ülke/bölge, doğum tarihi gibi zorunlu alanları doldur → **Create**.
4. Bu hesabı gerçek cihazda **Settings → App Store → Sandbox Account** (iOS 18+) veya **Settings → Developer → Sandbox Apple Account** altında oturum açarak kullanacaksın — TestFlight aşamasında.

- [ ] Sandbox test hesabı oluştur — TestFlight'a geçince satın alma akışını bununla test edeceksin

---

## Telefon/tablet gelince yapılacaklar (bu checklist'in dışında, ayrı)

- [x] Codemagic build → TestFlight'a yükle. İlk denemelerde iki ayrı engel çıktı ve ikisi de düzeltildi: (1) proje `codemagic.yaml` yerine Codemagic'in görsel "Workflow Editor"ını kullanıyordu — "Switch to yaml configuration" ile gerçek `ios-release` workflow'una geçildi; (2) Flutter 3.44+'ın varsayılan Swift Package Manager entegrasyonu, CocoaPods tabanlı `ios/Podfile` ile çakışıp gerçek plugin'lerin (`app_links`, `purchases_flutter` vb.) hiç kurulmamasına yol açıyordu — `flutter config --no-enable-swift-package-manager` build script'ine eklendi ve doğru şekilde çözümlenmiş `ios/Podfile.lock` repoya commit edildi. Ayrıca imzalama (App Store Connect API key rolü Admin olmalı) ve `APP_STORE_APPLE_ID`/env grupları da bu süreçte kuruldu. Build başarıyla derlendi, imzalandı ve TestFlight'a yüklendi, App Store Connect işlemesini tamamladı.
- [ ] Kendi cihazında: free tek-araç akışı, reminder bildirimleri, household davet/paylaşım akışı, sandbox satın alma testi — **bloklandı**: elde bulunan iPad mini 4 (A1538) donanımsal olarak iOS 15.8.x'te kilitli, Xcode 26 ile derlenen build'leri TestFlight "iOS 16 gerekli" diyerek reddediyor (bilinen, Apple tarafında henüz resmi çözümü olmayan bir Xcode 26 kısıtlaması — bkz. üstteki not). iOS 16+ çalıştırabilen bir cihaz bulununca bu adım tamamlanacak; şimdilik fonksiyonel akış MacinCloud'daki iOS Simulator üzerinden doğrulanıyor.
- [ ] Bulunan buglar için düzeltme
- [ ] Submission'ı gönder (bu checklist'teki her şey hazırsa sadece "Submit for Review" kalır)
