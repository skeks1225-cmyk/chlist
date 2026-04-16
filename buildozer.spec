[app]
title = CheckSheet
package.name = checksheetapp
package.domain = org.example
source.dir = .
source.include_exts = py,png,jpg,kv,atlas,ttf,xlsx,json
version = 1.0

# [App requirements]
requirements = python3,kivy,openpyxl,et_xmlfile,jdcal,pyjnius,android,pysmb,pyasn1,six,tqdm

orientation = portrait
fullscreen = 0

# [Permissions]
android.permissions = READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, MANAGE_EXTERNAL_STORAGE, INTERNET, ACCESS_NETWORK_STATE

# [Android Gradle dependencies]
android.gradle_dependencies = com.github.barteksc:android-pdf-viewer:3.2.0-beta.1
android.gradle_repositories = https://jitpack.io

# [AndroidX support]
android.enable_androidx = True

# [Build settings]
android.accept_sdk_license = True
android.api = 33
android.minapi = 21

[buildozer]
log_level = 2
warn_on_root = 0
