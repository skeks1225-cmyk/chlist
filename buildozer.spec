[app]
title = PDFTestFinal2
package.name = pdftestfinal2
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,ttf,pdf
source.exclude_dirs = backup, bin, .buildozer
version = 1.1

requirements = python3,kivy,pyjnius,android

orientation = portrait
fullscreen = 0

android.permissions = READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, MANAGE_EXTERNAL_STORAGE

# [해결] 명시적 저장소 설정을 제거하여 기본 MavenCentral을 사용하도록 유도
android.gradle_dependencies = com.github.barteksc:android-pdf-viewer:2.8.2

android.enable_androidx = True
android.accept_sdk_license = True

# 안정성을 위해 API 31 유지
android.api = 31
android.minapi = 21
android.ndk_api = 21

[buildozer]
log_level = 2
warn_on_root = 0
