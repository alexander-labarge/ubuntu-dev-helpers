//! VirtualBox Secure Boot Manager
//!
//! Author: Alexander La Barge
//! Date: 19 Nov 2025
//! Contact: alex@labarge.dev
//! Program Name: virtualbox-sb-manager
//! Version: 0.1.0-beta

use clap::{Parser, Subcommand};
use log::LevelFilter;
use virtualbox_secure_boot_manager::{cli, config::Config, utils};

#[derive(Parser)]
#[command(
    name = "virtualbox-sb-manager",
    version,
    about = "VirtualBox Secure Boot Manager - Manage VirtualBox module signing for Secure Boot",
    long_about = "A comprehensive CLI tool for managing VirtualBox kernel module signing on Linux systems with UEFI Secure Boot enabled."
)]
struct Cli {
    /// Enable verbose logging
    #[arg(short, long, global = true)]
    verbose: bool,
    
    /// Enable debug logging
    #[arg(short, long, global = true)]
    debug: bool,
    
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Complete setup: create signing keys and enroll MOK
    Setup,
    
    /// Sign VirtualBox kernel modules
    Sign,
    
    /// Verify module signatures
    Verify,
    
    /// Load VirtualBox kernel modules
    Load,
    
    /// Rebuild VirtualBox modules via DKMS
    Rebuild,
    
    /// Full process: rebuild, sign, verify, and load
    Full,
    
    /// KVM management commands
    Kvm {
        #[command(subcommand)]
        action: KvmAction,
    },
    
    /// Show system status
    Status,
    
    /// Launch interactive menu mode
    Interactive,
}

#[derive(Subcommand)]
enum KvmAction {
    /// Disable KVM temporarily (until reboot)
    Disable {
        /// Disable KVM permanently (survives reboot)
        #[arg(short, long)]
        permanent: bool,
    },
    
    /// Re-enable KVM
    Enable,
    
    /// Show KVM status
    Status,
}

fn main() {
    let cli = Cli::parse();
    
    // Determine log level
    let log_level = if cli.debug {
        LevelFilter::Debug
    } else if cli.verbose {
        LevelFilter::Info
    } else {
        LevelFilter::Warn
    };
    
    // Initialize logger
    let config = Config::default();
    if let Err(e) = utils::logger::VBoxLogger::init(&config.log_file, log_level) {
        eprintln!("Warning: Failed to initialize logger: {}", e);
        // Continue without file logging
    }
    
    log::info!("VirtualBox Secure Boot Manager started");
    log::info!("Version: {}", env!("CARGO_PKG_VERSION"));
    
    // Execute command
    let result = match cli.command {
        Some(Commands::Setup) => cli::commands::setup_command(&config),
        Some(Commands::Sign) => cli::commands::sign_command(&config),
        Some(Commands::Verify) => cli::commands::verify_command(),
        Some(Commands::Load) => cli::commands::load_command(),
        Some(Commands::Rebuild) => cli::commands::rebuild_command(),
        Some(Commands::Full) => cli::commands::full_command(&config),
        Some(Commands::Kvm { action }) => match action {
            KvmAction::Disable { permanent } => cli::commands::kvm_disable_command(permanent),
            KvmAction::Enable => cli::commands::kvm_enable_command(),
            KvmAction::Status => {
                use virtualbox_secure_boot_manager::modules::kvm;
                match kvm::check_kvm_status() {
                    Ok(status) => {
                        utils::output::print_header("KVM Status");
                        if status.kvm_loaded {
                            utils::output::print_warning("KVM: Loaded");
                        } else {
                            utils::output::print_success("KVM: Not loaded");
                        }
                        if status.kvm_intel_loaded {
                            println!("  kvm_intel: loaded");
                        }
                        if status.kvm_amd_loaded {
                            println!("  kvm_amd: loaded");
                        }
                        if status.blacklisted {
                            utils::output::print_info("Blacklist: Enabled (permanent)");
                        } else {
                            println!("  Blacklist: disabled");
                        }
                        Ok(())
                    }
                    Err(e) => Err(e),
                }
            }
        },
        Some(Commands::Status) => cli::commands::status_command(&config),
        Some(Commands::Interactive) => cli::interactive::run_interactive(&config),
        None => {
            // No command specified, run interactive mode
            cli::interactive::run_interactive(&config)
        }
    };
    
    // Handle result
    match result {
        Ok(_) => {
            log::info!("Command completed successfully");
            std::process::exit(0);
        }
        Err(e) => {
            log::error!("Command failed: {}", e);
            utils::output::print_error(&e.user_message());
            std::process::exit(1);
        }
    }
}
