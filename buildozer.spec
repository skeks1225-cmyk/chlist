[app]
title = CheckSheetFinal
package.name = checksheetv40
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,ttf,pdf,xlsx,json,html,js,css,map
source.exclude_dirs = backup, bin, .buildozer
android.add_assets = pdfjs
version = 4.0

# [수정] 강제 종료 방지를 위해 android 제거
requirements = python3,kivy,pyjnius,openpyxl,pysmb,pyasn1,six,tqdm,et_xmlfile,jdcal,pycryptodome

orientation = portrait
fullscreen = 0

# [수정] 충돌 가능성 있는 권한 축소
android.permissions = READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, INTERNET

android.enable_androidx = True
android.enable_jetifier = True

android.api = 33
android.minapi = 21
android.ndk_api = 21
android.accept_sdk_license = True

[buildozer]
log_level = 2
warn_on_root = 0
