# Codex Windows sandbox setup

Diagnose and repair the Codex Desktop loop that shows **Finish Windows setup to continue**.

The banner is Codex's elevated-sandbox setup gate. `CodexSandboxService` runs as LocalSystem and later cannot open `%USERPROFILE%\.codex\.sandbox-bin` with `WRITE_DAC`, because an earlier lock made that directory user-owned and protected. Clicking Continue works once, then the next sandbox re-provision fails again. Re-provision is usually triggered by an offline firewall port change, not by a failed sandbox package update.

## Diagnose

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Repair-CodexSandboxBin.ps1
```

Exit `2` means this bug. Exit `0` means the directory owner is already fine.

## Repair

Run in an elevated PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Repair-CodexSandboxBin.ps1 -Repair
```

That runs `takeown /F "%USERPROFILE%\.codex\.sandbox-bin" /A`. It changes the owner to `BUILTIN\Administrators` and does not rewrite the DACL. Then click **Continue** once in Codex.

Do not delete or rename `.sandbox-bin`. Codex recreates it as your user, and the lockout comes back. Do not add a SYSTEM permission entry by hand; the next lock replaces the whole DACL.

Details and the upstream issue are in [references/mechanism.md](references/mechanism.md).

## Install as a skill

Copy this folder to `%USERPROFILE%\.codex\skills\codex-windows-sandbox-setup` and, if you use other agents that load skills from there, also to `%USERPROFILE%\.agents\skills\codex-windows-sandbox-setup`.

## License

MIT
