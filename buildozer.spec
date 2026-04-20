[app]
title = CheckSheetFinal
package.name = checksheetv160
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,ttf,pdf,xlsx,json
version = 16.0
requirements = python3,kivy,android,pyjnius,openpyxl,pysmb,pyasn1,six,tqdm,et_xmlfile,jdcal,pycryptodome
orientation = portrait
fullscreen = 0
android.permissions = READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, MANAGE_EXTERNAL_STORAGE, INTERNET
android.api = 33
android.minapi = 21
android.ndk_api = 21
android.accept_sdk_license = True
[buildozer]
log_level = 2
warn_on_root = 0
