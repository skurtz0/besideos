use crate::facts::{Disk, HostFacts, IsoFacts, Partition, PartitionStyle, Request};
use crate::plan::Refusal;

pub const FAT32_MAX_FILE: u64 = 4 * 1024 * 1024 * 1024 - 1;
pub const STAGING_MARGIN: u64 = 512 * 1024 * 1024;

pub fn staging_size(iso: &IsoFacts) -> Result<u64, Refusal> {
    iso.extracted_bytes
        .checked_add(STAGING_MARGIN)
        .ok_or_else(|| Refusal::InvalidInput("ISO boyutu taşıyor".into()))
}

pub fn check<'a>(
    host: &'a HostFacts,
    iso: &IsoFacts,
    req: &Request,
) -> Result<(&'a Disk, &'a Partition), Refusal> {
    if !host.uefi {
        return Err(Refusal::NotUefi);
    }
    let (dn, pn) = host.windows_partition;
    let disk = host
        .disks
        .iter()
        .find(|d| d.number == dn)
        .ok_or(Refusal::NoSuitableDisk)?;
    let part = disk
        .partitions
        .iter()
        .find(|p| p.number == pn)
        .ok_or(Refusal::NoSuitableDisk)?;
    if disk.dynamic {
        return Err(Refusal::DynamicDisk);
    }
    if part.encrypted != Some(false) {
        return Err(Refusal::EncryptedTarget);
    }
    if disk.style == PartitionStyle::Mbr && disk.partitions.len() >= 4 {
        return Err(Refusal::TooManyPrimaryPartitions);
    }
    if iso.largest_file_bytes > FAT32_MAX_FILE {
        return Err(Refusal::IsoFileTooLargeForFat32 {
            name: iso.largest_file_name.clone(),
            size: iso.largest_file_bytes,
        });
    }
    let available = part
        .size_bytes
        .checked_sub(part.used_bytes)
        .ok_or_else(|| Refusal::InvalidInput("kullanılan alan bölüm boyutundan büyük".into()))?;
    let needed = req
        .linux_space_bytes
        .checked_add(staging_size(iso)?)
        .ok_or_else(|| Refusal::InvalidInput("istenen alan taşıyor".into()))?;
    if needed > available {
        return Err(Refusal::NotEnoughFreeSpace { needed, available });
    }
    Ok((disk, part))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::facts::PartitionStyle;

    const GIB: u64 = 1024 * 1024 * 1024;

    fn part(n: u32) -> Partition {
        Partition {
            number: n,
            size_bytes: 100 * GIB,
            used_bytes: 20 * GIB,
            filesystem: "ntfs".into(),
            is_system: n == 3,
            encrypted: Some(false),
        }
    }
    fn host() -> HostFacts {
        HostFacts {
            uefi: true,
            windows_partition: (0, 3),
            disks: vec![Disk {
                number: 0,
                size_bytes: 500 * GIB,
                style: PartitionStyle::Gpt,
                dynamic: false,
                partitions: vec![part(1), part(2), part(3)],
            }],
        }
    }
    fn iso() -> IsoFacts {
        IsoFacts {
            size_bytes: 3 * GIB,
            extracted_bytes: 3 * GIB,
            largest_file_bytes: GIB,
            largest_file_name: "big".into(),
        }
    }
    fn req() -> Request {
        Request {
            linux_space_bytes: 20 * GIB,
        }
    }
    fn win(h: &mut HostFacts) -> &mut Partition {
        &mut h.disks[0].partitions[2]
    }

    #[test]
    fn refuses_non_uefi() {
        let mut h = host();
        h.uefi = false;
        assert_eq!(check(&h, &iso(), &req()).unwrap_err(), Refusal::NotUefi);
    }
    #[test]
    fn refuses_missing_windows_partition() {
        let mut h = host();
        h.windows_partition = (0, 9);
        assert_eq!(
            check(&h, &iso(), &req()).unwrap_err(),
            Refusal::NoSuitableDisk
        );
        h.windows_partition = (7, 3);
        assert_eq!(
            check(&h, &iso(), &req()).unwrap_err(),
            Refusal::NoSuitableDisk
        );
    }
    #[test]
    fn refuses_dynamic_disk() {
        let mut h = host();
        h.disks[0].dynamic = true;
        assert_eq!(check(&h, &iso(), &req()).unwrap_err(), Refusal::DynamicDisk);
    }
    #[test]
    fn refuses_encrypted_true() {
        let mut h = host();
        win(&mut h).encrypted = Some(true);
        assert_eq!(
            check(&h, &iso(), &req()).unwrap_err(),
            Refusal::EncryptedTarget
        );
    }
    #[test]
    fn refuses_encrypted_unknown() {
        let mut h = host();
        win(&mut h).encrypted = None;
        assert_eq!(
            check(&h, &iso(), &req()).unwrap_err(),
            Refusal::EncryptedTarget
        );
    }
    #[test]
    fn accepts_encrypted_false() {
        let h = host();
        let (d, p) = check(&h, &iso(), &req()).unwrap();
        assert_eq!((d.number, p.number), (0, 3));
    }
    #[test]
    fn refuses_mbr_with_four_partitions() {
        let mut h = host();
        h.disks[0].style = PartitionStyle::Mbr;
        h.disks[0].partitions.push(part(4));
        assert_eq!(
            check(&h, &iso(), &req()).unwrap_err(),
            Refusal::TooManyPrimaryPartitions
        );
    }
    #[test]
    fn accepts_gpt_with_four_partitions() {
        let mut h = host();
        h.disks[0].partitions.push(part(4));
        assert!(check(&h, &iso(), &req()).is_ok());
    }
    #[test]
    fn refuses_iso_file_over_fat32_limit() {
        let mut i = iso();
        i.largest_file_bytes = FAT32_MAX_FILE + 1;
        assert_eq!(
            check(&host(), &i, &req()).unwrap_err(),
            Refusal::IsoFileTooLargeForFat32 {
                name: "big".into(),
                size: FAT32_MAX_FILE + 1
            }
        );
    }
    #[test]
    fn accepts_iso_file_at_fat32_limit() {
        let mut i = iso();
        i.largest_file_bytes = FAT32_MAX_FILE;
        assert!(check(&host(), &i, &req()).is_ok());
    }
    fn needed() -> u64 {
        req().linux_space_bytes + staging_size(&iso()).unwrap()
    }
    #[test]
    fn refuses_one_byte_short() {
        let mut h = host();
        let w = win(&mut h);
        w.used_bytes = 0;
        w.size_bytes = needed() - 1;
        assert_eq!(
            check(&h, &iso(), &req()).unwrap_err(),
            Refusal::NotEnoughFreeSpace {
                needed: needed(),
                available: needed() - 1
            }
        );
    }
    #[test]
    fn accepts_exactly_enough() {
        let mut h = host();
        let w = win(&mut h);
        w.used_bytes = 0;
        w.size_bytes = needed();
        assert!(check(&h, &iso(), &req()).is_ok());
    }
    #[test]
    fn huge_values_do_not_overflow() {
        let mut i = iso();
        i.extracted_bytes = u64::MAX;
        assert!(matches!(staging_size(&i), Err(Refusal::InvalidInput(_))));
        assert!(matches!(
            check(&host(), &i, &req()),
            Err(Refusal::InvalidInput(_))
        ));
        let r = Request {
            linux_space_bytes: u64::MAX,
        };
        assert!(matches!(
            check(&host(), &iso(), &r),
            Err(Refusal::InvalidInput(_))
        ));
        let mut h = host();
        win(&mut h).used_bytes = u64::MAX; // used > size
        assert!(matches!(
            check(&h, &iso(), &req()),
            Err(Refusal::InvalidInput(_))
        ));
    }
    #[test]
    fn check_order_not_uefi_wins_over_others() {
        let mut h = host();
        h.uefi = false;
        h.disks[0].dynamic = true;
        win(&mut h).encrypted = None;
        assert_eq!(check(&h, &iso(), &req()).unwrap_err(), Refusal::NotUefi);
    }
    #[test]
    fn no_disks_is_no_suitable_disk() {
        let mut h = host();
        h.disks.clear();
        assert_eq!(
            check(&h, &iso(), &req()).unwrap_err(),
            Refusal::NoSuitableDisk
        );
    }
}
