# Run by vm.sh provision over SSH from a temp folder holding client-cert.p12 and vpn-fed.pem.
# The .p12 password arrives on stdin so it never appears in a command line or a file. Safe to run again.
param(
    [switch]$NoUpdates,
    [string]$FortiInstaller = ''
)
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$p12Password = [Console]::In.ReadLine()

function Step($text) { Write-Output "== $text" }

Step 'certificates'
# The posture check needs the vpn-fed CA itself in the machine's Personal store, not only the user certificate
$ca = Join-Path $dir 'vpn-fed.pem'
Import-Certificate -FilePath $ca -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
Import-Certificate -FilePath $ca -CertStoreLocation Cert:\LocalMachine\My | Out-Null
$secure = ConvertTo-SecureString $p12Password -AsPlainText -Force
$cert = Import-PfxCertificate -FilePath (Join-Path $dir 'client-cert.p12') -CertStoreLocation Cert:\LocalMachine\My -Password $secure
$cert | ForEach-Object { Write-Output "imported $($_.Subject), valid until $($_.NotAfter.ToString('yyyy-MM-dd'))" }

Step 'bitlocker'
$volume = Get-BitLockerVolume -MountPoint 'C:'
$types = $volume.KeyProtector.KeyProtectorType
# Enable-BitLocker -TpmProtector fails when WinRE is off; manage-bde does not need WinRE
if ($types -notcontains 'RecoveryPassword') { manage-bde -protectors -add C: -recoverypassword | Out-Null }
if ($types -notcontains 'Tpm') { manage-bde -protectors -add C: -tpm | Out-Null }
if ($volume.VolumeStatus -eq 'FullyDecrypted') { manage-bde -on C: -used -skiphardwaretest | Out-Null }
(Get-BitLockerVolume -MountPoint 'C:').KeyProtector |
    Where-Object KeyProtectorType -eq 'RecoveryPassword' |
    ForEach-Object { Write-Output "RECOVERY-PASSWORD $($_.KeyProtectorId) $($_.RecoveryPassword)" }

if ($NoUpdates) {
    Step 'windows update off'
    'wuauserv', 'UsoSvc' | ForEach-Object { Stop-Service $_ -Force -ErrorAction SilentlyContinue; Set-Service $_ -StartupType Disabled }
    # WaaSMedicSvc re-enables the update services; its startup type can only be changed in the registry
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc' -Name Start -Value 4
    $au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    New-Item -Path $au -Force | Out-Null
    Set-ItemProperty $au -Name NoAutoUpdate -Value 1 -Type DWord
    Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name DisableWindowsUpdateAccess -Value 1 -Type DWord
}

if ($FortiInstaller) {
    Step 'forticlient'
    $installer = Join-Path $dir $FortiInstaller
    if ($installer -like '*.msi') {
        Start-Process msiexec.exe -ArgumentList '/i', "`"$installer`"", '/quiet', '/norestart' -Wait
    } else {
        Start-Process $installer -ArgumentList '/quiet', '/norestart' -Wait
    }
    Write-Output 'FortiClient installed: the VM needs a full restart before the first connection'
}

Step 'vpn mtu'
# The T-Mobile manual requires MTU 1300 on the FortiClient adapter; it exists only after FortiClient is installed
$forti = Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue | Where-Object InterfaceDescription -like '*Fortinet*'
if ($forti) {
    $forti | ForEach-Object {
        netsh interface ipv4 set subinterface "$($_.Name)" mtu=1300 store=persistent | Out-Null
        Write-Output "MTU 1300 on $($_.Name)"
    }
} else {
    Write-Output 'no FortiClient adapter yet: run vm.sh provision again after installing FortiClient'
}
