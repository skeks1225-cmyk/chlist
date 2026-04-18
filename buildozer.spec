[app]
title = Step3Test
package.name = checksheetstep3
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,ttf
version = 0.8
requirements = python3,kivy,pyjnius,openpyxl,et_xmlfile,jdcal,pysmb,pyasn1,six,tqdm,pycryptodome,android
android.add_assets = pdfjs
orientation = portrait
fullscreen = 0
android.permissions = INTERNET
android.api = 33
android.minapi = 21
android.ndk_api = 21
android.accept_sdk_license = True

[buildozer]
log_level = 2
warn_on_root = 0
