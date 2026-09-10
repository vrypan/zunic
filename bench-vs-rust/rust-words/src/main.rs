use std::{hint::black_box, path::Path, time::Instant};
use unicode_segmentation::UnicodeSegmentation;

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

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct Result {
    count: usize,
    checksum: u64,
}
impl Result {
    fn add(&mut self, start: usize, end: usize) {
        self.count += 1;
        self.checksum = self.checksum.wrapping_mul(31).wrapping_add(start as u64);
        self.checksum = self.checksum.wrapping_mul(31).wrapping_add(end as u64);
    }
}

fn split_word_bound_indices(bytes: &[u8]) -> Result {
    let text = std::str::from_utf8(black_box(bytes)).unwrap();
    let mut result = Result::default();
    for (start, segment) in text.split_word_bound_indices() {
        result.add(start, start + segment.len());
    }
    result
}

fn split_word_bound_indices_collect(bytes: &[u8]) -> Result {
    let text = std::str::from_utf8(black_box(bytes)).unwrap();
    let items: Vec<(usize, &str)> = text.split_word_bound_indices().collect();
    let mut result = Result::default();
    for &(start, segment) in &items {
        result.add(start, start + segment.len());
    }
    // Expose the complete collection before its destruction, not just its length.
    black_box(&items);
    result
}

fn unicode_words(bytes: &[u8]) -> Result {
    let text = std::str::from_utf8(black_box(bytes)).unwrap();
    let mut result = Result::default();
    for (start, word) in text.unicode_word_indices() {
        result.add(start, start + word.len());
    }
    result
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
    let mut items = Result::default();
    for sample in &mut samples {
        let start = Instant::now();
        for _ in 0..iterations {
            items = pass(text);
            black_box(items);
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
        items.count,
        deviations[SAMPLES / 2],
        items.checksum,
    );
}

// Byte-for-byte the mix in zunic's own benchmark harness, so the two peers'
// checksums are comparable rather than merely similar.
fn mix(state: u64, value: u64) -> u64 {
    (state ^ value.wrapping_add(0x9e37_79b9_7f4a_7c15)).wrapping_mul(0xbf58_476d_1ce4_e5b9)
}

/// The partition, each segment tagged with whether the crate considers it a
/// word.
///
/// The crate's `has_alphanumeric` is private and its tables are Unicode 17,
/// so reimplementing the predicate with `char::is_alphabetic` would silently
/// substitute the standard library's Unicode version. Instead this walks
/// `unicode_word_indices()` alongside the partition: `unicode_words` is
/// documented as the filtered subset of exactly these segments, in order, so
/// matching offsets identifies them and the flag comes from the crate itself.
fn tagged_bounds(text: &str) -> impl Iterator<Item = (usize, usize, bool)> + '_ {
    let mut words = text.unicode_word_indices().peekable();
    text.split_word_bound_indices()
        .map(move |(offset, segment)| {
            let is_word = words.peek().is_some_and(|(start, _)| *start == offset);
            if is_word {
                words.next();
            }
            (offset, offset + segment.len(), is_word)
        })
}

/// Segment extents and the word-like flag, in one checksum per corpus. Both
/// peers derive `end` the same way, so the two are directly comparable.
fn checksums(text: &str) -> (usize, usize, u64, u64) {
    let mut segments = 0usize;
    let mut words = 0usize;
    let mut bounds = 0xcbf29ce484222325u64;
    let mut flagged = 0xcbf29ce484222325u64;
    for (start, end, is_word) in tagged_bounds(text) {
        bounds = mix(mix(bounds, start as u64), end as u64);
        flagged = mix(flagged, u64::from(is_word));
        segments += 1;
        if is_word {
            words += 1;
        }
    }
    (segments, words, bounds, flagged)
}

fn load(directory: &Path, name: &str) -> String {
    std::fs::read_to_string(directory.join(format!("{name}.txt")))
        .unwrap_or_else(|error| panic!("failed to read corpus {name}: {error}"))
}

const HELP: &str = "Usage: unicode-words-bench CORPUS_DIR MODE\n\nModes:\n  --bench  Run timing benchmarks\n  --dump   Print exact output records (bytes are hex-encoded)\n  --check  Print output counts and checksums\n  --help, -h  Print this help\n\nNo arguments prints help. CORPUS_DIR is read before timing.\n";

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
        .expect("usage: unicode-words-bench CORPUS_DIR MODE");
    let mode = args.next();
    let mode = mode.as_deref().and_then(|value| value.to_str());
    assert!(args.next().is_none(), "unexpected extra argument");
    let directory = Path::new(&directory);

    let version = unicode_segmentation::UNICODE_VERSION;
    if mode == Some("--check") {
        for name in CORPORA {
            let text = load(directory, name);
            let (segments, words, bounds, flags) = checksums(&text);
            println!(
                "case={name} bytes={} segments={segments} words={words} \
                 bounds_checksum={bounds:016x} flag_checksum={flags:016x}",
                text.len()
            );
        }
        return;
    }

    if mode == Some("--dump") {
        for name in CORPORA {
            let text = load(directory, name);
            print!("case={name} input=");
            for byte in text.as_bytes() {
                print!("{byte:02x}");
            }
            println!();
            println!("case={name} bytes={}", text.len());
            for (start, end, is_word) in tagged_bounds(&text) {
                println!("S {start} {end} {}", u8::from(is_word));
            }
        }
        return;
    }
    assert_eq!(mode, Some("--bench"));

    println!(
        "protocol=1 suite=words peer=rust engine=unicode-segmentation-1.13.3 unicode={}.{}.{} samples={SAMPLES} calibration_ms={} input=bytes consumption=range_checksum_v1",
        version.0,
        version.1,
        version.2,
        TARGET_NS / 1_000_000,
    );
    for name in CORPORA {
        let text = std::fs::read(directory.join(format!("{name}.txt"))).unwrap();
        measure(name, "us_word_bounds", &text, split_word_bound_indices);
        measure(
            name,
            "us_word_bounds_collect",
            &text,
            split_word_bound_indices_collect,
        );
        measure(name, "us_words", &text, unicode_words);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn corpus_dir() -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../texts")
    }

    #[test]
    fn word_bounds_partition_every_shared_corpus() {
        for name in CORPORA {
            let text = load(&corpus_dir(), name);
            let mut cursor = 0usize;
            let mut segments = 0usize;
            for (offset, segment) in text.split_word_bound_indices() {
                assert_eq!(
                    offset, cursor,
                    "{name}: segment {segments} is not contiguous"
                );
                assert!(!segment.is_empty(), "{name}: empty segment {segments}");
                cursor = offset + segment.len();
                segments += 1;
            }
            assert_eq!(
                cursor,
                text.len(),
                "{name}: partition does not reach the end"
            );
            assert!(segments > 0, "{name}");
        }
    }

    // The flag in --check and --dump comes from walking unicode_word_indices
    // beside the partition. If that walk ever fell out of step the comparison
    // against Zunic would be meaningless, so pin it against the crate directly.
    #[test]
    fn tagged_bounds_reproduces_unicode_words_exactly() {
        for name in CORPORA {
            let text = load(&corpus_dir(), name);
            let tagged: Vec<&str> = tagged_bounds(&text)
                .filter(|(_, _, is_word)| *is_word)
                .map(|(start, end, _)| &text[start..end])
                .collect();
            let words: Vec<&str> = text.unicode_words().collect();
            assert_eq!(tagged, words, "{name}");
        }
    }

    #[test]
    fn the_measured_operations_agree_on_item_counts() {
        for name in CORPORA {
            let text = load(&corpus_dir(), name);
            let (segments, words, _, _) = checksums(&text);
            assert_eq!(
                split_word_bound_indices(text.as_bytes()),
                split_word_bound_indices_collect(text.as_bytes())
            );
            let mut expected = Result::default();
            for (start, end, is_word) in tagged_bounds(&text) {
                if is_word {
                    expected.add(start, end);
                }
            }
            assert_eq!(unicode_words(text.as_bytes()), expected);
            assert_eq!(
                split_word_bound_indices(text.as_bytes()).count,
                segments,
                "{name}"
            );
            assert_eq!(
                split_word_bound_indices_collect(text.as_bytes()).count,
                segments,
                "{name}"
            );
            assert_eq!(unicode_words(text.as_bytes()).count, words, "{name}");
        }
    }
}
