use std::{hint::black_box, path::Path, time::Instant};
use unicode_normalization::UnicodeNormalization;

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

fn load(directory: &Path, name: &str) -> String {
    std::fs::read_to_string(directory.join(format!("{name}.txt"))).unwrap()
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct BenchResult {
    units: usize,
    checksum: u64,
}

fn consume(iter: impl Iterator<Item = char>) -> BenchResult {
    iter.fold(BenchResult::default(), |mut result, cp| {
        result.units += 1;
        result.checksum = result.checksum.wrapping_add(cp as u64);
        result
    })
}

fn nfc_bytes(bytes: &[u8]) -> BenchResult {
    consume(
        std::str::from_utf8(bytes)
            .expect("benchmark requires valid UTF-8")
            .nfc(),
    )
}

fn nfd_bytes(bytes: &[u8]) -> BenchResult {
    consume(
        std::str::from_utf8(bytes)
            .expect("benchmark requires valid UTF-8")
            .nfd(),
    )
}

fn nfkc_bytes(bytes: &[u8]) -> BenchResult {
    consume(
        std::str::from_utf8(bytes)
            .expect("benchmark requires valid UTF-8")
            .nfkc(),
    )
}

fn nfkd_bytes(bytes: &[u8]) -> BenchResult {
    consume(
        std::str::from_utf8(bytes)
            .expect("benchmark requires valid UTF-8")
            .nfkd(),
    )
}

const HELP: &str = "Usage: unicode-normalization-zunic CORPUS_DIR MODE\n\nModes:\n  --bench  Run timing benchmarks\n  --dump   Print exact output records (bytes are hex-encoded)\n  --bench-prevalidated  Diagnostic timings with UTF-8 validation excluded\n  --help, -h  Print this help\n\nNo arguments prints help. CORPUS_DIR is read before timing.\n";

fn main() {
    let cli: Vec<_> = std::env::args_os().collect();
    if cli.len() == 1 || (cli.len() == 2 && (cli[1] == "--help" || cli[1] == "-h")) {
        print!("{}", HELP);
        return;
    }
    if cli.len() != 3
        || !["--bench", "--dump", "--bench-prevalidated"]
            .iter()
            .any(|mode| cli[2] == *mode)
    {
        eprintln!("Invalid arguments.\n{HELP}");
        std::process::exit(2);
    }

    let mut args = std::env::args_os().skip(1);
    let directory = args
        .next()
        .expect("usage: unicode-normalization-zunic CORPUS_DIR --dump");
    let mode_arg = args.next();
    let mode = mode_arg.as_deref().and_then(|value| value.to_str());
    assert!(args.next().is_none());
    if matches!(mode, Some("--bench" | "--bench-prevalidated")) {
        assert_eq!(unicode_normalization::UNICODE_VERSION, (16, 0, 0));
        let prevalidated = mode == Some("--bench-prevalidated");
        let input = if prevalidated {
            "prevalidated"
        } else {
            "bytes"
        };
        println!("protocol=1 suite=normalize peer=rust engine=unicode-normalization-0.1.24 unicode=16.0.0 samples=15 calibration_ms=50 input={input} consumption=scalar_sum_v1");
        for name in CORPORA {
            if !prevalidated {
                // File I/O is outside timing; validation is inside every pass.
                let bytes =
                    std::fs::read(Path::new(&directory).join(format!("{name}.txt"))).unwrap();
                measure(name, "nfc", bytes.as_slice(), bytes.len(), nfc_bytes);
                measure(name, "nfd", bytes.as_slice(), bytes.len(), nfd_bytes);
                measure(name, "nfkc", bytes.as_slice(), bytes.len(), nfkc_bytes);
                measure(name, "nfkd", bytes.as_slice(), bytes.len(), nfkd_bytes);
                continue;
            }
            let text = load(Path::new(&directory), name);
            measure(name, "nfc", text.as_str(), text.len(), |text| {
                consume(text.nfc())
            });
            measure(name, "nfd", text.as_str(), text.len(), |text| {
                consume(text.nfd())
            });
            measure(name, "nfkc", text.as_str(), text.len(), |text| {
                consume(text.nfkc())
            });
            measure(name, "nfkd", text.as_str(), text.len(), |text| {
                consume(text.nfkd())
            });
        }
        return;
    }
    assert_eq!(mode, Some("--dump"));
    for name in CORPORA {
        let text = load(Path::new(&directory), name);
        for (form, normalized) in [
            ("nfc", text.nfc().collect::<String>()),
            ("nfd", text.nfd().collect::<String>()),
            ("nfkc", text.nfkc().collect::<String>()),
            ("nfkd", text.nfkd().collect::<String>()),
        ] {
            print!("case={name} form={form} input=");
            for byte in text.bytes() {
                print!("{byte:02x}");
            }
            print!(" hex=");
            for byte in normalized.bytes() {
                print!("{byte:02x}");
            }
            println!();
        }
    }
}

fn measure<T: Copy>(
    name: &str,
    operation: &str,
    input: T,
    byte_len: usize,
    pass: fn(T) -> BenchResult,
) {
    let mut iterations = 1usize;
    loop {
        let start = Instant::now();
        for _ in 0..iterations {
            black_box(pass(black_box(input)));
        }
        let elapsed = start.elapsed().as_nanos();
        if elapsed >= 50_000_000 || iterations >= 1 << 20 {
            break;
        }
        iterations = iterations
            .saturating_mul((50_000_000 / elapsed.max(1)).max(2) as usize)
            .min(1 << 20);
    }
    let mut samples = [0u128; 15];
    let mut result = BenchResult::default();
    for sample in &mut samples {
        let start = Instant::now();
        for _ in 0..iterations {
            result = pass(black_box(input));
            black_box(result);
        }
        *sample = start.elapsed().as_nanos() / iterations as u128;
    }
    println!("case={name} op={operation} raw_samples={samples:?}");
    samples.sort_unstable();
    let per = samples[7];
    let mut deviations = samples.map(|sample| sample.abs_diff(per));
    deviations.sort_unstable();
    println!("case={name} op={operation} bytes={byte_len} units={} iterations={iterations} ns={per} mad={} checksum={}", result.units, deviations[7], result.checksum);
}

#[cfg(test)]
mod tests {
    use super::*;
    use unicode_normalization::{is_nfc, is_nfd, is_nfkc, is_nfkd};

    #[test]
    fn byte_passes_match_prevalidated_and_reject_invalid_utf8() {
        for text in ["", "ASCII", "a\u{301}", "\u{d4db}", "\u{fb01}"] {
            assert_eq!(
                nfc_bytes(text.as_bytes()).checksum,
                text.nfc().map(|cp| cp as u64).sum()
            );
            assert_eq!(
                nfd_bytes(text.as_bytes()).checksum,
                text.nfd().map(|cp| cp as u64).sum()
            );
            assert_eq!(
                nfkc_bytes(text.as_bytes()).checksum,
                text.nfkc().map(|cp| cp as u64).sum()
            );
            assert_eq!(
                nfkd_bytes(text.as_bytes()).checksum,
                text.nfkd().map(|cp| cp as u64).sum()
            );
        }
        for pass in [nfc_bytes, nfd_bytes, nfkc_bytes, nfkd_bytes] {
            assert!(std::panic::catch_unwind(|| pass(&[0xff])).is_err());
        }
    }

    fn decode_fixture_field(field: &str) -> String {
        field
            .split_whitespace()
            .map(|hex| char::from_u32(u32::from_str_radix(hex, 16).unwrap()).unwrap())
            .collect()
    }
    #[test]
    fn canonical_forms_are_idempotent_over_shared_corpora_and_crate_regressions() {
        let mut inputs = vec![
            "a\u{301}".to_string(),
            "\u{2126}".to_string(),
            "\u{1e0b}\u{323}".to_string(),
            "\u{d4db}".to_string(),
            "a\u{300}\u{305}\u{315}\u{5ae}b".to_string(),
        ];
        let directory = Path::new(env!("CARGO_MANIFEST_DIR")).join("../texts");
        inputs.extend(CORPORA.iter().map(|name| load(&directory, name)));
        for text in inputs {
            let nfc = text.nfc().collect::<String>();
            let nfd = text.nfd().collect::<String>();
            let nfkc = text.nfkc().collect::<String>();
            let nfkd = text.nfkd().collect::<String>();
            assert!(is_nfc(&nfc));
            assert!(is_nfd(&nfd));
            assert!(is_nfkc(&nfkc));
            assert!(is_nfkd(&nfkd));
            assert_eq!(nfc.nfc().collect::<String>(), nfc);
            assert_eq!(nfd.nfd().collect::<String>(), nfd);
            assert_eq!(nfkc.nfkc().collect::<String>(), nfkc);
            assert_eq!(nfkd.nfkd().collect::<String>(), nfkd);
        }
    }

    #[test]
    fn rust_peer_agrees_with_zunics_vendored_unicode_16_fixture() {
        let fixture = include_str!("../../../src/data/NormalizationTest-16.0.0.txt");
        let mut cases = 0usize;
        for raw in fixture.lines() {
            let body = raw.split_once('#').map_or(raw, |(body, _)| body).trim();
            if body.is_empty() || body.starts_with('@') {
                continue;
            }
            let fields: Vec<_> = body.split(';').take(5).map(str::trim).collect();
            assert_eq!(fields.len(), 5, "{raw}");
            let columns: Vec<_> = fields
                .iter()
                .map(|field| decode_fixture_field(field))
                .collect();
            for (index, input) in columns.iter().enumerate() {
                let (nfc, nfd) = if index < 3 {
                    (&columns[1], &columns[2])
                } else {
                    (&columns[3], &columns[4])
                };
                assert_eq!(&input.nfc().collect::<String>(), nfc, "{raw}");
                assert_eq!(&input.nfd().collect::<String>(), nfd, "{raw}");
                // NFKC and NFKD target c4 and c5 regardless of which column
                // is the source -- unlike NFC/NFD, which split at index 3.
                assert_eq!(&input.nfkc().collect::<String>(), &columns[3], "{raw}");
                assert_eq!(&input.nfkd().collect::<String>(), &columns[4], "{raw}");
            }
            cases += 1;
        }
        assert_eq!(cases, 19_965);
    }
}
