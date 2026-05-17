$env:GO111MODULE="on"
$env:GOPROXY="https://goproxy.cn,direct"
$env:PATH="$env:PATH;D:\GO\bin;C:\Users\admin\go\bin"
$env:ANDROID_HOME="D:\SDK"
$env:ANDROID_SDK_ROOT="D:\SDK"
$env:ANDROID_NDK_HOME="D:\SDK\ndk\26.2.11394342"

$ErrorActionPreference = "Stop"

Write-Host "Building Go core for Android..."

# Create libs directory if not exists
New-Item -ItemType Directory -Force -Path "android\app\libs" | Out-Null

# Run gomobile bind
Set-Location "go_core"
Write-Host "Current directory: $(Get-Location)"

# Build for arm64, armeabi-v7a, and x86_64 (amd64) to support all modern devices
gomobile bind -v -target="android/arm,android/arm64,android/amd64" -androidapi 24 -ldflags="-s -w" -trimpath -o ../android/app/libs/libxray.aar .

Set-Location ".."
Write-Host "Build successful: android\app\libs\libxray.aar"