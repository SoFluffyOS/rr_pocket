"""Set android:debuggable to false in a binary AndroidManifest.xml, in place.

Usage: undebug_manifest.py <AndroidManifest.xml from an APK>
"""
import struct
import sys

DEBUGGABLE = 0x0101000F
path = sys.argv[1]
data = bytearray(open(path, "rb").read())

res_ids = []
pos = 8
while pos < len(data):
    ctype, header, size = struct.unpack_from("<HHI", data, pos)
    if ctype == 0x0180:  # resource map: string index -> resource id
        res_ids = list(struct.unpack_from(f"<{(size - 8) // 4}I", data, pos + 8))
    elif ctype == 0x0102:  # start element
        attr_start, attr_size, attr_count = struct.unpack_from("<HHH", data, pos + 24)
        for i in range(attr_count):
            a = pos + 16 + attr_start + i * attr_size
            name = struct.unpack_from("<I", data, a + 4)[0]
            if name < len(res_ids) and res_ids[name] == DEBUGGABLE:
                struct.pack_into("<I", data, a + 16, 0)
                open(path, "wb").write(data)
                print("debuggable -> false")
                sys.exit(0)
    pos += size
sys.exit("android:debuggable not found")
