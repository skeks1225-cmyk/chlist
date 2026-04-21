[app]
title = CheckSheetFinal
package.name = checksheetv163
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,ttf,pdf,xlsx,json
version = 16.3
requirements = python3,kivy,android,pyjnius,openpyxl,pysmb,pyasn1,six,tqdm,et_xmlfile,jdcal,pycryptodome
orientation = portrait
fullscreen = 0
android.permissions = READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, MANAGE_EXTERNAL_STORAGE, INTERNET
android.api = 31
android.minapi = 21
android.ndk_api = 21

android.accept_sdk_license = True

# ✅ 핵심 (정답 조합: 3.2.0 버전 + jitpack 단독)
android.gradle_dependencies = com.github.barteksc:android-pdf-viewer:3.2.0-beta.1
android.gradle_repositories = https://jitpack.io

android.enable_androidx = True
android.enable_jetifier = True

android.manifest.activities = org.example.checksheetv163.PdfActivity
android.add_src = src
[buildozer]
log_level = 2
warn_on_root = 0
