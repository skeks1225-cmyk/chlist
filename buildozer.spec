[app]
title = PDFTestV5
package.name = pdftestv5
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,ttf,pdf
source.exclude_dirs = backup, bin, .buildozer
version = 0.5

requirements = python3,kivy,pyjnius,android

orientation = portrait
fullscreen = 0

android.permissions = READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, MANAGE_EXTERNAL_STORAGE

# [수정] JitPack 표준 명칭(대소문자) 및 버전 적용
android.gradle_dependencies = com.github.barteksc:AndroidPdfViewer:3.2.0-beta.1
android.gradle_repositories = https://jitpack.io

android.enable_androidx = True
android.accept_sdk_license = True
android.api = 33
android.minapi = 21
android.ndk_api = 21

[buildozer]
log_level = 2
warn_on_root = 0
