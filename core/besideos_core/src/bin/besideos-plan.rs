#![forbid(unsafe_code)]
use besideos_core::facts::{HostFacts, IsoFacts, Request};
use besideos_core::plan::Refusal;
use besideos_core::win_to_linux::plan_windows_to_linux;
use std::process::ExitCode;

const USAGE: &str = "Kullanım: besideos-plan --host host.json --iso iso.json --request request.json --iso-path <yol>";

fn arg(args: &[String], name: &str) -> Result<String, String> {
    let i = args
        .iter()
        .position(|a| a == name)
        .ok_or_else(|| format!("{name} eksik. {USAGE}"))?;
    args.get(i + 1)
        .cloned()
        .ok_or_else(|| format!("{name} için değer eksik. {USAGE}"))
}

fn read(path: &str) -> Result<String, String> {
    std::fs::read_to_string(path).map_err(|e| format!("'{path}' okunamadı: {e}"))
}

fn run(args: &[String]) -> Result<Result<String, Refusal>, String> {
    let host = read(&arg(args, "--host")?)?;
    let iso = read(&arg(args, "--iso")?)?;
    let req = read(&arg(args, "--request")?)?;
    let iso_path = arg(args, "--iso-path")?;
    // Malformed JSON is a usage error (exit 1), not a planner refusal.
    let parsed = (|| {
        Ok::<_, Refusal>((
            HostFacts::from_json(&host)?,
            IsoFacts::from_json(&iso)?,
            Request::from_json(&req)?,
        ))
    })()
    .map_err(|r| r.message())?;
    let plan = plan_windows_to_linux(&parsed.0, &parsed.1, &parsed.2, &iso_path);
    Ok(plan.map(|p| serde_json::to_string_pretty(&p).expect("plan serializes") + "\n"))
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(Ok(json)) => {
            print!("{json}");
            ExitCode::SUCCESS
        }
        Ok(Err(r)) => {
            let v = serde_json::json!({ "refused": r.code(), "message": r.message() });
            println!("{}", serde_json::to_string_pretty(&v).expect("json"));
            ExitCode::from(2)
        }
        Err(msg) => {
            eprintln!("{msg}");
            ExitCode::from(1)
        }
    }
}
