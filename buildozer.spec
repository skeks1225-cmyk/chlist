[app]
title = CheckSheetFinal
package.name = checksheetv163
package.domain = org.example
source.dir = .
source.include_exts = py,kv,jpg,png,ttf
version = 16.3

requirements = python3,kivy,pyjnius,openpyxl,pysmb,pyasn1,six,tqdm,et_xmlfile,jdcal,pycryptodome

orientation = portrait
fullscreen = 0

# ✅ API 안정 조합
android.api = 31
android.minapi = 21
android.ndk_api = 21

android.accept_sdk_license = True

# 🔥 핵심 (이 조합이 성공률 최고)
android.gradle_dependencies = com.github.barteksc:android-pdf-viewer:3.2.0-beta.1
android.gradle_repositories = https://jitpack.io

android.enable_androidx = True
android.enable_jetifier = True

# Java Activity 연결
android.manifest.activities = org.example.checksheetv163.PdfActivity
android.add_src = src

# 권한
android.permissions = INTERNET,READ_EXTERNAL_STORAGE,WRITE_EXTERNAL_STORAGE,MANAGE_EXTERNAL_STORAGE

# 엔트리
android.entrypoint = org.kivy.android.PythonActivity

[buildozer]
log_level = 2
warn_on_root = 0
