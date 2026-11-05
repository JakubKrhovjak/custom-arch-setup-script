# Runs once at the first logon (FirstLogonCommands), from the unattend CD next to authorized_keys and host-ip.txt.
# Goal: the host can reach the VM over SSH with its key; everything else is done later by vm.sh provision.
$ErrorActionPreference = 'Continue'
$cd = $PSScriptRoot
$log = 'C:\ProgramData\tmobile-firstlogon.log'
Start-Transcript -Path $log -Append | Out-Null

$tools = Get-PSDrive -PSProvider FileSystem |
    ForEach-Object { Join-Path $_.Root 'virtio-win-guest-tools.exe' } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1
if ($tools) {
    # NetKVM (the network driver) and the QEMU guest agent come from here; without it the VM has no network
    Start-Process -FilePath $tools -ArgumentList '/install', '/quiet', '/norestart' -Wait
}

$deadline = (Get-Date).AddMinutes(10)
while (-not (Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet) -and (Get-Date) -lt $deadline) { Start-Sleep 10 }

# OpenSSH Server is a Feature on Demand: it downloads from Windows Update, hence the wait for the network
Get-WindowsCapability -Online -Name 'OpenSSH.Server*' |
    Where-Object State -ne 'Installed' |
    ForEach-Object { Add-WindowsCapability -Online -Name $_.Name }
Set-Service sshd -StartupType Automatic
Start-Service sshd
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -PropertyType String -Force `
    -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' | Out-Null

$hostIp = (Get-Content (Join-Path $cd 'host-ip.txt') -Raw).Trim()
Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue |
    Set-NetFirewallRule -Profile Any -RemoteAddress $hostIp
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Direction Inbound `
        -Protocol TCP -LocalPort 22 -Action Allow -Profile Any -RemoteAddress $hostIp | Out-Null
}

# Admin users read keys only from this file, and sshd ignores it unless only Administrators and SYSTEM can access it
$keys = 'C:\ProgramData\ssh\administrators_authorized_keys'
Copy-Item (Join-Path $cd 'authorized_keys') $keys -Force
icacls $keys /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null

# A sleeping VM drops the VPN and the tunnel with it
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
powercfg /change hibernate-timeout-ac 0

Set-Content -Path 'C:\ProgramData\tmobile-firstlogon.done' -Value (Get-Date -Format o)
Stop-Transcript | Out-Null
