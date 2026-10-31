# ========================================================
# CheckSheet 안드로이드 릴리즈 APK 초고속 안전 빌드 & 자동 아카이빙 스크립트
# ========================================================

$ErrorActionPreference = "Stop"

# 1. 환경 변수 설정
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.21.21-hotspot"
$env:PATH = "$env:JAVA_HOME\bin;$env:LOCALAPPDATA\Android\Sdk\platform-tools;$env:PATH"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:ANDROID_SDK_ROOT = "$env:LOCALAPPDATA\Android\Sdk"

# 2. 버전 정보 자동 추출 (Git 커밋 수 기반 자동 증가)
$buildNum = 1
try {
    $buildNum = (git rev-list --count HEAD).Trim()
} catch {
    $buildNum = [int]((Get-Date).ToString("yyyyMMdd"))
}

$shortHash = "local"
try {
    $shortHash = (git rev-parse --short HEAD).Trim()
} catch {}

$dateStr = Get-Date -Format "yyyyMMdd_HHmm"

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  [CheckSheet] 안드로이드 릴리즈 APK 빌드 & 아카이빙" -ForegroundColor Cyan
Write-Host "  타겟 플랫폼            : arm64-v8a (최신 스마트폰 초경량 고속)" -ForegroundColor White
Write-Host "  버전코드(versionCode) : $buildNum (원클릭 업데이트 지원)" -ForegroundColor White
Write-Host "  커밋(Git Hash)         : $shortHash" -ForegroundColor White
Write-Host "  빌드 일시              : $dateStr" -ForegroundColor White
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

# 3. 플러터 릴리즈 빌드 실행 (arm64-v8a 전용 초경량 빌드)
Write-Host ">> 플러터 릴리즈 APK 빌드 시작 (arm64-v8a 초경량)..." -ForegroundColor Yellow
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

flutter build apk --release --build-number=$buildNum --target-platform=android-arm64

$stopwatch.Stop()
$elapsedSec = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "❌ [빌드 실패] 에러 로그를 확인해 주세요." -ForegroundColor Red
    exit $LASTEXITCODE
}

# 4. 역대 버전 아카이빙 폴더로 자동 복사
$releasesDir = Join-Path $PSScriptRoot "releases"
if (-not (Test-Path $releasesDir)) {
    New-Item -ItemType Directory -Force -Path $releasesDir | Out-Null
}

$sourceApk = Join-Path $PSScriptRoot "build\app\outputs\flutter-apk\app-release.apk"
$targetApkName = "checksheet_${dateStr}_v${buildNum}_${shortHash}.apk"
$targetApk = Join-Path $releasesDir $targetApkName
$latestApk = Join-Path $releasesDir "checksheet_latest.apk"

Copy-Item -Path $sourceApk -Destination $targetApk -Force
Copy-Item -Path $sourceApk -Destination $latestApk -Force

$apkSizeMB = [math]::Round((Get-Item $targetApk).Length / 1MB, 1)

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "  [빌드 및 아카이빙 완료!]" -ForegroundColor Green
Write-Host "  소요 시간 : ${elapsedSec}초" -ForegroundColor White
Write-Host "  파일 크기 : ${apkSizeMB} MB" -ForegroundColor White
Write-Host "  보관 파일 : $targetApk" -ForegroundColor Yellow
Write-Host "  최신 파일 : $latestApk" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""

# 5. 윈도우 탐색기에서 생성된 파일 자동 선택 노출
try {
    & explorer.exe /select,$targetApk
} catch {}

