#!/usr/bin/env python3
"""Build dist/index.html with the JSX precompiled.

The source index.html ships babel-standalone (~3MB of compiler JS) and compiles the
whole app in the browser on every visit — seconds of parse time on a shop tablet.
This script compiles the <script type="text/babel"> block with esbuild, inlines the
result as plain JS, and drops the babel-standalone <script> tag. Authoring workflow is
unchanged: keep editing index.html; deploy dist/index.html.

Usage: python3 scripts/build.py        (requires node/npx on PATH)
"""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
src = (root / "index.html").read_text()

m = re.search(r'<script type="text/babel">(.*?)</script>', src, re.S)
if not m:
    sys.exit("No <script type=\"text/babel\"> block found in index.html")

result = subprocess.run(
    ["npx", "--yes", "esbuild", "--loader=jsx", "--minify", "--target=es2019"],
    input=m.group(1), capture_output=True, text=True,
)
if result.returncode != 0:
    sys.stderr.write(result.stderr)
    sys.exit("esbuild failed — fix the JSX before deploying")

out = src.replace(m.group(0), "<script>" + result.stdout + "</script>")
out = re.sub(r'<script src="https://cdnjs\.cloudflare\.com/ajax/libs/babel-standalone[^"]*"></script>\n?', "", out)

dist = root / "dist"
dist.mkdir(exist_ok=True)
(dist / "index.html").write_text(out)
print(f"Wrote dist/index.html ({len(out) // 1024} KB, babel-standalone removed)")
