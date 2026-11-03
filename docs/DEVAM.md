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

## Linux ana bilgisayar (GRUB loopback) - 3 Kasım 2026

- `probe/linux/besideos-grub.sh` (`check`, `prepare`, `undo`, `status`; `--execute` olmadan kuru çalıştırma). ISO'yu bölüm küçültmeden, mevcut diskteki dosyadan GRUB `custom.cfg` girişiyle açar; geri almak yalnızca işaretli bloğu siler.
- Tarifler: `loopback.cfg` olan ISO'lar (Ubuntu ailesi, Mint, Debian live) = doğrulanacak; Fedora (`dracut`) ve Arch (`archiso`) = deneysel, `--allow-experimental` ister. Gerçek açılışta hiçbiri henüz denenmedi.
- Henüz Flutter arayüzüne bağlı değil ve katalogda `hosts` alanına `linux` eklenmedi. Gerçek açılış testi geçince eklenecek.
- Test: `test/install/grub_script_test.dart` (sahte ISO ve sahte GRUB klasörü, root gerekmez).
- Linux ana bilgisayarda da yer açılır (Windows'taki gibi): `besideos-grub.sh disks` küçültülebilir bölümleri (ext4, btrfs, NTFS; GPT) listeler, `prepare --shrink-dev DEV --shrink-gb N` bölümü küçültür (dosya sistemi, sonra `parted resizepart`), `undo` bölümü eski boyutuna büyütür. Her dağıtımın kendi GRUB girişi vardır (`--name`). **Gerçek diskte henüz denenmedi**; ilk deneme yedeği olan, sistem dışı bir bölümde yapılmalı.

## Windows acilis menusu (apply-plan.ps1 -Menu) - 3 Kasim 2026

- Uygulama `-Menu -MenuTitle <ad>` verir: kurulum girdisi {bootmgr} displayorder'in basina eklenir, `default` yapilir, `timeout 5`, `displaybootmenu yes`. Girdi adi: "BesideOS: 5 saniye icinde kurulacak: <ad>".
- Eski default/timeout/displaybootmenu `apply-state.json` icindeki `menu` altina kaydedilir (degisiklikten ONCE). `ProgramData\BesideOS\menu-reset.cmd` + `BesideOSMenuReset` zamanlanmis gorevi (SYSTEM, onstart) Windows'un bir sonraki acilisinda eskiyi geri koyar ve girdiyi menuden cikarir (tek seferlik). `-Undo` once bunu geri alir, sonra girdiyi siler.
- Menu kurulamazsa betik dogrulanmis eski yola (bootsequence ile dogrudan acilis) duser; `-Menu` verilmezse davranis eskisiyle ayni.
- **Gercek Windows'ta DENENMEDI.** Ozellikle: Linux ISO'su icin ({bootmgr} kopyasi, firmware uygulamasi) Windows menusunden secilince acilip acilmadigi bilinmiyor; Windows ISO'su (ramdisk osloader) icin menu daha guvenli bir yol.

## Windows menusu: gercek Windows'ta test listesi - 3 Kasim 2026

Statik kontrol (Linux'ta PowerShell 7 ile): `probe/windows/*.ps1` sozdizimi hatasiz; `Get-BcdValue` ornek `bcdedit /enum {bootmgr}` ciktisinda `default`, `timeout`, `displaybootmenu` degerlerini dogru okuyor. Gercek bcdedit denenmedi.

Yedegi olan, sistem disi bir diskte ya da VM'de, yonetici PowerShell ile:

1. Kuru calistirma: `apply-plan.ps1 -PlanFile <plan.json> -Menu -MenuTitle Test` (`-Execute` yok, hicbir sey degismez). Gunlukte "then the boot menu: ..." satiri gorunmeli.
2. Gercek kurulum (`-Execute -Menu -MenuTitle Test`), once `bcdedit /enum {bootmgr}` ciktisini kaydet (default, timeout, displaybootmenu).
3. Yeniden baslat: menu 5 saniye gorunuyor mu, "BesideOS: 5 saniye icinde kurulacak: Test" secili mi?
4. Linux ISO'su: giris Windows menusunden secilince yukleyici aciliyor mu? (en buyuk belirsizlik) Windows ISO'su: RAM disk girisi aciliyor mu?
5. Windows'a donunce: `bcdedit /enum {bootmgr}` eski degerlere donmus mu, `schtasks /query /tn BesideOSMenuReset` "bulunamadi" demeli, `%ProgramData%\BesideOS\menu-reset.cmd` silinmis olmali.
6. Menuyu gorup Windows'u secersen de ayni sey olmali (gorev bir sonraki Windows acilisinda calisir).
7. `-Undo -Execute`: menu ayarlari, girdi ve bolum geri gelmeli. Sonucu bu dosyaya yaz.
