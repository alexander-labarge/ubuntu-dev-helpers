//! System utilities for privilege checking and command execution

use crate::error::{Result, VBoxError};
use std::process::{Command, Output};

/// Check if running as root
pub fn check_root() -> Result<()> {
    if !nix::unistd::Uid::effective().is_root() {
        return Err(VBoxError::PermissionDenied(
            "This operation requires root privileges".to_string(),
        ));
    }
    Ok(())
}

/// Execute a command and return the output
pub fn execute_command(cmd: &str, args: &[&str]) -> Result<Output> {
    log::debug!("Executing command: {} {}", cmd, args.join(" "));
    
    let output = Command::new(cmd)
        .args(args)
        .output()
        .map_err(|e| VBoxError::CommandFailed(format!("Failed to execute {}: {}", cmd, e)))?;
    
    log::debug!("Command exit status: {}", output.status);
    
    Ok(output)
}

/// Execute a command and check if it succeeds
pub fn execute_command_checked(cmd: &str, args: &[&str]) -> Result<Output> {
    let output = execute_command(cmd, args)?;
    
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(VBoxError::CommandFailed(format!(
            "Command '{}' failed: {}",
            cmd, stderr
        )));
    }
    
    Ok(output)
}

/// Execute a command and return stdout as string
pub fn execute_command_output(cmd: &str, args: &[&str]) -> Result<String> {
    let output = execute_command_checked(cmd, args)?;
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// Check if a command exists in PATH
pub fn command_exists(cmd: &str) -> bool {
    which::which(cmd).is_ok()
}

/// Check if a kernel module is loaded
pub fn is_module_loaded(module: &str) -> Result<bool> {
    let output = execute_command("lsmod", &[])?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    Ok(stdout.lines().any(|line| line.starts_with(module)))
}

/// Load a kernel module
pub fn load_module(module: &str) -> Result<()> {
    log::info!("Loading module: {}", module);
    execute_command_checked("modprobe", &[module])?;
    log::info!("Module {} loaded successfully", module);
    Ok(())
}

/// Unload a kernel module
pub fn unload_module(module: &str) -> Result<()> {
    log::info!("Unloading module: {}", module);
    let result = execute_command("modprobe", &["-r", module]);
    
    match result {
        Ok(output) if output.status.success() => {
            log::info!("Module {} unloaded successfully", module);
            Ok(())
        }
        Ok(output) => {
            let stderr = String::from_utf8_lossy(&output.stderr);
            log::warn!("Failed to unload module {}: {}", module, stderr);
            // Don't fail if module wasn't loaded
            Ok(())
        }
        Err(e) => {
            log::warn!("Failed to unload module {}: {}", module, e);
            Ok(())
        }
    }
}

/// Check if Secure Boot is enabled
pub fn is_secure_boot_enabled() -> Result<bool> {
    // Check for EFI variables
    let efi_vars_path = std::path::Path::new("/sys/firmware/efi/efivars");
    if !efi_vars_path.exists() {
        log::warn!("EFI variables not accessible");
        return Ok(false);
    }
    
    // Try using mokutil
    if command_exists("mokutil") {
        match execute_command_output("mokutil", &["--sb-state"]) {
            Ok(output) => Ok(output.contains("SecureBoot enabled")),
            Err(_) => Ok(false),
        }
    } else {
        Ok(false)
    }
}

/// Check required dependencies
pub fn check_dependencies() -> Result<Vec<String>> {
    let deps = vec!["openssl", "mokutil", "modinfo", "modprobe", "zstd"];
    let mut missing = Vec::new();
    
    for dep in deps {
        if !command_exists(dep) {
            missing.push(dep.to_string());
        }
    }
    
    Ok(missing)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_command_exists() {
        assert!(command_exists("ls"));
        assert!(!command_exists("this_command_does_not_exist_12345"));
    }
    
    #[test]
    fn test_execute_command() {
        let result = execute_command("echo", &["test"]);
        assert!(result.is_ok());
        
        if let Ok(output) = result {
            assert!(output.status.success());
            let stdout = String::from_utf8_lossy(&output.stdout);
            assert_eq!(stdout.trim(), "test");
        }
    }
}
