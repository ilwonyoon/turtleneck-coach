# Debug Data Archive

Use `scripts/archive_debug_session.sh` to copy current debug artifacts from `/tmp`
into a repo-controlled archive directory.

Archive layout:

```text
debug_data/
  sessions/
    YYYYMMDD_HHMMSS/
      metadata.txt
      turtle_cvadebug.log
      turtle_debug_snapshots/
      turtle_manual_snapshots/
```

Behavior:

- Creates a timestamped folder under `debug_data/sessions/`
- Copies `/tmp/turtle_cvadebug.log` if present
- Copies `/tmp/turtle_debug_snapshots` if present
- Copies `/tmp/turtle_manual_snapshots` if present
- Writes `metadata.txt` with timestamp and source-path status

Run:

```bash
./scripts/archive_debug_session.sh
```
