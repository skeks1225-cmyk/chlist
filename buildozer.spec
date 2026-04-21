[app]
title = CheckSheetFinal
package.name = checksheetv163
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,ttf,json
version = 16.3

# 🔥 핵심: 정석대로 pysmb 1.2.9.1 버전 고정 (빌드 재현성 확보)
requirements = python3==3.10.11,kivy==2.2.0,pyjnius==1.5.0,openpyxl,pysmb==1.2.9.1

orientation = portrait
fullscreen = 0

android.permissions = INTERNET,READ_EXTERNAL_STORAGE,WRITE_EXTERNAL_STORAGE,MANAGE_EXTERNAL_STORAGE

# 🔥 안정 핵심 (NDK 자동 선택 유도)
android.api = 31
android.minapi = 21
android.ndk_api = 21

android.accept_sdk_license = True

# ✅ PDF (검증)
android.gradle_dependencies = com.github.barteksc:android-pdf-viewer:2.8.2
android.gradle_repositories = https://jitpack.io

android.enable_androidx = True
android.enable_jetifier = True

# Gradle 메모리 확보
android.gradle_options = -Xmx4g

android.manifest.activities = org.example.checksheetv163.PdfActivity
android.add_src = src

[buildozer]
log_level = 2
warn_on_root = 1
