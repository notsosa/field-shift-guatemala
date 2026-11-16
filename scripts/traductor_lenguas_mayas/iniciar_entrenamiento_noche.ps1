# Lanza entrenar_noche.py en segundo plano (ventana oculta) y deja el log en modelos\logs\.
# Uso (desde la raíz del repo o desde esta carpeta):
#   powershell -ExecutionPolicy Bypass -File scripts\traductor_lenguas_mayas\iniciar_entrenamiento_noche.ps1 -Horas 8
# Ver progreso:
#   Get-Content modelos\logs\ESTADO.txt
#   Get-Content (Get-ChildItem modelos\logs\noche-*.log | Sort-Object LastWriteTime | Select-Object -Last 1) -Tail 20 -Wait
# Detenerlo:
#   Get-Content modelos\logs\PID.txt | ForEach-Object { Stop-Process -Id $_ }
param([double]$Horas = 8, [string]$Modelo = "", [int]$MaxEjemplos = 0, [int]$MaxEval = 60)

$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$raiz = Resolve-Path (Join-Path $aqui "..\..")
$python = Join-Path $raiz ".venv\Scripts\python.exe"
$logs = Join-Path $raiz "modelos\logs"
New-Item -ItemType Directory -Force $logs | Out-Null
$fecha = Get-Date -Format "yyyyMMdd-HHmm"
$log = Join-Path $logs "noche-$fecha.log"

$env:PYTHONIOENCODING = "utf-8"
$env:HF_HUB_OFFLINE = "1"          # el modelo base ya está descargado; no depende de internet
$p = Start-Process -FilePath $python -WindowStyle Hidden -PassThru `
    -WorkingDirectory $aqui `
    -ArgumentList (@("-u", "entrenar_noche.py", "--horas", "$Horas", "--max-ejemplos", "$MaxEjemplos", "--max-eval", "$MaxEval") + $(if ($Modelo) { @("--modelo", "`"$Modelo`"") } else { @() })) `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err"
$p.Id | Out-File -Encoding ascii (Join-Path $logs "PID.txt")
Write-Host "Entrenamiento iniciado en segundo plano (PID $($p.Id), $Horas h)."
Write-Host "Log:    $log"
Write-Host "Estado: $(Join-Path $logs 'ESTADO.txt')"
