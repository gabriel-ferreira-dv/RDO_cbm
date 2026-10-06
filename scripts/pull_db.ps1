<#
Puxa o banco SQLite do app instalado no emulador/dispositivo Android conectado
e salva uma cópia local em registro_diario.db, na raiz do projeto.

Uso:
  .\scripts\pull_db.ps1
  .\scripts\pull_db.ps1 -PackageName com.outro.pacote -Destino C:\caminho\saida.db
#>
param(
    [string]$PackageName = "com.example.flutter_application_1",
    [string]$Destino = (Join-Path (Split-Path $PSScriptRoot -Parent) "registro_diario.db")
)

$ErrorActionPreference = "Stop"

$candidatosAdb = @(
    "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    "adb.exe",
    "adb"
)
$adb = $null
foreach ($c in $candidatosAdb) {
    if ($c -in @("adb.exe", "adb")) {
        if (Get-Command $c -ErrorAction SilentlyContinue) { $adb = $c; break }
    } elseif (Test-Path $c) {
        $adb = $c; break
    }
}
if (-not $adb) {
    Write-Error "adb não encontrado. Instale o Android SDK Platform-Tools."
    exit 1
}

Write-Host "Usando adb: $adb"
Write-Host "Puxando banco do pacote '$PackageName'..."

# cmd.exe faz redirecionamento binário puro; o operador '>' do PowerShell
# (Out-File) trataria a saída como texto e corromperia o arquivo .db.
cmd /c "`"$adb`" exec-out run-as $PackageName cat databases/registro_diario.db > `"$Destino`""

if (-not (Test-Path $Destino) -or (Get-Item $Destino).Length -eq 0) {
    Write-Error "Falha ao copiar o banco. Confirme que o app já foi aberto pelo menos uma vez no dispositivo/emulador e que ele está conectado (adb devices)."
    exit 1
}

Write-Host "Banco copiado para: $Destino"
