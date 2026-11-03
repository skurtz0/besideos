# BesideOS: nerede kaldık (3 Kasım 2026)

Bu dosya, projeye başka bir bilgisayarda (ör. Linux'ta Claude ile) devam etmek için yazıldı.

## Proje

- **Site + Windows uygulaması:** Flutter (`lib/`), tek kod tabanı. Site: https://besideos.pages.dev (Cloudflare Pages, Direct Upload). Uygulama: `BesideOS.exe` (Windows, tam ekran açılır).
- **Planlayıcı:** Rust, `core/besideos_core` (`besideos-plan`). Çıkış kodları: 0 plan, 2 ret, 1 hata.
- **Motor:** `probe/windows/*.ps1` (Windows PowerShell 5.1, yalnızca ASCII): `collect-host-facts`, `inspect-iso`, `apply-plan`, `boot-entries`.
- **Katalog:** `assets/catalog/catalog.json` (21 sistem), ekran görüntüleri `assets/screens/`.
- Derleme (Windows): `tool\build_windows.ps1` (Rust planlayıcı + Flutter + `engine/` klasörü). Testler: `flutter test` (208), `cargo test` (core).

## Ne yapar

Windows'ta bir bölümü küçültür, ISO'yu FAT32 `BESIDEOS` bölümüne açar, tek seferlik UEFI girişi ekler. Yeniden başlatmayı **kullanıcı** yapar (uygulama kendiliğinden başlatmaz).

- Linux ISO'ları: `{bootmgr}` kopyası girişle doğrudan yükleyiciyi açar. ISO etiketine/UUID'ye bakan sistemler için açılış ayarları `BESIDEOS` etiketine çevrilir (`Update-BootLabel`).
- Windows ISO'ları (`sources\boot.wim` + `boot\boot.sdi`): `{bootmgr}` kopyası **çalışmaz** (0xc0000034). Bunun yerine RAM disk girişi (`ramdisk=[D:]\sources\boot.wim`, `winpe yes`) yazılır; geri alma iki nesneyi de siler. 4 GiB üstü `install.wim`, DISM ile `install.swm` parçalarına bölünür.
- Geri alma: uygulamadaki "Geri al" ya da `apply-plan.ps1 -Undo -Execute`. Durum dosyası `%LOCALAPPDATA%\BesideOS\work\apply-state.json`.
- Açılış sistemi sayfası (`/boot`, yalnızca uygulama): kurulu sistemleri listeler, "bir sonraki açılışta" ya da "hep bunu aç" seçtirir.

## Doğrulananlar (gerçek bilgisayarda)

- Linux Mint ISO'su: ön kontrol, plan, `E:` veri diskinde gerçek kurulum hazırlığı ve geri alma. Sonradan kullanıcı Mint'i kurmuş görünüyor (diskte 30 GiB'lık Linux bölümü var); **Mint'in açılıp açılmadığı henüz bilinmiyor.**
- Windows 8.1 (TR) ISO'su: RAM disk girişiyle Windows Kurulum ekranı geldi. Kurulum bilerek bitirilmedi.
- Sahte 4,4 GiB `install.wim`'li ISO: bölme ve kopyalama geçici FAT32 diskinde çalıştı (Windows Kurulum'un `install.swm`'yi okuması denenmedi).
- BIOS-only ISO ön kontrolde reddedilir; 4 GiB üstü tek dosya ve aşırı alan isteği planda reddedilir.
- Fedora 44 ve Arch 2026.11 ISO'larında etiket/UUID değişikliği geçici FAT32 diskinde doğrulandı (yalnızca ayar dosyaları).
- Açılış sistemi betiği: liste ve kuru çalıştırma denendi; gerçek `next`/`default` değişikliği denenmedi.

## Doğrulanmayanlar / yarının işleri

1. **Linux testleri:** Her dağıtımın gerçekten açılması. Öncelik: Mint (kurulu mu, açılış girişi var mı), sonra Ubuntu ailesi, Debian, Fedora, Arch tabanlılar. `oneClickCaveats` (`lib/install/install_section.dart`) etiket gerektiren sistemler için "doğrulanmadı" uyarısı gösterir; test ettikçe kaldır.
2. 4 GiB üstü tek dosyalı ISO'lar (ör. Bazzite 7-9 GB) FAT32'ye sığmaz, planlayıcı reddeder. Kullanıcıya daha iyi bir yol gerekebilir.
3. Açılış sistemi sayfasında gerçek `next`/`default` değişikliği ve ikinci sistem varken görünüm.
4. Windows 8.1/10/11 kurulumunun sonuna kadar gitmesi.
5. Windows imzasız (SmartScreen uyarısı). Kod imzalama yok.

## Yayın

- GitHub: `skurtz0/besideos` (özel), dal `main`.
- Site yayını: `tool/` altında değil, elle yapıldı: `flutter build web` + uygulama zip'i (`BesideOS-windows.zip`, içinde `BesideOS/` klasörü) tek bir site zip'ine konur (**eğik çizgili** yollar; `Compress-Archive` ters eğik çizgi yazar ve yüklemeyi bozar), Cloudflare Pages > besideos > Create deployment ile yüklenir. 10 MB üstü dosya yükleme sınırı için yerel CORS sunucusu kullanıldı.
- GitHub Actions: `.github/workflows/deploy-web.yml` yalnızca elle (`workflow_dispatch`) çalışır; Cloudflare'e bağlı değil.

## Dikkat

- Betikler yalnızca ASCII olmalı (5.1 BOM'suz dosyayı ANSI okur); `scripts_test.dart` bunu denetler.
- PowerShell değişken adları büyük/küçük harfe duyarsız (`$id` ile `$Id` aynı).
- `bcdedit /enum <olmayan guid>` çıkış kodu 0 verir; varlığı çıktıdan anla.
- Sonsuz animasyonlar yüzünden widget testlerinde `pumpAndSettle` yerine sabit `pump` kullan.
- Kullanıcıya ait GitHub token'ı bir kez sohbete yapıştırıldı; kullanılmadı, iptal edilmesi gerekiyor.
