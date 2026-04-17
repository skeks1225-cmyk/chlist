[app]
title = CheckSheetFinal
package.name = checksheetv60
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,ttf,pdf,xlsx,json,html,js,css,map,ftl
source.exclude_dirs = backup, bin, .buildozer
version = 6.0

# [체크] android 모듈 ?��?
requirements = python3,kivy,android,pyjnius,openpyxl,pysmb,pyasn1,six,tqdm,et_xmlfile,jdcal,pycryptodome

orientation = portrait
fullscreen = 0

# [?�정] 권한 축소
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
