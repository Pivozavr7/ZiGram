//! Builds `libzigram_core.a` with zig and links it into this crate.

use std::path::{Path, PathBuf};
use std::process::Command;

fn main() {
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let repo = manifest
        .join("..")
        .canonicalize()
        .expect("repository root must exist");

    println!("cargo:rerun-if-changed={}", repo.join("src").display());
    println!("cargo:rerun-if-changed={}", repo.join("build.zig").display());
    build_zig(&repo);

    let lib_dir = repo.join("zig-out/lib");
    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    println!("cargo:rustc-link-lib=static=zigram_core");
    println!("cargo:rustc-link-lib=dylib=m");
    println!("cargo:rustc-link-lib=dylib=pthread");
    println!("cargo:rustc-link-lib=dylib=dl");
}

/// Runs `zig build` in the repository root so the archive is fresh.
fn build_zig(repo: &Path) {
    let status = Command::new("zig")
        .arg("build")
        .current_dir(repo)
        .status()
        .expect("`zig` must be on PATH to build zigram_core");
    if !status.success() {
        panic!("`zig build` failed with {status}");
    }
}
