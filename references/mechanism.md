# Why the Windows setup banner returns

## What fails

`CodexSandboxService` runs as LocalSystem. Before that service is called, the interactive Codex process creates `%USERPROFILE%\.codex\.sandbox-bin`, so the user owns it.

The first provision can still open the directory because it inherits SYSTEM Full Control. `lock_sandbox_bin_dir` then replaces that with a protected DACL:

- SYSTEM: Modify (`0x1301BF`), no WRITE_DAC (`0x40000`)
- Administrators: Modify, no WRITE_DAC
- Interactive user: Modify plus WRITE_DAC
- `CodexSandboxUsers`: ReadAndExecute

The next provision opens the existing directory with `READ_CONTROL | WRITE_DAC` from the ProvisionOnly path. LocalSystem is not the owner and has no WRITE_DAC, so the open fails. The logged error drops the Win32 code:

```text
helper_sandbox_lock_failed: lock sandbox bin dir \\?\C:\Users\<user>\.codex\.sandbox-bin failed: open directory \\?\C:\Users\<user>\.codex\.sandbox-bin
```

Older builds log the same failure as `SetNamedSecurityInfoW sandbox dir failed: 5`.

`prepare_setup_marker()` truncates `setup_marker.json` before provisioning. A failed provision leaves a 0-byte marker, so every later command reports `sandbox setup marker missing or incompatible` and the desktop shows **Finish Windows setup to continue**.

Clicking Continue runs setup as the interactive user. That user still has WRITE_DAC, so it succeeds once. The next service provision fails again.

## What triggers the repeat

Re-provision runs when the saved offline firewall allowlist does not match the current request. On machines that toggle a local proxy, the log alternates:

```text
sandbox setup required: offline firewall settings changed (stored_ports=[...], desired_ports=[...])
```

That is a settings refresh, not a failed install of a new sandbox package. A Codex update can also force a new provision, and then the same lock fails.

## Why `takeown /A` sticks

`takeown /F "%USERPROFILE%\.codex\.sandbox-bin" /A` assigns ownership to `BUILTIN\Administrators` (`S-1-5-32-544`). LocalSystem's token includes that group, so a later open with WRITE_DAC succeeds. Codex rewrites the DACL on every lock and does not change the owner, so the repair survives later provisions, reboots, and desktop updates that leave the directory in place.

These look similar and do not stick:

- Granting SYSTEM WRITE_DAC by hand. The next lock replaces the DACL.
- Renaming `.sandbox-bin` so Codex creates a new one. The new directory is user-owned, and the following lock seals SYSTEM out again.

## Upstream

The behavior is tracked in [openai/codex#51468](https://github.com/openai/codex/issues/51468). The local owner change is a workaround. A durable product fix is for the service to take ownership or keep WRITE_DAC for SYSTEM, and to keep the previous marker until the new provision succeeds.
