//! Module signing functionality

use crate::config::{Config, SystemPaths};
use crate::error::{Result, VBoxError};
use crate::utils::system;
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

/// Information about a kernel module
#[derive(Debug, Clone)]
pub struct ModuleInfo {
    pub path: PathBuf,
    pub name: String,
    pub compressed: bool,
    pub compression_type: Option<CompressionType>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum CompressionType {
    Xz,
    Gz,
    Zst,
}

/// Find all VirtualBox kernel modules
pub fn find_vbox_modules() -> Result<Vec<ModuleInfo>> {
    log::info!("Locating VirtualBox kernel modules...");
    
    let module_dir = SystemPaths::vbox_module_dir()?;
    log::info!("Module directory: {}", module_dir.display());
    
    let mut modules = Vec::new();
    
    for entry in WalkDir::new(&module_dir)
        .follow_links(true)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        let path = entry.path();
        let filename = path.file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("");
        
        if filename.starts_with("vbox") && is_module_file(filename) {
            let (compression_type, compressed) = detect_compression(filename);
            let name = extract_module_name(filename);
            
            modules.push(ModuleInfo {
                path: path.to_path_buf(),
                name,
                compressed,
                compression_type,
            });
        }
    }
    
    if modules.is_empty() {
        return Err(VBoxError::ModuleNotFound(format!(
            "No VirtualBox modules found in {}",
            module_dir.display()
        )));
    }
    
    log::info!("Found {} VirtualBox module(s)", modules.len());
    for module in &modules {
        log::debug!("  - {} at {}", module.name, module.path.display());
    }
    
    Ok(modules)
}

/// Check if a filename is a module file
fn is_module_file(filename: &str) -> bool {
    filename.ends_with(".ko")
        || filename.ends_with(".ko.xz")
        || filename.ends_with(".ko.gz")
        || filename.ends_with(".ko.zst")
}

/// Detect compression type from filename
fn detect_compression(filename: &str) -> (Option<CompressionType>, bool) {
    if filename.ends_with(".ko.xz") {
        (Some(CompressionType::Xz), true)
    } else if filename.ends_with(".ko.gz") {
        (Some(CompressionType::Gz), true)
    } else if filename.ends_with(".ko.zst") {
        (Some(CompressionType::Zst), true)
    } else {
        (None, false)
    }
}

/// Extract module name from filename
fn extract_module_name(filename: &str) -> String {
    filename
        .trim_end_matches(".xz")
        .trim_end_matches(".gz")
        .trim_end_matches(".zst")
        .trim_end_matches(".ko")
        .to_string()
}

/// Decompress a module file
fn decompress_module(module: &ModuleInfo) -> Result<PathBuf> {
    if !module.compressed {
        return Ok(module.path.clone());
    }
    
    log::info!("Decompressing {}...", module.path.display());
    
    let decompressed_path = module.path.with_extension("");
    
    match module.compression_type {
        Some(CompressionType::Xz) => {
            system::execute_command_checked("xz", &["-dk", module.path.to_str().unwrap()])?;
        }
        Some(CompressionType::Gz) => {
            system::execute_command_checked("gunzip", &["-k", module.path.to_str().unwrap()])?;
        }
        Some(CompressionType::Zst) => {
            system::execute_command_checked("zstd", &["-dkfq", module.path.to_str().unwrap()])?;
        }
        None => {}
    }
    
    Ok(decompressed_path)
}

/// Recompress a module file
fn recompress_module(decompressed_path: &Path, compression_type: CompressionType) -> Result<()> {
    log::info!("Recompressing {}...", decompressed_path.display());
    
    match compression_type {
        CompressionType::Xz => {
            system::execute_command_checked("xz", &["-f", decompressed_path.to_str().unwrap()])?;
        }
        CompressionType::Gz => {
            system::execute_command_checked("gzip", &["-f", decompressed_path.to_str().unwrap()])?;
        }
        CompressionType::Zst => {
            system::execute_command_checked(
                "zstd",
                &["-qf", "--rm", decompressed_path.to_str().unwrap()],
            )?;
        }
    }
    
    Ok(())
}

/// Sign a single module
pub fn sign_module(module: &ModuleInfo, config: &Config, passphrase: &str) -> Result<()> {
    log::info!("Signing module: {}...", module.path.display());
    
    // Find sign-file tool
    let sign_file_tool = SystemPaths::find_sign_file_tool()?;
    log::debug!("Using sign-file tool: {}", sign_file_tool.display());
    
    // Decompress if needed
    let module_to_sign = decompress_module(module)?;
    
    // Set passphrase environment variable
    std::env::set_var("KBUILD_SIGN_PIN", passphrase);
    
    // Sign the module
    let result = system::execute_command_checked(
        sign_file_tool.to_str().unwrap(),
        &[
            &config.hash_algo,
            config.private_key.to_str().unwrap(),
            config.public_key.to_str().unwrap(),
            module_to_sign.to_str().unwrap(),
        ],
    );
    
    // Clear passphrase from environment
    std::env::remove_var("KBUILD_SIGN_PIN");
    
    result?;
    
    // Recompress if it was compressed
    if module.compressed {
        if let Some(ref compression_type) = module.compression_type {
            recompress_module(&module_to_sign, compression_type.clone())?;
        }
    }
    
    log::info!("Successfully signed: {}", module.name);
    Ok(())
}

/// Sign all VirtualBox modules
pub fn sign_all_modules(config: &Config, passphrase: &str) -> Result<()> {
    system::check_root()?;
    log::info!("Starting VirtualBox module signing process...");
    
    // Verify keys exist
    if !config.keys_exist() {
        return Err(VBoxError::KeyNotFound(
            "Signing keys not found. Run 'setup' command first.".to_string(),
        ));
    }
    
    // Find modules
    let modules = find_vbox_modules()?;
    
    let mut signed_count = 0;
    let mut failed_count = 0;
    
    for module in &modules {
        match sign_module(module, config, passphrase) {
            Ok(_) => signed_count += 1,
            Err(e) => {
                log::error!("Failed to sign {}: {}", module.name, e);
                failed_count += 1;
            }
        }
    }
    
    log::info!(
        "Signing complete: {} successful, {} failed",
        signed_count,
        failed_count
    );
    
    if failed_count > 0 {
        Err(VBoxError::Other(format!(
            "{} module(s) failed to sign",
            failed_count
        )))
    } else {
        log::info!("All modules signed successfully!");
        Ok(())
    }
}

/// Rebuild VirtualBox modules via DKMS
pub fn rebuild_vbox_modules() -> Result<()> {
    system::check_root()?;
    log::info!("Rebuilding VirtualBox kernel modules via DKMS...");
    
    // Check if virtualbox-dkms is installed
    let dpkg_output = system::execute_command("dpkg", &["-l"])?;
    let dpkg_stdout = String::from_utf8_lossy(&dpkg_output.stdout);
    
    if !dpkg_stdout.contains("virtualbox-dkms") {
        log::warn!("virtualbox-dkms package not found");
        return Err(VBoxError::DkmsBuildFailed(
            "virtualbox-dkms is not installed".to_string(),
        ));
    }
    
    // Find VirtualBox DKMS version
    let dkms_output = system::execute_command("dkms", &["status", "virtualbox"])?;
    let dkms_stdout = String::from_utf8_lossy(&dkms_output.stdout);
    
    let version = dkms_stdout
        .lines()
        .next()
        .and_then(|line| {
            line.split(',')
                .next()
                .and_then(|s| s.split('/').nth(1))
        })
        .ok_or_else(|| {
            VBoxError::DkmsBuildFailed("Could not determine VirtualBox DKMS version".to_string())
        })?;
    
    log::info!("Found VirtualBox DKMS version: {}", version);
    
    let kernel_version = SystemPaths::kernel_version()?;
    
    // Unload modules if loaded
    log::info!("Unloading existing VirtualBox modules...");
    for module in ["vboxnetadp", "vboxnetflt", "vboxdrv"].iter() {
        system::unload_module(module)?;
    }
    
    // Force rebuild
    log::info!("Forcing DKMS rebuild (this may take a minute)...");
    system::execute_command_checked(
        "dkms",
        &[
            "install",
            &format!("virtualbox/{}", version),
            "-k",
            &kernel_version,
            "--force",
        ],
    )?;
    
    log::info!("VirtualBox modules rebuilt successfully");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_is_module_file() {
        assert!(is_module_file("vboxdrv.ko"));
        assert!(is_module_file("vboxdrv.ko.xz"));
        assert!(is_module_file("vboxdrv.ko.gz"));
        assert!(is_module_file("vboxdrv.ko.zst"));
        assert!(!is_module_file("vboxdrv.txt"));
    }
    
    #[test]
    fn test_detect_compression() {
        let (comp, compressed) = detect_compression("vboxdrv.ko.xz");
        assert_eq!(comp, Some(CompressionType::Xz));
        assert!(compressed);
        
        let (comp, compressed) = detect_compression("vboxdrv.ko");
        assert_eq!(comp, None);
        assert!(!compressed);
    }
    
    #[test]
    fn test_extract_module_name() {
        assert_eq!(extract_module_name("vboxdrv.ko"), "vboxdrv");
        assert_eq!(extract_module_name("vboxdrv.ko.xz"), "vboxdrv");
        assert_eq!(extract_module_name("vboxnetflt.ko.gz"), "vboxnetflt");
    }
}
