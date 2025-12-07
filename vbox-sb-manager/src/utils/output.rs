//! Terminal output utilities

use colored::*;

/// Print a success message
pub fn print_success(msg: &str) {
    println!("{} {}", "[SUCCESS]".green().bold(), msg);
}

/// Print an info message
pub fn print_info(msg: &str) {
    println!("{} {}", "[INFO]".blue(), msg);
}

/// Print a warning message
pub fn print_warning(msg: &str) {
    println!("{} {}", "[WARNING]".yellow().bold(), msg);
}

/// Print an error message
pub fn print_error(msg: &str) {
    eprintln!("{} {}", "[ERROR]".red().bold(), msg);
}

/// Print a header
pub fn print_header(msg: &str) {
    let separator = "=".repeat(msg.len() + 4);
    println!("{}", separator.cyan());
    println!("  {}  ", msg.bold());
    println!("{}", separator.cyan());
}

/// Print a section
pub fn print_section(msg: &str) {
    println!();
    println!("{}", msg.bold().underline());
    println!();
}

/// Print a progress indicator
pub fn print_progress(current: usize, total: usize, item: &str) {
    println!("[{}/{}] {}", current, total, item);
}

/// Print a styled box
pub fn print_box(title: &str, lines: &[&str]) {
    let max_width = lines.iter().map(|l| l.len()).max().unwrap_or(0).max(title.len());
    let top = format!("╔{}╗", "═".repeat(max_width + 2));
    let bottom = format!("╚{}╝", "═".repeat(max_width + 2));
    
    println!("{}", top.cyan());
    println!("║ {}{} ║", title.bold(), " ".repeat(max_width - title.len() + 1));
    if !lines.is_empty() {
        println!("║{}║", " ".repeat(max_width + 2));
    }
    for line in lines {
        println!("║ {}{} ║", line, " ".repeat(max_width - line.len() + 1));
    }
    println!("{}", bottom.cyan());
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_output_functions() {
        // These functions print to stdout/stderr, so we just test they don't panic
        print_success("test");
        print_info("test");
        print_warning("test");
        print_error("test");
        print_header("test");
        print_section("test");
        print_progress(1, 10, "test");
        print_box("Test", &["line 1", "line 2"]);
    }
}
