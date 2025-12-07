//! Custom error types for the VirtualBox Secure Boot Manager

use thiserror::Error;

/// Result type alias for the application
pub type Result<T> = std::result::Result<T, VBoxError>;

/// Main error type for the application
#[derive(Error, Debug)]
pub enum VBoxError {
    #[error("Permission denied: {0}. Please run with sudo.")]
    PermissionDenied(String),

    #[error("Dependency not found: {0}. Please install it first.")]
    DependencyMissing(String),

    #[error("Module not found: {0}")]
    ModuleNotFound(String),

    #[error("Signing key not found: {0}. Run 'setup' command first.")]
    KeyNotFound(String),

    #[error("Signature verification failed for module: {0}")]
    SignatureVerificationFailed(String),

    #[error("Failed to load module: {0}")]
    ModuleLoadFailed(String),

    #[error("MOK not enrolled. Please enroll MOK and reboot.")]
    MokNotEnrolled,

    #[error("VirtualBox not installed. Please install VirtualBox first.")]
    VirtualBoxNotInstalled,

    #[error("Secure Boot not enabled")]
    SecureBootNotEnabled,

    #[error("KVM conflict: {0}")]
    KvmConflict(String),

    #[error("DKMS build failed: {0}")]
    DkmsBuildFailed(String),

    #[error("OpenSSL error: {0}")]
    OpenSslError(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Command execution failed: {0}")]
    CommandFailed(String),

    #[error("Configuration error: {0}")]
    ConfigError(String),

    #[error("User cancelled operation")]
    UserCancelled,

    #[error("{0}")]
    Other(String),
}

impl VBoxError {
    /// Provides recovery suggestions for the error
    pub fn recovery_suggestion(&self) -> Option<String> {
        match self {
            VBoxError::PermissionDenied(_) => {
                Some("Run the command with sudo or as root user.".to_string())
            }
            VBoxError::DependencyMissing(dep) => Some(format!(
                "Install the missing dependency:\n  sudo apt install {}",
                dep
            )),
            VBoxError::KeyNotFound(_) => Some(
                "Run the setup command to create signing keys:\n  sudo vbox-sb-manager setup"
                    .to_string(),
            ),
            VBoxError::MokNotEnrolled => Some(
                "Enroll the MOK and reboot:\n  sudo mokutil --import /root/module-signing/MOK.der\n  sudo reboot"
                    .to_string(),
            ),
            VBoxError::VirtualBoxNotInstalled => Some(
                "Install VirtualBox:\n  sudo apt install virtualbox virtualbox-dkms".to_string(),
            ),
            VBoxError::KvmConflict(_) => Some(
                "Disable KVM:\n  sudo vbox-sb-manager kvm disable".to_string(),
            ),
            VBoxError::DkmsBuildFailed(_) => Some(
                "Install build dependencies:\n  sudo apt install build-essential linux-headers-$(uname -r)"
                    .to_string(),
            ),
            _ => None,
        }
    }

    /// Returns a user-friendly error message with recovery suggestions
    pub fn user_message(&self) -> String {
        let mut message = format!("Error: {}", self);
        if let Some(suggestion) = self.recovery_suggestion() {
            message.push_str(&format!("\n\nSuggestion:\n{}", suggestion));
        }
        message
    }
}

/// Converts nix::Error to VBoxError
impl From<nix::Error> for VBoxError {
    fn from(err: nix::Error) -> Self {
        VBoxError::Other(format!("System error: {}", err))
    }
}

/// Converts serde_json::Error to VBoxError
impl From<serde_json::Error> for VBoxError {
    fn from(err: serde_json::Error) -> Self {
        VBoxError::ConfigError(format!("JSON parsing error: {}", err))
    }
}

/// Converts dialoguer::Error to VBoxError
impl From<dialoguer::Error> for VBoxError {
    fn from(err: dialoguer::Error) -> Self {
        match err {
            dialoguer::Error::IO(e) => VBoxError::Io(e),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_recovery_suggestions() {
        let err = VBoxError::PermissionDenied("test".to_string());
        assert!(err.recovery_suggestion().is_some());

        let err = VBoxError::KeyNotFound("test".to_string());
        assert!(err.recovery_suggestion().is_some());
    }

    #[test]
    fn test_user_message() {
        let err = VBoxError::PermissionDenied("access denied".to_string());
        let msg = err.user_message();
        assert!(msg.contains("Error:"));
        assert!(msg.contains("Suggestion:"));
    }
}
