# BesideOS uygulaması: tasarım

Tarih: 2026-11-01. Durum: onaylandı (kullanıcı).

Kullanıcı kararı: ilk sürüm imzasız dağıtılır (Windows SmartScreen ve macOS Gatekeeper uyarısı kabul edildi). Kod imzalama sertifikası sonraya bırakıldı. README'de uyarı ve açma adımları açıkça yazılır.

## Amaç ve neden
BesideOS, kullanıcının mevcut işletim sisteminin yanına, USB bellek olmadan ikinci bir işletim sistemi kurabildiği indirilebilir bir masaüstü uygulamasıdır. Uygulama içinde dağıtımları tanıtır (açıklama, görünüş, rehber), seçileni tek tıkla indirir ve doğrular, sonra diski hazırlayıp bir sonraki açılışta kurulumu başlatır. Aynı katalog ve rehber `besideos.com` sitesinde de görünür.

Neden: USB hazırlamak, disk bölmek ve önyükleme ayarlamak sıradan kullanıcı için zor ve riskli. Uygulama bunu planı gösterip onay alarak tek akışta yapar.

## Hedefler
- Katalog ve distro rehberi: uygulamada ve sitede aynı veriden.
- Tek tıkla indirme: ilerleme, kaldığı yerden devam.
- Doğrulama: SHA-256 (ve dağıtım imza yayımlıyorsa imza). Eşleşmezse kurulum reddedilir.
- Dört kurulum yönü: Windows→Linux, Linux→Windows, Windows→Windows, Mac(M1/M2)→Linux.
- Her yıkıcı adım önce plan olarak gösterilir, kullanıcı onaylar. Varsayılan mod dry-run.

## Hedef olmayanlar
- Herhangi bir sistemin yanına macOS (Apple lisansı ve donanımı izin vermiyor).
- Apple Silicon Mac yanına Windows (Boot Camp yok, çift açılış desteklenmiyor). Katalogda nedeniyle "desteklenmiyor" gösterilir.
- M3 ve sonrası Mac'te Linux (Asahi desteklemiyor veya kısmi). Uygulama çipi algılar ve reddeder.
- Legacy BIOS, 32-bit, şifreli disk (BitLocker/FileVault/LUKS) üzerinde yeniden boyutlandırma. İlk sürümde reddedilir.
- Mobil uygulama.

## Karşı hedefler (başarısızlık sayılır)
- Kullanıcı verisinin kaybı. Plan göstermeden veya onaysız disk değişikliği.
- Doğrulanmamış ISO ile kurulum.
- Yönetici yetkisinin gereğinden geniş kullanımı.

## Kısıtlar
- Windows ISO'sunu Microsoft dağıtır, doğrudan sabit bağlantıyla indirmek lisans ve teknik açıdan sorunlu. Katalog Windows için "kendi ISO'nu seç" veya Microsoft'un resmi indirme sayfasına yönlendirme sunar. Doğrulama yine yapılır. (Benim kararım, itiraz edilebilir.)
- Mac→Linux motoru kendi disk kodunu yazmaz, resmi Asahi yükleyicisini çalıştırır (benim kararım: sıfırdan yazmak riskli ve gereksiz).
- Gerçek disk işlemleri bu Mac'te güvenle denenemez, sanal makine gerekir (aşağıda).

## Yaklaşımlar
- A. Hepsi Flutter/Dart: tek dil, ama disk ve önyükleme işleri için zayıf.
- B. Flutter arayüz + Rust çekirdek: **seçildi**. Arayüz mevcut sitenin kodunu paylaşır, kritik kısım güvenli dilde.
- C. Tauri/Electron + Rust: mevcut Flutter işi atılır, kullanıcının stack'ine uymaz.

Seçim nedeni: disk hatası veri kaybettirir, bu kısım Rust'ta yazılmalı.

## Mimari (benim önerim, kullanıcı B'yi onayladı)
```
catalog/            tek JSON kaynak + şema (site ve uygulama aynısını okur)
app/                Flutter: masaüstü (Win/Linux/macOS) + web (site) ortak paket
core/ (Rust)
  download/         HTTP indirme, devam, ilerleme
  verify/           SHA-256, imza doğrulama
  plan/             yıkıcı adımları üreten, yürütmeden gösteren planlayıcı
  engine-win-linux/ engine-linux-win/ engine-win-win/ engine-mac-linux/
helper/             yönetici yetkisiyle çalışan küçük program (yalnız planı uygular)
```
Flutter, Rust çekirdeğe FFI ile bağlanır. Arayüz asla doğrudan disk komutu çalıştırmaz, yalnız plan ister ve onaylı planı helper'a verir.

## Katalog alanları
id, ad, aile (Linux/Windows), kısa ve uzun açıklama, "ne için uygun", masaüstü ortamı, görünüş (ekran görüntüleri), temel aldığı sistem, ISO bağlantıları (mimari başına: x86_64, arm64), sha256 veya sağlama dosyası URL'si, imza URL'si, boyut, donanım gereksinimi, kurulum rehberi adımları, hangi ana sistemlerde kurulabildiği (destek matrisi), lisans notu. Katalog imzalı yayımlanır, uygulama imzayı doğrular.

## Kurulum motorları (ortak akış)
Algıla (UEFI mi, şifreli mi, boş yer, çip) → plan üret → kullanıcıya göster, yedek uyarısı → onay → uygula → tek seferlik önyükleme kaydı → yeniden başlat → geri alma: kaydı sil, bölümü geri ver.
- Windows→Linux: bölümü küçült, ISO için bölüm aç, ISO'yu çıkar, tek seferlik önyükleme kaydı (BCD veya ESP üzerinden). Secure Boot açıksa imzalı shim kullanılır.
- Linux→Windows: ext4/btrfs küçült, NTFS bölüm aç, Windows ISO'yu yaz (install.wim 4 GB sınırı için wimlib ile bölme), GRUB chainload girişi.
- Windows→Windows: C: küçült, yeni bölüm, ISO'daki boot.wim ile BCD girişi, Windows kurulumu açılır.
- Mac→Linux: çip ve macOS sürümü kontrolü, resmi Asahi yükleyicisini başlat, ilerlemeyi arayüzde göster.

## Test
- Rust birim testleri: plan üretimi, doğrulama, SHA hatası, bozuk ISO, yarım indirme.
- Her motor: önce dry-run planı beklenen komutlarla eşleşiyor mu.
- Gerçek uygulama: UTM/QEMU sanal makineleri (Windows 11 ARM, Ubuntu ARM, UEFI). Bu Mac Apple Silicon olduğu için ARM yolları doğal, x86_64 yolları emülasyonla yavaş denenir veya gerçek PC'ye bırakılır.
- Mac→Linux sanal makinede denenemez (Asahi gerçek donanım ister). Yalnız çip/OS kontrolü ve komut hazırlığı otomatik test edilir, gerçek çalıştırma gerçek M1/M2'de elle.

## Sıra
1. Katalog + rehber (frontend, site ve uygulama).
2. İndirme + doğrulama.
3. Motorlar: Windows→Linux, sonra Linux→Windows, Windows→Windows, Mac→Linux.
Her aşama kendi planı ve testleriyle ayrı ilerler.

## Builder'a bırakılanlar
Rust/Flutter FFI aracı (flutter_rust_bridge benzeri), indirme kütüphanesi, imza şeması, Windows ve Linux'ta imza ve sertifika yönetimi, kurulum paketleri (msi/dmg/AppImage).

## Açık riskler
Kurulum motorları gerçek donanımda ilk kez denenecek, hata veri kaybettirebilir. Windows ISO dağıtımı lisans nedeniyle kısıtlı. Dağıtım indirme bağlantıları zamanla değişir, katalog güncel tutulmalı.
