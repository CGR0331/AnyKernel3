#!/usr/bin/env python3
# 补齐 SUSFS 日志条件块 #else 分支缺失的 SUSFS_LOGI_RL / SUSFS_LOGE_RL
import re
import sys

path = sys.argv[1]
src = open(path, encoding='utf-8', errors='surrogateescape').read()
if 'root logs hidden' not in src:
    print('susfs.c 未做条件替换，跳过宏补齐')
    raise SystemExit(0)
m = re.search(r'#if 0 /\* root logs hidden \*/(.*?)#endif', src, re.S)
if not m:
    print('未定位到 SUSFS 日志宏条件块，跳过')
    raise SystemExit(0)
block = m.group(1)
else_part = block.split('#else', 1)[1] if '#else' in block else block
missing = [n for n in ('SUSFS_LOGI_RL', 'SUSFS_LOGE_RL')
           if not re.search(r'#define\s+%s\b' % n, else_part)]
if not missing:
    print('SUSFS 限流宏已齐备')
    raise SystemExit(0)
inject = ''.join('#define %s(fmt, ...)\n' % n for n in missing)
src = src[:m.end(1)] + inject + src[m.end(1):]
open(path, 'w', encoding='utf-8', errors='surrogateescape').write(src)
print('已补入缺失宏: ' + ', '.join(missing))
