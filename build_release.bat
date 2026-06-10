@echo off
echo ============================================================
echo [NUCLEAR BUILD] Starting Pure Release Build Workflow...
echo ============================================================

:: 1. Rebuild Go Core (Physical Overwrite)
echo [1/4] Rebuilding Go Core (.aar)...
powershell -ExecutionPolicy Bypass -File .\build_android_core.ps1
if %errorlevel% neq 0 (
    echo [ERROR] Go Core build failed!
    exit /b %errorlevel%
)

:: 2. Deep Clean Flutter
echo [2/4] Flutter Deep Cleaning...
call flutter clean
if %errorlevel% neq 0 (
    echo [ERROR] Flutter clean failed!
    exit /b %errorlevel%
)

:: 3. Deep Clean Android (Smash Gradle Cache)
echo [3/4] Android Deep Cleaning...
cd android
call .\gradlew.bat clean
if %errorlevel% neq 0 (
    echo [ERROR] Gradle clean failed!
    exit /b %errorlevel%
)
cd ..

:: 4. Final APK Build (Split per ABI)
echo [4/4] Executing Final Release Build...
call flutter build apk --release --split-per-abi
if %errorlevel% neq 0 (
    echo [ERROR] Final build failed!
    exit /b %errorlevel%
)

echo ============================================================
echo [SUCCESS] Nuclear build completed successfully!
echo Artifacts: android\app\build\outputs\apk\release\
echo ============================================================
pause
