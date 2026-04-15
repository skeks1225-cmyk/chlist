[app]
title = CheckSheet
package.name = checksheetapp
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,atlas,ttf,xlsx,json
version = 1.3

# SMB 연동을 위한 pysmb, pyasn1 라이브러리 추가
requirements = python3,kivy,openpyxl,et_xmlfile,jdcal,pyjnius,android,pysmb,pyasn1

orientation = portrait
fullscreen = 0

# 네트워크 사용 및 저장소 권한 설정
android.permissions = INTERNET, READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, MANAGE_EXTERNAL_STORAGE

# Android API 레벨 설정
android.api = 33
android.minapi = 21

[buildozer]
log_level = 2
warn_on_root = 1
