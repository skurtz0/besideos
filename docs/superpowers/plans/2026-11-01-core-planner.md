# Rust Çekirdek: Windows→Linux Plan Üretici (Aşama 3a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Windows yanına Linux kurulumunun ne yapacağını, diske HİÇ dokunmadan, doğrulanabilir bir plan (JSON) olarak üreten saf Rust kütüphanesi ve küçük bir komut satırı aracı.

**Architecture:** `core/` altında Cargo workspace. Bir `HostFacts` (diskler, bölümler, UEFI mi, şifreleme) ve bir `IsoFacts` (boyut, en büyük dosya) girdisi alan saf bir fonksiyon, ya bir `Plan` (sıralı adımlar, riskler) ya da bir `Refusal` (nedenleriyle ret) döner. Hiçbir G/Ç yapılmaz; gerçek disk okuma ve uygulama sonraki aşamadadır (3b: gerçek host bilgisi toplama, 3c: planı sanal makinede uygulama).

**Tech Stack:** Rust (stable, rustup ile), `serde` + `serde_json`. Başka bağımlılık yok (CLI için `clap` yok).

**Spec:** `docs/superpowers/specs/2026-11-01-besideos-app-design.md` (bölümler: Kurulum motorları ortak akış, Windows→Linux; Hedef olmayanlar: eski BIOS, şifreli disk; Karşı hedefler: onaysız disk değişikliği)

## Global Constraints

- Bu aşamada hiçbir kod diske yazmaz, disk komutu çalıştırmaz, ağa çıkmaz. `core/` testleri yalnız bellek içi veri ve geçici dosya kullanır.
- Plan üretimi saf ve belirleyicidir (aynı girdi → birebir aynı JSON).
- Reddedilen durumlar `Refusal` olur, asla "dene ve gör" değil: UEFI olmayan sistem, şifreli (BitLocker) hedef bölüm, MBR diskte 4 birincil bölüm dolu, dinamik disk, boş yer yetersiz, ISO içinde FAT32 sınırını (4 GiB − 1 bayt) aşan dosya.
- Her `Step` insan okunur bir `description` taşır (Türkçe) ve geri alma bilgisi (`undo`) içerir.
- Birimler bayt; GiB = 1024³. Tüm boyut hesapları taşmasız (`u64`, `checked_*`).
- Rust 2021, `#![forbid(unsafe_code)]`, `cargo clippy -- -D warnings` temiz.
- Bu klasör yerel git deposudur (branch `main`, remote yok).
- Flutter tarafına bu aşamada dokunulmaz.

## Review Focus

- `free_bytes` tam sınırda (tam yetecek kadar / 1 bayt eksik): doğru karar (Task 3).
- Çok büyük `u64` değerleri: taşma yok, `Refusal` ya da hata (Task 3, 4).
- Sıfır bölümlü / hiç diski olmayan host: çökme yok, anlaşılır ret (Task 2, 3).
- Bilinmeyen alanlı veya eksik alanlı JSON: kapalı-hata (Task 2).
- BitLocker bayrağı bilinmiyorsa (`null`): şifreli kabul edilir ve reddedilir (Task 3).
- Aynı girdiyle iki çalıştırma aynı çıktıyı verir (Task 5).

---

### Task 1: Workspace ve plan türleri

**Files:**
- Create: `core/Cargo.toml` (workspace), `core/besideos_core/Cargo.toml`, `core/besideos_core/src/lib.rs`, `core/besideos_core/src/plan.rs`
- Test: `core/besideos_core/src/plan.rs` içinde `#[cfg(test)]`

**Interfaces:**
- Produces (`plan.rs`, hepsi `serde::{Serialize, Deserialize}`, `Debug`, `PartialEq`):
  - `enum Step { ShrinkPartition { disk: u32, partition: u32, shrink_bytes: u64 }, CreatePartition { disk: u32, size_bytes: u64, filesystem: Fs, label: String }, ExtractIso { iso_path: String, target_label: String }, AddOneShotBootEntry { loader_path: String, description: String }, Reboot }`
  - `enum Fs { Fat32, Ntfs }`
  - `struct PlannedStep { description: String, step: Step, undo: Option<Step> }`
  - `struct Plan { steps: Vec<PlannedStep>, risks: Vec<String>, total_shrink_bytes: u64 }`
  - `enum Refusal { NotUefi, EncryptedTarget, TooManyPrimaryPartitions, DynamicDisk, NotEnoughFreeSpace { needed: u64, available: u64 }, IsoFileTooLargeForFat32 { name: String, size: u64 }, NoSuitableDisk, InvalidInput(String) }` ve `Refusal::message(&self) -> String` (Türkçe)

- [ ] **Step 1: Write failing tests** `plan_roundtrips_through_json` (Plan → JSON → Plan eşit), `refusal_messages_are_turkish_and_nonempty` (her varyant), `step_serializes_with_snake_case_tag` (`"type":"shrink_partition"`).
- [ ] **Step 2: Run** `cd core && cargo test` → FAIL (crate yok).
- [ ] **Step 3: Implement** workspace + `plan.rs`; `serde` `#[serde(tag = "type", rename_all = "snake_case")]`.
- [ ] **Step 4: Run** `cargo test && cargo clippy -- -D warnings` → PASS.
- [ ] **Step 5: Commit** `feat(core): plan types`.

### Task 2: Host ve ISO girdi modeli

**Files:**
- Create: `core/besideos_core/src/facts.rs`
- Modify: `core/besideos_core/src/lib.rs`
- Test: `facts.rs` içinde

**Interfaces:**
- Consumes: `Refusal` (Task 1)
- Produces:
  - `struct Partition { number: u32, size_bytes: u64, used_bytes: u64, filesystem: String, is_system: bool, encrypted: Option<bool> }`
  - `enum PartitionStyle { Gpt, Mbr }`
  - `struct Disk { number: u32, size_bytes: u64, style: PartitionStyle, dynamic: bool, partitions: Vec<Partition> }`
  - `struct HostFacts { uefi: bool, disks: Vec<Disk>, windows_partition: (u32, u32) }` (disk, partition; JSON'da `{"disk":..,"partition":..}`)
  - `struct IsoFacts { size_bytes: u64, extracted_bytes: u64, largest_file_bytes: u64, largest_file_name: String }`
  - `struct Request { linux_space_bytes: u64 }` (kullanıcının yeni sistem için istediği alan)
  - `fn HostFacts::from_json(&str) -> Result<HostFacts, Refusal>` (`deny_unknown_fields`, eksik alan → `InvalidInput`), aynısı `IsoFacts`, `Request` için.

- [ ] **Step 1: Write failing tests**: `parses_valid_host_json`, `unknown_field_is_rejected`, `missing_field_is_invalid_input`, `empty_disk_list_parses` (ret kararı Task 3'te), `encrypted_null_parses_as_none`.
- [ ] **Step 2: Run** `cargo test` → FAIL.
- [ ] **Step 3: Implement** `facts.rs` (`#[serde(deny_unknown_fields)]`).
- [ ] **Step 4: Run** `cargo test && cargo clippy -- -D warnings` → PASS.
- [ ] **Step 5: Commit** `feat(core): host and iso facts`.

### Task 3: Ön koşul denetimleri (ret mantığı)

**Files:**
- Create: `core/besideos_core/src/checks.rs`
- Modify: `core/besideos_core/src/lib.rs`
- Test: `checks.rs` içinde

**Interfaces:**
- Consumes: `HostFacts`, `IsoFacts`, `Request`, `Refusal`, `Disk`, `Partition` (Task 1-2)
- Produces:
  - `const FAT32_MAX_FILE: u64 = 4 * 1024 * 1024 * 1024 - 1;`
  - `const STAGING_MARGIN: u64 = 512 * 1024 * 1024;`
  - `fn staging_size(iso: &IsoFacts) -> Result<u64, Refusal>`: `extracted_bytes + STAGING_MARGIN`, `checked_add`, taşmada `InvalidInput`.
  - `fn check(host: &HostFacts, iso: &IsoFacts, req: &Request) -> Result<(&Disk, &Partition), Refusal>`: Windows bölümünün diskini ve bölümünü döndürür. Sıra: `NotUefi` → `NoSuitableDisk` (disk/bölüm bulunamaz) → `DynamicDisk` → `EncryptedTarget` (`encrypted != Some(false)`, yani `None` da reddedilir) → `TooManyPrimaryPartitions` (MBR ve ≥4 bölüm) → `IsoFileTooLargeForFat32` → `NotEnoughFreeSpace` (boş = `size_bytes − used_bytes`; gerekli = `linux_space_bytes + staging_size`; `needed > available` ise ret, eşitlik kabul).

- [ ] **Step 1: Write failing tests**, her biri adıyla: `refuses_non_uefi`, `refuses_missing_windows_partition`, `refuses_dynamic_disk`, `refuses_encrypted_true`, `refuses_encrypted_unknown`, `accepts_encrypted_false`, `refuses_mbr_with_four_partitions`, `accepts_gpt_with_four_partitions`, `refuses_iso_file_over_fat32_limit` (tam `FAT32_MAX_FILE + 1`), `accepts_iso_file_at_fat32_limit`, `refuses_one_byte_short`, `accepts_exactly_enough`, `huge_values_do_not_overflow` (u64::MAX), `check_order_not_uefi_wins_over_others`, `no_disks_is_no_suitable_disk`.
- [ ] **Step 2: Run** `cargo test checks` → FAIL.
- [ ] **Step 3: Implement** `checks.rs`.
- [ ] **Step 4: Run** `cargo test && cargo clippy -- -D warnings` → PASS.
- [ ] **Step 5: Commit** `feat(core): preflight checks`.

### Task 4: Windows→Linux planlayıcı

**Files:**
- Create: `core/besideos_core/src/win_to_linux.rs`
- Modify: `core/besideos_core/src/lib.rs`
- Test: `win_to_linux.rs` içinde

**Interfaces:**
- Consumes: `check`, `staging_size` (Task 3), `Plan`, `PlannedStep`, `Step`, `Fs` (Task 1)
- Produces: `pub fn plan_windows_to_linux(host: &HostFacts, iso: &IsoFacts, req: &Request, iso_path: &str) -> Result<Plan, Refusal>`
  - Adımlar sırayla: `ShrinkPartition{ shrink = linux_space + staging }` (undo: `None`, risk notu "bölüm küçültme geri alınamaz, yedek al"), `CreatePartition{ size = staging, Fat32, label "BESIDEOS" }` (undo: yok edilecek bölümün silinmesi `Step` olarak yoksa `None`), `ExtractIso{ iso_path, target_label "BESIDEOS" }`, `AddOneShotBootEntry{ loader_path "\\EFI\\BOOT\\BOOTX64.EFI" (x86_64 varsayımı, `risks`te belirtilir) }`, `Reboot`.
  - `total_shrink_bytes` = shrink; `risks` en az: yedek uyarısı, Secure Boot notu, "kurulum sonrası BESIDEOS bölümü silinebilir".
  - `PlannedStep.description` Türkçe, boyutları GiB olarak gösterir (örn. "C: bölümü 52,5 GiB küçültülecek").

- [ ] **Step 1: Write failing tests**: `plan_has_five_steps_in_order`, `shrink_equals_linux_space_plus_staging`, `plan_is_deterministic` (iki çağrı JSON eşit), `refusal_passes_through` (örn. `NotUefi`), `risks_mention_backup_and_secure_boot`, `descriptions_are_turkish_with_gib` (içinde "GiB"), `no_step_when_refused` (Err).
- [ ] **Step 2: Run** `cargo test win_to_linux` → FAIL.
- [ ] **Step 3: Implement** `plan_windows_to_linux`; GiB biçimi için küçük yardımcı `fmt_gib(u64) -> String` (bir ondalık, virgül).
- [ ] **Step 4: Run** `cargo test && cargo clippy -- -D warnings` → PASS.
- [ ] **Step 5: Commit** `feat(core): windows to linux planner`.

### Task 5: Komut satırı aracı, örnek veriler, README

**Files:**
- Create: `core/besideos_core/src/bin/besideos-plan.rs`, `core/besideos_core/tests/golden.rs`, `core/besideos_core/tests/data/host_ok.json`, `host_bitlocker.json`, `iso.json`, `request.json`, `plan_ok.golden.json`, `core/README.md`
- Modify: `README.md` (kök, bir paragraf: çekirdek ve durum)

**Interfaces:**
- Consumes: `plan_windows_to_linux`, `HostFacts::from_json`, `IsoFacts::from_json`, `Request::from_json`, `Refusal::message` (Task 1-4)
- Produces: `besideos-plan --host host.json --iso iso.json --request request.json --iso-path <yol>` → stdout'a plan JSON (güzel biçimli) ve çıkış kodu 0; ret durumunda stdout'a `{"refused": "<kod>", "message": "<Türkçe>"}` ve çıkış kodu 2; hatalı argüman/dosya/JSON → stderr'e Türkçe mesaj, çıkış kodu 1. Hiçbir dosyayı yazmaz.

- [ ] **Step 1: Write failing tests** `golden.rs`: `ok_host_matches_golden_plan` (çıktı `plan_ok.golden.json` ile birebir), `bitlocker_host_is_refused_exit_2`, `missing_file_exits_1`, `output_is_stable_across_runs`; CLI testi `env!("CARGO_BIN_EXE_besideos-plan")` ile.
- [ ] **Step 2: Run** `cd core && cargo test` → FAIL.
- [ ] **Step 3: Implement** ikili ve örnek veriler; golden dosyası ilk uygulama çıktısından üretilir ve elle okunup doğrulanır. `core/README.md` çekirdeğin DİSKE DOKUNMADIĞINI ve 3b/3c'nin ne yapacağını yazar.
- [ ] **Step 4: Run** `cargo test && cargo clippy -- -D warnings && cargo fmt --check` ve ayrıca `flutter analyze` + `flutter test` (Flutter tarafı etkilenmemeli) → hepsi geçer.
- [ ] **Step 5: Commit** `feat(core): plan cli, golden tests, docs`.
