[app]
title = PDFTestFinal3
package.name = pdftestfinal3
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,ttf,pdf
source.exclude_dirs = backup, bin, .buildozer
version = 1.2

requirements = python3,kivy,pyjnius,android

orientation = portrait
fullscreen = 0

android.permissions = READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, MANAGE_EXTERNAL_STORAGE

# [해결] JitPack에서 가장 성공률이 높은 mhiew 포크 버전의 3.2.0-beta.1 사용
android.gradle_dependencies = com.github.mhiew:android-pdf-viewer:3.2.0-beta.1
android.gradle_repositories = https://jitpack.io, https://repo.maven.apache.org/maven2/

android.enable_androidx = True
android.accept_sdk_license = True

# 다시 API 33으로 복구 (최신 빌드 도구 사용 유도)
android.api = 33
android.minapi = 21
android.ndk_api = 21

[buildozer]
log_level = 2
warn_on_root = 0
