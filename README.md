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
