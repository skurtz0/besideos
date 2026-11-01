# besideos_core

Windows yanına Linux kurulumunun ne yapacağını bir **plan (JSON)** olarak üreten saf Rust kütüphanesi ve küçük komut satırı aracı (`besideos-plan`).

**Diske DOKUNMAZ.** Hiçbir şey yazmaz, disk komutu çalıştırmaz, ağa çıkmaz; yalnız verilen JSON girdilerini okur ve plan ya da ret (`Refusal`) üretir. Aynı girdi her zaman birebir aynı çıktıyı verir.

```
cd core
cargo run --bin besideos-plan -- --host host.json --iso iso.json --request request.json --iso-path <yol>
```

Çıkış kodu: 0 = plan (stdout); 1 = kullanım/G-Ç/JSON ayrıştırma hatası (stderr); 2 = ret (`{"refused","message"}` stdout), ön koşul denetimlerinden gelen `invalid_input` (tutarsız girdi) dahil.

Mimari: x86_64 ve arm64 desteklenir; `HostFacts.arch` ile `IsoFacts.arch` aynı olmalı (aksi `arch_mismatch`). Önyükleyici yolu mimariye göre `\EFI\BOOT\BOOTX64.EFI` / `BOOTAA64.EFI`; arm64 yolu şimdilik yalnız kuru çalıştırmayla doğrulandı.

Reddedilenler: mimari uyuşmazlığı, NTFS olmayan ya da tutarsız (diskten büyük, çakışan numaralı) hedef, 8 GiB'tan az Linux alanı, 32 GiB'ı aşan geçici bölüm, Windows için %10 (en az 10 GiB) pay bırakılamaması; UEFI olmayan sistem, şifreli ya da şifreleme durumu bilinmeyen hedef bölüm, MBR diskte 4 bölüm dolu, dinamik disk, boş yer yetersiz, ISO içinde FAT32 sınırını (4 GiB − 1 bayt) aşan dosya.

## Sonraki aşamalar
- **3b:** gerçek host bilgisini (diskler, bölümler, UEFI, BitLocker) toplayıp `HostFacts` JSON'una çevirmek (salt okunur).
- **3c:** planı önce sanal makinede, sonra kullanıcı onayıyla gerçek makinede uygulamak.
