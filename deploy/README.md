# Despliegue masivo del agente EmpMonitor

Paquete para instalar el agente en los ~200 equipos Windows. El agente opera en
**office mode**: se auto-registra en el backend al arrancar (por MAC + hostname +
usuario de Windows) — no requiere credenciales ni interaccion del empleado.

## Contenido

| Archivo | Que es |
|---|---|
| `Install-EmpMonitor.ps1` | Instalador idempotente (MSI silencioso + config + verificacion) |
| `config.js` | Config self-hosted: org `OjUpRAB` (id 1) + endpoints `*.mefasa` |

Ademas colocar en la misma carpeta el MSI oficial renombrado a **`emp-agent.msi`**
(los instaladores no van a git; distribuirlo por share interno).

## Despliegue

### Dominio (GPO, corre como SYSTEM)
Crear GPO → *Computer Configuration → Policies → Windows Settings → Scripts → Startup*:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "\\DC\SYSVOL\<dominio>\scripts\empmonitor\Install-EmpMonitor.ps1" -SourceDir "\\DC\SYSVOL\<dominio>\scripts\empmonitor"
```

Los equipos lo aplican al reiniciar (o `gpupdate /force` + reboot).

### PDQ Deploy / Intune / RMM
Mismo comando PowerShell con `-SourceDir` apuntando al share que contiene
`emp-agent.msi` + `config.js`.

### Manual / PsExec
```
psexec \\EQUIPO -s powershell -ExecutionPolicy Bypass -File "\\share\empmonitor\Install-EmpMonitor.ps1" -SourceDir "\\share\empmonitor"
```

## Prerequisitos de red (criticos)

Cada equipo debe resolver y alcanzar:

| Destino | Puerto | Uso |
|---|---|---|
| `empmonitor-agent.mefasa` → `192.168.0.206` | 80 | registro/auth/config (`/api/v3`) |
| `empmonitor-logs.mefasa` → `192.168.0.206` | 80 | actividad + screenshots (`/api/v1`) |
| `192.168.0.206` | 9000 | MinIO — los presigned URLs de screenshots los abre el navegador del admin, no el agente |

**El wildcard DNS `*.mefasa` actual apunta a `192.168.5.5` (incorrecto).** Hasta
arreglarlo, el script puede añadir entradas en `hosts` como workaround temporal
(descomentar el bloque HOSTS en el script si hace falta) — pero lo correcto es
corregir el DNS interno.

## Que hace el script

1. Verifica admin/SYSTEM → instala el MSI solo si `EmpMonitor` no esta instalado
   (ProductName en registry de Uninstall).
2. Copia `config.js` a `C:\Program Files\EmpMonitor\EmpMonitor\gui\configs\` solo
   si difiere (hash SHA256) — re-correrlo es seguro.
3. Reinicia el watchdog `BrowserHandlingService` (que relanza el agente y
   sobrevive reinicios de Windows via `HKLM\...\Run`).
4. Verifica que `empmonitor.exe` quedo corriendo; log en
   `%ProgramData%\EmpMonitor-deploy.log`.

Exit codes: `0` ok · `1` sin admin · `2` msiexec/agente fallo · `3` config no copiada · `4` archivos fuente no encontrados.

## Soporte remoto — MeshCentral

Servicio separado de EmpMonitor (monitoreo), en el mismo servidor `.206`.

| Que | Donde |
|---|---|
| Consola admin | `https://192.168.0.206:4430` (cert autofirmado — aceptar advertencia) |
| Puerto agentes | TCP `4430` — los equipos deben alcanzar `192.168.0.206:4430` |
| Credenciales | usuario `admin` + password en env `MC_ADMIN_PASSWORD` de Coolify |

### Alta de equipos (una sola vez)

1. Entrar a la consola → **My Devices** → **Add Device Group**
   (nombre ej. `Mefasa PCs`, tipo *Agent for Windows*).
2. Click **Add Agent** en el grupo → descargar el instalador **Windows x64**
   (`meshagent64-MefasaPCs.exe` — ya trae embebidos: URL del servidor, hash del
   cert y el grupo destino — por eso no hace falta CA interna).
3. Desplegarlo con el mismo mecanismo del agente EmpMonitor:
   `meshagent64-MefasaPCs.exe -fullinstall` (silencioso, como SYSTEM).
   En segundos el equipo aparece en el grupo dentro de la consola.

### Uso

Consola → grupo → equipo → **Desktop** (remoto completo), **Terminal**,
**Files** — todo por el navegador, sin VPN ni software extra en el tecnico.

### Notas de seguridad

- `newAccounts` quedo en `false` (env `MC_NEW_ACCOUNTS`) — solo el admin crea
  usuarios desde **My Users**.
- La consola usa cert autofirmado sobre `192.168.0.206` — los agentes traen el
  hash embebido en su instalador, asi que la confianza agente→servidor no
  depende del navegador ni del DNS.
- Si se migra a hostname (ej. `soporte.mefasa`), hay que cambiar `cert` en el
  command del compose + regenerar los instaladores de agente.

## Notas

- El MSI original era build "personal" de otra org (`OjUpUCT`); `config.js` lo
  repunta a la org self-hosted — la misma tecnica sirve para cualquier equipo.
- Screenshots/screen-record y demas features vienen del `user/config` remoto —
  se controlan a nivel org/empleado desde el dashboard, sin reinstalar agentes.
- Las capturas van a MinIO local (`192.168.0.206:9000`) — nada sale a internet.
