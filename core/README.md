# besideos_core

Windows yanına Linux kurulumunun ne yapacağını bir **plan (JSON)** olarak üreten saf Rust kütüphanesi ve küçük komut satırı aracı (`besideos-plan`).

**Diske DOKUNMAZ.** Hiçbir şey yazmaz, disk komutu çalıştırmaz, ağa çıkmaz; yalnız verilen JSON girdilerini okur ve plan ya da ret (`Refusal`) üretir. Aynı girdi her zaman birebir aynı çıktıyı verir.

```
cd core
cargo run --bin besideos-plan -- --host host.json --iso iso.json --request request.json --iso-path <yol>
```

Çıkış kodu: 0 = plan (stdout), 2 = ret (`{"refused","message"}` stdout), 1 = hatalı argüman/dosya/JSON (stderr).

Reddedilenler: UEFI olmayan sistem, şifreli ya da şifreleme durumu bilinmeyen hedef bölüm, MBR diskte 4 bölüm dolu, dinamik disk, boş yer yetersiz, ISO içinde FAT32 sınırını (4 GiB − 1 bayt) aşan dosya.

## Sonraki aşamalar
- **3b:** gerçek host bilgisini (diskler, bölümler, UEFI, BitLocker) toplayıp `HostFacts` JSON'una çevirmek (salt okunur).
- **3c:** planı önce sanal makinede, sonra kullanıcı onayıyla gerçek makinede uygulamak.
