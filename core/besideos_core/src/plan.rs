use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Fs {
    Fat32,
    Ntfs,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Step {
    ShrinkPartition {
        disk: u32,
        partition: u32,
        shrink_bytes: u64,
    },
    CreatePartition {
        disk: u32,
        size_bytes: u64,
        filesystem: Fs,
        label: String,
    },
    ExtractIso {
        iso_path: String,
        target_label: String,
    },
    AddOneShotBootEntry {
        loader_path: String,
        description: String,
    },
    Reboot,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlannedStep {
    pub description: String,
    pub step: Step,
    pub undo: Option<Step>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Plan {
    pub steps: Vec<PlannedStep>,
    pub risks: Vec<String>,
    pub total_shrink_bytes: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Refusal {
    NotUefi,
    EncryptedTarget,
    TooManyPrimaryPartitions,
    DynamicDisk,
    NotEnoughFreeSpace { needed: u64, available: u64 },
    IsoFileTooLargeForFat32 { name: String, size: u64 },
    NoSuitableDisk,
    InvalidInput(String),
}

impl Refusal {
    /// Stable machine-readable code (used by the CLI).
    pub fn code(&self) -> &'static str {
        match self {
            Refusal::NotUefi => "not_uefi",
            Refusal::EncryptedTarget => "encrypted_target",
            Refusal::TooManyPrimaryPartitions => "too_many_primary_partitions",
            Refusal::DynamicDisk => "dynamic_disk",
            Refusal::NotEnoughFreeSpace { .. } => "not_enough_free_space",
            Refusal::IsoFileTooLargeForFat32 { .. } => "iso_file_too_large_for_fat32",
            Refusal::NoSuitableDisk => "no_suitable_disk",
            Refusal::InvalidInput(_) => "invalid_input",
        }
    }

    pub fn message(&self) -> String {
        match self {
            Refusal::NotUefi => "Bu bilgisayar UEFI ile açılmıyor (eski BIOS); desteklenmiyor.".into(),
            Refusal::EncryptedTarget => "Windows bölümü şifreli (BitLocker) ya da şifreleme durumu bilinmiyor; önce şifrelemeyi kaldırın.".into(),
            Refusal::TooManyPrimaryPartitions => "MBR diskte 4 birincil bölüm dolu; yeni bölüm açılamaz.".into(),
            Refusal::DynamicDisk => "Disk dinamik disk türünde; desteklenmiyor.".into(),
            Refusal::NotEnoughFreeSpace { needed, available } => format!(
                "Boş yer yetersiz: {needed} bayt gerekli, {available} bayt var."
            ),
            Refusal::IsoFileTooLargeForFat32 { name, size } => format!(
                "ISO içindeki '{name}' dosyası ({size} bayt) FAT32 sınırını (4 GiB − 1 bayt) aşıyor."
            ),
            Refusal::NoSuitableDisk => "Windows'un kurulu olduğu uygun disk ya da bölüm bulunamadı.".into(),
            Refusal::InvalidInput(m) => format!("Geçersiz girdi: {m}"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Plan {
        Plan {
            steps: vec![
                PlannedStep {
                    description: "küçült".into(),
                    step: Step::ShrinkPartition {
                        disk: 0,
                        partition: 3,
                        shrink_bytes: 10,
                    },
                    undo: None,
                },
                PlannedStep {
                    description: "aç".into(),
                    step: Step::CreatePartition {
                        disk: 0,
                        size_bytes: 5,
                        filesystem: Fs::Fat32,
                        label: "X".into(),
                    },
                    undo: Some(Step::Reboot),
                },
            ],
            risks: vec!["r".into()],
            total_shrink_bytes: 10,
        }
    }

    #[test]
    fn plan_roundtrips_through_json() {
        let p = sample();
        let back: Plan = serde_json::from_str(&serde_json::to_string(&p).unwrap()).unwrap();
        assert_eq!(p, back);
    }

    #[test]
    fn refusal_messages_are_turkish_and_nonempty() {
        let all = [
            Refusal::NotUefi,
            Refusal::EncryptedTarget,
            Refusal::TooManyPrimaryPartitions,
            Refusal::DynamicDisk,
            Refusal::NotEnoughFreeSpace {
                needed: 2,
                available: 1,
            },
            Refusal::IsoFileTooLargeForFat32 {
                name: "a".into(),
                size: 9,
            },
            Refusal::NoSuitableDisk,
            Refusal::InvalidInput("x".into()),
        ];
        for r in all {
            let m = r.message();
            assert!(!m.is_empty());
            assert!(
                m.chars().any(|c| "çğıöşüÇĞİÖŞÜ".contains(c)) || m.contains("Geçersiz"),
                "{m}"
            );
        }
    }

    #[test]
    fn step_serializes_with_snake_case_tag() {
        let s = serde_json::to_string(&Step::ShrinkPartition {
            disk: 0,
            partition: 1,
            shrink_bytes: 2,
        })
        .unwrap();
        assert!(s.contains("\"type\":\"shrink_partition\""), "{s}");
    }
}
