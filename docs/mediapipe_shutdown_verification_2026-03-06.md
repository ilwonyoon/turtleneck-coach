# MediaPipe Shutdown Verification
Date: 2026-03-06
Owner: Track C

## Goal
Verify that stopping monitoring or quitting the app tears down the Python MediaPipe helper.

## Manual Verification
1. Build and launch the app.
2. Start monitoring and wait for MediaPipe to connect.
3. Capture the current helper PID set:
   - `pgrep -fl "pose_server.py|\\.pt_turtle/server"`
4. Start monitoring if needed and capture the new PID delta.
5. Stop monitoring from the app.
6. Confirm the newly started helper exits within a few seconds:
   - `pgrep -fl "pose_server.py|\\.pt_turtle/server"`
   - expected: the PID started by this run disappears
7. Start monitoring again and confirm the helper starts again.
8. Quit the app.
9. Confirm the helper started by this run is gone again:
   - `pgrep -fl "pose_server.py|\\.pt_turtle/server"`
   - expected: the PID started by this run disappears

## Notes
- `stopMonitoring()` now requests async MediaPipe shutdown to avoid blocking the UI.
- App termination uses a synchronous shutdown path so quit does not leave the helper running.
