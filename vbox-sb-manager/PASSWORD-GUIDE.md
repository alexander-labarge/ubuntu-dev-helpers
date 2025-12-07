# Password Guide - Understanding the Two Passwords

When running `sudo ./sign-vbox-modules.sh --setup`, you will be prompted for **TWO DIFFERENT PASSWORDS**. This document clarifies what each one is for.

## Summary Table

| Password | Tool | When Entered | Purpose | How Often Used | Can Forget? |
|----------|------|--------------|---------|----------------|-------------|
| **Signing Key Passphrase** | OpenSSL | During key creation | Protects private signing key | Every kernel update | NO - Write it down! |
| **Temporary MOK Password** | mokutil | During MOK import | One-time boot authentication | Only next boot | YES - After enrollment |

---

## Password #1: Signing Key Passphrase (OpenSSL)

### What You'll See:
```
Generating a RSA private key
.......................+++++
.......................+++++
writing new private key to '/root/module-signing/MOK.priv'
-----
Enter PEM pass phrase:           <-- FIRST PROMPT
Verifying - Enter PEM pass phrase:  <-- SECOND PROMPT (type same password)
-----
```

### Details:
- **Tool**: OpenSSL
- **Purpose**: Protects your private signing key (`MOK.priv`)
- **When needed**: Every time you sign VirtualBox modules (after kernel updates)
- **Frequency**: Could be weekly or monthly depending on kernel updates
- **Security**: Make it secure but memorable
- **If forgotten**: You must recreate keys and re-enroll MOK (big hassle!)

### Recommendations:
- Use a passphrase you'll remember (e.g., "MyVBox2025Signing!")
- Write it down in a password manager or secure location
- Make it at least 12 characters
- Don't make it too complex - you'll type it often

---

## Password #2: Temporary MOK Password (mokutil)

### What You'll See:
```
input password:           <-- FIRST PROMPT
input password again:     <-- SECOND PROMPT (type same password)
```

### Details:
- **Tool**: mokutil (Machine Owner Key utility)
- **Purpose**: One-time password for MOK enrollment at next boot
- **When needed**: ONLY at the next boot in the MOK Manager (blue screen)
- **Frequency**: Once (then never again unless you re-enroll)
- **Security**: Can be simple - it's temporary
- **If forgotten**: Just re-run `mokutil --import` with a new password

### Recommendations:
- Make it simple and easy to type (e.g., "temppass123")
- Minimum 8 characters (mokutil requirement)
- You only need to remember it until after next reboot
- Can be the same as signing key passphrase (but doesn't need to be)

---

## Complete Flow Example

Here's what happens when you run `sudo ./sign-vbox-modules.sh --setup`:

```
Step 1: Script asks for certificate name
  → Enter your name or press Enter for default

Step 2: OpenSSL prompts for SIGNING KEY PASSPHRASE (Password #1)
  → Enter PEM pass phrase: [type your main password]
  → Verifying - Enter PEM pass phrase: [type it again - must match]
  [DONE] Keys created!

Step 3: mokutil prompts for TEMPORARY MOK PASSWORD (Password #2)
  → input password: [type temporary password]
  → input password again: [type it again - must match]
  [DONE] MOK import scheduled!

Step 4: Reboot and use Password #2 in MOK Manager
  → Enter the temporary password in the blue screen
  [DONE] MOK enrolled!

Step 5: After reboot, use Password #1 to sign modules
  → sudo ./sign-vbox-modules.sh --sign
  → Passphrase for /root/module-signing/MOK.priv: [type Password #1]
  [DONE] Modules signed!
```

---

## Common Issues

### "password doesn't match" Error

**During OpenSSL (Password #1)**:
- You typed different passwords in the two prompts
- Solution: Run `sudo ./sign-vbox-modules.sh --setup` again and type carefully

**During mokutil (Password #2)**:
- You typed different passwords in the two prompts
- Solution: Run `sudo ./sign-vbox-modules.sh --setup` again
- Or run: `sudo mokutil --import /root/module-signing/MOK.der` separately

### Password Too Short

mokutil requires at least **8 characters** for the temporary password.

If you see repeated "password doesn't match" errors, try a longer password.

### Which Password Do I Use When?

**After initial setup:**

| Action | Which Password? |
|--------|----------------|
| Signing modules (`--sign`) | Password #1 (Signing Key Passphrase) |
| MOK Manager at boot | Password #2 (Temporary MOK Password) |
| Re-enrolling MOK | New temporary password (like Password #2) |

---

## Quick Tips

1. **Two different tools = Two different passwords**
   - OpenSSL → Signing Key Passphrase (permanent)
   - mokutil → Temporary Password (one-time)

2. **They can be the same or different**
   - It's your choice
   - Different is more secure
   - Same is easier to remember

3. **Write down Password #1**
   - You'll need it often
   - Can't recover if forgotten

4. **Password #2 is disposable**
   - Only matters until next boot
   - Can set a new one if you re-enroll

---

## Still Confused?

If you're unsure which password is being asked for, look at the prompt:

- **"Enter PEM pass phrase:"** → Password #1 (OpenSSL, permanent)
- **"input password:"** → Password #2 (mokutil, temporary)

The script now provides clear messages before each password prompt to help you understand which one is being requested.
