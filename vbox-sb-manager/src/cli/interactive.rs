//! Interactive menu mode

use crate::cli::commands;
use crate::config::Config;
use crate::error::Result;
use crate::utils::output;
use dialoguer::{theme::ColorfulTheme, Select};

/// Menu options
#[derive(Debug, Clone, Copy)]
enum MenuOption {
    Setup,
    Rebuild,
    Sign,
    Verify,
    Load,
    Full,
    KvmDisable,
    KvmEnable,
    Status,
    Exit,
}

impl MenuOption {
    fn as_str(&self) -> &str {
        match self {
            MenuOption::Setup => "Complete Setup (create keys + enroll MOK)",
            MenuOption::Rebuild => "Rebuild VirtualBox Modules (DKMS)",
            MenuOption::Sign => "Sign VirtualBox Modules",
            MenuOption::Verify => "Verify Module Signatures",
            MenuOption::Load => "Load VirtualBox Modules",
            MenuOption::Full => "Full Process (rebuild + sign + verify + load)",
            MenuOption::KvmDisable => "Disable KVM",
            MenuOption::KvmEnable => "Enable KVM",
            MenuOption::Status => "System Status",
            MenuOption::Exit => "Exit",
        }
    }
    
    fn all_options() -> Vec<Self> {
        vec![
            MenuOption::Setup,
            MenuOption::Rebuild,
            MenuOption::Sign,
            MenuOption::Verify,
            MenuOption::Load,
            MenuOption::Full,
            MenuOption::KvmDisable,
            MenuOption::KvmEnable,
            MenuOption::Status,
            MenuOption::Exit,
        ]
    }
}

/// Run interactive menu mode
pub fn run_interactive(config: &Config) -> Result<()> {
    loop {
        output::print_header("VirtualBox Secure Boot Manager");
        
        let options = MenuOption::all_options();
        let option_strings: Vec<&str> = options.iter().map(|o| o.as_str()).collect();
        
        let selection = Select::with_theme(&ColorfulTheme::default())
            .with_prompt("Select an option")
            .items(&option_strings)
            .default(0)
            .interact()?;
        
        let selected_option = options[selection];
        
        println!(); // Add spacing
        
        let result = match selected_option {
            MenuOption::Setup => commands::setup_command(config),
            MenuOption::Rebuild => commands::rebuild_command(),
            MenuOption::Sign => commands::sign_command(config),
            MenuOption::Verify => commands::verify_command(),
            MenuOption::Load => commands::load_command(),
            MenuOption::Full => commands::full_command(config),
            MenuOption::KvmDisable => {
                let permanent = dialoguer::Confirm::new()
                    .with_prompt("Disable KVM permanently (survives reboot)?")
                    .default(false)
                    .interact()?;
                commands::kvm_disable_command(permanent)
            }
            MenuOption::KvmEnable => commands::kvm_enable_command(),
            MenuOption::Status => commands::status_command(config),
            MenuOption::Exit => {
                output::print_info("Exiting...");
                break;
            }
        };
        
        // Handle errors
        match result {
            Ok(_) => {}
            Err(e) => {
                output::print_error(&e.user_message());
            }
        }
        
        println!(); // Add spacing
        
        // Wait for user to press Enter before showing menu again
        if !matches!(selected_option, MenuOption::Exit) {
            dialoguer::Input::<String>::new()
                .with_prompt("Press Enter to continue")
                .allow_empty(true)
                .interact_text()?;
        }
    }
    
    Ok(())
}
