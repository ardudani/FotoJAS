"""Genera las carpetas android/ y windows/ con `flutter create` y aplica los
ajustes que necesita FotoJAS (permisos, nombre de la app, HTTP local...).
Se ejecuta automáticamente en GitHub Actions."""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
platform = sys.argv[1] if len(sys.argv) > 1 else "android,windows"

subprocess.run(
    ["flutter", "create", "--platforms", platform, "--org", "es.fotojas",
     "--project-name", "fotojas", "."],
    cwd=root, check=True, shell=sys.platform == "win32",
)

manifest = root / "android/app/src/main/AndroidManifest.xml"
if manifest.exists():
    m = manifest.read_text(encoding="utf-8")
    perms = [
        "android.permission.INTERNET",
        "android.permission.CAMERA",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.ACCESS_WIFI_STATE",
    ]
    for p in perms:
        if p not in m:
            m = m.replace("<application", f'<uses-permission android:name="{p}"/>\n    <application', 1)
    m = re.sub(r'android:label="[^"]*"', 'android:label="FotoJAS"', m, count=1)
    if "usesCleartextTraffic" not in m:
        # Necesario para hablar IPP (http://IP:631) con la impresora en la red local
        m = m.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
    manifest.write_text(m, encoding="utf-8")
    print("AndroidManifest.xml ajustado")

# R8 (minificación) elimina clases de plugins que se llaman por JNI
# (p. ej. shared_preferences / path_provider) y la app falla en release.
rules = root / "android/app/proguard-rules.pro"
if (root / "android").exists():
    rules.write_text(
        "-keep class io.flutter.plugins.** { *; }\n"
        "-keep class dev.fluttercommunity.** { *; }\n"
        "-keep class com.github.dart_lang.jni.** { *; }\n"
        "-keep class net.nfet.flutter.printing.** { *; }\n"
        "-keep class kotlin.coroutines.** { *; }\n"
        "-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod\n"
        "-dontwarn **\n",
        encoding="utf-8",
    )
for name in ("build.gradle.kts", "build.gradle"):
    gradle = root / "android/app" / name
    if not gradle.exists():
        continue
    g = gradle.read_text(encoding="utf-8")
    if "isMinifyEnabled" not in g and "minifyEnabled" not in g:
        kts = name.endswith(".kts")
        extra = ("\n            isMinifyEnabled = false\n            isShrinkResources = false"
                 if kts else "\n            minifyEnabled false\n            shrinkResources false")
        g, n = re.subn(r'(release\s*\{)', r'\1' + extra, g, count=1)
        print(f"{name}: minificación desactivada ({n})")
        gradle.write_text(g, encoding="utf-8")
