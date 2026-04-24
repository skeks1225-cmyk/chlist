# Bouncy Castle 라이브러리 보호
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# jCIFS-ng 및 SMBJ 보호
-keep class jcifs.** { *; }
-keep class com.hierynomus.** { *; }
-dontwarn jcifs.**
-dontwarn com.hierynomus.**

# 자바 표준 라이브러리 경고 무시
-dontwarn javax.annotation.**
-dontwarn org.jspecify.**
