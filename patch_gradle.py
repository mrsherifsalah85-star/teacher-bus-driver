import os, re, sys

d = sys.argv[1]
kts = os.path.join(d, "build.gradle.kts")
groovy = os.path.join(d, "build.gradle")

if os.path.exists(kts):
    s = open(kts, encoding="utf-8").read()
    signing = '''    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("KEYSTORE_PATH"))
            storePassword = System.getenv("KEYSTORE_PASSWORD")
            keyAlias = System.getenv("KEY_ALIAS")
            keyPassword = System.getenv("KEY_PASSWORD")
        }
    }

'''
    assert "    buildTypes {" in s, "buildTypes not found"
    s = s.replace("    buildTypes {", signing + "    buildTypes {", 1)
    s, n = re.subn(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
                   'signingConfig = signingConfigs.getByName("release")', s)
    assert n >= 1, "debug signing line not found"
    assert "compileOptions {" in s, "compileOptions not found"
    s = s.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
    s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    open(kts, "w", encoding="utf-8").write(s)
    print("patched kts")
elif os.path.exists(groovy):
    s = open(groovy, encoding="utf-8").read()
    signing = '''    signingConfigs {
        release {
            storeFile file(System.getenv("KEYSTORE_PATH"))
            storePassword System.getenv("KEYSTORE_PASSWORD")
            keyAlias System.getenv("KEY_ALIAS")
            keyPassword System.getenv("KEY_PASSWORD")
        }
    }

'''
    assert "    buildTypes {" in s, "buildTypes not found"
    s = s.replace("    buildTypes {", signing + "    buildTypes {", 1)
    s, n = re.subn(r'signingConfig\s+signingConfigs\.debug', 'signingConfig signingConfigs.release', s)
    assert n >= 1, "debug signing line not found"
    assert "compileOptions {" in s, "compileOptions not found"
    s = s.replace("compileOptions {", "compileOptions {\n        coreLibraryDesugaringEnabled true", 1)
    s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    open(groovy, "w", encoding="utf-8").write(s)
    print("patched groovy")
else:
    raise SystemExit("no gradle file found")
