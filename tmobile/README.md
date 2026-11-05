# T-Mobile CZ work setup (optional)

Not run by `first-login.sh`. It recreates the T-Mobile CZ (GPC) setup on a fresh install: a small Windows VM for the
FortiClient VPN, an SSH tunnel from Linux into it, Firefox routed through the tunnel with a Windows User-Agent, and
the environment for the GPC apps.

Why a VM: the VPN gateway runs an EMS posture check (BitLocker, Defender, the vpn-fed certificates) and needs a
special FortiClient build for Windows. Arch is not in its rules. Linux reaches the internal network through
`ssh -D` into the VM (socks5://127.0.0.1:1080). Only the domains in the PAC file go through it.

> The VM gets around the device check. Agree it with the client first. The browser sends a Windows User-Agent,
> but `navigator.platform` still reports Linux.

## Secrets: Proton Pass vault `tmobile-files`

Proton Pass is already installed by `setup-script.sh`, so every file that is not a shell variable lives in the vault
`tmobile-files`. Each file is a note whose title is its path (`files.list`) and whose content is base64.

| Item | Where it goes |
|---|---|
| `.config/tmobile/tmcz-ca.pem`, `slovak-telekom-root-ca2.pem` | `~/.config/tmobile/` (`ca-bundle-itc.pem` = system bundle + Slovak root, built on restore) |
| `.kube/configs/tmobile*.yaml`, `.aws/*`, `.m2/settings.xml` | `~/…`, kubeconfigs merged into `~/.kube/config` |
| `vm/client-cert.p12`, `vm/vpn-fed.pem` | only into the VM (LocalMachine\My, CA also Root) |
| `vm/client-cert-password` | **Login** item you create by hand: password = .p12 protection password |
| `vm/bitlocker-recovery-tmobile-vpn` | written by `vm.sh provision` |

Shell variables (GitLab/ITC/Jira tokens, `KEYSTONE_API_KEY`, DB passwords) stay in the `env-secrets` vault (see the main README).

**Fill the vault once, from the machine that has everything:** `bash tmobile/files.sh push`. Missing items are
created and existing ones are kept (`--force` replaces them). Then add `vm/client-cert-password` in the app.
Check with `bash tmobile/files.sh status`. The personal certificate is valid for 1 year
(https://mfa.telekom.sk). After you renew it, run `files.sh push --force` and `vm.sh provision`.

## New machine

1. `pass-cli login`, then `bash tmobile/setup.sh`. It installs the tunnel units, the Firefox policy, restores the files,
   merges the kubeconfig, pulls `~/projects/tmobile` from Proton Drive and turns on its hourly sync.
2. Download the Windows 11 ISO (https://www.microsoft.com/software-download/windows11, English) and run
   `bash tmobile/vm.sh create --iso ~/Downloads/Win11_*.iso`. It asks for the Windows password (save it in Proton Pass).
   In the console, press a key at *Press any key to boot from CD*. The install then needs no input (~30 min):
   Windows 11 **Pro**, local account, virtio drivers + guest agent, OpenSSH server (only the host may connect)
   with your `~/.ssh/id_ed25519.pub`, no sleep.
3. `bash tmobile/vm.sh provision`: waits for SSH, ejects the install media, deletes the unattend ISO (it holds the
   password), imports the certificates, turns on BitLocker (TPM + recovery key into Proton Pass).
   `--no-updates` also turns Windows Update off, like on the old VM.
   `--forticlient FortiClient.exe` installs an installer you already have.
4. In the VM, unless you used `--forticlient`: FortiClient from https://vpnclientcz.tcko.net/ (ex-account + 2FA). Only that build works.
   Install it and **restart** the VM. Then *Remote access* → user `ex…@external.t-mobile.cz`, certificate **Identita / vpn-fed** → Connect.
5. `bash tmobile/vm.sh provision` again: sets MTU 1300 on the FortiClient adapter (the T-Mobile manual requires it).
6. `bash tmobile/apps.sh --clone`: clones the repos (VPN + tokens). Then the databases (`scripts/db-restore.sh` in
   `~/projects/tmobile`) and the stack (`/sylius-fresh` or `dev-up.sh`).

## Scripts

| Script | What it does |
|---|---|
| `setup.sh [--vm-iso ISO]` | `tunnel.sh` → `firefox.sh` → `apps.sh` (+ `vm.sh create`) |
| `vm.sh create / provision / status / console / ssh` | VM `tmobile-vpn`: 2 vCPU, 6 GB RAM, 64 GB thin qcow2, UEFI Secure Boot, TPM 2.0, fixed IP 192.168.122.239 (DHCP reservation) |
| `tunnel.sh` | user units `tmobile-socks` (1080), `tmobile-socks-watch.timer` (starts the tunnel when the VM is up), `tmobile-http-proxy` (3128, pproxy, for Claude Keystone), on demand `tmobile-dev1-pg` (15433), `tmobile-test2-pg` (15432) |
| `firefox.sh` | `~/.config/tmobile/proxy.pac` + merges `firefox/policies-tmobile.json` (PAC proxy, User-Agent String Switcher with a Windows UA for Telekom/T-Mobile domains) into `/etc/firefox/policies/policies.json`. Run it again after `post-install.sh`, which overwrites that file |
| `apps.sh [--clone]` | kubelogin, uv + Python 3.12 (PCS), `files.sh restore`, kubeconfig merge, `claude-keystone` via the HTTP proxy, work folder + `tmobile-proton-sync.timer`, repos |
| `files.sh push / restore / get / status` | Proton Pass vault ↔ files |

Every value (VM name, IP, user, CPUs, RAM, disk folder, ports, vault) is in `env.sh`. Override it in the environment or in
`~/.config/tmobile/env`, e.g. `TM_VM_MEMORY_MB=8192`, `TM_VM_DIR=/mnt/data/vm`.

## Troubleshooting

- *Device not compliant*: the posture rules are in `C:\Program Files\Fortinet\FortiClient\logs\ec\host_verification.plain`.
  Usually the vpn-fed CA is missing from LocalMachine\My, or BitLocker is not done (`manage-bde -status`).
- The tunnel does not come up: `vm.sh status`, `journalctl --user -u tmobile-socks`. The VM does not answer ping
  (Windows firewall), so every check uses TCP 22.
- Restoring an older disk snapshot asks for the BitLocker recovery key, because the vTPM state is not in disk snapshots.
- The VPN pushes `192.168.0.0/16`. Routes to a more specific home LAN still win.
