//! Module verification and loading

use crate::error::{Result, VBoxError};
use crate::modules::signing::{find_vbox_modules, CompressionType, ModuleInfo};
use crate::utils::system;

/// Verify a single module signature
pub fn verify_module_signature(module: &ModuleInfo) -> Result<bool> {
    let module_path = if module.compressed {
        // Decompress temporarily for verification
        let decompressed = decompress_for_verification(module)?;
        decompressed
    } else {
        module.path.clone()
    };
    
    // Use modinfo to check for signature
    let output = system::execute_command(
        "modinfo",
        &[module_path.to_str().unwrap()],
    )?;
    
    let stdout = String::from_utf8_lossy(&output.stdout);
    let is_signed = stdout.contains("sig_id:") || stdout.contains("signer:");
    
    // Clean up decompressed file if we created it
    if module.compressed {
        let _ = std::fs::remove_file(&module_path);
    }
    
    Ok(is_signed)
}

/// Decompress a module temporarily for verification
fn decompress_for_verification(module: &ModuleInfo) -> Result<std::path::PathBuf> {
    let decompressed_path = module.path.with_extension("");
    
    // If already decompressed, just return the path
    if decompressed_path.exists() {
        return Ok(decompressed_path);
    }
    
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

/// Verify all VirtualBox module signatures
pub fn verify_all_modules() -> Result<()> {
    log::info!("Verifying VirtualBox module signatures...");
    
    let modules = find_vbox_modules()?;
    
    let mut verified_count = 0;
    let mut unverified_count = 0;
    
    for module in &modules {
        match verify_module_signature(module) {
            Ok(true) => {
                log::info!("Module is signed: {}", module.name);
                verified_count += 1;
            }
            Ok(false) => {
                log::error!("Module is NOT signed: {}", module.name);
                unverified_count += 1;
            }
            Err(e) => {
                log::error!("Failed to verify {}: {}", module.name, e);
                unverified_count += 1;
            }
        }
    }
    
    log::info!(
        "Verification complete: {} signed, {} unsigned",
        verified_count,
        unverified_count
    );
    
    if unverified_count > 0 {
        Err(VBoxError::SignatureVerificationFailed(format!(
            "{} module(s) are not signed",
            unverified_count
        )))
    } else {
        log::info!("All modules are properly signed!");
        Ok(())
    }
}

/// Load VirtualBox kernel modules
pub fn load_vbox_modules() -> Result<()> {
    system::check_root()?;
    log::info!("Loading VirtualBox kernel modules...");
    
    let modules = vec!["vboxdrv", "vboxnetflt", "vboxnetadp"];
    
    for module in modules {
        match system::load_module(module) {
            Ok(_) => log::info!("Loaded module: {}", module),
            Err(e) => {
                log::error!("Failed to load module {}: {}", module, e);
                return Err(VBoxError::ModuleLoadFailed(format!(
                    "Failed to load {}: {}",
                    module, e
                )));
            }
        }
    }
    
    log::info!("All VirtualBox modules loaded successfully");
    Ok(())
}

/// Unload VirtualBox kernel modules
pub fn unload_vbox_modules() -> Result<()> {
    system::check_root()?;
    log::info!("Unloading VirtualBox kernel modules...");
    
    // Unload in reverse order
    let modules = vec!["vboxnetadp", "vboxnetflt", "vboxdrv"];
    
    for module in modules {
        system::unload_module(module)?;
    }
    
    log::info!("All VirtualBox modules unloaded");
    Ok(())
}

/// Check if VirtualBox modules are loaded
pub fn check_modules_loaded() -> Result<Vec<String>> {
    let modules = vec!["vboxdrv", "vboxnetflt", "vboxnetadp"];
    let mut loaded = Vec::new();
    
    for module in modules {
        if system::is_module_loaded(module)? {
            loaded.push(module.to_string());
        }
    }
    
    Ok(loaded)
}

/// Get module information
pub fn get_module_info(module_name: &str) -> Result<String> {
    let output = system::execute_command_checked("modinfo", &[module_name])?;
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_check_modules_loaded() {
        // This test should work on any system
        let result = check_modules_loaded();
        assert!(result.is_ok());
    }
}
