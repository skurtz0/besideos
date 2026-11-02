# besideos_site

The besideos.com website, built with Flutter web. A landing page plus a distro catalog and install guides at `/#/distros` and `/#/distros/<id>` (hash-based URLs) (data: `assets/catalog/catalog.json`).

Built with Flutter 3.47.7; `flutter analyze` and `flutter test` pass. Web and macOS release builds are verified; Windows and Linux builds are not. No installer exists yet. First time on a machine with Flutter:

```
flutter create . --platforms web --project-name besideos_site
flutter pub get
flutter test
flutter run -d chrome
flutter build web --release --no-web-resources-cdn
```

`flutter create .` only fills in what is missing; it keeps the files here. If it replaces `web/index.html`, restore the title, description and noscript text from git.

Icons are a placeholder: `python3 tool/make_icons.py`.

Flutter web draws to a canvas, so search engines see little beyond the `<noscript>` text in `web/index.html`. Fine for a landing page; reconsider before adding a blog or docs.


Desktop platforms (`windows/`, `macos/`, `linux/`) were added with `flutter create . --platforms windows,macos,linux --project-name besideos_site`:

```
flutter build macos --release     # verified on macOS
flutter build windows --release   # not verified (needs a Windows machine)
flutter build linux --release     # not verified (needs a Linux machine)
```

Web release build (`flutter build web --release --no-web-resources-cdn`) verified. Windows and Linux: doğrulanmadı.


## İndirme ve doğrulama

Rehber sayfasındaki **İndir** düğmesi (yalnız masaüstü uygulamada) ISO dosyasını resmi dağıtım sunucusundan `~/Downloads/BesideOS` klasörüne indirir. Önce resmi sağlama dosyası (SHA256SUMS / CHECKSUM) alınır, indirme bitince dosyanın SHA-256 değeri karşılaştırılır; eşleşmezse dosya silinir. Katalog sağlama değeri taşımaz, sağlama dosyası her seferinde çalışma anında alınır. Arayüz yalnız "İndirildi ve doğrulandı" der; **kurulum motoru yok**, hiçbir şey kurulmaz. Sağlama değeri indirme kaynağıyla aynı siteden alındığı için bozulmayı yakalar, ele geçirilmiş bir kaynağa karşı koruma sağlamaz. Fedora CHECKSUM dosyasının PGP imzası uygulamada doğrulanmaz.

Windows için BesideOS ISO sağlamaz: kendi ISO dosyanın yolunu ve Microsoft sayfasındaki SHA-256 değerini girip "Doğrula"ya basarsın.

Web sürümünde indirme kapalıdır. macOS sandbox'ı için `macos/Runner/*.entitlements` dosyalarına `com.apple.security.network.client` ve `com.apple.security.files.downloads.read-write` eklendi. Windows ve Linux derlemeleri doğrulanmadı.

ISO girdileri `assets/catalog/catalog.json` içinde (`isos`); Debian `current/` ve Fedora sürüm adresleri yeni sürümde değişir, katalog elle güncellenmelidir.

## Tek tıkla kurulum (yalnız Windows masaüstü uygulaması)

Dağıtım sayfasındaki **"<dağıtım> kur"** düğmesi sırayla: ISO'yu indirip doğrular → ISO'yu bağlayıp içeriğini ölçer (`probe/windows/inspect-iso.ps1`) → disk bilgisini toplar (`collect-host-facts.ps1`, UAC ister) → `besideos-plan` ile planı üretir. **Bu noktaya kadar diske hiçbir şey yazılmaz.** Plan, riskler ve Linux için ayrılacak alan (20–120 GiB) gösterilir; yedek kutusu işaretlenip `KUR` yazılmadan uygulama başlamaz. Onaydan sonra `apply-plan.ps1 -Execute -Reboot` (UAC ister): Windows bölümünü küçültür, FAT32 `BESIDEOS` bölümü açar, ISO içeriğini kopyalar, tek seferlik UEFI önyükleme girdisi ekler ve yeniden başlatır. Açılışta dağıtımın kendi kurulum ekranı gelir; kurulumun kendisi o ekranda yapılır. Hata olursa ya da vazgeçilirse **"Değişiklikleri geri al"** (`-Undo -Execute`) uygulanan adımları tersine çevirir. Çalışma dosyaları ve günlükler `%LOCALAPPDATA%\BesideOS\work` altındadır.

Derleme (Rust planlayıcıyı da pakete koyar): `powershell -File tool\build_windows.ps1`. Gerekenler: Flutter, Rust (cargo), Visual Studio "Desktop development with C++". Motor `build\windows\x64\runner\Release\engine\` altına kopyalanır; geliştirirken `flutter run -d windows` depo içindeki betikleri ve `core\target\release\besideos-plan.exe` dosyasını kullanır.

Sınırlar: ISO içeriğini FAT32 bölüme açıp UEFI ile açma yöntemi yalnız Ubuntu arm64 ile sanal makinede denendi. Fedora Live ISO etiketiyle kurulum ortamını aradığı için açılmayabilir (arayüz uyarır). 4 GiB'dan büyük dosya içeren ISO'lar (ör. Ubuntu masaüstü) planlayıcı tarafından reddedilir. Gerçek bir diskte `-Execute` ve yeniden başlatma bu depoda denenmedi; kuru çalıştırma (preflight) gerçek Windows 10 üzerinde doğrulandı.

Türkçe yerel ayar (tr-TR) notu: PowerShell'de büyük/küçük harf duyarsız `[A-Za-z]` eşleşmesi büyük `I`'yı kaçırır ve `ToLower()` `I`'yı `ı` yapar. Betiklerde `-cmatch` ve `ToLowerInvariant()` kullanılır; yeni regex eklerken buna dikkat et.

## Çekirdek (Rust)

`core/` altında, Windows yanına Linux kurulumunun planını üreten saf bir Rust kütüphanesi ve `besideos-plan` aracı bulunur. Diske dokunmaz, yalnız plan (JSON) ya da gerekçeli ret üretir; gerçek host bilgisi toplama (3b) ve planı uygulama (3c) sonraki aşamalardır. Ayrıntı: `core/README.md`.
