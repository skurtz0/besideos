use crate::plan::Refusal;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Partition {
    pub number: u32,
    pub size_bytes: u64,
    pub used_bytes: u64,
    pub filesystem: String,
    pub is_system: bool,
    /// `null` = unknown (treated as encrypted). Key itself is required.
    #[serde(deserialize_with = "Option::deserialize")]
    pub encrypted: Option<bool>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PartitionStyle {
    Gpt,
    Mbr,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Disk {
    pub number: u32,
    pub size_bytes: u64,
    pub style: PartitionStyle,
    pub dynamic: bool,
    pub partitions: Vec<Partition>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HostFacts {
    pub uefi: bool,
    pub disks: Vec<Disk>,
    /// (disk, partition); JSON shape `{"disk":..,"partition":..}`.
    #[serde(with = "win_part")]
    pub windows_partition: (u32, u32),
}

mod win_part {
    use serde::{Deserialize, Deserializer, Serialize, Serializer};

    #[derive(Serialize, Deserialize)]
    #[serde(deny_unknown_fields)]
    struct Repr {
        disk: u32,
        partition: u32,
    }

    pub fn serialize<S: Serializer>(v: &(u32, u32), s: S) -> Result<S::Ok, S::Error> {
        Repr {
            disk: v.0,
            partition: v.1,
        }
        .serialize(s)
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<(u32, u32), D::Error> {
        let r = Repr::deserialize(d)?;
        Ok((r.disk, r.partition))
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct IsoFacts {
    pub size_bytes: u64,
    pub extracted_bytes: u64,
    pub largest_file_bytes: u64,
    pub largest_file_name: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Request {
    pub linux_space_bytes: u64,
}

macro_rules! from_json {
    ($($t:ty),*) => {$(
        impl $t {
            pub fn from_json(s: &str) -> Result<Self, Refusal> {
                serde_json::from_str(s).map_err(|e| Refusal::InvalidInput(e.to_string()))
            }
        }
    )*};
}
from_json!(HostFacts, IsoFacts, Request);

#[cfg(test)]
mod tests {
    use super::*;

    const HOST: &str = r#"{"uefi":true,"windows_partition":{"disk":0,"partition":3},
      "disks":[{"number":0,"size_bytes":1000,"style":"gpt","dynamic":false,
      "partitions":[{"number":3,"size_bytes":900,"used_bytes":400,"filesystem":"ntfs","is_system":true,"encrypted":false}]}]}"#;

    #[test]
    fn parses_valid_host_json() {
        let h = HostFacts::from_json(HOST).unwrap();
        assert!(h.uefi);
        assert_eq!(h.windows_partition, (0, 3));
        assert_eq!(h.disks[0].style, PartitionStyle::Gpt);
        assert_eq!(h.disks[0].partitions[0].encrypted, Some(false));
    }

    #[test]
    fn unknown_field_is_rejected() {
        let j = HOST.replace("\"uefi\":true", "\"uefi\":true,\"extra\":1");
        assert!(matches!(
            HostFacts::from_json(&j),
            Err(Refusal::InvalidInput(_))
        ));
        assert!(matches!(
            Request::from_json(r#"{"linux_space_bytes":1,"x":2}"#),
            Err(Refusal::InvalidInput(_))
        ));
    }

    #[test]
    fn missing_field_is_invalid_input() {
        assert!(matches!(
            HostFacts::from_json(r#"{"uefi":true}"#),
            Err(Refusal::InvalidInput(_))
        ));
        assert!(matches!(
            IsoFacts::from_json(r#"{"size_bytes":1}"#),
            Err(Refusal::InvalidInput(_))
        ));
        assert!(matches!(
            Request::from_json("{}"),
            Err(Refusal::InvalidInput(_))
        ));
    }

    #[test]
    fn empty_disk_list_parses() {
        let h = HostFacts::from_json(
            r#"{"uefi":true,"disks":[],"windows_partition":{"disk":0,"partition":1}}"#,
        )
        .unwrap();
        assert!(h.disks.is_empty());
    }

    #[test]
    fn encrypted_null_parses_as_none() {
        let j = HOST.replace("\"encrypted\":false", "\"encrypted\":null");
        assert_eq!(
            HostFacts::from_json(&j).unwrap().disks[0].partitions[0].encrypted,
            None
        );
    }
}
