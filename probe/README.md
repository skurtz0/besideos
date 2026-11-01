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

## Bilinen: VM'de otomasyon (probe/README)
- UTM'de computer-use ile yazarken `type` eylemi tek karakteri tekrarlıyor; tuşlar tek tek gönderilmeli, '.' tuşu VM'e ulaşmıyor (Tab tamamlama da çalışmadı); dosya adı için `gci \coll*` joker kullanıldı. Probe diski MBR bölümlü olmalı, yoksa Windows sürücü harfi vermiyor.

## Plan uygulama (Aşama 3c) — `apply-plan.ps1`
**Yalnız yedeği/snapshot'ı olan test VM'inde.** Önce VM snapshot'ı al.
1. Mac: `probe/make-probe-image.sh --force --plan plan.json [--execute] [--reboot] [--undo] out.img` (plan: `besideos-plan` çıktısı; `extract_iso` kaynağı VM'de var olan bir `.iso` yolu ya da takılı medya kökü, örn. `E:\`).
2. VM'e takıp `run-apply.cmd`'ye çift tıkla. Mod, imajdaki bayrak dosyalarından seçilir: hiçbiri yok = **kuru çalıştırma** (preflight + yapılacakları yazar, hiçbir şeyi değiştirmez); `EXECUTE.flag` = gerçekten uygula; `REBOOT.flag` = (EXECUTE ile) sonunda yeniden başlat; `UNDO.flag` = geri al (EXECUTE yoksa o da kuru).
3. **Önce kuru çalıştır**, `apply.log`'u oku (`make-probe-image.sh --read img` ile), sonra `--execute` imajını hazırla.
4. Durum `apply-state.json`'da tutulur (küçültülen bölüm + özgün boyut, oluşturulan bölüm, önyükleme girdisi GUID'i). Hata olursa script durur; `--undo --execute` imajıyla geri al: girdi silinir, BESIDEOS bölümü (yalnız bizim oluşturduğumuz) silinir, Windows bölümü eski boyutuna büyütülür. Olmadı: VM snapshot'ına dön.

Doğrulanmadı (Windows'ta hiç çalıştırılmadı): bkz. `windows/apply-plan.selfcheck.md` — özellikle ARM64'te `bcdedit /copy {bootmgr}`, tek seferlik `bootsequence`, FAT32 biçimlendirme, robocopy, Resize-Partition hizalaması.
