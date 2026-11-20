<#
.SYNOPSIS
    KJL-OFFICE 品牌化 + 停用遥测/更新检查（幂等，可重复执行）

.DESCRIPTION
    在 solomd 仓库根目录执行，改动 8 处：
      · app/src-tauri/tauri.conf.json          productName / identifier / mainBinaryName / title / publisher
      · app/src-tauri/tauri.windows.conf.json  title
      · app/src-tauri/Cargo.toml               [[bin]] name（必须与 mainBinaryName 一致）
      · app/src-tauri/installer.nsh            SoloMD.exe -> KJL-OFFICE.exe；ProgID 改 KJLOFFICE.*
      · app/index.html                         <title>
      · app/package.json                       name
      · app/src/lib/telemetry.ts               替换为 no-op
      · app/src/lib/check-update.ts            替换为 no-op
    已改过的内容不会重复改，可安全地在 CI 里每轮执行。
#>

[CmdletBinding()]
param(
    [string]$NewName    = "KJL-OFFICE",
    [string]$Publisher  = "KJL",
    [string]$Identifier = "app.kjl.office",
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}
function Read-Utf8([string]$Path) {
    [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
}
function Swap([string]$Path, [string]$Pattern, [string]$Replacement, [string]$Label) {
    if (-not (Test-Path $Path)) { Write-Warning "缺少文件：$Path"; return }
    $t = Read-Utf8 $Path
    $new = [regex]::Replace($t, $Pattern, $Replacement)
    if ($new -ne $t) {
        Write-Utf8NoBom $Path $new
        Write-Host "  [改] $Label"
    } else {
        Write-Host "  [跳过] $Label（已是目标值或未匹配）"
    }
}

$tauri    = Join-Path $Root "app/src-tauri/tauri.conf.json"
$tauriWin = Join-Path $Root "app/src-tauri/tauri.windows.conf.json"
$cargo    = Join-Path $Root "app/src-tauri/Cargo.toml"
$nsh      = Join-Path $Root "app/src-tauri/installer.nsh"
$html     = Join-Path $Root "app/index.html"
$pkg      = Join-Path $Root "app/package.json"

Write-Host "== 1. 产品身份 =="
Swap $tauri    '"productName"\s*:\s*"[^"]*"'    ('"productName": "' + $NewName + '"')      "productName"
Swap $tauri    '"identifier"\s*:\s*"[^"]*"'     ('"identifier": "' + $Identifier + '"')    "identifier"
Swap $tauri    '"mainBinaryName"\s*:\s*"[^"]*"' ('"mainBinaryName": "' + $NewName + '"')  "mainBinaryName"
Swap $tauri    '"title"\s*:\s*"[^"]*"'          ('"title": "' + $NewName + '"')            "window.title"
Swap $tauri    '"publisher"\s*:\s*"[^"]*"'      ('"publisher": "' + $Publisher + '"')      "publisher"

Write-Host "== 2. Windows 专属配置 =="
Swap $tauriWin '"title"\s*:\s*"[^"]*"' ('"title": "' + $NewName + '"') "tauri.windows window.title"

Write-Host "== 3. Cargo 可执行名 =="
Swap $cargo '(?m)^name\s*=\s*"SoloMD"' ('name = "' + $NewName + '"') "Cargo.toml [[bin]] name"

Write-Host "== 4. NSIS 钩子 =="
Swap $nsh 'SoloMD\.exe' ($NewName + '.exe') 'installer.nsh exe 名'
Swap $nsh 'SoloMD\.md'  'KJLOFFICE.md'      'installer.nsh ProgID .md'
Swap $nsh 'SoloMD\.txt' 'KJLOFFICE.txt'     'installer.nsh ProgID .txt'

Write-Host "== 5. 前端入口 =="
Swap $html '<title>[^<]*</title>' ('<title>' + $NewName + '</title>') "index.html title"
Swap $pkg  '"name"\s*:\s*"solomd"' '"name": "kjl-office"'           "package.json name"

Write-Host "== 6. 停用遥测与更新检查 =="
foreach ($f in @("telemetry.ts", "check-update.ts")) {
    $src = Join-Path $PSScriptRoot $f
    $dst = Join-Path $Root ("app/src/lib/" + $f)
    if (-not (Test-Path $src)) { Write-Warning "缺少 $src"; continue }
    Copy-Item $src $dst -Force
    Write-Host "  [改] $f -> no-op"
}

Write-Host ""
Write-Host "== 校验 =="
$t = Read-Utf8 $tauri
if ($t -notmatch ('"productName"\s*:\s*"' + [regex]::Escape($NewName) + '"')) {
    throw "productName 改写失败"
}
$c = Read-Utf8 $cargo
if ($c -notmatch ('name\s*=\s*"' + [regex]::Escape($NewName) + '"')) {
    throw "Cargo.toml [[bin]] name 改写失败"
}
Write-Host "OK: productName=$NewName, bin=$NewName, identifier=$Identifier"
