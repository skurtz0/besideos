# Katalog ve Dağıtım Rehberi (Aşama 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dağıtım kataloğunu ve her dağıtımın rehber sayfasını, aynı Flutter kodundan hem `besideos.com` sitesinde hem masaüstü uygulamada göstermek (yalnız frontend).

**Architecture:** Tek bir JSON katalog dosyası asset olarak paketlenir. `Catalog.parse` onu doğrulayıp modele çevirir. Katalog sayfası listeyi, dağıtım sayfası açıklama, görünüş, rehber adımlarını ve destek matrisini gösterir. İndirme ve kurulum bu aşamada YOK.

**Tech Stack:** Flutter 3.47.7 / Dart ^3.5.0, yeni bağımlılık yok (yönlendirme `onGenerateRoute` ile).

**Spec:** `docs/superpowers/specs/2026-11-01-besideos-app-design.md` (bölümler: Katalog alanları, Sıra 1, Hedef olmayanlar)

## Global Constraints

- Yeni paket bağımlılığı eklenmez.
- Katalog hiçbir yerde "macOS'u konuk olarak kurma" veya "Apple Silicon Mac yanına Windows" iddia etmez; bunlar `unsupported` olarak nedenleriyle gösterilir.
- Windows için doğrudan ISO bağlantısı yok; yalnız Microsoft'un resmi indirme sayfası ve "kendi ISO'nu seç" notu.
- Mac→Linux yalnız Apple Silicon M1/M2 için "desteklenir"; M3 ve sonrası desteklenmez.
- Mevcut koyu tema renkleri (`_bg`, `_panel`, `_text`, `_muted`, `_accent`) yeniden kullanılır; ikinci bir tema yazılmaz.
- Görünüş için telifli ekran görüntüsü kullanılmaz; metin açıklama + vurgu rengi.
- Bu klasör git deposu değil; "commit" yerine her görev sonunda `SECOND_HAND.md`'ye bir satır yazılır.

## Review Focus

- Boş `distros` listesi: katalog sayfası çökmez, "katalog boş" gösterir (Task 4).
- Aynı `id` iki kez: parse hata verir (Task 1).
- Bilinmeyen `family` değeri: parse hata verir, sessizce yutulmaz (Task 1).
- İsteğe bağlı alan (`screenshotsNote`, `download.page`) yok: model null döner, sayfa çökmez (Task 1, 5).
- Dar ekranda (320 px) kart ve rehber taşmaz (Task 4, 5).
- Bilinmeyen rota `/distros/yok`: "Bulunamadı" sayfası, çökme yok (Task 5).

---

### Task 1: Model ve doğrulayıcı

**Files:**
- Create: `lib/catalog/distro.dart`
- Test: `test/catalog/distro_test.dart`

**Interfaces:**
- Produces:
  - `enum DistroFamily { linux, windows }`
  - `class GuideStep { final String title; final String body; }`
  - `class Distro { final String id; final String name; final DistroFamily family; final String tagline; final String description; final String bestFor; final String? desktop; final String look; final int accent; final List<GuideStep> guide; final List<String> requirements; final List<String> hosts; final String downloadPage; final bool userSuppliedIso; final String license; }`
  - `class Catalog { final List<Distro> distros; static Catalog parse(String json); Distro? byId(String id); }`
  - `class CatalogException implements Exception { final String message; }`

- [ ] **Step 1: Write failing tests** in `test/catalog/distro_test.dart`: `parses a valid catalog` (1 distro, alanlar eşleşir, `byId('a')` döner), `rejects duplicate ids` (`CatalogException`), `rejects unknown family` (`family: "bsd"` → `CatalogException`), `rejects empty id`, `optional desktop may be null`, `byId unknown returns null`, `empty distros list parses`.
- [ ] **Step 2: Run** `flutter test test/catalog/distro_test.dart` → FAIL (dosya yok).
- [ ] **Step 3: Implement** `distro.dart`. `parse` önce `jsonDecode`, her zorunlu alanı tür kontrolüyle okur, eksik/yanlış tür için `CatalogException('<id veya index>: <alan> ...')`. `hosts` değerleri yalnız `windows`, `linux`, `mac-m1m2` olabilir, başkası `CatalogException`.
- [ ] **Step 4: Run** aynı komut → PASS.
- [ ] **Step 5: Checkpoint** `SECOND_HAND.md`'ye "Task 1 model hazır" satırı.

### Task 2: Destek matrisi

**Files:**
- Create: `lib/catalog/support_matrix.dart`
- Test: `test/catalog/support_matrix_test.dart`

**Interfaces:**
- Consumes: `DistroFamily` (Task 1)
- Produces:
  - `enum Host { windows, linux, macM1M2, macOther }`
  - `class SupportEntry { final bool supported; final String reason; }`
  - `SupportEntry supportFor(Host host, DistroFamily guest)`
  - `const List<MapEntry<String, SupportEntry>> unsupportedTargets` (macOS konuk, vb., gösterim için)

- [ ] **Step 1: Write failing tests**: `windows→linux supported`, `linux→windows supported`, `windows→windows supported`, `macM1M2→linux supported`, `macM1M2→windows unsupported` (reason "Apple Silicon" içerir), `macOther→linux unsupported` (reason "M1/M2" içerir), `macOther→windows unsupported`, `linux→linux unsupported` (spec'te Linux yanına Linux yok; reason "kapsam dışı" içerir).
- [ ] **Step 2: Run** → FAIL. 
- [ ] **Step 3: Implement** `supportFor` bir `switch` ile; her `reason` Türkçe, nedeni açıklar.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Checkpoint** SECOND_HAND.md satırı.

### Task 3: Katalog verisi

**Files:**
- Create: `assets/catalog/catalog.json`
- Modify: `pubspec.yaml` (`flutter: assets: - assets/catalog/`)
- Test: `test/catalog/bundled_catalog_test.dart`

**Interfaces:**
- Consumes: `Catalog.parse`, `Distro` (Task 1)
- Produces: `assets/catalog/catalog.json`, sürüm anahtarı yok; en az 5 dağıtım: `ubuntu`, `linux-mint`, `fedora`, `debian` (family linux), `windows-11` (family windows, `userSuppliedIso: true`).

- [ ] **Step 1: Write failing test** `bundled catalog parses and is sane`: `rootBundle.loadString('assets/catalog/catalog.json')` → `Catalog.parse`; `distros.length >= 5`; her `id` benzersiz küçük harf/tire; `windows-11.userSuppliedIso == true`; hiçbir Windows kaydında `downloadPage` `.iso` ile bitmez; her kayıtta `guide.length >= 3` ve `hosts` boş değil; hiçbir kayıtta `hosts` içinde `macos` yok.
- [ ] **Step 2: Run** → FAIL (asset yok).
- [ ] **Step 3: Write** `catalog.json`. Bağlantılar yalnız resmi indirme sayfaları (ubuntu.com/download/desktop, linuxmint.com/download.php, fedoraproject.org/workstation/download, debian.org/distrib, microsoft.com/software-download/windows11). Boyut, hash ve sürüm numarası YAZILMAZ (Aşama 2). Açıklamalar bilinen, doğrulanabilir bilgidir (ör. Ubuntu GNOME, Mint Cinnamon); emin olunmayan teknik iddia yazılmaz.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Checkpoint** SECOND_HAND.md satırı.

### Task 4: Katalog sayfası

**Files:**
- Create: `lib/catalog/catalog_page.dart`
- Test: `test/catalog/catalog_page_test.dart`

**Interfaces:**
- Consumes: `Catalog`, `Distro`, `DistroFamily`, `Host`, `supportFor` (Task 1–2)
- Produces: `class CatalogPage extends StatefulWidget { const CatalogPage({required this.catalog, required this.onOpen}); final Catalog catalog; final void Function(Distro) onOpen; }`

- [ ] **Step 1: Write failing widget tests**: `lists every distro name`, `family filter shows only windows`, `host filter "Mac M1/M2" hides windows distros`, `empty catalog shows "Katalog boş"`, `does not overflow at 320x640` (hata fırlamaz), `tapping a card calls onOpen with that distro`.
- [ ] **Step 2: Run** `flutter test test/catalog/catalog_page_test.dart` → FAIL.
- [ ] **Step 3: Implement** `CatalogPage`: ailelere göre `FilterChip` + ana sistem seçici (`Host`), `Wrap` kart ızgarası; kartta ad, `tagline`, vurgu rengi şeridi. Filtre `supportFor(host, distro.family).supported` ile yapılır. Mevcut `_bg`/`_panel` renkleri `main.dart`'tan ortak `lib/theme.dart`'a taşınır (tek değişiklik, mevcut test geçmeli).
- [ ] **Step 4: Run** bu test + `flutter test` → PASS.
- [ ] **Step 5: Checkpoint** SECOND_HAND.md satırı.

### Task 5: Dağıtım rehberi sayfası ve rotalar

**Files:**
- Create: `lib/catalog/distro_page.dart`, `lib/catalog/routes.dart`
- Test: `test/catalog/distro_page_test.dart`

**Interfaces:**
- Consumes: `Catalog`, `Distro`, `supportFor`, `unsupportedTargets`, `CatalogPage` (Task 1–4)
- Produces:
  - `class DistroPage extends StatelessWidget { const DistroPage({required this.distro}); final Distro distro; }`
  - `Route<dynamic> catalogRoute(RouteSettings s, Catalog catalog)`: `/distros` → `CatalogPage`, `/distros/<id>` → `DistroPage`, bilinmeyen id → "Bulunamadı" sayfası.

- [ ] **Step 1: Write failing tests**: `shows name, description, look and every guide step`, `shows supported hosts`, `download button is disabled and says it arrives in the next stage`, `windows distro shows the bring-your-own-ISO note`, `unknown id route shows "Bulunamadı"`, `/distros route shows the catalog`, `no overflow at 320x640`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `DistroPage` (başlık, `look` bölümü vurgu rengiyle, numaralı rehber adımları, gereksinimler, destek matrisi, resmi sayfa bağlantısı metni, devre dışı "İndir (yakında)" düğmesi) ve `catalogRoute`.
- [ ] **Step 4: Run** bu test + `flutter test` → PASS.
- [ ] **Step 5: Checkpoint** SECOND_HAND.md satırı.

### Task 6: Ana sayfaya bağlama, masaüstü platformları, doğrulama

**Files:**
- Modify: `lib/main.dart` (rota ve `Catalog` yükleme, ana sayfada "Dağıtımlara göz at" bağlantısı), `README.md`
- Test: `test/widget_test.dart` (mevcut), `test/catalog/navigation_test.dart`

**Interfaces:**
- Consumes: `Catalog.parse`, `catalogRoute` (Task 1, 5)
- Produces: `BesideSite({Catalog? catalog})` (testte katalog enjekte edilir, verilmezse asset'ten yüklenir)

- [ ] **Step 1: Write failing test** `home link opens catalog, tapping a distro opens its guide` (`navigation_test.dart`, küçük sahte katalog ile).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `BesideSite.onGenerateRoute`: `/` ana sayfa, `/distros...` `catalogRoute`. Katalog yüklenemezse (parse hatası) hata sayfası, boş ekran değil. Ana sayfa hero'suna bağlantı ekle.
- [ ] **Step 4: Run** `flutter create . --platforms windows,macos,linux --project-name besideos_site`, sonra `flutter pub get && flutter analyze && flutter test` → "No issues", tüm testler PASS.
- [ ] **Step 5: Build doğrulaması**: `flutter build web --release --no-web-resources-cdn` ve `flutter build macos --release` başarılı; tarayıcıda `/distros` ve `/distros/ubuntu` açılır (kaydır, 375 px ve masaüstü). Windows/Linux build'i bu makinede çalıştırılamaz, README'de "doğrulanmadı" yazılır.
- [ ] **Step 6: Checkpoint** README (imzasız dağıtım uyarısı dahil değil, o Aşama 2) ve SECOND_HAND.md güncellenir.
