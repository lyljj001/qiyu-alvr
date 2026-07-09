#!/usr/bin/env python3
"""Extract JNI class references and Java_com_... symbol names from an ELF .so
to determine what Java classes/methods the native library expects to find at
load time (JNI_OnLoad / RegisterNatives)."""
import sys
import re
import struct

def extract_strings(data, min_len=4):
    """Yield ASCII strings of at least min_len chars from binary data."""
    current = bytearray()
    for b in data:
        if 0x20 <= b < 0x7f:
            current.append(b)
        else:
            if len(current) >= min_len:
                yield current.decode('ascii', 'replace')
            current = bytearray()
    if len(current) >= min_len:
        yield current.decode('ascii', 'replace')

def extract_dyn_symbols(path):
    """Parse ELF64 .dynsym table and return symbol names containing 'Java_'."""
    with open(path, 'rb') as f:
        data = f.read()
    if data[:4] != b'\x7fELF' or data[4] != 2:
        return []
    # Parse ELF64 header
    (e_type, e_machine, e_version, e_entry, e_phoff, e_shoff,
     e_flags, e_ehsize, e_phentsize, e_phnum,
     e_shentsize, e_shnum, e_shstrndx) = struct.unpack_from('<HHIQQQIHHHHHH', data, 16)

    # Parse section headers to find .dynsym and .dynstr
    symbols = []
    if e_shoff == 0 or e_shnum == 0:
        # No section headers -- fall back to string search
        return symbols_from_strings(data)

    sections = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        (sh_name, sh_type, sh_flags, sh_addr, sh_offset, sh_size,
         sh_link, sh_info, sh_addralign, sh_entsize) = struct.unpack_from('<IIQQQQIIQQ', data, off)
        sections.append((sh_name, sh_type, sh_offset, sh_size, sh_link, sh_entsize))

    # Find SHT_DYNSYM (type 11)
    for i, (sh_name, sh_type, sh_offset, sh_size, sh_link, sh_entsize) in enumerate(sections):
        if sh_type == 11:  # SHT_DYNSYM
            # sh_link points to the string table section
            strtab_idx = sh_link
            if strtab_idx >= len(sections):
                continue
            strtab_off = sections[strtab_idx][2]
            strtab_size = sections[strtab_idx][3]
            strtab = data[strtab_off:strtab_off + strtab_size]
            # Parse symbol entries (ELF64 Sym = 24 bytes)
            num_syms = sh_size // sh_entsize if sh_entsize > 0 else 0
            for j in range(num_syms):
                off = sh_offset + j * sh_entsize
                (st_name, st_info, st_other, st_shndx, st_value, st_size) = struct.unpack_from('<IBBHQQ', data, off)
                if st_name < len(strtab):
                    end = strtab.index(b'\x00', st_name) if b'\x00' in strtab[st_name:] else len(strtab)
                    name = strtab[st_name:end].decode('ascii', 'replace')
                    if name:
                        symbols.append(name)
    return symbols

def symbols_from_strings(data):
    """Fallback: search raw strings for Java_ patterns."""
    results = []
    for s in extract_strings(data, 8):
        if 'Java_' in s or 'com/qiyi' in s or 'qiyisdkcore' in s:
            results.append(s)
    return results

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(os.path.dirname(__file__), '..', 'app', 'src', 'main', 'jniLibs', 'arm64-v8a', 'libqiyivrsdkcore.so')
    print("Analyzing: %s" % path)
    print("=" * 70)

    with open(path, 'rb') as f:
        data = f.read()

    # 1) Extract all strings, filter for JNI-relevant ones
    print("\n--- JNI class references (com/...) ---")
    class_refs = set()
    for s in extract_strings(data, 6):
        if s.startswith('com/') and ('qiyi' in s.lower() or 'sdk' in s.lower()):
            class_refs.add(s)
    for c in sorted(class_refs):
        print("  %s" % c)

    print("\n--- Java_ symbol names (from .dynsym) ---")
    syms = extract_dyn_symbols(path)
    java_syms = [s for s in syms if s.startswith('Java_')]
    if not java_syms:
        print("  (no Java_ symbols in .dynsym; checking strings)")
        for s in extract_strings(data, 10):
            if 'Java_com_qiyi' in s:
                java_syms.append(s)
    # Group by class
    classes = {}
    for s in java_syms:
        # Java_com_qiyi_qiyisdkcore_androidplugin_methodName
        parts = s.split('_')
        # Reconstruct: after Java_, each _ separates package/class/method components
        # This is ambiguous, but we can group by prefix
        if 'qiyisdkcore' in s:
            # Find the class portion
            m = re.match(r'Java_(com_qiyi_qiyisdkcore_\w+?)_(\w+)$', s)
            if m:
                cls = m.group(1).replace('_', '.')
                method = m.group(2)
                classes.setdefault(cls, []).append(method)
            else:
                classes.setdefault(s, []).append('')
    for cls in sorted(classes):
        print("  Class: %s" % cls)
        for method in sorted(classes[cls]):
            print("    native %s(...)" % method)

    # 2) Search for RegisterNatives method name strings
    print("\n--- Possible RegisterNatives method names ---")
    method_names = set()
    for s in extract_strings(data, 3):
        if s.startswith('native') and len(s) < 60:
            method_names.add(s)
        if s in ('nativeInit', 'nativeDestroy', 'nativeResume', 'nativePause',
                 'nativeRender', 'nativeSetup', 'nativeStart', 'nativeStop',
                 'nativeQuery', 'nativeSet', 'nativeGet'):
            method_names.add(s)
    for m in sorted(method_names):
        print("  %s" % m)

    # 3) Search for any mention of "androidplugin"
    print("\n--- 'androidplugin' mentions ---")
    for s in extract_strings(data, 6):
        if 'androidplugin' in s.lower():
            print("  %s" % s)

if __name__ == '__main__':
    import os
    main()
