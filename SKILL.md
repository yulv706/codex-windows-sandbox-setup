---
name: codex-windows-sandbox-setup
description: >-
  Diagnose and repair the Codex Windows elevated-sandbox loop that shows
  "Finish Windows setup to continue" when LocalSystem cannot lock
  %USERPROFILE%\.codex\.sandbox-bin. Use when Codex or ChatGPT Desktop reports
  helper_sandbox_lock_failed, "open directory" on .sandbox-bin,
  SetNamedSecurityInfoW error 5, "sandbox setup marker missing or incompatible",
  or an Agent sandbox prompt that returns after Continue.
metadata:
  short-description: Repair Codex Windows sandbox setup lockout
---

# Codex Windows sandbox setup

The banner is Codex's elevated-sandbox setup gate. It is not Windows OOBE. Do not edit OOBE registry keys, and do not rename or delete `.sandbox-bin`.

## Workflow

1. Run the diagnose script from this skill directory. It does not change permissions.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Repair-CodexSandboxBin.ps1
```

2. Act on the diagnosis:

| Exit | Meaning | Action |
|---|---|---|
| 0 | Owner can be locked by LocalSystem, and the marker is intact | Stop. The banner has another cause. |
| 2 | `.sandbox-bin` is a protected, user-owned directory and SYSTEM has no WRITE_DAC | Repair below. |
| 3 | Ownership is already fixed, but `setup_marker.json` is empty or `setup_error.json` is still the lock error | Do not run `takeown` again. Ask the user to click **Continue** once. |
| 1 or 4 | Missing directory, or the ACL does not match this bug | Read [references/mechanism.md](references/mechanism.md) before changing anything. |

3. Repair only after exit code 2, in an elevated PowerShell. This changes the directory owner to `BUILTIN\Administrators` and leaves the DACL unchanged.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Repair-CodexSandboxBin.ps1 -Repair
```

4. Ask the user to click **Continue** once and approve UAC if it appears. Codex must rewrite `setup_marker.json` itself. Do not hand-write that file or invent a setup payload.
5. Run the script again. Stop when it prints `diagnosis: ok`.

## Rules

- Do not add a SYSTEM WRITE_DAC entry. The next successful lock rewrites the whole DACL and removes it.
- Do not delete, rename, or recreate `.sandbox-bin`. Codex recreates it as the interactive user, and the lockout returns on the next provision.
- Do not change `[windows] sandbox` away from `elevated` unless the user explicitly wants to give up the elevated sandbox.
- Do not take ownership of `WindowsApps` or the rest of `%USERPROFILE%\.codex`.
- A proxy-port change in the sandbox log (`offline firewall settings changed`) is the usual trigger, not a failed sandbox package update. After the owner fix, those re-provisions should succeed.

Read [references/mechanism.md](references/mechanism.md) when explaining why it comes back, or when the script result does not match the banner.
