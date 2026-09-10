use std::{hint::black_box, io::Write, path::Path, time::Instant};
const SAMPLES: usize = 15;
const TARGET_NS: u128 = 50_000_000;

const CORPORA: &[&str] = &[
    "plain_ascii",
    "plain_ascii_64k",
    "sparse_sgr",
    "dense_sgr",
    "unicode",
    "osc_links",
    "commands_only",
    "custom_osc",
    "split_grapheme",
    "long_osc",
];
const CASES: &[&str] = &[
    "plain_ascii",
    "plain_ascii_64k",
    "sparse_sgr",
    "dense_sgr",
    "unicode",
    "osc_links",
    "commands_only",
    "custom_osc",
    "split_grapheme",
    "long_osc",
    "controls",
    "invalid_utf8",
    "incomplete_csi",
    "incomplete_osc",
    "dcs",
    "c1",
    "malformed_osc",
    "empty",
];

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct Result {
    count: usize,
    checksum: u64,
}
fn consume(bytes: &[u8]) -> Result {
    let mut checksum = 0xcbf29ce484222325u64;
    for &byte in bytes {
        checksum = (checksum ^ u64::from(byte)).wrapping_mul(0x100000001b3);
    }
    Result {
        count: bytes.len(),
        checksum,
    }
}
fn write_reused(bytes: &[u8], output: &mut Vec<u8>) {
    output.clear();
    // Reset the parser for every independent document. into_inner flushes the
    // crate's internal LineWriter. Its allocation and destruction remain timed.
    let mut writer = strip_ansi_escapes::Writer::new(output);
    writer.write_all(black_box(bytes)).unwrap();
    writer.into_inner().unwrap();
}
fn allocated(bytes: &[u8]) -> Result {
    let output = strip_ansi_escapes::strip(black_box(bytes));
    let result = consume(&output);
    black_box(&output);
    result // Vec destruction is inside the measured pass.
}
fn measure(name: &str, op: &str, text: &[u8], mut pass: impl FnMut(&[u8]) -> Result) {
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
    let mut lines = Result::default();
    for sample in &mut samples {
        let start = Instant::now();
        for _ in 0..iterations {
            lines = pass(text);
            black_box(lines);
        }
        *sample = start.elapsed().as_nanos() / iterations as u128;
    }
    println!("case={name} op={op} raw_samples={samples:?}");
    samples.sort_unstable();
    let median = samples[SAMPLES / 2];
    let mut deviations = samples.map(|sample| sample.abs_diff(median));
    deviations.sort_unstable();
    println!(
        "case={name} op={op} bytes={} units={} iterations={iterations} ns={median} mad={} checksum={}",
        text.len(),
        lines.count,
        deviations[SAMPLES / 2],
        lines.checksum,
    );
}

fn load(directory: &Path, name: &str) -> Vec<u8> {
    std::fs::read(directory.join(format!("{name}.txt"))).unwrap()
}
const HELP: &str = "Usage: rust-strip-ansi-bench CORPUS_DIR MODE\n\nModes:\n  --bench  Run timing benchmarks\n  --dump   Print exact output records (bytes are hex-encoded)\n  --check  Print output counts and checksums\n  --help, -h  Print this help\n\nNo arguments prints help. CORPUS_DIR is read before timing.\n";

fn main() {
    let cli: Vec<_> = std::env::args_os().collect();
    if cli.len() == 1 || (cli.len() == 2 && (cli[1] == "--help" || cli[1] == "-h")) {
        print!("{}", HELP);
        return;
    }
    if cli.len() != 3
        || !["--bench", "--dump", "--check"]
            .iter()
            .any(|mode| cli[2] == *mode)
    {
        eprintln!("Invalid arguments.\n{HELP}");
        std::process::exit(2);
    }

    let args: Vec<_> = std::env::args().skip(1).collect();
    assert!((1..=2).contains(&args.len()));
    let directory = Path::new(&args[0]);
    if args[1] != "--bench" {
        assert!(args[1] == "--dump" || args[1] == "--check");
        for &name in CASES {
            let input = load(directory, name);
            let output = strip_ansi_escapes::strip(&input);
            let mut reused = Vec::with_capacity(input.len() * 3);
            write_reused(&input, &mut reused);
            assert_eq!(output, reused, "Rust APIs differ for {name}");
            if args[1] == "--dump" {
                print!("case={name} input=");
                for byte in &input {
                    print!("{byte:02x}");
                }
                print!("\nB ");
                for byte in &output {
                    print!("{byte:02x}");
                }
                println!();
            } else {
                let result = consume(&output);
                println!(
                    "case={name} bytes={} units={} checksum={}",
                    input.len(),
                    result.count,
                    result.checksum
                );
            }
        }
        return;
    }
    println!("protocol=1 suite=strip_ansi peer=rust engine=strip-ansi-escapes-0.2.1 unicode=not-applicable samples=15 calibration_ms=50 input=bytes consumption=bytes_fnv1");
    for &name in CORPORA {
        let input = load(directory, name);
        let mut output = Vec::with_capacity(input.len());
        measure(name, "rust_reuse", &input, |bytes| {
            write_reused(bytes, &mut output);
            let result = consume(&output);
            black_box(&output);
            result
        });
        measure(name, "rust_alloc", &input, allocated);
    }
}
#[test]
fn byte_outputs_match_between_rust_apis() {
    for input in [
        b"\x1b[31mred\x1b[0m".as_slice(),
        b"",
        b"a\xff\t",
        b"\x1b]8;;url\x07x\x1b]8;;\x07",
    ] {
        let mut output = Vec::with_capacity(input.len() * 3);
        write_reused(input, &mut output);
        assert_eq!(output, strip_ansi_escapes::strip(input));
    }
}
