unshield 1.6.2 (https://github.com/twogood/unshield, tag 1.6.2, MIT: LICENSE), the library and its command-line tool only,
for the Mods window's Restore from Disc (tools/gta_restore.py: the San Andreas DVD installer's .cab archives). lib/unshield_config.h
is written by hand for macOS (CMake's checks, its own MD5). Built into the downloaded app by recomp/setup/suite.json
(make_suite.sh "helpers"): clang -O2 -DHAVE_CONFIG_H -I . -I lib -I lib/md5 lib/*.c lib/md5/md5c.c src/unshield.c -lz -liconv
