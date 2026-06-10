# 1. 环境准备
$env:GOROOT="C:\Users\admin\sdk\go1.26.2" 
$env:Path="$env:GOROOT\bin;$env:Path" 
$env:GO111MODULE="on" 
$env:GOPROXY="https://goproxy.cn,direct" 
 
$workDir = "go_core" 
if (!(Test-Path $workDir)) { New-Item -ItemType Directory -Path $workDir | Out-Null } 
Set-Location $workDir 
 
if (!(Test-Path "go.mod")) { 
    go mod init build_windows_core 
} 

# 强制拉取指定版本的源码
Write-Host "正在获取 Xray 核心源码 (v1.260327.0)..."
go get github.com/xtls/xray-core@v1.260327.0
if ($LASTEXITCODE -ne 0) { Write-Error "获取源码失败"; exit 1 }
 
Write-Host "[1/3] 同步依赖并本地化源码 (Vendor)..." 
go mod tidy 
go mod vendor 
if ($LASTEXITCODE -ne 0) { Write-Error "Vendor 失败"; exit 1 }
 
Write-Host "[2/3] 正在执行源码级“越狱”手术..." 
$targetDir = "vendor\github.com\xtls\xray-core\" 
 
# A. 拆除时间炸弹 (所有 .go 文件)
$files = Get-ChildItem -Path $targetDir -Recurse -Filter *.go 
foreach ($file in $files) { 
    $content = Get-Content -LiteralPath $file.FullName -Raw 
    if ($content -match 'time\.Now\(\)\.After') { 
        $modified = $content -replace 'time\.Now\(\)\.After\(.+?\)', 'false' 
        Set-Content -LiteralPath $file.FullName -Value $modified 
    } 
} 
 
# B. 切除 allowInsecure 硬拦截 (核心手术)
$transportGo = "vendor\github.com\xtls\xray-core\infra\conf\transport_internet.go" 
if (Test-Path $transportGo) { 
    $content = Get-Content -LiteralPath $transportGo -Raw 
    
    # 使用正则表达式匹配整个 allowInsecure 判定逻辑块
    # 匹配模式：从 if c.AllowInsecure { 开始，到对应的结束大括号
    # 包含了 PrintRemovedFeatureError 的特征
    $pattern = '(?s)if c\.AllowInsecure \{.+?errors\.PrintRemovedFeatureError.+?config\.AllowInsecure = true\s+\}\s+\}'
    $replacement = "config.AllowInsecure = c.AllowInsecure" 
    
    $modified = $content -replace $pattern, $replacement 
    
    if ($modified -ne $content) { 
        # 清理未使用导入
        $modified = $modified -replace '(?m)^\s+"time"\s*$', ''
        Set-Content -LiteralPath $transportGo -Value $modified -Encoding UTF8
        Write-Host "  [+] Success: allowInsecure 硬拦截已物理切除！" 
    } else {
        # 兜底方案：如果正则匹配失败，尝试查找特定行号范围进行替换
        Write-Warning "  [!] 正则匹配失败，尝试行级替换..."
        $lines = Get-Content $transportGo
        $newLines = @()
        $skip = $false
        foreach ($line in $lines) {
            if ($line -like "*if c.AllowInsecure {*") {
                $newLines += "	config.AllowInsecure = c.AllowInsecure"
                $skip = $true
                continue
            }
            if ($skip) {
                if ($line -like "*if c.PinnedPeerCertSha256 != "" {*") {
                    $skip = $false
                    $newLines += $line
                }
                continue
            }
            $newLines += $line
        }
        Set-Content -LiteralPath $transportGo -Value $newLines -Encoding UTF8
        Write-Host "  [+] Success: 行级替换完成！"
    }
} 
 
Write-Host "[3/3] 开始编译 Windows 专属特权版 xray-core.exe..." 
$outPath = "..\assets\windows\xray-core.exe" 

if (Test-Path $outPath) { Remove-Item $outPath -Force }

go build -mod=vendor -o $outPath -trimpath -ldflags="-s -w" .\vendor\github.com\xtls\xray-core\main 

if ($LASTEXITCODE -eq 0 -and (Test-Path $outPath)) {
    Write-Host "✅ 编译成功！"
    Write-Host "✅ PC 端底层核心已越狱并更新。" 
} else {
    Write-Error "❌ 编译失败！"
    exit 1
}
