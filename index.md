# Crystal Compiler Explained

This is an explanation of the Crystal compiler written by kojix2 with the help of Claude, ChatGPT, and others. I wrote it to understand how the Crystal compiler works.

## Documents

- Japanese: [JA.md](JA.md)
- English: [EN.md](EN.md)
- Compiler API docs: [compiler/index.html](compiler/index.html)

## Maintenance Rule (JA/EN)

- `JA.md` and `EN.md` stay as separate files.
- Keep structure synchronized at least at the numbered section level (`## 1.` ... `## 12.`).
- Run `bash scripts/check_doc_sync.sh JA.md EN.md` before pushing.
- CI (`.github/workflows/doc-sync.yml`) must pass for structural changes.