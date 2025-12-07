//! Logging utilities

use crate::error::Result;
use chrono::Local;
use colored::*;
use log::{Level, LevelFilter, Log, Metadata, Record};
use std::fs::OpenOptions;
use std::io::Write;
use std::path::Path;
use std::sync::Mutex;

/// Custom logger that writes to both console and file
pub struct VBoxLogger {
    log_file: Mutex<std::fs::File>,
    console_enabled: bool,
}

impl VBoxLogger {
    /// Creates a new logger
    pub fn new<P: AsRef<Path>>(log_file_path: P, console_enabled: bool) -> Result<Self> {
        let log_file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(log_file_path)?;
        
        Ok(Self {
            log_file: Mutex::new(log_file),
            console_enabled,
        })
    }
    
    /// Initializes the global logger
    pub fn init<P: AsRef<Path>>(log_file_path: P, level: LevelFilter) -> Result<()> {
        let logger = Box::new(Self::new(log_file_path, true)?);
        log::set_boxed_logger(logger)
            .map_err(|e| crate::error::VBoxError::Other(format!("Failed to set logger: {}", e)))?;
        log::set_max_level(level);
        Ok(())
    }
    
    fn format_console_message(&self, record: &Record) -> String {
        let level_str = match record.level() {
            Level::Error => "[ERROR]".red().bold(),
            Level::Warn => "[WARNING]".yellow().bold(),
            Level::Info => "[INFO]".blue(),
            Level::Debug => "[DEBUG]".cyan(),
            Level::Trace => "[TRACE]".normal(),
        };
        
        format!("{} {}", level_str, record.args())
    }
    
    fn format_file_message(&self, record: &Record) -> String {
        let timestamp = Local::now().format("%Y-%m-%d %H:%M:%S");
        format!("[{}] [{}] {}", timestamp, record.level(), record.args())
    }
}

impl Log for VBoxLogger {
    fn enabled(&self, metadata: &Metadata) -> bool {
        metadata.level() <= Level::Trace
    }
    
    fn log(&self, record: &Record) {
        if self.enabled(record.metadata()) {
            // Write to file
            if let Ok(mut file) = self.log_file.lock() {
                let _ = writeln!(file, "{}", self.format_file_message(record));
            }
            
            // Write to console
            if self.console_enabled {
                eprintln!("{}", self.format_console_message(record));
            }
        }
    }
    
    fn flush(&self) {
        if let Ok(mut file) = self.log_file.lock() {
            let _ = file.flush();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;
    
    #[test]
    fn test_logger_creation() {
        let temp_file = NamedTempFile::new().unwrap();
        let logger = VBoxLogger::new(temp_file.path(), true);
        assert!(logger.is_ok());
    }
}
