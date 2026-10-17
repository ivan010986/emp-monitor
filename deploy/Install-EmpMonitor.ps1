#requires -RunAsAdministrator
<#
.SYNOPSIS
    Instala/actualiza el agente EmpMonitor (office mode, auto-registro) en equipos Windows.

.DESCRIPTION
    Idempotente y pensado para despliegue masivo (GPO startup script, PDQ Deploy,
    Intune, PsExec o ejecucion manual). Pasos:
      1. Instala el MSI en silencio (si el producto no esta ya instalado).
      2. Sobreescribe gui\configs\config.js con la config self-hosted (org + endpoints).
      3. Reinicia el servicio watchdog (BrowserHandlingService) y verifica el agente.

.USO
    Colocar junto al script:   emp-agent.msi  +  config.js  (misma carpeta o -SourceDir)
      .\Install-EmpMonitor.ps1
      .\Install-EmpMonitor.ps1 -SourceDir "\\SRV\share\empmonitor" -WhatIf:$false

    GPO (startup script, corre como SYSTEM):
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "\\DC\SYSVOL\...\Install-EmpMonitor.ps1" -SourceDir "\\DC\SYSVOL\...\empmonitor"

.EXITCODES 0=ok | 1=no admin | 2=msiexec fallo | 3=config no copiada | 4=archivos fuente no encontrados
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SourceDir = $PSScriptRoot,
    [string]$MsiName = 'emp-agent.msi',          # renombra el MSI a este nombre generico
    [string]$LogFile = "$env:ProgramData\EmpMonitor-deploy.log",
    # Workaround temporal mientras el DNS *.mefasa no resuelva a 192.168.0.206:
    # -UseHostsFile escribe las entradas en C:\Windows\System32\drivers\etc\hosts
    [switch]$UseHostsFile,
    [string]$BackendIp = '192.168.0.206'
)

$ConfigDestDir = "$env:ProgramFiles\EmpMonitor\EmpMonitor\gui\configs"
$ConfigDest = Join-Path $ConfigDestDir 'config.js'
$ProductName = 'EmpMonitor'
$GuiExe = "$env:ProgramFiles\EmpMonitor\EmpMonitor\gui\empmonitor.exe"
$ServiceName = 'BrowserHandlingService'

function Write-Log([string]$msg, [string]$level = 'INFO') {
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $level, $msg
    try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch {}
    Write-Host $line
}

# --- 0. Prerequisitos ---------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Log "Requiere ejecucion como administrador/SYSTEM." 'ERROR'; exit 1 }

$msiPath = Join-Path $SourceDir $MsiName
$configSrc = Join-Path $SourceDir 'config.js'
if (-not (Test-Path $configSrc)) { Write-Log "No existe config.js en $SourceDir" 'ERROR'; exit 4 }
if (-not (Test-Path $msiPath)) { Write-Log "No existe $MsiName en $SourceDir" 'ERROR'; exit 4 }

# --- 0b. Workaround hosts file (solo si el DNS interno aun no resuelve *.mefasa) --
if ($UseHostsFile) {
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $hostNames = @('empmonitor.mefasa', 'empmonitor-api.mefasa', 'empmonitor-agent.mefasa',
        'empmonitor-logs.mefasa', 'empmonitor-ws.mefasa', 'empmonitor-remote.mefasa',
        'empmonitor-rt.mefasa')
    $existing = Get-Content $hostsPath -ErrorAction SilentlyContinue
    foreach ($h in $hostNames) {
        if (-not ($existing | Select-String -SimpleMatch " $h")) {
            Add-Content $hostsPath "$BackendIp`t$h"
            Write-Log "hosts: $BackendIp -> $h"
        }
    }
}

# --- 1. Instalar MSI solo si el producto no esta presente ---------------------
$installed = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' `
    -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $ProductName }

if ($installed) {
    Write-Log "EmpMonitor ya instalado (v$($installed.DisplayVersion)) - se omite msiexec, solo se actualiza config."
}
else {
    Write-Log "Instalando $msiPath ..."
    $msiLog = "$env:TEMP\empmonitor-install-$((Get-Date).ToString('yyyyMMddHHmmss')).log"
    $p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @(
        '/i', "`"$msiPath`"", '/qn', '/norestart', '/l*v', "`"$msiLog`""
    )
    if ($p.ExitCode -ne 0) { Write-Log "msiexec fallo (codigo $($p.ExitCode)). Ver $msiLog" 'ERROR'; exit 2 }
    Write-Log "Instalacion MSI completada."
}

# --- 2. Desplegar config.js self-hosted ---------------------------------------
if (-not (Test-Path $ConfigDestDir)) { Write-Log "No existe $ConfigDestDir - instalacion incompleta" 'ERROR'; exit 3 }
$srcHash = (Get-FileHash $configSrc -Algorithm SHA256).Hash
$dstHash = if (Test-Path $ConfigDest) { (Get-FileHash $ConfigDest -Algorithm SHA256).Hash } else { '' }

if ($srcHash -eq $dstHash) {
    Write-Log "config.js ya esta actualizado."
}
else {
    Copy-Item $configSrc $ConfigDest -Force
    Write-Log "config.js actualizado -> $ConfigDest"
    # la config cambia los endpoints: hay que reiniciar el agente para tomarlos
    $needRestart = $true
}

# --- 3. (Re)arrancar servicio watchdog y agente --------------------------------
$svc = Get-Service $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    if ($needRestart -or $svc.Status -ne 'Running') {
        Restart-Service $ServiceName -Force -ErrorAction SilentlyContinue
        Write-Log "Servicio $ServiceName reiniciado."
    }
    # el watchdog relanza empmonitor.exe; si no arranca en 15s lo levantamos manual
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline -and -not (Get-Process empmonitor -ErrorAction SilentlyContinue)) {
        Start-Sleep -Seconds 2
    }
}
if (-not (Get-Process empmonitor -ErrorAction SilentlyContinue)) {
    Write-Log "Watchdog no levanto el agente; arrancando empmonitor.exe directamente." 'WARN'
    if (Test-Path $GuiExe) { Start-Process $GuiExe }
}

# --- 4. Verificacion -----------------------------------------------------------
$agentOk = [bool](Get-Process empmonitor -ErrorAction SilentlyContinue)
$svcOk = (Get-Service $ServiceName -ErrorAction SilentlyContinue).Status -eq 'Running'
$agentTxt = if ($agentOk) { 'corriendo' } else { 'NO' }
$svcTxt = if ($svcOk) { 'activo' } else { 'NO' }
Write-Log "Resultado: agente=$agentTxt servicio=$svcTxt"
if (-not $agentOk) { Write-Log "El agente no quedo corriendo." 'ERROR'; exit 2 }

Write-Log "Instalacion/despliegue OK. El equipo se auto-registrara como empleado (office mode)."
exit 0
