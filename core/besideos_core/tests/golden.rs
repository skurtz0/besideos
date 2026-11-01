use std::path::PathBuf;
use std::process::{Command, Output};

fn data(name: &str) -> String {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/data")
        .join(name)
        .to_str()
        .unwrap()
        .to_string()
}

fn run(host: &str) -> Output {
    Command::new(env!("CARGO_BIN_EXE_besideos-plan"))
        .args([
            "--host",
            &data(host),
            "--iso",
            &data("iso.json"),
            "--request",
            &data("request.json"),
            "--iso-path",
            "C:\\iso\\ubuntu.iso",
        ])
        .output()
        .unwrap()
}

#[test]
fn ok_host_matches_golden_plan() {
    let o = run("host_ok.json");
    assert_eq!(o.status.code(), Some(0));
    let golden = std::fs::read_to_string(data("plan_ok.golden.json")).unwrap();
    assert_eq!(String::from_utf8(o.stdout).unwrap(), golden);
}

#[test]
fn bitlocker_host_is_refused_exit_2() {
    let o = run("host_bitlocker.json");
    assert_eq!(o.status.code(), Some(2));
    let v: serde_json::Value = serde_json::from_slice(&o.stdout).unwrap();
    assert_eq!(v["refused"], "encrypted_target");
    assert!(!v["message"].as_str().unwrap().is_empty());
}

#[test]
fn missing_file_exits_1() {
    let o = run("nope.json");
    assert_eq!(o.status.code(), Some(1));
    assert!(o.stdout.is_empty());
    assert!(!o.stderr.is_empty());
}

#[test]
fn output_is_stable_across_runs() {
    assert_eq!(run("host_ok.json").stdout, run("host_ok.json").stdout);
}

#[test]
fn bitlocker_refusal_matches_golden() {
    let o = run("host_bitlocker.json");
    let golden = std::fs::read_to_string(data("refusal_bitlocker.golden.json")).unwrap();
    assert_eq!(String::from_utf8(o.stdout).unwrap(), golden);
}

#[test]
fn arm64_host_matches_golden_plan() {
    let o = Command::new(env!("CARGO_BIN_EXE_besideos-plan"))
        .args([
            "--host",
            &data("host_arm64.json"),
            "--iso",
            &data("iso_arm64.json"),
            "--request",
            &data("request.json"),
            "--iso-path",
            "C:\\iso\\ubuntu.iso",
        ])
        .output()
        .unwrap();
    assert_eq!(o.status.code(), Some(0));
    let golden = std::fs::read_to_string(data("plan_arm64.golden.json")).unwrap();
    assert_eq!(String::from_utf8(o.stdout).unwrap(), golden);
}

#[test]
fn arch_mismatch_exits_2() {
    let o = Command::new(env!("CARGO_BIN_EXE_besideos-plan"))
        .args([
            "--host",
            &data("host_arm64.json"),
            "--iso",
            &data("iso.json"),
            "--request",
            &data("request.json"),
            "--iso-path",
            "x",
        ])
        .output()
        .unwrap();
    assert_eq!(o.status.code(), Some(2));
    let v: serde_json::Value = serde_json::from_slice(&o.stdout).unwrap();
    assert_eq!(v["refused"], "arch_mismatch");
}
