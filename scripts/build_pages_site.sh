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

render_markdown_page() {
  local md_file="$1"
  local title="$2"
  local out_file="$3"

  cat > "$out_file" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${title}</title>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.8.1/github-markdown-light.min.css">
  <style>
    body { margin: 0; background: #f6f8fa; }
    .container { max-width: 980px; margin: 0 auto; padding: 2rem 1rem; }
    .markdown-body { background: #fff; border: 1px solid #d0d7de; border-radius: 8px; padding: 2rem; }
    .topnav { margin-bottom: 1rem; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  </style>
</head>
<body>
  <div class="container">
    <div class="topnav"><a href="index.html">Back to top</a></div>
    <article id="content" class="markdown-body">Loading...</article>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
  <script>
    fetch("${md_file}")
      .then(function (res) { return res.text(); })
      .then(function (md) {
        document.getElementById("content").innerHTML = marked.parse(md);
      })
      .catch(function (err) {
        document.getElementById("content").textContent = "Failed to load markdown: " + err;
      });
  </script>
</body>
</html>
EOF
}

render_markdown_page "JA.md" "Crystal Compiler Explained (JA)" "site/ja.html"
render_markdown_page "EN.md" "Crystal Compiler Explained (EN)" "site/en.html"

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
    <li><a href="ja.html">Japanese</a></li>
    <li><a href="en.html">English</a></li>
    <li><a href="compiler/index.html">Compiler API docs</a></li>
  </ul>
</body>
</html>
EOF

echo "[docs] Built static Pages artifact in ./site"
