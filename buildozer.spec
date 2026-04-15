[app]

# (str) Title of your application
title = CheckSheet

# (str) Package name
package.name = checksheetapp

# (str) Package domain (needed for android packaging)
package.domain = org.example

# (str) Source code where the main.py live
source.dir = .

# (list) Source files to include (let empty to include all the files)
source.include_exts = py,png,jpg,kv,atlas,ttf,xlsx,json

# (str) Application versioning (method 1)
version = 1.2

# (list) Application requirements
# comma separated e.g. requirements = sqlite3,kivy
requirements = python3,kivy,openpyxl,et_xmlfile,jdcal,pyjnius,android

# (str) Supported orientation (one of landscape, sensorLandscape, portrait or all)
orientation = portrait

# (bool) Indicate if the application should be fullscreen or not
fullscreen = 0

# (list) Permissions
android.permissions = READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE, MANAGE_EXTERNAL_STORAGE

# (int) Android API to use
android.api = 33

# (int) Minimum API your APK will support.
android.minapi = 21

# (str) Android NDK version to use
#android.ndk = 25b

# (bool) Use --private data storage (True) or --dir public storage (False)
#android.private_storage = True

[buildozer]

# (int) Log level (0 = error only, 1 = info, 2 = debug (with command output))
log_level = 2

# (int) Display warning if buildozer is run as root (0 = off, 1 = on)
warn_on_root = 1
