# probe — Windows host bilgisi toplayıcı (Aşama 3b)

Windows VM/PC'nin disk, bölüm, UEFI, BitLocker bilgisini toplayıp `facts.json` üretir (`core` planlayıcısının `HostFacts` biçimi). **Salt okunurdur**: yalnız `Get-*`, kayıt defteri/CIM okuma, `bcdedit /enum`, `manage-bde -status` kullanır; diske hiçbir şey yazmaz/değiştirmez. Yazdığı tek şey `facts.json` ve `probe.log`.

## Paketleme (Mac)
```
probe/make-probe-image.sh [--force] [cikti.img]   # varsayılan probe/besideprobe.img
```
64 MB FAT32 ham imaj (`BESIDEPROBE`) yapar; içine `collect-host-facts.ps1` ve `run-probe.cmd` kopyalanır. Var olan imajın üzerine `--force` olmadan yazmaz.

## UTM'e takma
UTM'de VM'i seç → Ayarlar → Drives → **New Drive** → *Import* ile `.img` dosyasını ekle → Interface: **USB**, "Removable" işaretli → Kaydet. VM'i başlat; Windows'ta `BESIDEPROBE` sürücüsü görünür.

## Windows'ta çalıştırma
Sürücüdeki `run-probe.cmd` dosyasına çift tıkla (yönetici izni ister; BitLocker ve küçültme alt sınırı için gerekli). Bittiğinde `facts.json` ve `probe.log` aynı sürücüye yazılır. VM'i kapat.

## Geri okuma (Mac)
```
probe/make-probe-image.sh --read probe/besideprobe.img facts.json
```
İmajı salt okunur bağlar, `facts.json` ve `probe.log` içeriğini basar, `facts.json`'u verilen yola kopyalar, çıkarır.

## Doğrulama
```
probe/validate-facts.sh facts.json
```
`besideos-plan`'ı örnek ISO/istek ile çalıştırır (mimariye göre). Çıkış: 0 plan, 2 ret, 1 hata.

Belirsiz her bilgi güvenli (fail-closed) değere düşer: `encrypted=null`, `used_bytes=size_bytes`, `min_size_bytes=size_bytes`. Başarısız çalışmada `facts.json` yazılmaz; nedeni `probe.log`'dadır.
