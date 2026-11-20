<#
.SYNOPSIS
    KJL-OFFICE 品牌化 + 停用遥测/更新检查 + 关闭赞助提示（幂等，可重复执行）

.DESCRIPTION
    在仓库根目录执行，改动这些地方：
      · app/src-tauri/tauri.conf.json          productName / identifier / mainBinaryName / title / publisher
      · app/src-tauri/tauri.windows.conf.json  title
      · app/src-tauri/Cargo.toml               [[bin]] name + description
      · app/src-tauri/installer.nsh            SoloMD.exe -> KJL-OFFICE.exe；ProgID 改 KJLOFFICE.*
      · app/index.html                         <title>
      · app/package.json                       name
      · app/src/**（.ts/.vue/.md/.css/.json）   界面里的所有可见品牌名 SoloMD -> KJL-OFFICE
      · app/src/lib/kjl-flags.ts               开关文件：KJL_SUPPORT_PROMPTS=false（赞助关闭）、KJL_STAR_PROMPT=true（Star 开启）
      · SettingsPanel / AboutDialog           所有赞助、打赏、推广入口用 v-if/守卫关掉
      · App.vue / AboutDialog                 Star 邀请与仓库链接指向本仓库
      · app/src-tauri（Rust/NSIS/wix）         打包层里的 SoloMD 字符串一并换掉
      · app/src/lib/telemetry.ts               替换为 no-op
      · app/src/lib/check-update.ts            替换为 no-op
    注意：小写 solomd 一律不动（localStorage 键、URL、MIME、CLI 名都靠它），
    字体族名 "SoloMD CJK" 也保留（@font-face 与 font-family 必须同名）。
    赞助提示只关入口，功能与文案代码全部保留：KJL_SUPPORT_PROMPTS 改回 true 即可恢复。
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
Swap $cargo '(?m)^description\s*=\s*"SoloMD' ('description = "' + $NewName) "Cargo.toml description"

Write-Host "== 4. NSIS 钩子 =="
Swap $nsh 'SoloMD\.exe' ($NewName + '.exe') 'installer.nsh exe 名'
Swap $nsh 'SoloMD\.md'  'KJLOFFICE.md'      'installer.nsh ProgID .md'
Swap $nsh 'SoloMD\.txt' 'KJLOFFICE.txt'     'installer.nsh ProgID .txt'

Write-Host "== 5. 前端入口 =="
Swap $html '<title>[^<]*</title>' ('<title>' + $NewName + '</title>') "index.html title"
Swap $pkg  '"name"\s*:\s*"solomd"' '"name": "kjl-office"'           "package.json name"

Write-Host "== 6. 界面品牌字符串（窗口标题 / 菜单 / 关于页 / 欢迎文档）=="
# 字体族名必须两端同名，先藏起来再还原，避免误改导致自定义字体失效
$fontGuard = "[[SOLOMD_CJK_KEEP]]"
$exts = @(".ts", ".vue", ".md", ".css", ".json", ".js", ".mjs", ".html")
$targets = @(Get-ChildItem -Path (Join-Path $Root "app/src") -Recurse -File |
             Where-Object { $exts -contains $_.Extension.ToLower() })
$targets += Get-Item $html

$touchedFiles = 0
$totalSubs = 0
foreach ($f in $targets) {
    try { $t = Read-Utf8 $f.FullName } catch { continue }
    if ($t -cnotmatch "SoloMD") { continue }
    $n = $t.Replace("SoloMD CJK", $fontGuard)
    $hits = ([regex]::Matches($n, "SoloMD")).Count
    $n = $n.Replace("SoloMD", $NewName)
    $n = $n.Replace($fontGuard, "SoloMD CJK")
    if ($n -ne $t) {
        Write-Utf8NoBom $f.FullName $n
        $touchedFiles++
        $totalSubs += $hits
    }
}
Write-Host ("  [改] 界面品牌名：{0} 处，涉及 {1} 个文件" -f $totalSubs, $touchedFiles)

Write-Host "== 7. 关闭赞助提示（Star 邀请保留并指向本仓库，只关入口）=="
$flagsSrc = Join-Path $PSScriptRoot "kjl-flags.ts"
$flagsDst = Join-Path $Root "app/src/lib/kjl-flags.ts"
if (-not (Test-Path $flagsSrc)) { throw "缺少 $flagsSrc" }
Copy-Item $flagsSrc $flagsDst -Force
Write-Host "  [改] kjl-flags.ts -> 赞助关、Star 开"

function PatchOnce([string]$Path, [string]$Sentinel, [string]$Pattern, [string]$Replacement, [string]$Label) {
    if (-not (Test-Path $Path)) { Write-Warning "缺少文件：$Path"; return }
    $t = Read-Utf8 $Path
    if ($t.Contains($Sentinel)) { Write-Host "  [跳过] $Label（已处理）"; return }
    $new = [regex]::Replace($t, $Pattern, $Replacement)
    if ($new -ceq $t) { Write-Host "  [跳过] $Label（锚点未命中）"; return }
    Write-Utf8NoBom $Path $new
    Write-Host "  [改] $Label"
}

$settings = Join-Path $Root "app/src/components/SettingsPanel.vue"
$about    = Join-Path $Root "app/src/components/AboutDialog.vue"
$star     = Join-Path $Root "app/src/lib/star-prompt.ts"

# —— Star 提示（若干天后的一次性弹窗，保持开启，动作指向本仓库）——
PatchOnce $star "from './kjl-flags';" '^/\*\*' ("import { KJL_STAR_PROMPT } from './kjl-flags';" + "`n`n/**") "star-prompt import"
PatchOnce $star "if (!KJL_STAR_PROMPT) return false;" `
    'export function shouldPrompt\(state: StarPromptState, today: string\): boolean \{' `
    ("export function shouldPrompt(state: StarPromptState, today: string): boolean {" + "`n  // KJL: Star 邀请由 KJL_STAR_PROMPT 控制（当前开启），原判断逻辑保留" + "`n  if (!KJL_STAR_PROMPT) return false;") `
    "star-prompt shouldPrompt"

# —— 设置面板：侧栏「支持」入口 + 打赏卡片 + 弹窗 ——
PatchOnce $settings "from '../lib/kjl-flags';" "import SupportDialog from './SupportDialog.vue';" `
    ("import SupportDialog from './SupportDialog.vue';" + "`nimport { KJL_SUPPORT_PROMPTS } from '../lib/kjl-flags';") `
    "SettingsPanel import"
PatchOnce $settings 'v-if="KJL_SUPPORT_PROMPTS" class="settings__nav-supporter-wrap"' `
    '<div class="settings__nav-supporter-wrap">' `
    '<div v-if="KJL_SUPPORT_PROMPTS" class="settings__nav-supporter-wrap">' `
    "设置侧栏「支持开发者」"
PatchOnce $settings '<div v-if="KJL_SUPPORT_PROMPTS" data-cat="basics"' `
    '<div\r?\n\s*data-cat="basics"\r?\n\s*class="settings__supporter-guide"' `
    '<div v-if="KJL_SUPPORT_PROMPTS" data-cat="basics" class="settings__supporter-guide"' `
    "设置页打赏卡片"
PatchOnce $settings '<SupportDialog v-if="KJL_SUPPORT_PROMPTS"' `
    '<SupportDialog\s*\r?\n\s*:open="supportModalOpen"' `
    '<SupportDialog v-if="KJL_SUPPORT_PROMPTS" :open="supportModalOpen"' `
    "设置页 SupportDialog"

# —— 关于页：徽章、支持入口、推广按钮、赞助者名单、sponsors.json 请求 ——
PatchOnce $about "from '../lib/kjl-flags';" "import SupportDialog from './SupportDialog.vue';" `
    ("import SupportDialog from './SupportDialog.vue';" + "`nimport { KJL_SUPPORT_PROMPTS } from '../lib/kjl-flags';") `
    "AboutDialog import"
PatchOnce $about 'KJL_SUPPORT_PROMPTS && activeBadge' 'v-if="activeBadge"' 'v-if="KJL_SUPPORT_PROMPTS && activeBadge"' "关于页支持者徽章"
PatchOnce $about '<button v-if="KJL_SUPPORT_PROMPTS" class="about__link"' `
    '<button class="about__link" @click="supportOpen = true">' `
    '<button v-if="KJL_SUPPORT_PROMPTS" class="about__link" @click="supportOpen = true">' `
    "关于页「支持开发者」"
PatchOnce $about 'KJL_SUPPORT_PROMPTS && !iapUseStoreFlow' `
    '<button v-if="!iapUseStoreFlow" class="about__promote"' `
    '<button v-if="KJL_SUPPORT_PROMPTS && !iapUseStoreFlow" class="about__promote"' `
    "关于页「帮忙推广」"
PatchOnce $about 'KJL_SUPPORT_PROMPTS && sponsors.length' `
    '<div v-if="sponsors.length" class="about__sponsors">' `
    '<div v-if="KJL_SUPPORT_PROMPTS && sponsors.length" class="about__sponsors">' `
    "关于页赞助者名单"
PatchOnce $about 'if (!KJL_SUPPORT_PROMPTS) return;' `
    'async function loadSponsors\(\) \{' `
    'async function loadSponsors() { if (!KJL_SUPPORT_PROMPTS) return;' `
    "关于页不发 sponsors.json 请求"
PatchOnce $about '<SupportDialog v-if="KJL_SUPPORT_PROMPTS"' `
    '<SupportDialog :open="supportOpen"' `
    '<SupportDialog v-if="KJL_SUPPORT_PROMPTS" :open="supportOpen"' `
    "关于页 SupportDialog"

# —— Star 邀请与关于页链接指向本仓库 ——
$repoSlug = "KJLLin/KJL-OFFICE-MARKDOWN"
$repoUrl  = "https://github.com/" + $repoSlug
$appVuePath = Join-Path $Root "app/src/App.vue"

function ReplaceLiteral([string]$Path, [string]$From, [string]$To, [string]$Label) {
    if (-not (Test-Path $Path)) { Write-Warning "缺少文件：$Path"; return }
    $t = Read-Utf8 $Path
    if (-not $t.Contains($From)) { Write-Host "  [跳过] $Label"; return }
    Write-Utf8NoBom $Path ($t.Replace($From, $To))
    Write-Host "  [改] $Label"
}

ReplaceLiteral $appVuePath "https://github.com/zhitongblog/solomd" $repoUrl "Star 提示 -> 本仓库"
ReplaceLiteral $about "zhitongblog/solomd" $repoSlug "关于页 GitHub 链接/文案"
ReplaceLiteral $about "https://solomd.app/whats-new" ($repoUrl + "/releases") "关于页更新日志 -> 本仓库 Releases"
ReplaceLiteral (Join-Path $Root "app/src/i18n/zh.ts") `
    "觉得 KJL-OFFICE 好用？去 GitHub 点个 Star 吧——它由一个人开发、免费开源，Star 能让更多人发现它。" `
    "觉得 KJL-OFFICE 好用？去 GitHub 点个 Star 吧——基于 MIT 开源项目改装的本地 Markdown 编辑器，Star 能让更多人发现它。" `
    "Star 提示中文文案"
ReplaceLiteral (Join-Path $Root "app/src/i18n/en.ts") `
    "it\'s made by one developer, and free." `
    "it\'s based on an MIT-licensed upstream editor." `
    "Star 提示英文文案"

Write-Host "== 8. 停用遥测与更新检查 =="
foreach ($f in @("telemetry.ts", "check-update.ts")) {
    $src = Join-Path $PSScriptRoot $f
    $dst = Join-Path $Root ("app/src/lib/" + $f)
    if (-not (Test-Path $src)) { Write-Warning "缺少 $src"; continue }
    Copy-Item $src $dst -Force
    Write-Host "  [改] $f -> no-op"
}

Write-Host ""
Write-Host "== 9. Rust / 打包层品牌字符串 =="
$tauriRoot = Join-Path $Root "app/src-tauri"
$exts2 = @(".rs", ".toml", ".json", ".nsh", ".wxs", ".yml", ".md")
$tauriFiles = @(Get-ChildItem -Path $tauriRoot -Recurse -File | Where-Object {
    $exts2 -contains $_.Extension.ToLower() -and
    $_.FullName -notmatch 'icons|binaries|target|gen'
})
$rFiles = 0
$rSubs = 0
foreach ($f in $tauriFiles) {
    try { $t = Read-Utf8 $f.FullName } catch { continue }
    if ($t -cnotmatch "SoloMD") { continue }
    $rSubs += ([regex]::Matches($t, "SoloMD")).Count
    $n = $t.Replace("SoloMD", $NewName)
    Write-Utf8NoBom $f.FullName $n
    $rFiles++
}
Write-Host ("  [改] 打包层品牌名：{0} 处，涉及 {1} 个文件" -f $rSubs, $rFiles)

Write-Host "== 校验 =="
$t = Read-Utf8 $tauri
if ($t -notmatch ('"productName"\s*:\s*"' + [regex]::Escape($NewName) + '"')) {
    throw "productName 改写失败"
}
$c = Read-Utf8 $cargo
if ($c -notmatch ('name\s*=\s*"' + [regex]::Escape($NewName) + '"')) {
    throw "Cargo.toml [[bin]] name 改写失败"
}

# 界面里不允许残留 SoloMD（字体族名除外；必须用 -cmatch，否则小写 solomd 也算命中）
$leftovers = @()
foreach ($f in $targets) {
    try { $t = Read-Utf8 $f.FullName } catch { continue }
    $probe = $t.Replace("SoloMD CJK", "")
    if ($probe -cmatch "SoloMD") { $leftovers += $f.FullName }
}
if ($leftovers.Count -gt 0) {
    throw ("界面里仍有 SoloMD 残留：" + ($leftovers -join "; "))
}

# 窗口标题是运行时由 App.vue 拼的，单独确认一次
$appVue = Read-Utf8 (Join-Path $Root "app/src/App.vue")
if ($appVue -cnotmatch ("— " + [regex]::Escape($NewName))) {
    throw "App.vue 的窗口标题没有改成 $NewName"
}

# 赞助提示必须已关闭（代码保留，只改开关）
$flags = Read-Utf8 (Join-Path $Root "app/src/lib/kjl-flags.ts")
if ($flags -notmatch 'KJL_SUPPORT_PROMPTS = false') {
    throw "kjl-flags.ts 没有关闭赞助提示"
}
foreach ($p in @($settings, $about)) {
    if ((Read-Utf8 $p) -notmatch 'KJL_SUPPORT_PROMPTS') { throw ("赞助提示未处理：" + $p) }
}

# Star 邀请必须开着，且指向本仓库
if ($flags -notmatch 'KJL_STAR_PROMPT = true') { throw "kjl-flags.ts 没有开启 Star 提示" }
if ((Read-Utf8 $star) -notmatch 'KJL_STAR_PROMPT') { throw "star-prompt.ts 未接入 Star 开关" }
$appVue3 = Read-Utf8 $appVuePath
if ($appVue3 -cnotmatch $repoSlug) { throw "App.vue 的 Star 提示未指向 $repoSlug" }
if ($appVue3 -cmatch 'zhitongblog/solomd') { throw "App.vue 仍指向上游仓库" }

# 打包层（Rust / NSIS / wix）不允许残留 SoloMD
$rLeft = @()
foreach ($f in $tauriFiles) {
    try { $t = Read-Utf8 $f.FullName } catch { continue }
    if ($t -cmatch 'SoloMD') { $rLeft += $f.FullName }
}
if ($rLeft.Count -gt 0) { throw ("打包层仍有 SoloMD 残留：" + ($rLeft -join "; ")) }

Write-Host "OK: productName=$NewName, bin=$NewName, identifier=$Identifier, 界面品牌名已统一, 赞助已关闭, Star 邀请开启并指向 $repoSlug"