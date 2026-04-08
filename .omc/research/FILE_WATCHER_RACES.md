# File Watcher Races: Concurrent JSON Edit Synchronization

**Status:** ✅ COMPLETE  
**Last Updated:** April 8, 2026

## Objective
Analyze and mitigate race conditions during concurrent JSON edits (e.g., when an external AI process and the user both modify the graph state).

## 1. Platform-Specific Watcher Gaps
- **`inotify` (Linux):** Watches the inode. If a file is replaced (common in "atomic save" patterns), the watch is lost unless watching the **parent directory**.
- **`kqueue` (macOS):** Requires an open file descriptor. If a file is replaced, the descriptor points to a dead inode.

## 2. The "Atomic Save" Pattern in Zig
To avoid the "Half-Written File" race condition (where the watcher reads a partial JSON), the writing process must follow this protocol:
1. **Write to Temporary File:** `config.json.tmp`.
2. **Flush & Sync:** Call `file.sync()` to ensure data is physically committed.
3. **Atomic Rename:** `std.fs.rename("config.json.tmp", "config.json")`.
   - On POSIX, this operation is atomic. The file path will always point to either the valid old file or the valid new one.

## 3. Synchronization Strategy: "Last Write Wins"
In a spatial graph environment, concurrent edits are frequent.

### Proposed Protocol:
- **Watcher Logic:** Monitor the **parent directory** for `CLOSE_WRITE` or `MOVED_TO` events.
- **Parsing:** Debounce events (e.g., wait 50ms) before re-parsing to avoid rapid-fire updates.
- **In-Memory Buffer:** Maintain the current state in memory. If the file on disk is newer, merge changes or prompt the user.

## 4. Mitigation for "Watch Lost"
Since Notcurses and AI streaming are high-performance, a file watcher crash could halt the system.
- **Self-Healing Watcher:** If a watch event is missed or an error occurs, the watcher should perform a full `re-stat` and re-establish watches on the parent directory.

## 5. Summary Recommendation
Implement an **Atomic Write-and-Rename** pattern for all Zig-initiated file saves. Configure the file watcher to monitor the **parent directory** rather than specific files to ensure compatibility with modern editor "atomic save" behaviors. This prevents data corruption and ensures a robust synchronization loop.
