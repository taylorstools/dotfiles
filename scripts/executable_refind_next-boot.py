#!/usr/bin/env python3

import array
import fcntl
import os
import sys

EFIVAR_NAME = 'PreviousBoot'
EFIVAR_GUID = '36d08fa7-cf0b-42f5-8f14-68df73ed3740'
EFIVAR_PREFIX = '/sys/firmware/efi/efivars'

PREFIX = b'\x07\x00\x00\x00'
SUFFIX = b'\x20\x00\x00\x00'

# Inode-flag ioctls (asm-generic _IOC layout, i.e. x86-64/aarch64).
FS_IOC_GETFLAGS = 0x80086601
FS_IOC_SETFLAGS = 0x40086602
FS_IMMUTABLE_FL = 0x00000010

if len(sys.argv) != 2:
    print('error: must pass exactly one argument', file=sys.stderr)
    sys.exit(1)

text = sys.argv[1]
filename = '{}/{}-{}'.format(EFIVAR_PREFIX, EFIVAR_NAME, EFIVAR_GUID)

# Clear the immutable bit (equivalent to `chattr -i`) without shelling out.
fd = os.open(filename, os.O_RDONLY)
try:
    buf = array.array('i', [0])
    fcntl.ioctl(fd, FS_IOC_GETFLAGS, buf, True)
    buf[0] &= ~FS_IMMUTABLE_FL
    fcntl.ioctl(fd, FS_IOC_SETFLAGS, buf, True)
finally:
    os.close(fd)

with open(filename, 'wb') as f:
    content = PREFIX + bytes(text, 'utf-16-le') + SUFFIX
    f.write(content)