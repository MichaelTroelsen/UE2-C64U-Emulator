//! `ue2-mkimage`: build a raw disk image from a host directory.
//!
//! The layout is the one `scripts/make-sd-image.sh` produces: an MBR with one FAT32-LBA partition
//! (type 0x0C) starting at sector 2048. That script needs `hdiutil`, `newfs_msdos` and `diskutil`,
//! so it only runs on macOS; this binary uses [`ue2_vfat::image::build`], the same code path
//! `--usb-dir` already uses, and therefore works anywhere the workspace builds.
//!
//! ```text
//! ue2-mkimage <image> <dir> [--size <N>[K|M|G]] [--label <NAME>] [--force]
//! ```
//!
//! Staging a directory and building from it replaces `make-sd-image.sh` plus `add-sd-files.sh`:
//! put exactly the files you want on the card into `<dir>`, then build.

use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::{bail, Context, Result};
use ue2_vfat::image;

const USAGE: &str = "usage: ue2-mkimage <image> <dir> [--size <N>[K|M|G]] [--label <NAME>] [--force]";

/// `64` and `64M` are MiB, `2G` GiB, `512K` KiB. The default when `--size` is absent is the one
/// `image::build` picks from the content size.
fn parse_size(s: &str) -> Result<u64> {
    let (digits, mult) = match s.as_bytes().last() {
        Some(b'K' | b'k') => (&s[..s.len() - 1], 1u64 << 10),
        Some(b'M' | b'm') => (&s[..s.len() - 1], 1u64 << 20),
        Some(b'G' | b'g') => (&s[..s.len() - 1], 1u64 << 30),
        _ => (s, 1u64 << 20),
    };
    let n: u64 = digits.trim().parse().with_context(|| format!("--size {s}: not a number"))?;
    if n == 0 {
        bail!("--size {s}: must not be zero");
    }
    Ok(n * mult)
}

struct Args {
    image: PathBuf,
    dir: PathBuf,
    size: Option<u64>,
    label: String,
    force: bool,
}

fn parse_args() -> Result<Args> {
    let (mut image, mut dir) = (None, None);
    let (mut size, mut label, mut force) = (None, "UE2SD".to_string(), false);
    let mut it = std::env::args().skip(1);
    while let Some(a) = it.next() {
        match a.as_str() {
            "-h" | "--help" => {
                println!("{USAGE}");
                std::process::exit(0);
            }
            "--force" => force = true,
            "--size" => size = Some(parse_size(&it.next().context("--size needs a value")?)?),
            "--label" => label = it.next().context("--label needs a value")?,
            _ if a.starts_with('-') => bail!("unknown option {a}\n{USAGE}"),
            _ if image.is_none() => image = Some(PathBuf::from(a)),
            _ if dir.is_none() => dir = Some(PathBuf::from(a)),
            _ => bail!("too many arguments\n{USAGE}"),
        }
    }
    let (Some(image), Some(dir)) = (image, dir) else { bail!("{USAGE}") };
    Ok(Args { image, dir, size, label, force })
}

fn run(args: &Args) -> Result<()> {
    if !args.dir.is_dir() {
        bail!("{}: not a directory", args.dir.display());
    }
    // `image::build` opens the file with `create_new`, so an existing image is an error there. Say so
    // here instead, where the fix can be named.
    if args.image.exists() {
        if !args.force {
            bail!("{}: already exists (--force replaces it)", args.image.display());
        }
        std::fs::remove_file(&args.image)
            .with_context(|| format!("replacing {}", args.image.display()))?;
    }
    // `build` expects a canonical root: `scan` reports paths relative to it.
    let root = args.dir.canonicalize().with_context(|| format!("resolving {}", args.dir.display()))?;

    let built = image::build(&root, &args.image, args.size, image::volume_label(&args.label))
        .with_context(|| format!("building {}", args.image.display()))?;

    for s in &built.skipped {
        eprintln!("skipped {}: {}", s.path, s.reason);
    }
    println!(
        "{}: {} MiB, label {}, {} file(s) and {} director(ies), {} bytes of content{}",
        args.image.display(),
        built.size >> 20,
        args.label,
        built.files,
        built.dirs,
        built.content,
        if built.skipped.is_empty() { String::new() } else { format!(", {} skipped", built.skipped.len()) },
    );
    Ok(())
}

fn main() -> ExitCode {
    let args = match parse_args() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("Error: {e}");
            return ExitCode::FAILURE;
        }
    };
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("Error: {e:#}");
            // A half-written image is worse than none: the firmware would try to mount it.
            if !args.image.exists() {
                return ExitCode::FAILURE;
            }
            let _ = std::fs::remove_file(&args.image);
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::parse_size;

    #[test]
    fn sizes_parse_with_and_without_a_suffix() {
        assert_eq!(parse_size("64").unwrap(), 64 << 20, "a bare number is MiB");
        assert_eq!(parse_size("64M").unwrap(), 64 << 20);
        assert_eq!(parse_size("2G").unwrap(), 2 << 30);
        assert_eq!(parse_size("512k").unwrap(), 512 << 10);
        assert!(parse_size("0").is_err());
        assert!(parse_size("big").is_err());
    }
}
