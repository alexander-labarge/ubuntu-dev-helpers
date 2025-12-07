//! CLI command implementations

use crate::config::Config;
use crate::error::Result;
use crate::modules::{kvm, mok, signing, verification};
use crate::utils::{output, system};
use dialoguer::{Password, Input, Confirm};

/// Setup command: Create signing keys and enroll MOK
pub fn setup_command(config: &Config) -> Result<()> {
    system::check_root()?;
    output::print_header("VirtualBox Secure Boot Setup");
    
    // Check if keys already exist
    if config.keys_exist() {
        output::print_warning("Signing keys already exist!");
        let recreate = Confirm::new()
            .with_prompt("Do you want to recreate them? (This will require re-enrolling MOK)")
            .default(false)
            .interact()?;
        
        if !recreate {
            output::print_info("Keeping existing keys");
            return Ok(());
        }
        
        // Delete existing keys
        std::fs::remove_file(&config.private_key)?;
        std::fs::remove_file(&config.public_key)?;
    }
    
    // Get certificate name
    let cert_name: String = Input::new()
        .with_prompt("Enter name for certificate")
        .default(config.cert_name.clone())
        .interact_text()?;
    
    output::print_section("Setting Signing Key Passphrase");
    output::print_info("This passphrase protects your private signing key.");
    output::print_info("You'll need it every time you sign modules (after kernel updates).");
    output::print_warning("Make it memorable and secure - write it down!");
    
    let key_passphrase = Password::new()
        .with_prompt("Enter passphrase for signing key")
        .with_confirmation("Confirm passphrase", "Passphrases don't match")
        .interact()?;
    
    output::print_section("Setting Temporary MOK Password");
    output::print_info("This is a temporary password for MOK enrollment at next boot.");
    output::print_info("Minimum 8 characters. Can be simple - it's only used once.");
    
    let mok_password = Password::new()
        .with_prompt("Enter temporary MOK password")
        .with_confirmation("Confirm MOK password", "Passwords don't match")
        .interact()?;
    
    // Perform setup
    mok::setup_complete(config, &cert_name, &key_passphrase, &mok_password)?;
    
    output::print_success("Setup complete!");
    output::print_box(
        "NEXT STEPS",
        &[
            "1. Reboot your system: sudo reboot",
            "2. In MOK Manager (blue screen):",
            "   - Select 'Enroll MOK'",
            "   - Select 'Continue'",
            "   - Select 'Yes'",
            "   - Enter the MOK password",
            "   - Reboot",
            "3. After reboot, sign modules:",
            "   sudo vbox-sb-manager sign",
        ],
    );
    
    Ok(())
}

/// Sign command: Sign VirtualBox modules
pub fn sign_command(config: &Config) -> Result<()> {
    system::check_root()?;
    output::print_header("Sign VirtualBox Modules");
    
    // Check if keys exist
    if !config.keys_exist() {
        return Err(crate::error::VBoxError::KeyNotFound(
            "Signing keys not found. Run 'setup' command first.".to_string(),
        ));
    }
    
    // Get passphrase
    let passphrase = Password::new()
        .with_prompt("Enter passphrase for signing key")
        .interact()?;
    
    // Sign modules
    signing::sign_all_modules(config, &passphrase)?;
    
    output::print_success("All modules signed successfully!");
    
    Ok(())
}

/// Verify command: Verify module signatures
pub fn verify_command() -> Result<()> {
    output::print_header("Verify Module Signatures");
    
    verification::verify_all_modules()?;
    
    output::print_success("All modules are properly signed!");
    
    Ok(())
}

/// Load command: Load VirtualBox modules
pub fn load_command() -> Result<()> {
    system::check_root()?;
    output::print_header("Load VirtualBox Modules");
    
    verification::load_vbox_modules()?;
    
    output::print_success("All VirtualBox modules loaded successfully!");
    
    Ok(())
}

/// Rebuild command: Rebuild VirtualBox modules via DKMS
pub fn rebuild_command() -> Result<()> {
    system::check_root()?;
    output::print_header("Rebuild VirtualBox Modules");
    
    signing::rebuild_vbox_modules()?;
    
    output::print_success("VirtualBox modules rebuilt successfully!");
    
    Ok(())
}

/// KVM disable command
pub fn kvm_disable_command(permanent: bool) -> Result<()> {
    system::check_root()?;
    output::print_header("Disable KVM");
    
    if permanent {
        output::print_info("Disabling KVM permanently...");
        kvm::disable_kvm_permanent()?;
        output::print_success("KVM disabled permanently (survives reboot)");
    } else {
        output::print_info("Disabling KVM temporarily...");
        kvm::disable_kvm_temporary()?;
        output::print_success("KVM disabled temporarily (until reboot)");
    }
    
    Ok(())
}

/// KVM enable command
pub fn kvm_enable_command() -> Result<()> {
    system::check_root()?;
    output::print_header("Enable KVM");
    
    kvm::enable_kvm()?;
    
    output::print_success("KVM re-enabled");
    output::print_warning("VirtualBox will NO LONGER work until KVM is disabled again");
    
    Ok(())
}

/// Status command: Show system status
pub fn status_command(config: &Config) -> Result<()> {
    output::print_header("System Status");
    
    // Kernel version
    let kernel_version = crate::config::SystemPaths::kernel_version()?;
    output::print_info(&format!("Kernel version: {}", kernel_version));
    
    // Secure Boot status
    match system::is_secure_boot_enabled() {
        Ok(true) => output::print_success("Secure Boot: Enabled"),
        Ok(false) => output::print_warning("Secure Boot: Disabled"),
        Err(_) => output::print_warning("Secure Boot: Cannot determine"),
    }
    
    // VirtualBox version
    if system::command_exists("VBoxManage") {
        match system::execute_command_output("VBoxManage", &["--version"]) {
            Ok(version) => output::print_info(&format!("VirtualBox version: {}", version)),
            Err(_) => output::print_warning("VirtualBox: Cannot determine version"),
        }
    } else {
        output::print_error("VirtualBox: Not installed");
    }
    
    // Signing keys
    if config.keys_exist() {
        output::print_success("Signing keys: Present");
    } else {
        output::print_warning("Signing keys: Not found");
    }
    
    // MOK enrollment
    match mok::is_mok_enrolled(config) {
        Ok(true) => output::print_success("MOK: Enrolled"),
        Ok(false) => output::print_warning("MOK: Not enrolled"),
        Err(_) => output::print_warning("MOK: Cannot determine"),
    }
    
    // KVM status
    match kvm::check_kvm_status() {
        Ok(status) => {
            if status.kvm_loaded {
                output::print_warning("KVM: Loaded (VirtualBox will NOT work!)");
            } else {
                output::print_success("KVM: Not loaded (VirtualBox can operate)");
            }
        }
        Err(_) => output::print_warning("KVM: Cannot determine status"),
    }
    
    // Loaded modules
    match verification::check_modules_loaded() {
        Ok(modules) if !modules.is_empty() => {
            output::print_success(&format!(
                "VirtualBox modules loaded: {}",
                modules.join(", ")
            ));
        }
        Ok(_) => output::print_info("VirtualBox modules: Not loaded"),
        Err(_) => output::print_warning("VirtualBox modules: Cannot determine"),
    }
    
    Ok(())
}

/// Full command: Rebuild, sign, verify, and load
pub fn full_command(config: &Config) -> Result<()> {
    system::check_root()?;
    output::print_header("Full Process: Rebuild, Sign, Verify, and Load");
    
    // Rebuild
    output::print_section("Step 1/4: Rebuilding modules");
    rebuild_command()?;
    
    // Sign
    output::print_section("Step 2/4: Signing modules");
    sign_command(config)?;
    
    // Verify
    output::print_section("Step 3/4: Verifying signatures");
    verify_command()?;
    
    // Load
    output::print_section("Step 4/4: Loading modules");
    load_command()?;
    
    output::print_success("Full process completed successfully!");
    
    Ok(())
}
