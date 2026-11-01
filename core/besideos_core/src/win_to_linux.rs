use crate::checks::{check, staging_size};
use crate::facts::{HostFacts, IsoFacts, Request};
use crate::plan::{Fs, Plan, PlannedStep, Refusal, Step};

const GIB: u128 = 1024 * 1024 * 1024;
const LABEL: &str = "BESIDEOS";

/// Bytes -> GiB, one decimal (half up), comma separator.
pub fn fmt_gib(bytes: u64) -> String {
    let tenths = (u128::from(bytes) * 10 + GIB / 2) / GIB;
    format!("{},{}", tenths / 10, tenths % 10)
}

pub fn plan_windows_to_linux(
    host: &HostFacts,
    iso: &IsoFacts,
    req: &Request,
    iso_path: &str,
) -> Result<Plan, Refusal> {
    let (disk, part) = check(host, iso, req)?;
    let staging = staging_size(iso)?;
    // check() already proved this cannot overflow.
    let shrink = req.linux_space_bytes + staging;
    let loader = "\\EFI\\BOOT\\BOOTX64.EFI";
    let step = |description: String, step: Step| PlannedStep {
        description,
        step,
        undo: None,
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
        ),
        step(
            format!(
                "ISO içeriği ({} GiB) '{LABEL}' bölümüne açılacak",
                fmt_gib(iso.extracted_bytes)
            ),
            Step::ExtractIso {
                iso_path: iso_path.into(),
                target_label: LABEL.into(),
            },
        ),
        step(
            "Bir sonraki açılış için tek seferlik UEFI önyükleme girdisi eklenecek".into(),
            Step::AddOneShotBootEntry {
                loader_path: loader.into(),
                description: "BesideOS kurulumu".into(),
            },
        ),
        step("Bilgisayar yeniden başlatılacak".into(), Step::Reboot),
    ];
    let risks = vec![
        "Bölüm küçültme geri alınamaz; işleme başlamadan önce yedek al (yedek uyarısı).".into(),
        "Secure Boot açıksa Linux yükleyicisi imzalı değilse açılmayabilir (Secure Boot notu)."
            .into(),
        "Önyükleyici yolu x86_64 (BOOTX64.EFI) varsayılır; ARM bilgisayarlarda çalışmaz.".into(),
        "Kurulum sonrası BESIDEOS bölümü silinebilir.".into(),
    ];
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
    use crate::facts::{Disk, Partition, PartitionStyle};

    const GIB: u64 = 1024 * 1024 * 1024;

    fn host() -> HostFacts {
        HostFacts {
            uefi: true,
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
                    filesystem: "ntfs".into(),
                    is_system: true,
                    encrypted: Some(false),
                }],
            }],
        }
    }
    fn iso() -> IsoFacts {
        IsoFacts {
            size_bytes: 3 * GIB,
            extracted_bytes: 3 * GIB,
            largest_file_bytes: GIB,
            largest_file_name: "f".into(),
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
        assert!(
            r.contains("yedek")
                && r.contains("secure boot")
                && r.contains("besideos")
                && r.contains("x86_64")
        );
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
    fn fmt_gib_rounds_to_one_decimal_with_comma() {
        assert_eq!(fmt_gib(0), "0,0");
        assert_eq!(fmt_gib(GIB * 105 / 2), "52,5");
        assert_eq!(fmt_gib(u64::MAX), "17179869184,0");
    }
    #[test]
    fn no_step_when_refused() {
        let r = Request {
            linux_space_bytes: 1000 * GIB,
        };
        assert!(plan_windows_to_linux(&host(), &iso(), &r, "x").is_err());
    }
}
