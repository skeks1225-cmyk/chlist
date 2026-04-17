[app]
title = CheckSheetApp
package.name = checksheetappv7
package.domain = org.example
source.dir = .
# [수정] xlsx와 json 확장자를 추가하여 데이터 파일 누락 방지
source.include_exts = py,png,jpg,kv,ttf,pdf,xlsx,json
source.exclude_dirs = backup, bin, .buildozer
version = 1.4

requirements = python3,kivy,pyjnius,android,openpyxl,pysmb,pyasn1,six,tqdm,et_xmlfile,jdcal

orientation = portrait
fullscreen = 0

android.permissions = READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, MANAGE_EXTERNAL_STORAGE, INTERNET, ACCESS_NETWORK_STATE

android.gradle_dependencies = com.github.mhiew:android-pdf-viewer:3.2.0-beta.1
android.gradle_repositories = https://jitpack.io

android.enable_androidx = True
android.accept_sdk_license = True

android.api = 33
android.minapi = 21
android.ndk_api = 21

[buildozer]
log_level = 2
warn_on_root = 0
