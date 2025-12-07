//! Integration tests for VirtualBox Secure Boot Manager

use assert_cmd::Command;
use predicates::prelude::*;

#[test]
fn test_help_command() {
    let mut cmd = Command::cargo_bin("virtualbox-sb-manager").unwrap();
    cmd.arg("--help");
    
    cmd.assert()
        .success()
        .stdout(predicate::str::contains("VirtualBox"))
        .stdout(predicate::str::contains("Commands:"));
}

#[test]
fn test_version_command() {
    let mut cmd = Command::cargo_bin("virtualbox-sb-manager").unwrap();
    cmd.arg("--version");
    
    cmd.assert()
        .success()
        .stdout(predicate::str::contains("virtualbox-sb-manager"));
}

#[test]
fn test_kvm_help() {
    let mut cmd = Command::cargo_bin("virtualbox-sb-manager").unwrap();
    cmd.args(["kvm", "--help"]);
    
    cmd.assert()
        .success()
        .stdout(predicate::str::contains("KVM management"));
}

#[test]
fn test_setup_help() {
    let mut cmd = Command::cargo_bin("virtualbox-sb-manager").unwrap();
    cmd.args(["setup", "--help"]);
    
    cmd.assert()
        .success()
        .stdout(predicate::str::contains("Complete setup"));
}

#[test]
fn test_sign_help() {
    let mut cmd = Command::cargo_bin("virtualbox-sb-manager").unwrap();
    cmd.args(["sign", "--help"]);
    
    cmd.assert()
        .success()
        .stdout(predicate::str::contains("Sign VirtualBox"));
}
