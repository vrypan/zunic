use std::{hint::black_box, path::Path, time::Instant};

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
const WIDTH: usize = 80;
const VIEWPORT: usize = 24;
const SAMPLES: usize = 15;
const TARGET_NS: u128 = 50_000_000;

#[cfg(feature = "cellwidth-bench")]
fn wrap_all(text: &str) -> usize {
    let lines = cellwidth::wrap(black_box(text), WIDTH);
    black_box(&lines);
    lines.len()
}

// cellwidth::wrap is eager: asking for a viewport still wraps and allocates
// the complete document before the caller can discard the tail.
#[cfg(feature = "cellwidth-bench")]
fn wrap_first_24(text: &str) -> usize {
    let lines = cellwidth::wrap(black_box(text), WIDTH);
    black_box(&lines);
    lines.len().min(VIEWPORT)
}

fn textwrap_options() -> textwrap::Options<'static> {
    textwrap::Options::new(WIDTH).wrap_algorithm(textwrap::WrapAlgorithm::FirstFit)
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct Result {
    count: usize,
    checksum: u64,
}

fn textwrap_pass(bytes: &[u8], limit: usize) -> Result {
    let text = std::str::from_utf8(black_box(bytes)).unwrap();
    let lines = textwrap::wrap(text, &textwrap_options());
    let count = lines.len().min(limit);
    let result = Result {
        count,
        checksum: checksum_textwrap(&lines[..count]),
    };
    // Materialized output remains observable until destruction, inside timing.
    black_box(&lines);
    result
}
fn textwrap_all(bytes: &[u8]) -> Result {
    textwrap_pass(bytes, usize::MAX)
}
fn textwrap_first_24(bytes: &[u8]) -> Result {
    textwrap_pass(bytes, VIEWPORT)
}

fn measure(name: &str, op: &str, text: &[u8], pass: impl Fn(&[u8]) -> Result) {
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

#[cfg(feature = "cellwidth-bench")]
fn checksum(lines: &[String]) -> u64 {
    let mut hash = 0xcbf29ce484222325u64;
    for line in lines {
        for byte in line.bytes() {
            hash ^= u64::from(byte);
            hash = hash.wrapping_mul(0x100000001b3);
        }
        hash ^= 0xff;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn checksum_textwrap(lines: &[std::borrow::Cow<'_, str>]) -> u64 {
    let mut hash = 0xcbf29ce484222325u64;
    for line in lines {
        for byte in line.bytes() {
            hash ^= u64::from(byte);
            hash = hash.wrapping_mul(0x100000001b3);
        }
        hash ^= 0xff;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn load(directory: &Path, name: &str) -> String {
    std::fs::read_to_string(directory.join(format!("{name}.txt")))
        .unwrap_or_else(|error| panic!("failed to read corpus {name}: {error}"))
}

const HELP: &str = "Usage: cellwidth-wrap-bench CORPUS_DIR MODE\n\nModes:\n  --bench  Run timing benchmarks\n  --dump   Print exact output records (bytes are hex-encoded)\n  --check  Print output counts and checksums\n  --help, -h  Print this help\n\nNo arguments prints help. CORPUS_DIR is read before timing.\n";

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

    let mut args = std::env::args_os().skip(1);
    let directory = args
        .next()
        .expect("usage: cellwidth-wrap-bench CORPUS_DIR MODE");
    let mode = args.next();
    let check = mode.as_deref() == Some(std::ffi::OsStr::new("--check"));
    let dump = mode.as_deref() == Some(std::ffi::OsStr::new("--dump"));
    assert!(
        mode.as_deref() == Some(std::ffi::OsStr::new("--bench")) || check || dump,
        "unknown mode"
    );
    assert!(args.next().is_none(), "unexpected extra argument");
    let directory = Path::new(&directory);

    if dump {
        for name in CORPORA {
            let text = load(directory, name);
            print!("case={name} input=");
            for byte in text.as_bytes() {
                print!("{byte:02x}");
            }
            println!();
            for line in textwrap::wrap(&text, &textwrap_options()) {
                print!("L ");
                for byte in line.as_bytes() {
                    print!("{byte:02x}");
                }
                println!();
            }
        }
        return;
    }
    if check {
        for name in CORPORA {
            let text = load(directory, name);
            let textwrap_lines = textwrap::wrap(&text, &textwrap_options());
            #[cfg(feature = "cellwidth-bench")]
            {
                let cellwidth_lines = cellwidth::wrap(&text, WIDTH);
                println!(
                    "engine=cellwidth case={name} bytes={} lines={} checksum={:016x}",
                    text.len(),
                    cellwidth_lines.len(),
                    checksum(&cellwidth_lines),
                );
            }
            println!(
                "engine=textwrap-first-fit case={name} bytes={} lines={} checksum={:016x}",
                text.len(),
                textwrap_lines.len(),
                checksum_textwrap(&textwrap_lines),
            );
        }
        return;
    }

    println!(
        "protocol=1 suite=wrap peer=rust engine=textwrap-0.16.2-first-fit unicode=15.0.0+width-17.0.0 samples={SAMPLES} calibration_ms={} input=bytes consumption=line_bytes_fnv1",
        TARGET_NS / 1_000_000,
    );
    for name in CORPORA {
        let text = std::fs::read(directory.join(format!("{name}.txt"))).unwrap();
        #[cfg(feature = "cellwidth-bench")]
        {
            measure(name, "cellwidth_wrap", &text, |bytes| Result {
                count: wrap_all(std::str::from_utf8(black_box(bytes)).unwrap()),
                checksum: 0,
            });
            measure(name, "cellwidth_full_take24", &text, |bytes| Result {
                count: wrap_first_24(std::str::from_utf8(black_box(bytes)).unwrap()),
                checksum: 0,
            });
        }
        measure(name, "textwrap_first_fit", &text, textwrap_all);
        measure(name, "textwrap_first_fit_take24", &text, textwrap_first_24);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wraps_every_shared_corpus_within_the_requested_width() {
        let directory = Path::new(env!("CARGO_MANIFEST_DIR")).join("../texts");
        for name in CORPORA {
            let text = load(&directory, name);
            #[cfg(feature = "cellwidth-bench")]
            {
                let lines = cellwidth::wrap(&text, WIDTH);
                assert!(!lines.is_empty(), "{name}");
                for (index, line) in lines.iter().enumerate() {
                    assert!(
                        cellwidth::width(line) <= WIDTH,
                        "{name} line {index} is wider than {WIDTH} columns"
                    );
                }
            }
            let lines = textwrap::wrap(&text, &textwrap_options());
            assert_eq!(
                textwrap_all(text.as_bytes()).checksum,
                checksum_textwrap(&lines)
            );
            assert_eq!(
                textwrap_first_24(text.as_bytes()).checksum,
                checksum_textwrap(&lines[..lines.len().min(VIEWPORT)])
            );
            assert!(!lines.is_empty(), "{name}");
            for (index, line) in lines.iter().enumerate() {
                assert!(
                    textwrap::core::display_width(line) <= WIDTH,
                    "textwrap: {name} line {index} is wider than {WIDTH} columns"
                );
            }
        }
    }

    #[test]
    fn viewport_operation_reports_at_most_24_lines() {
        let directory = Path::new(env!("CARGO_MANIFEST_DIR")).join("../texts");
        for name in CORPORA {
            let text = load(&directory, name);
            #[cfg(feature = "cellwidth-bench")]
            assert_eq!(
                wrap_first_24(&text),
                wrap_all(&text).min(VIEWPORT),
                "{name}"
            );
            assert_eq!(
                textwrap_first_24(text.as_bytes()).count,
                textwrap_all(text.as_bytes()).count.min(VIEWPORT),
                "textwrap: {name}"
            );
        }
    }
}
