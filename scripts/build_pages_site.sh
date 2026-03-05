#!/usr/bin/env bash
set -euo pipefail

# Build Crystal compiler docs from latest crystal master.
rm -rf crystal-master crystal-master.tar.gz
wget -O crystal-master.tar.gz https://github.com/crystal-lang/crystal/archive/refs/heads/master.tar.gz
tar xvf crystal-master.tar.gz

(
  cd crystal-master
  make docs DOCS_OPTIONS=src/compiler/crystal.cr
)

# Assemble static Pages output without Jekyll.
rm -rf site
mkdir -p site/compiler
cp README.md JA.md EN.md site/
cp -R crystal-master/docs/. site/compiler/
touch site/.nojekyll

cat > site/index.html <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Crystal Compiler Explained</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; line-height: 1.6; margin: 2rem auto; max-width: 860px; padding: 0 1rem; }
    h1 { margin-bottom: 0.5rem; }
    ul { padding-left: 1.2rem; }
  </style>
</head>
<body>
  <h1>Crystal Compiler Explained</h1>
  <p>
    This is an explanation of the Crystal compiler written by kojix2 with the help of Claude,
    ChatGPT, and others. I wrote it to understand how the Crystal compiler works.
  </p>

  <h2>Documents</h2>
  <ul>
    <li><a href="JA.md">Japanese (JA.md)</a></li>
    <li><a href="EN.md">English (EN.md)</a></li>
    <li><a href="compiler/index.html">Compiler API docs</a></li>
  </ul>
</body>
</html>
EOF

echo "[docs] Built static Pages artifact in ./site"
