#!/usr/bin/env python3
"""Prints the root helper script that SecondaryUserPrefixManager.buildRootScript() would produce.

Usage: extract-script.py <SecondaryUserPrefixManager.java> <userId> <appUid> <appPid>
Reads the Java source of the patched tree, so the test always covers the shipped script.
"""
import re
import sys

src_path, user_id, app_uid, app_pid = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
src = open(src_path, encoding="utf-8").read()
start = src.index("static String buildRootScript(")
ret = src.index('return "PATH=', start)
body = src[ret + len("return "):src.index(";\n", src.index("exit 0", ret))]
values = {"userId": user_id, "appUid": app_uid, "appPid": app_pid}
out = []
for lit, ident in re.findall(r'"((?:[^"\\]|\\.)*)"|\b(userId|appUid|appPid)\b', body):
    if ident:
        out.append(values[ident])
    else:
        out.append(bytes(lit, "utf-8").decode("unicode_escape"))
sys.stdout.write("".join(out))
