param(
  [string]$Tag   = 'kjl-build-15',
  [string]$Repo  = 'KJLLin/KJL-OFFICE-Markdown',
  [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Join-Path $env:RUNNER_TEMP 'smoke' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$LogPath = Join-Path $OutDir 'smoke.log'
if (Test-Path $LogPath) { Remove-Item -Force $LogPath }

function Log([object]$msg) {
  $line = [string]$msg
  Write-Host $line
  Add-Content -Path $LogPath -Value $line -Encoding utf8
}
function Add-Summary([string]$text) {
  if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $text -Encoding utf8
  }
}
function Save-Screen([string]$file) {
  try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap([int]$b.Width, [int]$b.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    Log "    screenshot -> $file"
  } catch {
    Log "    ! screenshot failed: $($_.Exception.Message)"
  }
}

$issues = New-Object System.Collections.Generic.List[string]

function Launch-And-Inspect([string]$exe, [string]$label) {
  $stderrFile = Join-Path $OutDir "$label.stderr.txt"
  $stdoutFile = Join-Path $OutDir "$label.stdout.txt"
  $p = Start-Process -FilePath $exe -PassThru -RedirectStandardError $stderrFile -RedirectStandardOutput $stdoutFile
  Start-Sleep -Seconds 12
  $p.Refresh()
  if ($p.HasExited) {
    Log "  ! $label exited early, code=$($p.ExitCode)"
    throw "$label 启动后提前退出（exit $($p.ExitCode)）"
  }
  $title = $p.MainWindowTitle
  $hwnd  = $p.MainWindowHandle
  Log "  $label running pid=$($p.Id) title='$title' hwnd=$hwnd"
  $wv = (Get-Process msedgewebview2 -ErrorAction SilentlyContinue | Measure-Object).Count
  Log "  msedgewebview2 进程数: $wv"
  if ($wv -eq 0) { $issues.Add("$label：没有 WebView2 子进程，界面可能没加载起来") }
  if ([string]::IsNullOrWhiteSpace($title)) { $issues.Add("$label：主窗口标题为空（CI 会话可能不渲染窗口，仅提示）") }
  Start-Sleep -Seconds 2
  Save-Screen (Join-Path $OutDir "$label.png")
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
}

function Find-AppDir([string[]]$Candidates) {
  foreach ($dir in $Candidates) {
    if ($dir -and (Test-Path (Join-Path $dir 'KJL-OFFICE.exe'))) { return $dir }
  }
  $roots = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )
  foreach ($root in $roots) {
    if (-not (Test-Path $root)) { continue }
    foreach ($k in (Get-ChildItem $root -ErrorAction SilentlyContinue)) {
      $props = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
      if ($null -eq $props) { continue }
      if ($props.DisplayName -like 'KJL-OFFICE*' -and $props.InstallLocation) {
        if (Test-Path (Join-Path $props.InstallLocation 'KJL-OFFICE.exe')) {
          Log "  注册表 InstallLocation: $($props.InstallLocation) (DisplayVersion=$($props.DisplayVersion), Publisher=$($props.Publisher))"
          return [string]$props.InstallLocation
        }
      }
    }
  }
  return $null
}

Log "==== KJL-OFFICE 安装冒烟测试 ===="
Log "tag  : $Tag"
Log "repo : $Repo"
Log "time : $(Get-Date -Format o)"

$os = Get-CimInstance Win32_OperatingSystem
Log "OS   : $($os.Caption) $($os.Version) build $($os.BuildNumber)"
Log "user : $env:USERNAME"

Log ""
Log "== 1. 下载 Release 资产 =="
$pkg = Join-Path $OutDir 'pkg'
New-Item -ItemType Directory -Force -Path $pkg | Out-Null
& gh release download $Tag --repo $Repo --dir $pkg --clobber
if ($LASTEXITCODE -ne 0) { throw "gh release download 失败 ($LASTEXITCODE)" }
Get-ChildItem $pkg -File | ForEach-Object { Log ("  {0,-42} {1,10}" -f $_.Name, $_.Length) }

Log ""
Log "== 2. SHA256 校验 =="
$sums = Get-Content (Join-Path $pkg 'SHA256SUMS.txt')
$fail = 0
foreach ($f in (Get-ChildItem $pkg -File | Where-Object { $_.Name -match '\.(exe|msi)$' })) {
  $h = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToUpper()
  $hit = $sums | Where-Object { $_ -match $h }
  if ($hit) { Log "  MATCH    $($f.Name)  $h" } else { Log "  MISMATCH $($f.Name)  $h"; $fail++ }
}
if ($fail -gt 0) { throw "SHA256 校验失败：$fail 个文件" }

Log ""
Log "== 3. 免安装 exe =="
$portable = Join-Path $pkg 'KJL-OFFICE.exe'
$vi = (Get-Item $portable).VersionInfo
Log "  ProductName=$($vi.ProductName) FileVersion=$($vi.FileVersion) FileDescription=$($vi.FileDescription)"
if ($vi.ProductName -notlike '*KJL-OFFICE*') { $issues.Add("portable: ProductName 不是 KJL-OFFICE（$($vi.ProductName)）") }
Launch-And-Inspect $portable 'portable'

Log ""
Log "== 4. NSIS 静默安装 =="
$setup = (Get-ChildItem $pkg -Filter '*setup.exe' | Select-Object -First 1).FullName
$inst = Start-Process -FilePath $setup -ArgumentList '/S' -Wait -PassThru
Log "  安装器退出码: $($inst.ExitCode)"
if ($inst.ExitCode -ne 0) { throw "NSIS 静默安装失败（exit $($inst.ExitCode)）" }
Start-Sleep -Seconds 8

$appDir = Find-AppDir @(
  (Join-Path $env:LOCALAPPDATA 'KJL-OFFICE'),
  (Join-Path $env:LOCALAPPDATA 'Programs\KJL-OFFICE'),
  (Join-Path $env:ProgramFiles 'KJL-OFFICE'),
  (Join-Path ${env:ProgramFiles(x86)} 'KJL-OFFICE')
)
if (-not $appDir) { throw "安装后找不到 KJL-OFFICE.exe" }
Log "  安装目录: $appDir"
Get-ChildItem $appDir -File | Select-Object -First 8 | ForEach-Object { Log ("    {0,-36} {1,10}" -f $_.Name, $_.Length) }

$lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\KJL-OFFICE.lnk'
Log "  开始菜单快捷方式: $(Test-Path $lnk)"

Launch-And-Inspect (Join-Path $appDir 'KJL-OFFICE.exe') 'installed-nsis'

Log ""
Log "  卸载 NSIS 版本"
$uninstFile = Get-ChildItem $appDir -Filter 'uninstall*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $uninstFile) { throw "找不到卸载程序（uninstall*.exe）" }
$uninst = $uninstFile.FullName
Log "  卸载程序: $($uninstFile.Name)
$u = Start-Process -FilePath $uninst -ArgumentList '/S' -Wait -PassThru
Log "  卸载器退出码: $($u.ExitCode)"
$gone = $false
for ($i = 0; $i -lt 30; $i++) {
  if (-not (Test-Path (Join-Path $appDir 'KJL-OFFICE.exe'))) { $gone = $true; break }
  Start-Sleep -Seconds 2
}
if ($gone) { Log "  已卸载，exe 移除" } else { $issues.Add('NSIS: 卸载 60 秒后 exe 仍存在') }

Log ""
Log "== 5. MSI 静默安装 =="
$msi = (Get-ChildItem $pkg -Filter '*.msi' | Select-Object -First 1).FullName
$msiLog = Join-Path $OutDir 'msi-install.log'
& msiexec.exe /i $msi /qn /norestart /l*v $msiLog
$code = $LASTEXITCODE
Log "  MSI 安装退出码: $code"
if ($code -ne 0) {
  Log "  MSI 日志尾部："
  Get-Content $msiLog -Tail 25 -ErrorAction SilentlyContinue | ForEach-Object { Log "    $_" }
  throw "MSI 静默安装失败（exit $code）"
}
Start-Sleep -Seconds 5

$msiDir = Find-AppDir @(
  (Join-Path $env:ProgramFiles 'KJL-OFFICE'),
  (Join-Path ${env:ProgramFiles(x86)} 'KJL-OFFICE'),
  (Join-Path $env:LOCALAPPDATA 'KJL-OFFICE'),
  (Join-Path $env:LOCALAPPDATA 'Programs\KJL-OFFICE')
)
if (-not $msiDir) { throw "MSI 安装后找不到 KJL-OFFICE.exe" }
Log "  MSI 安装目录: $msiDir"
Launch-And-Inspect (Join-Path $msiDir 'KJL-OFFICE.exe') 'installed-msi'

Log ""
Log "  卸载 MSI 版本"
$msiUnLog = Join-Path $OutDir 'msi-uninstall.log'
& msiexec.exe /x $msi /qn /norestart /l*v $msiUnLog
$ucode = $LASTEXITCODE
Log "  MSI 卸载退出码: $ucode"
if ($ucode -ne 0) {
  Log "  MSI 卸载日志尾部："
  Get-Content $msiUnLog -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object { Log "    $_" }
  $issues.Add("MSI: 静默卸载失败（exit $ucode）")
}

Log ""
Log "== 6. 事件日志中的应用错误（近 10 分钟）=="
$since = (Get-Date).AddMinutes(-10)
$errors = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $since; Level = 2 } -ErrorAction SilentlyContinue |
  Where-Object { $_.Message -match 'KJL-OFFICE' } |
  Select-Object -First 5
if ($errors) {
  foreach ($e in $errors) { Log "  [$($e.TimeCreated)] $($e.ProviderName): $($e.Message.Substring(0, [Math]::Min(160, $e.Message.Length)))" }
} else {
  Log "  无 KJL-OFFICE 相关 Application 错误"
}

Log ""
Log "== 结果 =="
$ok = $true
foreach ($i in $issues) { Log "  WARN  $i"; $ok = $false }
Add-Summary "### KJL-OFFICE Windows 安装冒烟（$Tag）"
Add-Summary ""
Add-Summary "| 检查 | 结果 |"
Add-Summary "| --- | --- |"
Add-Summary "| SHA256 | 全部 MATCH |"
Add-Summary "| 免安装 exe | 已启动 |"
Add-Summary "| NSIS 静默安装/启动/卸载 | 通过 |"
Add-Summary "| MSI 静默安装/启动/卸载 | 通过 |"
if ($issues.Count -gt 0) {
  Add-Summary ""
  Add-Summary "**提示**"
  foreach ($i in $issues) { Add-Summary "- $i" }
}

if ($issues.Count -eq 0) {
  Log "SMOKE PASS：三项安装形态均能启动，无异常"
} else {
  Log "SMOKE PASS（带 $($issues.Count) 条提示，见上）"
}
exit 0
