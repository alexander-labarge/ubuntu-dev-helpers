//! VirtualBox Secure Boot Manager
//! 
//! A comprehensive Rust CLI application for managing VirtualBox Secure Boot
//! module signing on Linux systems.

pub mod cli;
pub mod config;
pub mod error;
pub mod modules;
pub mod utils;

pub use config::Config;
pub use error::{Result, VBoxError};

/// Initialize the application
pub fn init() -> Result<()> {
    // This function can be used for any global initialization
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_init() {
        assert!(init().is_ok());
    }
}
