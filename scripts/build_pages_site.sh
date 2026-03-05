#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CRYSTAL_REF="${CRYSTAL_REF:-master}"
CRYSTAL_ARCHIVE_URL="https://github.com/crystal-lang/crystal/archive/refs/heads/${CRYSTAL_REF}.tar.gz"

CRYSTAL_ARCHIVE="${REPO_ROOT}/crystal-master.tar.gz"
CRYSTAL_SRC_DIR="${REPO_ROOT}/crystal-master"
SITE_DIR="${REPO_ROOT}/site"
COMPILER_DOCS_DIR="${CRYSTAL_SRC_DIR}/docs"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"

DOC_FILES=("README.md" "JA.md" "EN.md")

log() {
  echo "[docs] $*"
}

require_tools() {
  local tools=(wget tar make sed cp)
  for tool in "${tools[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || {
      echo "[docs] ERROR: required command not found: $tool" >&2
      exit 1
    }
  done
}

require_files() {
  local file
  for file in "${DOC_FILES[@]}" "${TEMPLATES_DIR}/index.html" "${TEMPLATES_DIR}/doc_page.html"; do
    [[ -f "${REPO_ROOT}/${file}" || -f "${file}" ]] || {
      echo "[docs] ERROR: required file not found: ${file}" >&2
      exit 1
    }
  done
}

download_crystal_source() {
  log "Downloading Crystal source (${CRYSTAL_REF})"
  rm -rf "${CRYSTAL_SRC_DIR}" "${CRYSTAL_ARCHIVE}"
  wget -O "${CRYSTAL_ARCHIVE}" "${CRYSTAL_ARCHIVE_URL}"
  tar xvf "${CRYSTAL_ARCHIVE}" -C "${REPO_ROOT}"
}

build_compiler_docs() {
  log "Generating compiler docs"
  (
    cd "${CRYSTAL_SRC_DIR}"
    make docs DOCS_OPTIONS=src/compiler/crystal.cr
  )
}

render_markdown_page() {
  local md_file="$1"
  local title="$2"
  local out_file="$3"
  sed \
    -e "s|__TITLE__|${title}|g" \
    -e "s|__MD_FILE__|${md_file}|g" \
    "${TEMPLATES_DIR}/doc_page.html" > "${out_file}"
}

assemble_site() {
  log "Assembling static Pages output"
  rm -rf "${SITE_DIR}"
  mkdir -p "${SITE_DIR}/compiler"

  cp "${REPO_ROOT}/README.md" "${REPO_ROOT}/JA.md" "${REPO_ROOT}/EN.md" "${SITE_DIR}/"
  cp -R "${COMPILER_DOCS_DIR}/." "${SITE_DIR}/compiler/"
  cp "${TEMPLATES_DIR}/index.html" "${SITE_DIR}/index.html"
  touch "${SITE_DIR}/.nojekyll"

  render_markdown_page "JA.md" "Crystal Compiler Explained (JA)" "${SITE_DIR}/ja.html"
  render_markdown_page "EN.md" "Crystal Compiler Explained (EN)" "${SITE_DIR}/en.html"
}

main() {
  cd "${REPO_ROOT}"
  require_tools
  require_files
  download_crystal_source
  build_compiler_docs
  assemble_site
  log "Built static Pages artifact in ${SITE_DIR}"
}

main "$@"
