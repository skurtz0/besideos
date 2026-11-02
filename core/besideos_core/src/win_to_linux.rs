use crate::checks::{check, staging_size};
use crate::facts::{Arch, HostFacts, IsoFacts, Request};
use crate::plan::{fmt_gib, Fs, Plan, PlannedStep, Refusal, Step};

const LABEL: &str = "BESIDEOS";

fn removable_loader(arch: Arch) -> &'static str {
    match arch {
        Arch::X86_64 => "\\EFI\\BOOT\\BOOTX64.EFI",
        Arch::Arm64 => "\\EFI\\BOOT\\BOOTAA64.EFI",
    }
}

pub fn plan_windows_to_linux(
    host: &HostFacts,
    iso: &IsoFacts,
    req: &Request,
    iso_path: &str,
) -> Result<Plan, Refusal> {
    let (disk, part, shrink) = check(host, iso, req)?;
    let staging = staging_size(iso)?;
    let loader = removable_loader(host.arch);
    let boot_desc = "BesideOS kurulumu";
    let step = |description: String, step: Step, undo: Option<Step>| PlannedStep {
        description,
        step,
        undo,
    };
    let steps = vec![
        step(
            format!(
                "Disk {} bölüm {} {} GiB küçültülecek",
                disk.number,
                part.number,
                fmt_gib(shrink)
            ),
            Step::ShrinkPartition {
                disk: disk.number,
                partition: part.number,
                shrink_bytes: shrink,
            },
            None,
        ),
        step(
            format!(
                "{} GiB'lık FAT32 '{LABEL}' bölümü oluşturulacak",
                fmt_gib(staging)
            ),
            Step::CreatePartition {
                disk: disk.number,
                size_bytes: staging,
                filesystem: Fs::Fat32,
                label: LABEL.into(),
            },
            Some(Step::DeletePartition {
                disk: disk.number,
                label: LABEL.into(),
            }),
        ),
        step(
            if iso.splittable_wim_bytes > 0 {
                format!(
                    "ISO içeriği ({} GiB) '{LABEL}' bölümüne açılacak; sources/install.wim ({} GiB) 4 GiB sınırı için parçalara bölünecek",
                    fmt_gib(iso.extracted_bytes),
                    fmt_gib(iso.splittable_wim_bytes)
                )
            } else {
                format!(
                    "ISO içeriği ({} GiB) '{LABEL}' bölümüne açılacak",
                    fmt_gib(iso.extracted_bytes)
                )
            },
            Step::ExtractIso {
                iso_path: iso_path.into(),
                target_label: LABEL.into(),
            },
            None,
        ),
        step(
            format!(
                "Bir sonraki açılış için tek seferlik UEFI önyükleme girdisi ({}) eklenecek",
                host.arch.as_str()
            ),
            Step::AddOneShotBootEntry {
                loader_path: loader.into(),
                description: boot_desc.into(),
            },
            Some(Step::RemoveBootEntry {
                description: boot_desc.into(),
            }),
        ),
        step("Bilgisayar yeniden başlatılacak".into(), Step::Reboot, None),
    ];
    let mut risks = vec![
        "Bölüm küçültme geri alınamaz; işleme başlamadan önce yedek al (yedek uyarısı).".into(),
        "Bir adım yarıda kalırsa geri alma adımları uygulanmalı.".into(),
        "Secure Boot açıksa Linux yükleyicisi imzalı değilse açılmayabilir (Secure Boot notu)."
            .into(),
        "Kurulum sonrası BESIDEOS bölümü silinebilir.".into(),
    ];
    if host.arch == Arch::Arm64 {
        risks.push("arm64 yolu şimdilik yalnız kuru çalıştırmayla (dry-run) doğrulandı.".into());
    }
    Ok(Plan {
        steps,
        risks,
        total_shrink_bytes: shrink,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::checks::STAGING_MARGIN;
    use crate::facts::{Arch, Disk, Partition, PartitionStyle};

    const GIB: u64 = 1024 * 1024 * 1024;

    fn host() -> HostFacts {
        HostFacts {
            uefi: true,
            arch: Arch::X86_64,
            windows_partition: (0, 3),
            disks: vec![Disk {
                number: 0,
                size_bytes: 500 * GIB,
                style: PartitionStyle::Gpt,
                dynamic: false,
                partitions: vec![Partition {
                    number: 3,
                    size_bytes: 300 * GIB,
                    used_bytes: 50 * GIB,
                    min_size_bytes: 50 * GIB,
                    filesystem: "ntfs".into(),
                    is_system: true,
                    encrypted: Some(false),
                }],
            }],
        }
    }
    fn iso() -> IsoFacts {
        IsoFacts {
            arch: Arch::X86_64,
            size_bytes: 3 * GIB,
            extracted_bytes: 3 * GIB,
            largest_file_bytes: GIB,
            largest_file_name: "f".into(),
            splittable_wim_bytes: 0,
        }
    }
    fn req() -> Request {
        Request {
            linux_space_bytes: 50 * GIB,
        }
    }
    fn plan() -> Plan {
        plan_windows_to_linux(&host(), &iso(), &req(), "C:\\iso\\x.iso").unwrap()
    }

    #[test]
    fn plan_has_five_steps_in_order() {
        let p = plan();
        assert!(matches!(
            p.steps[0].step,
            Step::ShrinkPartition {
                disk: 0,
                partition: 3,
                ..
            }
        ));
        assert!(matches!(
            p.steps[1].step,
            Step::CreatePartition {
                filesystem: Fs::Fat32,
                ..
            }
        ));
        assert!(matches!(p.steps[2].step, Step::ExtractIso { .. }));
        assert!(matches!(p.steps[3].step, Step::AddOneShotBootEntry { .. }));
        assert_eq!(p.steps[4].step, Step::Reboot);
        assert_eq!(p.steps.len(), 5);
    }
    #[test]
    fn shrink_equals_linux_space_plus_staging() {
        let p = plan();
        let want = 50 * GIB + 3 * GIB + STAGING_MARGIN;
        assert_eq!(p.total_shrink_bytes, want);
        assert!(
            matches!(p.steps[0].step, Step::ShrinkPartition { shrink_bytes, .. } if shrink_bytes == want)
        );
        assert!(
            matches!(p.steps[1].step, Step::CreatePartition { size_bytes, .. } if size_bytes == 3 * GIB + STAGING_MARGIN)
        );
    }
    #[test]
    fn plan_is_deterministic() {
        assert_eq!(
            serde_json::to_string(&plan()).unwrap(),
            serde_json::to_string(&plan()).unwrap()
        );
    }
    #[test]
    fn refusal_passes_through() {
        let mut h = host();
        h.uefi = false;
        assert_eq!(
            plan_windows_to_linux(&h, &iso(), &req(), "x").unwrap_err(),
            Refusal::NotUefi
        );
    }
    #[test]
    fn risks_mention_backup_and_secure_boot() {
        let r = plan().risks.join(" ").to_lowercase();
        assert!(r.contains("yedek") && r.contains("secure boot") && r.contains("besideos"));
    }
    #[test]
    fn descriptions_are_turkish_with_gib() {
        let p = plan();
        assert!(
            p.steps[0].description.contains("53,5 GiB"),
            "{}",
            p.steps[0].description
        );
        assert!(p.steps[0].description.contains("küçültülecek"));
        assert!(p.steps.iter().all(|s| !s.description.is_empty()));
    }
    #[test]
    fn extract_step_mentions_the_split_when_there_is_a_big_wim() {
        let mut i = iso();
        i.splittable_wim_bytes = 5 * GIB;
        i.extracted_bytes = 7 * GIB;
        let p = plan_windows_to_linux(&host(), &i, &req(), "C:\\iso\\w.iso").unwrap();
        assert!(p.steps[2].description.contains("parçalara bölünecek"));
        assert!(p.steps[2].description.contains("5,0 GiB"));
        assert!(!plan().steps[2].description.contains("bölünecek"));
    }
    #[test]
    fn fmt_gib_rounds_to_one_decimal_with_comma() {
        assert_eq!(fmt_gib(0), "0,0");
        assert_eq!(fmt_gib(GIB * 105 / 2), "52,5");
        assert_eq!(fmt_gib(u64::MAX), "17179869184,0");
    }
    #[test]
    fn undo_present_only_for_create_and_boot_entry() {
        let p = plan();
        assert_eq!(p.steps[0].undo, None);
        assert_eq!(
            p.steps[1].undo,
            Some(Step::DeletePartition {
                disk: 0,
                label: "BESIDEOS".into()
            })
        );
        assert_eq!(p.steps[2].undo, None);
        let Step::AddOneShotBootEntry { description, .. } = &p.steps[3].step else {
            panic!()
        };
        assert_eq!(
            p.steps[3].undo,
            Some(Step::RemoveBootEntry {
                description: description.clone()
            })
        );
        assert_eq!(p.steps[4].undo, None);
    }
    #[test]
    fn plan_with_undo_roundtrips_json() {
        let p = plan();
        let j = serde_json::to_string(&p).unwrap();
        assert!(
            j.contains("\"type\":\"delete_partition\"")
                && j.contains("\"type\":\"remove_boot_entry\"")
        );
        assert_eq!(serde_json::from_str::<Plan>(&j).unwrap(), p);
    }
    #[test]
    fn risks_mention_irreversible_shrink_and_interrupted_steps() {
        let r = plan().risks.join(" ");
        assert!(
            r.contains("geri alınamaz")
                && r.contains("yarıda kalırsa geri alma adımları uygulanmalı")
        );
    }
    fn loader_of(p: &Plan) -> (String, String) {
        let Step::AddOneShotBootEntry { loader_path, .. } = &p.steps[3].step else {
            panic!()
        };
        (loader_path.clone(), p.steps[3].description.clone())
    }
    #[test]
    fn x86_64_uses_bootx64_and_has_no_arm_note() {
        let p = plan();
        let (l, d) = loader_of(&p);
        assert_eq!(l, "\\EFI\\BOOT\\BOOTX64.EFI");
        assert!(d.contains("x86_64"));
        assert!(!p.risks.join(" ").contains("arm64"));
    }
    #[test]
    fn arm64_pair_uses_bootaa64_and_notes_dry_run() {
        let mut h = host();
        h.arch = Arch::Arm64;
        let mut i = iso();
        i.arch = Arch::Arm64;
        let p = plan_windows_to_linux(&h, &i, &req(), "x").unwrap();
        let (l, d) = loader_of(&p);
        assert_eq!(l, "\\EFI\\BOOT\\BOOTAA64.EFI");
        assert!(d.contains("arm64"));
        assert!(p.risks.join(" ").contains("dry-run"));
    }
    #[test]
    fn arch_mismatch_is_refused() {
        let mut h = host();
        h.arch = Arch::Arm64;
        assert!(matches!(
            plan_windows_to_linux(&h, &iso(), &req(), "x"),
            Err(Refusal::ArchMismatch { .. })
        ));
        let mut i = iso();
        i.arch = Arch::Arm64;
        assert!(matches!(
            plan_windows_to_linux(&host(), &i, &req(), "x"),
            Err(Refusal::ArchMismatch { .. })
        ));
    }
    #[test]
    fn no_step_when_refused() {
        let r = Request {
            linux_space_bytes: 1000 * GIB,
        };
        assert!(plan_windows_to_linux(&host(), &iso(), &r, "x").is_err());
    }
}
