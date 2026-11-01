# besideos_site

The besideos.com website, built with Flutter web. A landing page plus a distro catalog and install guides at `/distros` and `/distros/<id>` (data: `assets/catalog/catalog.json`).

Flutter is not installed where this was written, so it has not been run yet. First time on a machine with Flutter:

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
