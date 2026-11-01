# İndirme ve Doğrulama (Aşama 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Masaüstü uygulamada, rehber sayfasından seçilen dağıtımın ISO'sunu tek tıkla indirmek, resmi sağlama dosyasıyla SHA-256 doğrulamak ve sonucu açıkça göstermek.

**Architecture:** Saf Dart. `dart:io` `HttpClient` ile Range destekli indirme, `crypto` ile akışlı SHA-256, resmi `SHA256SUMS` dosyasının indirilip ayrıştırılması. Bir `DownloadController` (ChangeNotifier) durum makinesini yürütür, `DistroPage` onu gösterir. Web'de indirme kapalıdır. Kurulum motorları bu aşamada YOK.

**Tech Stack:** Flutter 3.47.7 / Dart ^3.5.0; tek yeni bağımlılık: `crypto` (dart.dev paketi). Rust yok (spec "Sapma" bölümü).

**Spec:** `docs/superpowers/specs/2026-11-01-besideos-app-design.md` (Hedefler: tek tıkla indirme, doğrulama; Karşı hedefler: doğrulanmamış ISO ile kurulum; Kısıtlar: Windows ISO)

## Global Constraints

- Tek yeni bağımlılık `crypto`. `http`, `dio`, `file_picker`, `path_provider`, `url_launcher` eklenmez.
- İndirme yalnız `https` ile yapılır (test sunucusu için açıkça `allowInsecureForTesting: true` parametresi gerekir, varsayılan false). Yönlendirmeler izlenir, son adres de `https` olmalı.
- Doğrulama kapalı-hata (fail closed) çalışır: sağlama değeri bulunamazsa, eşleşmezse veya hesaplanamazsa dosya "doğrulanmadı" sayılır, kurulum için işaretlenmez.
- Eşleşmeyen dosya silinir; yarım dosya `<ad>.part` olarak kalır ve yalnız devam için kullanılır.
- Dosya adı katalogdan/sağlama dosyasından gelirse temizlenir: yol ayracı (`/`, `\`), `..` içeremez.
- Windows ISO'sunu BesideOS indirmez. Windows için kullanıcı kendi ISO yolunu ve Microsoft sayfasından aldığı SHA-256'yı girer, uygulama yalnız doğrular.
- Büyük dosya belleğe tamamen yüklenmez (akış).
- İndirme düğmesi yalnız masaüstünde ve katalogda o mimari için ISO varsa etkindir; web'de gizli/kapalı ve nedeni yazılı.
- Yalnız masaüstü macOS için: `network.client` ve `files.downloads.read-write` yetkileri eklenir (sandbox yoksa indirme sessizce çalışmaz).
- Dürüstlük: kurulum motoru yok; arayüz "indirildi ve doğrulandı" der, "kuruldu" ya da "kurulum hazır" demez.
- Windows ve Linux build'leri bu makinede doğrulanamaz, README'de "doğrulanmadı" kalır.
- Bu klasör yerel git deposudur (branch `main`, remote yok); her görev kendi commit'iyle biter.

## Review Focus

- Sunucu `Range`'i yok sayıp 200 dönerse: devam etmek yerine baştan, bozuk birleştirme yok (Task 3).
- İndirme ortasında bağlantı kopması/iptal: `.part` kalır, tekrar denenince kaldığı yerden sürer (Task 3, 5).
- Sağlama dosyasında ISO adı yok / hash biçimi bozuk / büyük-küçük harf farkı: kapalı-hata veya normalize (Task 2).
- Katalogdan `../../x` benzeri dosya adı: reddedilir (Task 1, 3).
- `http://` ISO veya sağlama adresi: katalog ayrıştırmada reddedilir (Task 1).
- Disk dolu / yazma izni yok: anlaşılır hata durumu, çökme yok (Task 5).
- 0 baytlık ve 5 GB'lık dosya: bellek şişmeden doğrulanır (Task 2).

---

### Task 1: Katalog şeması: ISO kayıtları

**Files:**
- Modify: `lib/catalog/distro.dart`
- Test: `test/catalog/distro_test.dart`

**Interfaces:**
- Produces:
  - `enum IsoArch { x86_64, arm64 }`
  - `class IsoAsset { final IsoArch arch; final String url; final String checksumUrl; final String fileName; final int? sizeBytes; }`
  - `Distro.isos` : `List<IsoAsset>` (varsayılan boş; JSON anahtarı `isos`, isteğe bağlı)
  - `IsoAsset? Distro.isoFor(IsoArch arch)`
  - JSON: `{"arch":"x86_64","url":"https://…","checksumUrl":"https://…","fileName":"x.iso","sizeBytes":123}`

- [ ] **Step 1: Write failing tests**: `parses isos list`, `isos absent means empty list`, `rejects http url` (`CatalogException`, mesajda id ve `isos`), `rejects http checksumUrl`, `rejects fileName with path separator or ..` (`/`, `\`, `..`), `rejects unknown arch`, `rejects duplicate arch within a distro`, `isoFor returns null when arch missing`.
- [ ] **Step 2: Run** `flutter test test/catalog/distro_test.dart` → FAIL.
- [ ] **Step 3: Implement** `IsoAsset`, `IsoArch`, ayrıştırma ve doğrulama `distro.dart` içinde; hata mesajları `<id>: isos[<i>].<alan> ...` biçiminde.
- [ ] **Step 4: Run** aynı komut + `flutter test` → PASS.
- [ ] **Step 5: Commit** `feat(catalog): iso assets in schema`.

### Task 2: Sağlama dosyası ayrıştırma ve akışlı SHA-256

**Files:**
- Create: `lib/download/checksum.dart`
- Modify: `pubspec.yaml` (`crypto` bağımlılığı)
- Test: `test/download/checksum_test.dart`

**Interfaces:**
- Produces:
  - `Map<String, String> parseChecksums(String text)`: `SHA256SUMS` biçimi (`<64 hex>  <ad>` veya `<64 hex> *<ad>`), anahtar ad, değer küçük harfli hex; geçersiz satırlar atlanır.
  - `Future<String> sha256OfFile(File f)`: akışlı, küçük harfli hex.
  - `String? expectedHashFor(Map<String,String> sums, String fileName)`
  - `bool isSafeFileName(String name)`: izin listesi `^[A-Za-z0-9][A-Za-z0-9._+-]*$`, `..` içermez, en çok 255 karakter; `.`, boşluk, NUL, `C:x`, `%2f`, sondaki nokta/boşluk reddedilir.
  - `String? normalizeSha256(String input)`: boşluk/`sha256:` önekini atar, 64 hex değilse `null`.

- [ ] **Step 1: Write failing tests**: `parses two-space and star formats`, `ignores comments and blank and bad lines`, `uppercase hash normalized to lowercase`, `expectedHashFor missing name returns null`, `sha256OfFile of empty file equals e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`, `sha256OfFile of "abc" equals ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`, `sha256OfFile streams a 20 MB file` (geçici dosya, bellek testi değil, doğru hash), `normalizeSha256 rejects 63 chars and non-hex`, `isSafeFileName accepts ubuntu-24.04-desktop-amd64.iso and rejects "..", ".", "a/b", "a\\b", "C:x.iso", "a b", NUL, "%2f", trailing dot, 256 chars`.
- [ ] **Step 2: Run** `flutter test test/download/checksum_test.dart` → FAIL.
- [ ] **Step 3: Implement** `lib/download/checksum.dart`; `crypto`'nun `sha256.bind(file.openRead())` akış API'sini kullan.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(download): checksum parsing and streaming sha256`.

### Task 3: Devam edebilen indirici

**Files:**
- Create: `lib/download/downloader.dart`
- Test: `test/download/downloader_test.dart`

**Interfaces:**
- Consumes: yok
- Produces:
  - `class DownloadCancelled implements Exception`, `class DownloadException implements Exception { final String message; }`
  - `class Downloader { Downloader({bool allowInsecureForTesting = false, HttpClient? client}); Future<File> download(Uri url, File dest, {void Function(int received, int? total)? onProgress, CancelToken? cancel}); }`
  - `class CancelToken { bool get isCancelled; void cancel(); }`
  - Davranış: `dest.path + '.part'` yazılır, bitince `dest`'e rename. Mevcut `.part` varsa `Range: bytes=<boyut>-`. 206 → ekle, 200 → baştan yaz (`.part` sıfırlanır), 416 ve `.part` tam boyutta ise tamamlanmış say, başka kodlar `DownloadException`. Yalnız `https` (veya `allowInsecureForTesting` ile `http`), yönlendirme sonrası son adres de aynı kurala tabi.

- [ ] **Step 1: Write failing tests** yerel `HttpServer` (loopback) ile: `downloads full file and reports progress`, `resumes from existing .part using Range (206)`, `server ignoring Range (200) restarts from zero without corrupt result`, `non-200 non-206 throws DownloadException`, `cancel keeps .part and throws DownloadCancelled`, `rejects http url when allowInsecureForTesting is false`, `follows redirect and rejects redirect to http`, `completes when .part already full and server says 416`.
- [ ] **Step 2: Run** `flutter test test/download/downloader_test.dart` → FAIL.
- [ ] **Step 3: Implement** `Downloader`; yanıt gövdesi `IOSink`'e akıtılır, `onProgress` her yığında çağrılır, iptal her yığında denetlenir. Yönlendirmeleri elle izle (en çok 5), her adımda şemayı denetle.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(download): resumable https downloader`.

### Task 4: ISO doğrulayıcı

**Files:**
- Create: `lib/download/iso_verifier.dart`
- Test: `test/download/iso_verifier_test.dart`

**Interfaces:**
- Consumes: `sha256OfFile`, `normalizeSha256` (Task 2)
- Produces:
  - `enum VerifyOutcome { ok, mismatch, unreadable }`
  - `class VerifyResult { final VerifyOutcome outcome; final String? actual; final String? expected; }`
  - `Future<VerifyResult> verifyIso(File f, String expectedSha256)`: beklenen değer geçersizse `unreadable`; eşleşmezse dosyayı SİLER ve `mismatch` döner; dosya yoksa `unreadable`.

- [ ] **Step 1: Write failing tests**: `ok when hash matches (case-insensitive expected)`, `mismatch deletes the file and returns both hashes`, `invalid expected hash returns unreadable and keeps file`, `missing file returns unreadable`.
- [ ] **Step 2: Run** `flutter test test/download/iso_verifier_test.dart` → FAIL.
- [ ] **Step 3: Implement** `verifyIso`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(download): iso verifier`.

### Task 5: Akış denetleyicisi

**Files:**
- Create: `lib/download/download_controller.dart`
- Test: `test/download/download_controller_test.dart`

**Interfaces:**
- Consumes: `Downloader`, `CancelToken`, `parseChecksums`, `expectedHashFor`, `verifyIso`, `IsoAsset` (Task 1-4)
- Produces:
  - `enum DownloadPhase { idle, fetchingChecksum, downloading, verifying, verified, mismatch, failed, cancelled }`
  - `class DownloadController extends ChangeNotifier { DownloadController({required Downloader downloader, required Directory targetDir}); DownloadPhase get phase; int get received; int? get total; String? get error; File? get file; Future<void> start(IsoAsset iso); void cancel(); }`
  - `Future<void> startWithManualHash(File isoFile, String expectedSha256)`: Windows "kendi ISO'm" yolu, yalnız doğrular.
  - Hedef: `targetDir/<fileName>` (`isSafeFileName` yazma noktasında yeniden denetlenir, katalog doğrulamasına güvenilmez) (`targetDir` yoksa oluşturulur); `defaultDownloadDir()` → `HOME/Downloads/BesideOS` (Windows `USERPROFILE`), ortam değişkeni yoksa `Directory.systemTemp/BesideOS`.

- [ ] **Step 1: Write failing tests** (sahte yerel sunucu): `happy path ends verified with matching checksum file`, `checksum file missing the iso name ends failed (fail closed)`, `hash mismatch ends mismatch and deletes file`, `network error ends failed with message`, `cancel ends cancelled and keeps .part`, `restart after cancel resumes`, `unwritable target dir ends failed without throwing`, `startWithManualHash ok and mismatch`, `unsafe iso fileName (e.g. 'C:x.iso', '.', 'a b') ends failed before any network call`, `phases notified in order` (dinleyici sırası).
- [ ] **Step 2: Run** `flutter test test/download/download_controller_test.dart` → FAIL.
- [ ] **Step 3: Implement** `DownloadController` ve `defaultDownloadDir`; tüm hatalar `failed` durumuna ve Türkçe `error` metnine çevrilir, hiçbiri dışarı fırlatılmaz.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(download): download controller state machine`.

### Task 6: Rehber sayfasında indirme arayüzü ve macOS yetkileri

**Files:**
- Modify: `lib/catalog/distro_page.dart`, `macos/Runner/DebugProfile.entitlements`, `macos/Runner/Release.entitlements`
- Create: `lib/download/download_section.dart`
- Test: `test/download/download_section_test.dart`

**Interfaces:**
- Consumes: `DownloadController`, `Distro.isoFor`, `IsoArch`, `kIsWeb`
- Produces: `class DownloadSection extends StatefulWidget { const DownloadSection({required Distro distro, DownloadController Function()? controllerFactory, IsoArch? hostArch, bool? isWeb}); }` (varsayılan `hostArch` = `Abi.current()` eşlemesi, varsayılan `isWeb` = `kIsWeb`); `DistroPage` içinde mevcut devre dışı "İndir (sonraki aşamada)" düğmesinin yerine geçer.

- [ ] **Step 1: Write failing widget tests** (sahte controller): `web build shows disabled button with reason` (kIsWeb simülasyonu için `isWeb` parametresi), `enabled button when iso exists for host arch`, `shows "bu mimari için ISO yok" when arch missing`, `progress bar and percentage while downloading`, `verified state says "İndirildi ve doğrulandı", not "kuruldu"`, `mismatch state shows both hashes and a retry button`, `windows distro shows path and SHA-256 fields and verify button, no download button`, `cancel button works`, `no overflow at 320x640`.
- [ ] **Step 2: Run** `flutter test test/download/download_section_test.dart` → FAIL.
- [ ] **Step 3: Implement** `DownloadSection` ve `DistroPage`'e bağla; entitlements dosyalarına `com.apple.security.network.client` ve `com.apple.security.files.downloads.read-write` ekle (her ikisi de `<true/>`).
- [ ] **Step 4: Run** `flutter test` ve `flutter analyze` → tümü geçer.
- [ ] **Step 5: Commit** `feat(app): download section on distro page`.

### Task 7: Gerçek ISO verisi, doğrulama ve README

**Files:**
- Modify: `assets/catalog/catalog.json`, `README.md`
- Test: `test/catalog/bundled_catalog_test.dart`

**Interfaces:**
- Consumes: `IsoAsset` şeması (Task 1)
- Produces: ubuntu, linux-mint, fedora, debian için `isos` (x86_64 zorunlu; resmi arm64 varsa o da); `windows-11` için `isos` YOK.

- [ ] **Step 1: Write failing test** `bundled isos are https, have checksumUrl, safe fileName, and windows has none`; `every non-windows distro has an x86_64 iso`.
- [ ] **Step 2: Run** `flutter test test/catalog/bundled_catalog_test.dart` → FAIL.
- [ ] **Step 3: Fill data**: her URL ve sağlama adresi resmi dağıtım sunucusundan alınır ve `curl -sI -L` ile 200 döndüğü ve sağlama dosyasının ISO adını içerdiği doğrulanır (çıktı rapora yazılır). Sürüm numarası uydurulmaz; doğrulanamayan dağıtım `isos` olmadan bırakılır ve raporda belirtilir. README'ye indirme davranışı, hedef klasör ve "kurulum motoru yok" notu eklenir.
- [ ] **Step 4: Run** `flutter test`, `flutter analyze`, `flutter build web --release --no-web-resources-cdn`, `flutter build macos --release` → hepsi başarılı.
- [ ] **Step 5: Commit** `feat(catalog): real iso entries; docs`.
