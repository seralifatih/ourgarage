# OurGarage — App Store Submission Checklist

Not: TestFlight/gerçek cihaz testi hâlâ eksik (iPhone bekleniyor). Bu checklist cihaz gerektirmeyen her şeyi kapsıyor; en alt bölümde iPhone gelince yapılacaklar ayrı listelendi.

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

- [ ] Screenshot'ları çek (cihaz/simülatör gerekiyor — sende)

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

- [ ] SKU belirle: `ourgarage-ios-2026` (yalnızca App Store Connect içinde kullanılan, kullanıcıya görünmeyen bir iç kod — yukarıdaki formda giriliyor, ayrı bir yerde tekrar ayarlamana gerek yok)
- [ ] Primary language: English (US) — hedef pazar EN (yukarıdaki formda ayarlandı)
- [ ] Kategori: App oluşturduktan sonra sol menüden **App Information** sayfasına git → **Category** bölümünde **Primary**: `Utilities`, **Secondary** (opsiyonel): `Lifestyle` seç → sağ üstten **Save**.

---

## 3. Listing metni

Bu metinler App Store Connect'te: sol menü → **App Store** sekmesi altında ilgili dil sürümüne tıklayınca (veya **Distribution** → sürüm sayfası) açılan formlara giriliyor. Aşağıdaki 4 alan aynı sayfada, üst üste sıralı şekilde bulunur.

**App Name (30 karakter sınırı):**
`OurGarage: Car Maintenance`

**Subtitle (30 karakter):**
`Family Car Care & Reminders` — "family" kelimesi farklılaştırmayı ilk satırda taşıyor.

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
```

**What's New (ilk sürüm için):**
`Welcome to OurGarage — track and share your family's vehicle maintenance in one place.`

**Giriş adımları:**
1. Sol menüden version'a tıkla (ör. `1.0 Prepare for Submission`).
2. **Promotional Text** (opsiyonel, atlanabilir), **Description**, **Keywords**, **What's New** alanlarını yukarıdaki metinlerle doldur.
3. **App Name** ve **Subtitle** alanları aynı sayfanın üst kısmında (bazı hesaplarda **App Information** sayfasında) — orada doldur.
4. Sağ üstten **Save**.

- [ ] Yukarıdaki metinleri ilgili alanlara gir

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

Not: [lib/services/auth_service.dart](lib/services/auth_service.dart) ve household paylaşım ekranı üzerinden kod tarafında **Sign in with Apple** kullanıldığı doğrulandı — App Privacy formunda bunu işaretlemen doğru olur.

- [ ] Privacy Policy URL (Supabase + RevenueCat kullanıldığı için: hangi veri toplanıyor — email/Sign in with Apple bilgisi, household üyelik verisi, satın alma durumu — bunları açıkça yaz). Bu bir web sayfası olmalı (basit bir statik sayfa yeterli, App Store Connect kendi barındırmıyor).
- [ ] Support URL (basit bir sayfa/e-posta yeterli)

**App Privacy (Nutrition Label) formu — adım adım:**
1. Sol menüden **App Privacy** sekmesine tıkla.
2. **Get Started** (ilk kez dolduruyorsan).
3. "Do you collect data from this app?" → **Yes**.
4. Veri kategorilerini tek tek işaretle:
   - **Contact Info** → **Email Address**: kullanım amacı olarak `App Functionality` ve `Account Creation` seç, "Linked to user" işaretle (Supabase auth email'e bağlı çalışıyor).
   - **Identifiers** → **User ID**: Sign in with Apple/Supabase user identifier için, `App Functionality`, "Linked to user" işaretli.
   - **Purchases** → **Purchase History**: RevenueCat üzerinden satın alma durumu takip ediliyor, kategori olarak `App Functionality`/`Analytics` (RevenueCat'in kendi analytics kullanımına göre) seç.
   - Household/veri paylaşımı ile ilgili ek bir "User Content" kategorisi eklemek istersen (araç/servis kayıtları), `App Functionality` amacıyla ekleyebilirsin — zorunlu değil ama şeffaflık için önerilir.
5. Free/local-only kullanım senaryosu (hesap açmadan kullanan biri) varsa, formun altındaki açıklama kutusunda bunu ayrı belirtebilirsin: "Data collection only applies to users who create an account or make a purchase."
6. Her kategori için **Save**, sonra sayfa sonunda **Publish**.

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
   - **Product ID**: RevenueCat'te kullanacağın ID ile aynı olmalı, ör. `ourgarage_lifetime_unlock`.
   - **Price**: **Price Schedule** üzerinden $9.99'a en yakın fiyat tier'ını seç.
   - **Display Name** / **Description**: kullanıcıya App Store'da görünecek başlık/açıklama (ör. "Lifetime Unlock" / "Unlock unlimited vehicles and family sharing, forever.").
   - Bir **screenshot** yüklemen istenir (satın alma ekranının görseli, App Review için) — uygulamanın paywall ekranından bir screenshot yeterli.
   - **Save** → sonra **Submit for Review** (ürün, app'in kendisiyle birlikte veya ayrı review'a girebilir).
3. Yıllık $4.99 ürünü için:
   - **Subscriptions** → önce bir **Subscription Group** oluştur (ör. `OurGarage Plus`).
   - Grup içinde **+** → yeni subscription: **Reference Name**: `Annual Plan`, **Product ID**: ör. `ourgarage_annual`, **Duration**: `1 Year`, **Price**: $4.99 tier.
   - Aynı şekilde Display Name/Description/screenshot doldur → **Save**.

- [ ] App Store Connect'te In-App Purchase ürünleri tanımla: $9.99 tek seferlik lifetime unlock + $4.99/yıl opsiyonel

**RevenueCat eşleştirmesi:**
1. [app.revenuecat.com](https://app.revenuecat.com) → ilgili proje → sol menü **Products**.
2. **+ New** → App Store Connect'te oluşturduğun `Product ID`'yi birebir aynı şekilde gir (ör. `ourgarage_lifetime_unlock`).
3. **Entitlements** sekmesinde bu ürünü ilgili entitlement'a bağla (uygulama kodundaki `purchases_flutter` entegrasyonunun kontrol ettiği entitlement ID ile eşleşmeli — kod tarafında hangi entitlement kullanıldığını sen biliyorsun, RevenueCat dashboard'daki isimle birebir aynı olmalı).
4. **Offerings** sekmesinde bu ürünleri bir offering/paywall'a ekle (varsayılan offering'e ekli değilse paywall'da görünmez).

- [ ] RevenueCat dashboard'da bu ürünleri App Store Connect ürünleriyle eşleştir

**Sandbox test hesabı:**
1. App Store Connect → sağ üstteki hesap/organizasyon menüsünden (veya sol alt) **Users and Access** → üstteki sekmelerden **Sandbox Testers**.
2. **+** → yeni bir test Apple ID oluştur (gerçek bir email olmak zorunda değil, Apple'ın kabul ettiği herhangi bir format + benzersiz olmalı, ör. `ourgarage.sandbox1@icloud.com` gibi bir isim — gerçekten var olan bir Apple ID ile çakışmasın).
3. Ülke/bölge, doğum tarihi gibi zorunlu alanları doldur → **Create**.
4. Bu hesabı gerçek cihazda **Settings → App Store → Sandbox Account** (iOS 18+) veya **Settings → Developer → Sandbox Apple Account** altında oturum açarak kullanacaksın — TestFlight aşamasında.

- [ ] Sandbox test hesabı oluştur — TestFlight'a geçince satın alma akışını bununla test edeceksin

---

## Telefon gelince yapılacaklar (bu checklist'in dışında, ayrı)

- [ ] Codemagic build → TestFlight'a yükle
- [ ] Kendi cihazında: free tek-araç akışı, reminder bildirimleri, household davet/paylaşım akışı, sandbox satın alma testi
- [ ] Bulunan buglar için düzeltme
- [ ] Submission'ı gönder (bu checklist'teki her şey hazırsa sadece "Submit for Review" kalır)
