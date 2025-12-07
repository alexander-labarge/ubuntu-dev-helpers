//! MOK (Machine Owner Key) enrollment and management

use crate::config::Config;
use crate::error::{Result, VBoxError};
use crate::utils::system;
use std::fs;

/// Create signing keys
pub fn create_signing_keys(config: &Config, cert_name: &str, passphrase: &str) -> Result<()> {
    system::check_root()?;
    log::info!("Creating signing keys...");
    
    // Check if keys already exist
    if config.keys_exist() {
        log::warn!("Signing keys already exist at {}", config.key_dir.display());
        return Err(VBoxError::Other(
            "Keys already exist. Delete them first if you want to recreate.".to_string(),
        ));
    }
    
    // Create key directory
    fs::create_dir_all(&config.key_dir).map_err(|e| {
        VBoxError::Other(format!("Failed to create key directory: {}", e))
    })?;
    
    log::info!("Generating RSA key pair...");
    
    // Set passphrase environment variable for OpenSSL
    std::env::set_var("OPENSSL_PASSPHRASE", passphrase);
    
    // Generate key pair
    let result = system::execute_command_checked(
        "openssl",
        &[
            "req",
            "-new",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-keyout",
            config.private_key.to_str().unwrap(),
            "-outform",
            "DER",
            "-out",
            config.public_key.to_str().unwrap(),
            "-days",
            &config.key_validity_days.to_string(),
            "-subj",
            &format!("/CN={}/", cert_name),
            "-passout",
            "env:OPENSSL_PASSPHRASE",
        ],
    );
    
    // Clear passphrase from environment
    std::env::remove_var("OPENSSL_PASSPHRASE");
    
    result?;
    
    // Set restrictive permissions on keys
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        
        for key_file in [&config.private_key, &config.public_key] {
            let mut perms = fs::metadata(key_file)?.permissions();
            perms.set_mode(0o600);
            fs::set_permissions(key_file, perms)?;
        }
    }
    
    log::info!("Signing keys created successfully");
    log::info!("Private key: {}", config.private_key.display());
    log::info!("Public key: {}", config.public_key.display());
    
    Ok(())
}

/// Enroll Machine Owner Key (MOK)
pub fn enroll_mok(config: &Config, mok_password: &str) -> Result<()> {
    system::check_root()?;
    log::info!("Enrolling Machine Owner Key (MOK)...");
    
    if !config.public_key.exists() {
        return Err(VBoxError::KeyNotFound(format!(
            "Public key not found at {}. Run setup first.",
            config.public_key.display()
        )));
    }
    
    // Check if key is already enrolled
    if is_mok_enrolled(config)? {
        log::info!("MOK already enrolled");
        return Ok(());
    }
    
    // Create a temporary file for the password
    let password_file = format!("/tmp/mok_password_{}", std::process::id());
    fs::write(&password_file, format!("{}\n{}\n", mok_password, mok_password))
        .map_err(|e| VBoxError::Other(format!("Failed to write password file: {}", e)))?;
    
    // Import MOK
    let result = std::process::Command::new("mokutil")
        .args(["--import", config.public_key.to_str().unwrap()])
        .stdin(std::process::Stdio::piped())
        .spawn()
        .and_then(|mut child| {
            if let Some(mut stdin) = child.stdin.take() {
                use std::io::Write;
                stdin.write_all(format!("{}\n{}\n", mok_password, mok_password).as_bytes())?;
            }
            child.wait()
        });
    
    // Clean up password file
    let _ = fs::remove_file(&password_file);
    
    match result {
        Ok(status) if status.success() => {
            log::info!("MOK import initiated successfully!");
            log::warn!("REBOOT REQUIRED: Please reboot and enroll MOK in MOK Manager");
            Ok(())
        }
        Ok(status) => Err(VBoxError::Other(format!(
            "MOK import failed with exit code: {}",
            status.code().unwrap_or(-1)
        ))),
        Err(e) => Err(VBoxError::Other(format!("Failed to execute mokutil: {}", e))),
    }
}

/// Check if MOK is enrolled
pub fn is_mok_enrolled(config: &Config) -> Result<bool> {
    if !system::command_exists("mokutil") {
        log::warn!("mokutil not found, cannot verify MOK enrollment");
        return Ok(false);
    }
    
    let output = system::execute_command("mokutil", &["--list-enrolled"])?;
    
    if !output.status.success() {
        return Ok(false);
    }
    
    // Get the subject from our certificate
    let cert_output = system::execute_command(
        "openssl",
        &[
            "x509",
            "-inform",
            "DER",
            "-in",
            config.public_key.to_str().unwrap(),
            "-noout",
            "-subject",
        ],
    )?;
    
    let cert_subject = String::from_utf8_lossy(&cert_output.stdout);
    let enrolled_list = String::from_utf8_lossy(&output.stdout);
    
    // Check if our certificate subject is in the enrolled list
    Ok(enrolled_list.contains(&cert_subject.trim()))
}

/// Verify MOK enrollment and display information
pub fn verify_mok_enrollment(config: &Config) -> Result<()> {
    log::info!("Verifying MOK enrollment...");
    
    if is_mok_enrolled(config)? {
        log::info!("MOK is enrolled");
        
        // Display enrolled MOK information
        let output = system::execute_command("mokutil", &["--list-enrolled"])?;
        let enrolled_info = String::from_utf8_lossy(&output.stdout);
        
        for line in enrolled_info.lines() {
            if line.contains("Subject:") {
                log::info!("  {}", line.trim());
            }
        }
        
        Ok(())
    } else {
        Err(VBoxError::MokNotEnrolled)
    }
}

/// Setup complete key generation and MOK enrollment process
pub fn setup_complete(
    config: &Config,
    cert_name: &str,
    key_passphrase: &str,
    mok_password: &str,
) -> Result<()> {
    log::info!("Starting complete setup process...");
    
    // Create signing keys
    create_signing_keys(config, cert_name, key_passphrase)?;
    
    // Enroll MOK
    enroll_mok(config, mok_password)?;
    
    log::info!("Setup complete!");
    log::warn!("NEXT STEPS:");
    log::warn!("1. Reboot your system");
    log::warn!("2. In MOK Manager (blue screen):");
    log::warn!("   - Select 'Enroll MOK'");
    log::warn!("   - Select 'Continue'");
    log::warn!("   - Select 'Yes'");
    log::warn!("   - Enter the MOK password");
    log::warn!("   - Reboot");
    log::warn!("3. After reboot, sign the modules:");
    log::warn!("   sudo vbox-sb-manager sign");
    
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;
    
    #[test]
    fn test_config_keys_exist() {
        let temp_dir = TempDir::new().unwrap();
        let mut config = Config::default();
        config.key_dir = temp_dir.path().to_path_buf();
        config.private_key = temp_dir.path().join("test.priv");
        config.public_key = temp_dir.path().join("test.der");
        
        assert!(!config.keys_exist());
        
        // Create dummy files
        std::fs::write(&config.private_key, "test").unwrap();
        std::fs::write(&config.public_key, "test").unwrap();
        
        assert!(config.keys_exist());
    }
}
