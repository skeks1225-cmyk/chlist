[app]
title = CheckSheetFinal
package.name = checksheetv163
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,ttf,json
version = 16.3

# 🔥 핵심: 버전 고정 (안정성 확보)
requirements = python3==3.10.11,kivy==2.2.0,pyjnius==1.5.0,android,openpyxl,pysmb,pyasn1,six,tqdm,et_xmlfile,jdcal,pycryptodome

orientation = portrait
fullscreen = 0

android.permissions = INTERNET,READ_EXTERNAL_STORAGE,WRITE_EXTERNAL_STORAGE,MANAGE_EXTERNAL_STORAGE

# 🔥 핵심 안정 조합 (절대 변경 금지)
android.api = 31
android.minapi = 21
android.ndk = 23b
android.ndk_api = 21

android.accept_sdk_license = True

# ❗ PDF viewer (안정)
android.gradle_dependencies = com.github.barteksc:android-pdf-viewer:2.8.2

# ❗ 저장소 (쉼표 없이)
android.gradle_repositories = https://jitpack.io

android.enable_androidx = True
android.enable_jetifier = True

android.manifest.activities = org.example.checksheetv163.PdfActivity
android.add_src = src

[buildozer]
log_level = 2
warn_on_root = 1
