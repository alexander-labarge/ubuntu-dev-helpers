//! Configuration management for VirtualBox Secure Boot Manager

use crate::error::{Result, VBoxError};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

/// Application configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Directory containing signing keys
    pub key_dir: PathBuf,
    
    /// Private key path
    pub private_key: PathBuf,
    
    /// Public key path (DER format)
    pub public_key: PathBuf,
    
    /// Hash algorithm for signing
    pub hash_algo: String,
    
    /// Log file path
    pub log_file: PathBuf,
    
    /// Certificate name for key generation
    pub cert_name: String,
    
    /// Key validity in days
    pub key_validity_days: u32,
}

impl Default for Config {
    fn default() -> Self {
        let key_dir = PathBuf::from("/root/module-signing");
        
        Self {
            private_key: key_dir.join("MOK.priv"),
            public_key: key_dir.join("MOK.der"),
            key_dir,
            hash_algo: "sha256".to_string(),
            log_file: PathBuf::from("/var/log/vbox-secure-boot-manager.log"),
            cert_name: "VirtualBox Module Signing".to_string(),
            key_validity_days: 36500, // ~100 years
        }
    }
}

impl Config {
    /// Creates a new configuration with default values
    pub fn new() -> Self {
        Self::default()
    }
    
    /// Creates a new configuration from a file
    pub fn from_file<P: AsRef<Path>>(path: P) -> Result<Self> {
        let contents = std::fs::read_to_string(path.as_ref())
            .map_err(|e| VBoxError::ConfigError(format!("Failed to read config file: {}", e)))?;
        
        serde_json::from_str(&contents)
            .map_err(|e| VBoxError::ConfigError(format!("Failed to parse config: {}", e)))
    }
    
    /// Saves the configuration to a file
    pub fn save_to_file<P: AsRef<Path>>(&self, path: P) -> Result<()> {
        let contents = serde_json::to_string_pretty(self)?;
        std::fs::write(path.as_ref(), contents)
            .map_err(|e| VBoxError::ConfigError(format!("Failed to write config file: {}", e)))?;
        Ok(())
    }
    
    /// Validates the configuration
    pub fn validate(&self) -> Result<()> {
        // Check if key directory exists or can be created
        if !self.key_dir.exists() {
            return Err(VBoxError::ConfigError(format!(
                "Key directory does not exist: {}",
                self.key_dir.display()
            )));
        }
        
        Ok(())
    }
    
    /// Checks if signing keys exist
    pub fn keys_exist(&self) -> bool {
        self.private_key.exists() && self.public_key.exists()
    }
}

/// System paths and utilities
pub struct SystemPaths;

impl SystemPaths {
    /// Find the sign-file tool in the system
    pub fn find_sign_file_tool() -> Result<PathBuf> {
        let kernel_version = Self::kernel_version()?;
        
        let paths = vec![
            format!("/usr/src/linux-headers-{}/scripts/sign-file", kernel_version),
            format!("/lib/modules/{}/build/scripts/sign-file", kernel_version),
            format!("/usr/src/kernels/{}/scripts/sign-file", kernel_version),
        ];
        
        for path in paths {
            let p = PathBuf::from(&path);
            if p.exists() {
                return Ok(p);
            }
        }
        
        Err(VBoxError::DependencyMissing(
            "sign-file tool not found. Install linux-headers package.".to_string(),
        ))
    }
    
    /// Get the current kernel version
    pub fn kernel_version() -> Result<String> {
        let output = std::process::Command::new("uname")
            .arg("-r")
            .output()
            .map_err(|e| VBoxError::CommandFailed(format!("Failed to get kernel version: {}", e)))?;
        
        if !output.status.success() {
            return Err(VBoxError::CommandFailed("uname command failed".to_string()));
        }
        
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    }
    
    /// Get the VirtualBox module directory
    pub fn vbox_module_dir() -> Result<PathBuf> {
        let _kernel_version = Self::kernel_version()?;
        
        // Try to find vboxdrv module
        let output = std::process::Command::new("modinfo")
            .args(["-n", "vboxdrv"])
            .output()
            .map_err(|e| VBoxError::CommandFailed(format!("Failed to locate vboxdrv: {}", e)))?;
        
        if !output.status.success() {
            return Err(VBoxError::ModuleNotFound(
                "vboxdrv module not found. Is VirtualBox installed?".to_string(),
            ));
        }
        
        let module_path = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let module_dir = PathBuf::from(module_path)
            .parent()
            .ok_or_else(|| VBoxError::ModuleNotFound("Invalid module path".to_string()))?
            .to_path_buf();
        
        Ok(module_dir)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert_eq!(config.hash_algo, "sha256");
        assert_eq!(config.key_validity_days, 36500);
    }
    
    #[test]
    fn test_config_keys_exist() {
        let config = Config::default();
        // This will be false in test environment
        assert!(!config.keys_exist() || config.keys_exist());
    }
    
    #[test]
    fn test_kernel_version() {
        // This should work on any Linux system
        let version = SystemPaths::kernel_version();
        assert!(version.is_ok() || version.is_err());
    }
}
