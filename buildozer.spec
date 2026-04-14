[app]
title = CheckSheet
package.name = checksheetapp
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,atlas,ttf,xlsx,json
version = 1.0

# 필수 라이브러리: openpyxl 및 et_xmlfile(openpyxl 종속성) 추가
requirements = python3,kivy,openpyxl,et_xmlfile,pyjnius,android

orientation = portrait
fullscreen = 0

# 안드로이드 권한 설정
android.permissions = READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, MANAGE_EXTERNAL_STORAGE

# Android API 레벨 설정 (33 = Android 13)
android.api = 33
android.minapi = 21
android.accept_sdk_license = True

[buildozer]
log_level = 2
warn_on_root = 0
