import re, sys

path = sys.argv[1]
s = open(path, encoding="utf-8").read()

perms = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_LOCATION",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.WAKE_LOCK",
]
add = "".join(
    '    <uses-permission android:name="%s"/>\n' % p
    for p in perms if p not in s
)
s = s.replace("<application", add + "    <application", 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="سائق الباص"', s, count=1)
open(path, "w", encoding="utf-8").write(s)
print("manifest patched")
