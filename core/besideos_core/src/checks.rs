use crate::facts::{Arch, Disk, HostFacts, IsoFacts, Partition, PartitionStyle, Request};
use crate::plan::Refusal;

const GIB: u64 = 1024 * 1024 * 1024;
pub const FAT32_MAX_FILE: u64 = 4 * GIB - 1;
pub const STAGING_MARGIN: u64 = 512 * 1024 * 1024;
/// Windows tools refuse FAT32 volumes over 32 GiB.
pub const MAX_STAGING: u64 = 32 * GIB;
pub const MIN_LINUX_SPACE: u64 = 8 * GIB;
const MIN_WINDOWS_RESERVE: u64 = 10 * GIB;
const MAX_GPT_PARTITIONS: usize = 128;
const MAX_MBR_PRIMARY: usize = 4;

pub fn staging_size(iso: &IsoFacts) -> Result<u64, Refusal> {
    iso.extracted_bytes
        .checked_add(STAGING_MARGIN)
        .ok_or_else(|| Refusal::InvalidInput("ISO boyutu taşıyor".into()))
}

/// Free space Windows must keep after the shrink: max(10% of partition, 10 GiB).
pub fn windows_reserve(part_size: u64) -> u64 {
    (part_size / 10).max(MIN_WINDOWS_RESERVE)
}

fn invalid<T>(m: &str) -> Result<T, Refusal> {
    Err(Refusal::InvalidInput(m.into()))
}

/// On success returns the target disk, partition and the total bytes to shrink
/// (`linux_space + staging`, exact by construction).
pub fn check<'a>(
    host: &'a HostFacts,
    iso: &IsoFacts,
    req: &Request,
) -> Result<(&'a Disk, &'a Partition, u64), Refusal> {
    if !host.uefi {
        return Err(Refusal::NotUefi);
    }
    if host.arch != Arch::X86_64 {
        return Err(Refusal::UnsupportedArch {
            arch: "arm64".into(),
        });
    }
    let (dn, pn) = host.windows_partition;
    let mut disks = host.disks.iter().filter(|d| d.number == dn);
    let disk = disks.next().ok_or(Refusal::NoSuitableDisk)?;
    if disks.next().is_some() {
        return invalid("aynı numaralı birden fazla disk var");
    }
    let mut parts = disk.partitions.iter().filter(|p| p.number == pn);
    let part = parts.next().ok_or(Refusal::NoSuitableDisk)?;
    if parts.next().is_some() {
        return invalid("hedef diskte aynı numaralı birden fazla bölüm var");
    }
    if disk.dynamic {
        return Err(Refusal::DynamicDisk);
    }
    if part.encrypted != Some(false) {
        return Err(Refusal::EncryptedTarget);
    }
    if !part.filesystem.eq_ignore_ascii_case("ntfs") {
        return invalid("Windows bölümü NTFS değil");
    }
    if part.size_bytes > disk.size_bytes {
        return invalid("bölüm diskten büyük");
    }
    let total = disk
        .partitions
        .iter()
        .try_fold(0u64, |a, p| a.checked_add(p.size_bytes));
    if total.is_none_or(|t| t > disk.size_bytes) {
        return invalid("bölümlerin toplamı disk boyutunu aşıyor");
    }
    let limit = match disk.style {
        PartitionStyle::Mbr => MAX_MBR_PRIMARY,
        PartitionStyle::Gpt => MAX_GPT_PARTITIONS,
    };
    // Room for the staging partition plus at least one for Linux.
    if disk.partitions.len() + 2 > limit {
        return Err(Refusal::TooManyPrimaryPartitions);
    }
    if iso.largest_file_bytes > FAT32_MAX_FILE {
        return Err(Refusal::IsoFileTooLargeForFat32 {
            name: iso.largest_file_name.clone(),
            size: iso.largest_file_bytes,
        });
    }
    if iso.extracted_bytes == 0 {
        return invalid("ISO içeriği boş");
    }
    if iso.largest_file_bytes > iso.extracted_bytes {
        return invalid("en büyük dosya toplam içerikten büyük");
    }
    if req.linux_space_bytes == 0 {
        return invalid("Linux için alan istenmedi");
    }
    if req.linux_space_bytes < MIN_LINUX_SPACE {
        return Err(Refusal::LinuxSpaceTooSmall {
            min: MIN_LINUX_SPACE,
            given: req.linux_space_bytes,
        });
    }
    let staging = staging_size(iso)?;
    if staging > MAX_STAGING {
        return Err(Refusal::StagingTooLarge {
            max: MAX_STAGING,
            given: staging,
        });
    }
    if part.min_size_bytes > part.size_bytes || part.used_bytes > part.size_bytes {
        return invalid("kullanılan ya da en az boyut bölüm boyutundan büyük");
    }
    let floor = part.used_bytes.max(part.min_size_bytes);
    let available = (part.size_bytes - floor).saturating_sub(windows_reserve(part.size_bytes));
    let needed = req
        .linux_space_bytes
        .checked_add(staging)
        .ok_or_else(|| Refusal::InvalidInput("istenen alan taşıyor".into()))?;
    if needed > available {
        return Err(Refusal::NotEnoughFreeSpace { needed, available });
    }
    Ok((disk, part, needed))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn part(n: u32) -> Partition {
        Partition {
            number: n,
            size_bytes: 100 * GIB,
            used_bytes: 20 * GIB,
            min_size_bytes: 20 * GIB,
            filesystem: "ntfs".into(),
            is_system: n == 3,
            encrypted: Some(false),
        }
    }
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
    fn err(h: &HostFacts, i: &IsoFacts, r: &Request) -> Refusal {
        check(h, i, r).unwrap_err()
    }
    fn invalid_input(r: Refusal) -> bool {
        matches!(r, Refusal::InvalidInput(_))
    }

    #[test]
    fn refuses_non_uefi() {
        let mut h = host();
        h.uefi = false;
        assert_eq!(err(&h, &iso(), &req()), Refusal::NotUefi);
    }
    #[test]
    fn refuses_arm64() {
        let mut h = host();
        h.arch = Arch::Arm64;
        assert!(matches!(
            err(&h, &iso(), &req()),
            Refusal::UnsupportedArch { .. }
        ));
    }
    #[test]
    fn refuses_missing_windows_partition() {
        let mut h = host();
        h.windows_partition = (0, 9);
        assert_eq!(err(&h, &iso(), &req()), Refusal::NoSuitableDisk);
        h.windows_partition = (7, 3);
        assert_eq!(err(&h, &iso(), &req()), Refusal::NoSuitableDisk);
    }
    #[test]
    fn refuses_dynamic_disk() {
        let mut h = host();
        h.disks[0].dynamic = true;
        assert_eq!(err(&h, &iso(), &req()), Refusal::DynamicDisk);
    }
    #[test]
    fn refuses_encrypted_true() {
        let mut h = host();
        win(&mut h).encrypted = Some(true);
        assert_eq!(err(&h, &iso(), &req()), Refusal::EncryptedTarget);
    }
    #[test]
    fn refuses_encrypted_unknown() {
        let mut h = host();
        win(&mut h).encrypted = None;
        assert_eq!(err(&h, &iso(), &req()), Refusal::EncryptedTarget);
    }
    #[test]
    fn accepts_encrypted_false() {
        let h = host();
        let (d, p, _) = check(&h, &iso(), &req()).unwrap();
        assert_eq!((d.number, p.number), (0, 3));
    }
    #[test]
    fn refuses_non_ntfs_target() {
        let mut h = host();
        win(&mut h).filesystem = "fat32".into();
        assert!(invalid_input(err(&h, &iso(), &req())));
        win(&mut h).filesystem = "NTFS".into();
        assert!(check(&h, &iso(), &req()).is_ok());
    }
    #[test]
    fn refuses_fat32_system_partition_bigger_than_disk() {
        let mut h = host();
        h.disks[0].size_bytes = 1000;
        let w = win(&mut h);
        w.filesystem = "fat32".into();
        w.size_bytes = 900_000_000_000;
        w.is_system = true;
        assert!(invalid_input(err(&h, &iso(), &req())));
    }
    #[test]
    fn refuses_partition_bigger_than_disk() {
        let mut h = host();
        h.disks[0].size_bytes = 50 * GIB;
        assert!(invalid_input(err(&h, &iso(), &req())));
    }
    #[test]
    fn refuses_partition_sum_over_disk_size() {
        let mut h = host();
        h.disks[0].size_bytes = 250 * GIB; // each <= disk, sum 300 > 250
        assert!(invalid_input(err(&h, &iso(), &req())));
    }
    #[test]
    fn refuses_partition_sum_overflow() {
        let mut h = host();
        h.disks[0].size_bytes = u64::MAX;
        h.disks[0].partitions[0].size_bytes = u64::MAX;
        h.disks[0].partitions[1].size_bytes = u64::MAX;
        assert!(invalid_input(err(&h, &iso(), &req())));
    }
    #[test]
    fn refuses_duplicate_disk_numbers() {
        let mut h = host();
        let d = h.disks[0].clone();
        h.disks.push(d);
        assert!(invalid_input(err(&h, &iso(), &req())));
    }
    #[test]
    fn refuses_duplicate_partition_numbers() {
        let mut h = host();
        h.disks[0].partitions[0].number = 3;
        assert!(invalid_input(err(&h, &iso(), &req())));
    }
    #[test]
    fn mbr_needs_room_for_two_more() {
        let mut h = host();
        h.disks[0].style = PartitionStyle::Mbr;
        assert_eq!(err(&h, &iso(), &req()), Refusal::TooManyPrimaryPartitions); // 3 + 2 > 4
        h.disks[0].partitions.remove(0);
        assert!(check(&h, &iso(), &req()).is_ok()); // 2 + 2 == 4
    }
    #[test]
    fn refuses_mbr_with_four_partitions() {
        let mut h = host();
        h.disks[0].style = PartitionStyle::Mbr;
        h.disks[0].partitions.push(part(4));
        assert_eq!(err(&h, &iso(), &req()), Refusal::TooManyPrimaryPartitions);
    }
    #[test]
    fn accepts_gpt_with_four_partitions() {
        let mut h = host();
        h.disks[0].partitions.push(part(4));
        assert!(check(&h, &iso(), &req()).is_ok());
    }
    #[test]
    fn gpt_limit_is_128_including_new_two() {
        let mut h = host();
        h.disks[0].size_bytes = 200_000 * GIB;
        h.disks[0].partitions = (1..=126).map(part).collect();
        h.windows_partition = (0, 3);
        win_at(&mut h, 2).size_bytes = GIB * 100;
        assert!(check(&h, &iso(), &req()).is_ok()); // 126 + 2 == 128
        h.disks[0].partitions.push(part(127));
        assert_eq!(err(&h, &iso(), &req()), Refusal::TooManyPrimaryPartitions);
    }
    fn win_at(h: &mut HostFacts, i: usize) -> &mut Partition {
        &mut h.disks[0].partitions[i]
    }
    #[test]
    fn disk_with_zero_partitions_is_no_suitable_disk() {
        let mut h = host();
        h.disks[0].partitions.clear();
        assert_eq!(err(&h, &iso(), &req()), Refusal::NoSuitableDisk);
    }
    #[test]
    fn refuses_iso_file_over_fat32_limit() {
        let mut i = iso();
        i.largest_file_bytes = FAT32_MAX_FILE + 1;
        i.extracted_bytes = FAT32_MAX_FILE + 1;
        assert_eq!(
            err(&host(), &i, &req()),
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
        i.extracted_bytes = FAT32_MAX_FILE;
        assert!(check(&host(), &i, &req()).is_ok());
    }
    #[test]
    fn refuses_largest_file_bigger_than_content() {
        let mut i = iso();
        i.largest_file_bytes = i.extracted_bytes + 1;
        assert!(invalid_input(err(&host(), &i, &req())));
    }
    #[test]
    fn refuses_zero_extracted_and_zero_linux_space() {
        let mut i = iso();
        i.extracted_bytes = 0;
        i.largest_file_bytes = 0;
        assert!(invalid_input(err(&host(), &i, &req())));
        assert!(invalid_input(err(
            &host(),
            &iso(),
            &Request {
                linux_space_bytes: 0
            }
        )));
    }
    #[test]
    fn linux_space_minimum_boundary() {
        let r = |n| Request {
            linux_space_bytes: n,
        };
        assert_eq!(
            err(&host(), &iso(), &r(MIN_LINUX_SPACE - 1)),
            Refusal::LinuxSpaceTooSmall {
                min: MIN_LINUX_SPACE,
                given: MIN_LINUX_SPACE - 1
            }
        );
        assert!(check(&host(), &iso(), &r(MIN_LINUX_SPACE)).is_ok());
    }
    #[test]
    fn staging_upper_bound() {
        let mut h = host();
        h.disks[0].size_bytes = 1000 * GIB;
        win(&mut h).size_bytes = 500 * GIB;
        let at = |extracted: u64| IsoFacts {
            size_bytes: extracted,
            extracted_bytes: extracted,
            largest_file_bytes: GIB,
            largest_file_name: "f".into(),
        };
        assert!(check(&h, &at(MAX_STAGING - STAGING_MARGIN), &req()).is_ok());
        assert_eq!(
            err(&h, &at(MAX_STAGING - STAGING_MARGIN + 1), &req()),
            Refusal::StagingTooLarge {
                max: MAX_STAGING,
                given: MAX_STAGING + 1
            }
        );
    }

    /// Request that makes needed == available for the default host (size 100, used/min 20).
    fn exact_req(h: &HostFacts) -> Request {
        let w = &h.disks[0].partitions[2];
        let avail =
            w.size_bytes - w.used_bytes.max(w.min_size_bytes) - windows_reserve(w.size_bytes);
        Request {
            linux_space_bytes: avail - staging_size(&iso()).unwrap(),
        }
    }
    #[test]
    fn accepts_exactly_enough() {
        let h = host();
        let r = exact_req(&h);
        let (_, _, needed) = check(&h, &iso(), &r).unwrap();
        assert_eq!(needed, r.linux_space_bytes + staging_size(&iso()).unwrap());
    }
    #[test]
    fn refuses_one_byte_short() {
        let h = host();
        let mut r = exact_req(&h);
        r.linux_space_bytes += 1;
        let Refusal::NotEnoughFreeSpace { needed, available } = err(&h, &iso(), &r) else {
            panic!()
        };
        assert_eq!(needed, available + 1);
    }
    #[test]
    fn min_size_dominates_used() {
        let mut h = host();
        win(&mut h).min_size_bytes = 60 * GIB; // used 20 -> floor 60
        let mut r = exact_req(&h);
        assert_eq!(
            r.linux_space_bytes + staging_size(&iso()).unwrap(),
            30 * GIB
        );
        assert!(check(&h, &iso(), &r).is_ok());
        r.linux_space_bytes += 1;
        assert!(matches!(
            err(&h, &iso(), &r),
            Refusal::NotEnoughFreeSpace { .. }
        ));
    }
    #[test]
    fn reserve_is_ten_percent_with_ten_gib_floor() {
        assert_eq!(windows_reserve(50 * GIB), 10 * GIB);
        assert_eq!(windows_reserve(400 * GIB), 40 * GIB);
    }
    #[test]
    fn refuses_min_size_over_partition_size() {
        let mut h = host();
        win(&mut h).min_size_bytes = 101 * GIB;
        assert!(invalid_input(err(&h, &iso(), &req())));
    }
    #[test]
    fn huge_values_do_not_overflow() {
        let mut i = iso();
        i.extracted_bytes = u64::MAX;
        assert!(matches!(staging_size(&i), Err(Refusal::InvalidInput(_))));
        assert!(invalid_input(err(&host(), &i, &req())));
        let r = Request {
            linux_space_bytes: u64::MAX,
        };
        assert!(invalid_input(err(&host(), &iso(), &r)));
        let mut h = host();
        win(&mut h).used_bytes = u64::MAX; // used > size
        assert!(invalid_input(err(&h, &iso(), &req())));
    }
    #[test]
    fn max_sized_disk_sum_fits_but_needed_exceeds_available() {
        let mut h = host();
        h.disks[0].size_bytes = u64::MAX;
        h.disks[0].partitions = vec![Partition {
            size_bytes: u64::MAX,
            used_bytes: 0,
            min_size_bytes: 0,
            ..part(3)
        }];
        let r = Request {
            linux_space_bytes: u64::MAX - 100 * GIB,
        };
        assert!(matches!(
            err(&h, &iso(), &r),
            Refusal::NotEnoughFreeSpace { .. }
        ));
    }
    #[test]
    fn check_order_not_uefi_wins_over_others() {
        let mut h = host();
        h.uefi = false;
        h.disks[0].dynamic = true;
        win(&mut h).encrypted = None;
        assert_eq!(err(&h, &iso(), &req()), Refusal::NotUefi);
    }
    #[test]
    fn no_disks_is_no_suitable_disk() {
        let mut h = host();
        h.disks.clear();
        assert_eq!(err(&h, &iso(), &req()), Refusal::NoSuitableDisk);
    }
}
