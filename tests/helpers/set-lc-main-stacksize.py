# platform: host-agnostic -- writes PROGRAM's LC_MAIN stacksize in place, as Apple ld's -stack_size would
# spec: tests/pthread-main-stacksize-test.sh -- lld does not implement -stack_size
import struct, sys
path, size = sys.argv[1], int(sys.argv[2])
with open(path, 'r+b') as f:
    data = bytearray(f.read())
    magic, cpu, sub, ftype, ncmds, sizeofcmds, flags, res = struct.unpack_from('<IiiIIIII', data, 0)
    if magic != 0xfeedfacf:
        sys.exit('set-lc-main-stacksize: %s is not a thin 64-bit Mach-O' % path)
    off = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', data, off)
        if cmd == 0x80000028:
            struct.pack_into('<Q', data, off + 16, size)
            f.seek(0)
            f.write(data)
            break
        off += cmdsize
    else:
        sys.exit('set-lc-main-stacksize: %s has no LC_MAIN' % path)
