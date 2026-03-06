# Turtleneck Coach Performance Audit

Date: 2026-03-06

## Scope

This audit covers runtime performance of the live monitoring flow, with emphasis on:

- monitor start latency
- camera preview smoothness
- analysis-loop blocking
- debug logging and file I/O
- timer-driven background work
- session persistence

## Current Findings

### 1. Startup latency was partly caused by synchronous MediaPipe connect on the main actor

- [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L569)
- [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L576)
- [MediaPipeClient.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/MediaPipeClient.swift#L148)

Before the latest patch, monitor start waited for camera start, warmup, and synchronous MediaPipe startup/connect. That path included Python server launch, sleeps, socket connect, and retry loops. This directly explains the menu bar "loading" phase feeling sticky at start.

### 2. Main-actor analysis backlog was a direct source of freezes

- [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L662)
- [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L681)
- [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L710)
- [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L725)

The analysis loop used a repeating timer and could queue new work before the previous round finished. That produced a classic lag burst pattern. An in-flight guard now drops overlapping analysis ticks.

### 3. MediaPipe was the last major hot path still doing request/response work in the analysis loop

- [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L710)
- [MediaPipeClient.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/MediaPipeClient.swift#L275)
- [MediaPipeClient.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/MediaPipeClient.swift#L308)

Vision fallback already had a background `detectAsync` path. MediaPipe was the inconsistent part. It now uses `sendFrameAsync`, which moves JPEG encode, socket send/recv, and JSON decode off the main actor.

### 4. Reconnect churn was a visible runtime risk

- [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L397)
- [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L728)
- [MediaPipeClient.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/MediaPipeClient.swift#L99)
- [MediaPipeClient.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/MediaPipeClient.swift#L211)

Recent logs showed repeated `Started Python server` lines in a single session. Reconnect attempts are now cooldown-gated and run in the background instead of blocking fallback frames.

### 5. UI redraw pressure was amplified by forced popover invalidation

- [MenuBarView.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Views/MenuBarView.swift#L22)
- [MenuBarView.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Views/MenuBarView.swift#L77)

The popover previously forced `engine.objectWillChange.send()` every second, invalidating the entire preview/status tree. That path was removed.

### 6. Debug log writes were on hot paths and now flow through a shared async writer

- [DebugLogWriter.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/DebugLogWriter.swift#L3)
- [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L245)
- [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L393)
- [PostureAnalyzer.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureAnalyzer.swift#L157)
- [MediaPipeClient.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/MediaPipeClient.swift#L375)
- [VisionPoseDetector.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/VisionPoseDetector.swift#L179)

The project already had a serial async log writer. Using that shared path prevents file writes from blocking the main actor during monitoring.

### 7. Camera frame conversion is still expensive

- [CameraManager.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/CameraManager.swift#L281)
- [CameraManager.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/CameraManager.swift#L290)
- [CameraManager.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/CameraManager.swift#L298)

Each frame becomes a `CIImage`, then a `CGImage`, then sometimes another rotated `CGImage`. This is happening before the frame reaches the analysis pipeline. The preview is currently smooth enough, but this remains a significant CPU cost center.

### 8. Session persistence still blocks the caller

- [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L1475)
- [PostureDataStore.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureDataStore.swift#L192)
- [PostureDataStore.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureDataStore.swift#L399)

`persistSessionSnapshot()` is called from the main actor, and `saveSession()` uses `ioQueue.sync`, which means the caller still blocks until JSON encode/write completes. This is low-frequency but still avoidable.

### 9. Periodic timers are reasonable, but some still deserve budget checks

- [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L211)
- [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L667)
- [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L1186)
- [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L1382)

The analysis timer, inactive probe timer, session save timer, and debug snapshot timer are not individually problematic. The main concern is whether their callbacks do blocking work. That has been reduced, but not fully eliminated.

## Changes Applied In This Round

### Applied

1. Removed forced full-popover invalidation in [MenuBarView.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Views/MenuBarView.swift#L22).
2. Added in-flight guard to the analysis loop in [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L681).
3. Gated hot-path `@Published` updates for pose/head state in [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L946).
4. Moved MediaPipe startup connect off the main actor in [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L576).
5. Moved MediaPipe reconnect attempts to a cooldown-based background path in [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L728).
6. Switched MediaPipe frame round-trip to async in [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/PostureEngine.swift#L710) and [MediaPipeClient.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/MediaPipeClient.swift#L308).
7. Routed hot-path debug logging through [DebugLogWriter.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/DebugLogWriter.swift#L3).

### Not Yet Applied

1. Camera pixel pipeline optimization.
2. Async session persistence.
3. Metrics/telemetry for per-stage timing.
4. View-model splitting for Settings and other non-critical surfaces.

## Solution Plan

### Phase 1: Stabilize startup and live monitoring

Status: mostly complete

1. Keep monitor start non-blocking even if MediaPipe is unavailable.
2. Prevent overlapping analysis work.
3. Keep reconnect attempts off the UI path.
4. Keep debug logging async and centralized.

Success criteria:

- no visible startup stall from MediaPipe connect
- no frozen preview during normal Good/Turtle testing
- no repeated Python-server churn without a visible recovery log

### Phase 2: Instrument the pipeline

Target changes:

1. Add timing around:
   - frame acquisition
   - MediaPipe round-trip
   - Vision detect path
   - score/state publish
2. Emit summarized perf logs every few seconds instead of frame-level spam.
3. Track dropped-analysis count from the in-flight guard.

Why:

Right now the code is structurally safer, but there is no hard timing budget report. Without instrumentation, future regressions will stay anecdotal.

### Phase 3: Reduce camera conversion cost

Target changes:

1. Avoid unnecessary `CGImage` creation for frames that will never hit the preview.
2. Revisit portrait rotation strategy in [CameraManager.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/CameraManager.swift#L296).
3. Consider carrying `CVPixelBuffer` deeper into the pipeline and converting later only where needed.

Why:

This is the cleanest remaining CPU optimization opportunity. It affects both preview and analysis throughput.

### Phase 4: Make persistence fully asynchronous

Target changes:

1. Change `saveSession` to an async entrypoint or fire-and-forget background save.
2. Keep JSON encode/write off the main actor.
3. Ensure stop-monitoring does not wait for disk flush unless explicitly needed.

Why:

Session writes are not high-frequency, but they still block the caller today. This is unnecessary latency at stop, auto-save, and dashboard refresh points.

### Phase 5: Narrow the UI observation surface

Target changes:

1. Split live camera state from static settings state.
2. Avoid observing the full engine from heavyweight SwiftUI surfaces when only a few values are needed.
3. Keep fast-changing preview/overlay state isolated from settings/dashboard forms.

Why:

The app is functionally correct, but large observed-object surfaces make UI regressions too easy to introduce.

## Recommended Next Validation

1. Launch monitoring and confirm the initial menu bar loading phase feels shorter.
2. Run one full calibration + Good/Turtle cycle.
3. Watch `/tmp/turtle_cvadebug.log` for:
   - repeated `Started Python server`
   - repeated fallback loops
   - unexpected gaps in `[SCORE/]` or `[EVAL]`
4. If startup still feels sticky, measure:
   - camera start time
   - first-frame time
   - MediaPipe connect completion time

## Bottom Line

The app had two distinct performance problems:

1. real-time blocking on the live monitoring path
2. unnecessary UI invalidation and file I/O overhead

The first wave of fixes addressed both. The next meaningful gains will come from instrumentation, camera-frame conversion reduction, and asynchronous persistence.
