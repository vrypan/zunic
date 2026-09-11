use std::{hint::black_box, path::Path, time::Instant};
use unicode_width::UnicodeWidthStr;

const CORPORA: &[&str] = &[
    "arabic",
    "hindi",
    "korean",
    "russian",
    "source_code",
    "english",
    "japanese",
    "mandarin",
];
const SAMPLES: usize = 15;
const TARGET_NS: u128 = 50_000_000;

fn str_width(bytes: &[u8]) -> usize {
    let text = std::str::from_utf8(black_box(bytes)).unwrap();
    text.width()
}

fn measure(name: &str, op: &str, text: &[u8], pass: impl Fn(&[u8]) -> usize) {
    black_box(pass(text));
    let mut iterations = 1usize;
    loop {
        let start = Instant::now();
        for _ in 0..iterations {
            black_box(pass(text));
        }
        let elapsed = start.elapsed().as_nanos();
        if elapsed >= TARGET_NS || iterations >= 1 << 20 {
            break;
        }
        let growth = (TARGET_NS / elapsed.max(1)).max(2) as usize;
        iterations = iterations.saturating_mul(growth).min(1 << 20);
    }

    let mut samples = [0u128; SAMPLES];
    let mut width = 0usize;
    for sample in &mut samples {
        let start = Instant::now();
        for _ in 0..iterations {
            width = pass(text);
            black_box(width);
        }
        *sample = start.elapsed().as_nanos() / iterations as u128;
    }
    println!("case={name} op={op} raw_samples={samples:?}");
    samples.sort_unstable();
    let median = samples[SAMPLES / 2];
    let mut deviations = samples.map(|sample| sample.abs_diff(median));
    deviations.sort_unstable();
    println!(
        "case={name} op={op} bytes={} units={width} iterations={iterations} ns={median} mad={} checksum={width}",
        text.len(),
        deviations[SAMPLES / 2],
    );
}

fn load(directory: &Path, name: &str) -> String {
    std::fs::read_to_string(directory.join(format!("{name}.txt")))
        .unwrap_or_else(|error| panic!("failed to read corpus {name}: {error}"))
}

const HELP: &str = "Usage: unicode-width-bench CORPUS_DIR MODE\n\nModes:\n  --bench  Run timing benchmarks\n  --dump   Print exact output records (bytes are hex-encoded)\n  --help, -h  Print this help\n\nNo arguments prints help. CORPUS_DIR is read before timing.\n";

fn main() {
    let cli: Vec<_> = std::env::args_os().collect();
    if cli.len() == 1 || (cli.len() == 2 && (cli[1] == "--help" || cli[1] == "-h")) {
        print!("{}", HELP);
        return;
    }
    if cli.len() != 3 || !["--bench", "--dump"].iter().any(|mode| cli[2] == *mode) {
        eprintln!("Invalid arguments.\n{HELP}");
        std::process::exit(2);
    }

    let mut args = std::env::args_os().skip(1);
    let directory = args
        .next()
        .expect("usage: unicode-width-bench CORPUS_DIR MODE");
    let mode = args.next();
    let mode = mode.as_deref().and_then(|value| value.to_str());
    assert!(args.next().is_none(), "unexpected extra argument");
    let directory = Path::new(&directory);

    if mode == Some("--dump") {
        for name in CORPORA {
            let text = load(directory, name);
            print!("case={name} input=");
            for byte in text.as_bytes() {
                print!("{byte:02x}");
            }
            println!(" width={}", text.width());
        }
        return;
    }
    assert_eq!(mode, Some("--bench"));

    println!(
        "protocol=1 suite=width peer=rust engine=unicode-width-0.2.2 unicode=17.0.0 samples={SAMPLES} calibration_ms={} input=bytes consumption=width_sum_v1",
        TARGET_NS / 1_000_000,
    );
    for name in CORPORA {
        let text = std::fs::read(directory.join(format!("{name}.txt"))).unwrap();
        measure(name, "unicode_width_str", &text, str_width);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn corpus_dir() -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../texts")
    }

    #[test]
    fn str_width_is_stable_across_repeated_calls() {
        for name in CORPORA {
            let text = load(&corpus_dir(), name);
            assert_eq!(str_width(text.as_bytes()), str_width(text.as_bytes()), "{name}");
        }
    }
}
