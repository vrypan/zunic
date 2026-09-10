use std::{hint::black_box, time::Instant};
use unicode_linebreak::{break_property, linebreaks, BreakOpportunity};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct Result {
    count: usize,
    checksum: u64,
}
fn full(bytes: &[u8]) -> Result {
    let text = std::str::from_utf8(black_box(bytes)).unwrap();
    let mut result = Result::default();
    for (offset, opportunity) in linebreaks(text) {
        result.count += 1;
        result.checksum = result.checksum.wrapping_mul(31).wrapping_add(offset as u64);
        let kind = match opportunity {
            BreakOpportunity::Allowed => 1,
            BreakOpportunity::Mandatory => 2,
        };
        result.checksum = result.checksum.wrapping_mul(31).wrapping_add(kind);
    }
    result
}

fn classify(bytes: &[u8]) -> Result {
    let text = std::str::from_utf8(black_box(bytes)).unwrap();
    let mut result = Result::default();
    for cp in text.chars() {
        result.count += 1;
        result.checksum = result
            .checksum
            .wrapping_add(break_property(cp as u32) as u64);
    }
    result
}

fn measure(name: &str, op: &str, text: &[u8], pass: impl Fn(&[u8]) -> Result) {
    let mut iterations = 1;
    loop {
        let start = Instant::now();
        for _ in 0..iterations {
            black_box(pass(text));
        }
        if start.elapsed().as_nanos() >= 50_000_000 {
            break;
        }
        iterations *= 2;
    }
    let mut samples = [0u128; 15];
    let mut result = Result::default();
    for sample in &mut samples {
        let start = Instant::now();
        for _ in 0..iterations {
            result = pass(text);
            black_box(result);
        }
        *sample = start.elapsed().as_nanos() / iterations;
    }
    println!("case={name} op={op} raw_samples={samples:?}");
    samples.sort_unstable();
    let median = samples[7];
    let mut devs = samples.map(|s| s.abs_diff(median));
    devs.sort_unstable();
    println!(
        "case={name} op={op} bytes={} units={} iterations={iterations} ns={median} mad={} checksum={}",
        text.len(),
        result.count,
        devs[7],
        result.checksum
    );
}

const HELP: &str = "Usage: diagnostic CORPUS_DIR MODE\n\nModes:\n  --bench  Run timing benchmarks\n  --dump   Print exact output records (bytes are hex-encoded)\n  --streams  Alias for --dump\n  --help, -h  Print this help\n\nNo arguments prints help. CORPUS_DIR is read before timing.\n";

fn main() {
    let cli: Vec<_> = std::env::args_os().collect();
    if cli.len() == 1 || (cli.len() == 2 && (cli[1] == "--help" || cli[1] == "-h")) {
        print!("{}", HELP);
        return;
    }
    if cli.len() != 3
        || !["--bench", "--dump", "--streams"]
            .iter()
            .any(|mode| cli[2] == *mode)
    {
        eprintln!("Invalid arguments.\n{HELP}");
        std::process::exit(2);
    }

    let directory = std::env::args().nth(1).expect("corpus directory");
    let streams = matches!(
        std::env::args().nth(2).as_deref(),
        Some("--dump" | "--streams")
    );
    let names = [
        "arabic",
        "hindi",
        "korean",
        "russian",
        "source_code",
        "english",
        "japanese",
        "mandarin",
    ];
    if streams {
        for name in names {
            let text = std::fs::read_to_string(format!("{directory}/{name}.txt")).unwrap();
            print!("case={name} input=");
            for byte in text.as_bytes() {
                print!("{byte:02x}");
            }
            println!();
            print!("case={name} stream=");
            for (offset, opportunity) in linebreaks(&text) {
                let kind = match opportunity {
                    BreakOpportunity::Allowed => "allowed",
                    BreakOpportunity::Mandatory => "mandatory",
                };
                print!("{offset}:{kind},");
            }
            println!();
        }
        return;
    }
    println!("protocol=1 suite=linebreak peer=rust engine=unicode-linebreak-0.1.5 unicode=15.0.0+SA samples=15 calibration_ms=50 input=bytes consumption=offset_status_checksum_v1");
    for name in names {
        let text = std::fs::read(format!("{directory}/{name}.txt")).unwrap();
        measure(name, "opportunities_only", &text, full);
        measure(name, "decode_classify", &text, classify);
    }
}
