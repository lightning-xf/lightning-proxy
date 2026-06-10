# Lightning VPN 一键打包脚本
# 作用：自动下载依赖、编译 Flutter、调用 Inno Setup 生成安装包

$ErrorActionPreference = "Stop"

Write-Host "🚀 开始全量打包流程..." -ForegroundColor Cyan

# 1. 检查并下载必备依赖
if (!(Test-Path "installer_assets")) { New-Item -ItemType Directory -Path "installer_assets" }
if (!(Test-Path "installer_assets\VC_redist.x64.exe")) {
    Write-Host "📦 正在下载 VC++ 运行库..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile "installer_assets\VC_redist.x64.exe" -UseBasicParsing
}

# 2. 清理并编译 Flutter
Write-Host "🧹 清理构建缓存..." -ForegroundColor Yellow
flutter clean
Write-Host "📦 正在编译 Flutter Windows Release..." -ForegroundColor Yellow
flutter pub get
flutter build windows --release

# 3. 调用 Inno Setup 打包
$ISCC = "B:\exe\Inno Setup 6\ISCC.exe"
if (!(Test-Path $ISCC)) {
    Write-Host "❌ 未找到 Inno Setup 编译器 (ISCC.exe)，请检查路径：$ISCC" -ForegroundColor Red
    exit 1
}

Write-Host "🛠️ 正在生成安装包..." -ForegroundColor Yellow
& $ISCC build_installer.iss

# 4. 完成
Write-Host "`n✅ 打包成功！" -ForegroundColor Green
$outputFile = Get-ChildItem "installer_build\LightningVPN_Setup_v*.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "📍 安装包位置：$($outputFile.FullName)" -ForegroundColor Cyan
