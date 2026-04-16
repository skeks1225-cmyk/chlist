[app]
title = PDFTest
package.name = pdftest
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,ttf,pdf
source.exclude_dirs = backup, bin, .buildozer
version = 0.4

requirements = python3,kivy,pyjnius,android

orientation = portrait
fullscreen = 0

android.permissions = READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, MANAGE_EXTERNAL_STORAGE

# [수정] 라이브러리 명칭과 버전을 가장 널리 쓰이는 조합으로 변경
android.gradle_dependencies = com.github.barteksc:android-pdf-viewer:3.1.0-beta.1
android.gradle_repositories = https://jitpack.io, https://maven.google.com

android.enable_androidx = True
android.accept_sdk_license = True
android.api = 33
android.minapi = 21
android.ndk_api = 21

[buildozer]
log_level = 2
warn_on_root = 0
