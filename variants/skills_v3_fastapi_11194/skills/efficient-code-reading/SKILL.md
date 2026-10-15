---
name: efficient-code-reading
description: How to inspect large source files without wasting tool calls — map structure with grep/sed first, read each range at most once, stop reading once the change site is found. Load this before exploring a file bigger than ~150 lines.
---

# Efficient Code Reading

`read_file` returns at most 150 lines / 10k chars per call, and every tool call
burns session budget. Repeated overlapping reads of the same file is the most
common way sessions die with zero edits. Follow this discipline exactly.

## 1. Map first, read second

Before opening a file, get its skeleton in ONE call:

```bash
grep -n "class \|def " path/to/file.py
```

Then read only the range that contains the symbol you need:

```bash
read_file(path/to/file.py, start_line=<a>, end_line=<b>)
```

For spans wider than 150 lines, prefer `run_command` with sed instead of
several paged `read_file` calls:

```bash
sed -n '100,220p' path/to/file.py
```

## 2. Read-once discipline

- Keep a mental list of the line ranges you have already seen.
- NEVER request a range that overlaps a range you already have. If a read was
  truncated, continue from the line AFTER the last one shown — do not restart.
- NEVER re-read a file "to confirm" something. If you saw it once, trust it.
- Budget: at most 2 `read_file` calls per file for orientation. If after 3
  reads of the same file you still cannot place the edit, use `grep -n` /
  `sed -n` to jump directly to the symbol instead of paging.

## 3. Stop reading, start editing

As soon as you can answer "which lines must change and to what", your NEXT
action is `edit_file` — not another read. Do not keep reading "the rest of the
file" or "the full constructor" unless the edit itself requires it.

## 4. Scope lock

Only the symbols named or implied by the problem statement are in scope. If
you notice OTHER suspicious code while reading (missing parameters, odd
defaults, unrelated TODOs), ignore it — investigating it is a distraction that
burns budget and produces the wrong patch.

## 5. If you feel lost

Do NOT re-read. Instead run ONE targeted command that answers the specific
question:

```bash
grep -n "convert_underscores" fastapi/params.py     # does symbol exist & where
sed -n '560,640p' fastapi/params.py                 # exact class constructor
python3 -c "import fastapi; ..."                    # check runtime behavior
```

Then edit.
