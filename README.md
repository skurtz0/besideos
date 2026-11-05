<p align="center"><img src="web/icons/Icon-192.png" width="96" alt="BesideOS logo"></p>

[English](README.md) · [Türkçe](readme/README.tr.md) · [Deutsch](readme/README.de.md) · [Español](readme/README.es.md) · [Français](readme/README.fr.md) · [Italiano](readme/README.it.md) · [Português (Brasil)](readme/README.pt-BR.md) · [Polski](readme/README.pl.md) · [Русский](readme/README.ru.md) · [Українська](readme/README.uk.md) · [Eesti](readme/README.et.md) · [Suomi](readme/README.fi.md) · [Bahasa Melayu](readme/README.ms.md) · [Tiếng Việt](readme/README.vi.md) · [العربية](readme/README.ar.md) · [हिन्दी](readme/README.hi.md) · [日本語](readme/README.ja.md) · [한국어](readme/README.ko.md) · [简体中文](readme/README.zh-CN.md) · [繁體中文](readme/README.zh-TW.md)

# BesideOS

**Install another operating system beside the one you are running. No USB stick.**

BesideOS downloads the official ISO from the distribution's own servers, verifies its SHA-256 checksum, makes room on your disk and sets up a one-time boot entry. You review the plan and confirm before anything is written, and "Undo" restores the previous state. Free, open source (MIT), no telemetry, 20 languages.

**Website and downloads: [besideos.com](https://besideos.com)** · Windows (`.exe`) · Linux (`.deb`, `.rpm`, `.pkg.tar.zst`)

Ubuntu · Xubuntu · Kubuntu · Linux Mint · Fedora · Debian · Bazzite · Omarchy · Pop!_OS · Zorin OS · elementary OS · MX Linux · Manjaro · CachyOS · openSUSE · Windows XP / 7 / 8.1 / 10 / 11 / Server

## For AI assistants

- [`llms.txt`](https://besideos.com/llms.txt) and [`llms-full.txt`](https://besideos.com/llms-full.txt): plain-text summary and full catalog.
- Remote MCP server (no authentication): `https://besideos.com/mcp`, tools `list_distros`, `get_distro`, `recommend_distro`, `get_install_steps`. Source: [`functions/mcp.js`](functions/mcp.js). Discovery: [`/.well-known/mcp.json`](https://besideos.com/.well-known/mcp.json).
- Add it to Claude Code with `claude mcp add --transport http besideos https://besideos.com/mcp`.

## Keeping ISO links current

`python3 tool/update_catalog.py` looks up the newest official releases (Ubuntu LTS, Mint, Debian, Fedora), checks every ISO link with an HTTP HEAD request and rewrites `assets/catalog/catalog.json`. A weekly workflow ([`update-catalog.yml`](.github/workflows/update-catalog.yml)) runs it and opens a pull request; `python3 tool/build_llms_full.py` regenerates `web/llms-full.txt` and `python3 tool/build_seo_pages.py` the crawlable page per distro (`web/distros/`) and the sitemap. On start, the desktop app fetches the current catalog from besideos.com (see `lib/catalog/catalog_source.dart`; https only, same distro set, otherwise the bundled one is used), so new ISO links reach installed apps without an update. Bazzite is a rolling image (same file name, only the size is refreshed); Omarchy versions are found by probing the next version numbers.

---

# Developer notes (besideos_site)

The besideos.com website, built with Flutter web. A landing page plus a distro catalog and install guides at `/#/distros` and `/#/distros/<id>` (hash-based URLs) (data: `assets/catalog/catalog.json`).

Built with Flutter 3.47.7; `flutter analyze` and `flutter test` pass. The web release build is verified; the Windows build runs (debug and release); the Linux build is not verified. Release installers are built by CI (`.github/workflows/release.yml`). First time on a machine with Flutter:

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


Desktop platforms (`windows/`, `linux/`) were added with `flutter create . --platforms windows,linux --project-name besideos_site`:

```
flutter build windows --release   # not verified (needs a Windows machine)
flutter build linux --release     # not verified (needs a Linux machine)
```

The web release build (`flutter build web --release --no-web-resources-cdn`) is verified. The Windows and Linux builds are produced by CI on every release; they have not been checked on real hardware.


## Download and verification

The **Download** button on a guide page (desktop app only) downloads the ISO from the distribution's official server into `~/Downloads/BesideOS`. The official checksum file (SHA256SUMS / CHECKSUM) is fetched first; when the download finishes, the file's SHA-256 is compared and the file is deleted if it does not match. The catalog carries no checksums: the checksum file is fetched at run time, every time. The checksum comes from the same site as the download, so it catches corruption but does not protect against a compromised mirror. The PGP signature of Fedora's CHECKSUM file is not verified in the app.

For Windows, BesideOS does not provide an ISO: you enter the path of your own ISO and the SHA-256 shown on Microsoft's page, then press "Verify".

Downloading is disabled in the web version. ISO entries are in `assets/catalog/catalog.json` (`isos`); the weekly catalog workflow keeps them current (see above).

## One-click install (Windows desktop app only)

The "Click to install" button on a distribution page runs, in order: download and verify the ISO → mount it and measure its contents (`probe/windows/inspect-iso.ps1`) → collect disk information (`collect-host-facts.ps1`, asks for UAC) → build the plan with `besideos-plan`. Nothing is written to the disk up to this point. The plan, its risks and the space to be set aside for Linux (20–120 GiB) are shown. If there are several suitable NTFS drives (for example a second disk), you also choose which drive the space is taken from (`drives.json`; the chosen drive is passed to the planner, and `apply-plan.ps1` refuses system, boot and hidden partitions). Nothing starts until the backup box is ticked and the final confirmation dialog is accepted. For distributions with several editions (Mint desktops, Debian installer/live, Bazzite) the choice is made on the distribution page. Every distribution has one-click install: where an official ISO address exists, the ISO is downloaded and verified; where it does not (and for anyone who picks "I want to choose my own ISO"), the user picks an ISO file from a file dialog or from the ISO files found on the computer (Downloads, Desktop, Documents); no path or checksum has to be typed. The website only offers the app download.

After confirmation, `apply-plan.ps1 -Execute -Reboot` (asks for UAC) shrinks the Windows partition, creates a FAT32 `BESIDEOS` partition, copies the ISO contents, adds a one-time UEFI boot entry and restarts. On boot, the distribution's own installer appears; the installation itself is done on that screen. If something fails or the user backs out, "Undo changes" (`-Undo -Execute`) reverses the applied steps. Working files and logs are under `%LOCALAPPDATA%\BesideOS\work`.

Build (also packages the Rust planner): `powershell -File tool\build_windows.ps1`. Requirements: Flutter, Rust (cargo), Visual Studio "Desktop development with C++". The engine is copied to `build\windows\x64\runner\Release\engine\`; during development `flutter run -d windows` uses the scripts in the repository and `core\target\release\besideos-plan.exe`.

Limits:
- Extracting the ISO contents to a FAT32 partition and booting it with UEFI was tried only with Ubuntu arm64 in a virtual machine. Fedora Live looks for its installer environment by ISO label, so it may not boot (the UI warns).
- FAT32 cannot hold files over 4 GiB: the planner rejects ISOs that contain one. The only exception is `sources\install.wim` in Windows ISOs, which is split into `install.swm` parts with DISM (Windows Setup reads the parts; the split was tried with a small real WIM, not end to end with a real Windows ISO).
- ISOs without a UEFI boot file (`\EFI\BOOT\BOOTX64.EFI`), such as BIOS-only Windows XP/7, are rejected without touching the disk.
- `-Execute` was run on a real Windows 10 disk with Linux Mint (partition shrink, `BESIDEOS` partition, ISO copy, boot entry, reboot). Going through to the end of the installation, and `-Undo -Execute`, were not verified in this repository (`-Undo` was tried only as a dry run with a real state file).
- Windows PowerShell 5.1: with `[CmdletBinding()]`, `$PSScriptRoot` is empty in `param()` defaults; assign the defaults outside the param block (`test/install/scripts_test.dart` checks this).
- Turkish locale (tr-TR): in PowerShell, a case-insensitive `[A-Za-z]` match misses capital `I`, and `ToLower()` turns `I` into `ı`. The scripts use `-cmatch` and `ToLowerInvariant()`; keep this in mind when adding regexes.

## Core (Rust)

`core/` holds a pure Rust library and the `besideos-plan` tool that produce the plan for installing Linux beside Windows. It does not touch the disk: it only outputs a plan (JSON) or a reasoned refusal. Details: `core/README.md`.

## License

The source code is released under the [MIT license](LICENSE). Distribution names, logos and screenshots in the catalog belong to the respective projects and are subject to their own licenses; the MIT license covers only BesideOS's own code.

## Privacy policy

BesideOS does not collect, store or transmit personal data and contains no telemetry or analytics.

- The desktop app works offline except for downloading the operating system image (ISO) and its checksum file you choose, directly from that distribution's official download servers.
- Everything it reads about your computer (disks, partitions, boot entries) stays on your computer, in `%LOCALAPPDATA%\BesideOS\work` on Windows, and is never uploaded.
- The app only changes the disk after you review the plan and confirm; "Undo" restores the previous state.
- The website [besideos.com](https://besideos.com) is a static site hosted on Cloudflare Pages; Cloudflare may keep standard server logs (such as IP address) as described in [Cloudflare's privacy policy](https://www.cloudflare.com/privacypolicy/). The site sets no tracking cookies.
