# MediaPipe Release Stabilization Execution Plan

Date: 2026-03-13
Goal: MediaPipe 유지한 채로 성능/안정성/보안 관점에서 런칭 블로커를 해결
Status: Phase 1–5 완료 (2026-03-13), Phase 6은 v1.0.1 대상

---

## Phase 1: Critical Security Fixes (P0 — 런칭 블로커)

### 1.1 Unix Socket 권한 설정
- **파일**: `python_server/pose_server.py`, `Core/MediaPipeClient.swift`
- **문제**: `/tmp/pt_turtle.sock`이 기본 umask로 생성됨 → 같은 머신의 다른 프로세스가 카메라 데이터 접근 가능
- **수정**:
  - Python: `bind()` 후 `os.chmod(SOCKET_PATH, 0o600)` 추가
  - Swift: 연결 전 소켓 파일 소유자 검증
  - 장기: `~/Library/Application Support/TurtleneckCoach/` 하위로 소켓 경로 이동 검토

### 1.2 Python 서버 예외 정보 노출 차단
- **파일**: `python_server/pose_server.py:539-542`
- **문제**: 내부 예외 메시지(`str(e)`)가 JSON 응답으로 클라이언트에 전달됨
- **수정**: 클라이언트에는 일반 에러 메시지, 상세 내용은 서버 로그에만 기록

### 1.3 Debug 로그 릴리즈 빌드 제외 보장
- **파일**: `Core/DebugLogWriter.swift`, `Core/PostureEngine.swift:237,279,606`
- **문제**: `/tmp/turtle_cvadebug.log` 및 `/tmp/turtle_debug_snapshots/` 경로가 릴리즈에 포함 가능
- **수정**:
  - 모든 디버그 로깅 코드에 `#if DEBUG` 가드 확인/보강
  - `build-release.sh`에서 `-DDEBUG=0` 플래그 명시
  - 릴리즈 빌드에 `print()` 문 잔존 여부 확인 (`CameraManager.swift:387` 등)

### 1.4 Sandbox 활성화 검토
- **파일**: `TurtleneckCoach/Resources/TurtleneckCoach.entitlements`
- **문제**: `com.apple.security.app-sandbox = false` — 파일 시스템 전체 접근 가능
- **수정**:
  - Sandbox 활성화 + 최소 entitlement 추가 (camera, temp files, app support)
  - MediaPipe Python 서버와의 IPC가 sandbox 내에서 동작하는지 검증 필요
  - **주의**: sandbox 활성화 시 Python bundled runtime 경로 접근 깨질 수 있음 → 충분한 테스트 필요

---

## Phase 2: Critical Stability Fixes (P0 — 크래시 방지)

### 2.1 MediaPipeClient Face Mesh 배열 인덱스 OOB 수정
- **파일**: `Core/MediaPipeClient.swift:788-791`
- **문제**: `flat.count >= 1434` 검사 후 루프에서 `flat[i+2]` 접근 시 i=1432일 때 1434 인덱스 접근 → 크래시
- **수정**: 루프 조건을 `stride(from: 0, to: flat.count - 2, by: 3)` 으로 변경

### 2.2 앱 종료 시 Python 프로세스 정리
- **파일**: `Core/PostureEngine.swift:660-666`, `Core/MediaPipeClient.swift`
- **문제**: `deinit`에서 async `shutdown()` 호출 → 완료 전 객체 해제 → 좀비 Python 프로세스
- **수정**:
  - `MediaPipeClient.shutdown()`에 동기 종료 경로 추가
  - `Process.terminate()` + `waitUntilExit()` 동기 호출
  - `appWillTerminate` 노티피케이션에서 동기 정리 보장

### 2.3 Python 크래시 후 소켓 파일 잔존 처리
- **파일**: `Core/MediaPipeClient.swift`
- **문제**: Python 프로세스 크래시 시 `/tmp/pt_turtle.sock` 잔존 → 재시작 시 연결 실패
- **수정**: 연결 실패 시 stale 소켓 파일 삭제 후 서버 재시작 시도

### 2.4 stopMonitoring 타이머 race condition
- **파일**: `Core/PostureEngine.swift:919-930`
- **문제**: 여러 타이머(`analysisTimer`, `probeTimer`, `sessionSaveTimer`, `debugSnapshotTimer`)가 정리 후에도 발화 가능
- **수정**:
  - `stopMonitoring()`에서 모든 타이머 동기 invalidate
  - 모든 타이머 콜백에서 `guard isMonitoring else { return }` 추가

---

## Phase 3: Critical Performance Fixes (P0 — 사용자 체감)

### 3.1 JPEG 인코딩 메인 스레드 블로킹 제거
- **파일**: `Core/MediaPipeClient.swift:754-759`
- **문제**: `NSBitmapImageRep` JPEG 인코딩이 매 프레임 30-50ms 소요 → 메인 스레드 블로킹
- **수정**:
  - 백그라운드 큐에서 인코딩 수행
  - 또는 `CGImageDestination` 기반 하드웨어 가속 인코딩 사용
  - 인코딩 완료 후 비동기로 소켓 전송

### 3.2 서버 시작 시 Thread.sleep(1.5) 제거
- **파일**: `Core/MediaPipeClient.swift:471`
- **문제**: 1.5초 동기 대기 → 메뉴바 UI 프리즈
- **수정**: `Task.sleep` 기반 비동기 대기 + 소켓 가용성 폴링 + 지수 백오프

### 3.3 소켓 타임아웃 3초 → 논블로킹 + Vision fallback
- **파일**: `Core/MediaPipeClient.swift:559-560`
- **문제**: MediaPipe 응답 지연 시 3초간 분석 중단, Vision fallback 없음
- **수정**:
  - 타임아웃 500ms로 축소
  - 타임아웃 시 즉시 Vision framework로 fallback
  - 비동기 소켓 읽기 또는 `O_NONBLOCK` + select/poll 적용

---

## Phase 4: High Priority Stability (P1 — 런칭 전 권장)

### 4.1 카메라 연결 해제 감지
- **파일**: `Core/CameraManager.swift`
- **문제**: USB 카메라 분리 시 무응답 — 분석은 계속되고 stale 데이터로 잘못된 알림 발생
- **수정**: `AVCaptureSessionWasInterrupted` 노티 모니터링 + UI 상태 표시

### 4.2 화면 잠금/슬립 시 리소스 절약
- **파일**: `Core/PostureEngine.swift`
- **문제**: 스크린 슬립 시에도 카메라+Vision+MediaPipe 풀 가동 → 배터리 소모
- **수정**: `NSWorkspace.screensDidSleepNotification` 감지 → 카메라 일시정지 + 분석 중단

### 4.3 CameraManager deinit 정리
- **파일**: `Core/CameraManager.swift`
- **문제**: `deinit` 없음 → 카메라 세션/리소스 미해제
- **수정**: `deinit`에서 `stopSession()` + input/output 제거

### 4.4 PostureDataStore 파일 I/O 에러 로깅
- **파일**: `Core/PostureDataStore.swift:395-396`
- **문제**: 디코딩 실패 시 빈 배열 반환, 에러 무시 → 세션 데이터 무단 손실
- **수정**: `try?` → `do/catch` + 에러 로깅, 손상 데이터 클리어

### 4.5 Notification 권한 결과 처리
- **파일**: `Services/NotificationService.swift:66-70`
- **문제**: `requestAuthorization` 결과(granted, error) 무시
- **수정**: 권한 거부 시 UI에 상태 표시, 에러 로깅

---

## Phase 5: High Priority Performance (P1 — 사용자 경험)

### 5.1 @Published currentFrame UI cascade 최적화
- **파일**: `Core/PostureEngine.swift:48-49`
- **문제**: 매 프레임 `@Published` 업데이트 → 전체 SwiftUI 뷰 트리 재조정
- **수정**:
  - 프레임 전달을 `@Published`에서 분리 (별도 ObservableObject 또는 직접 바인딩)
  - 또는 프레임 업데이트 빈도를 10fps로 낮추기

### 5.2 Face Mesh 렌더링 최적화
- **파일**: `Views/CameraPreviewView.swift:110-159`
- **문제**: 1322 edge × 2 stroke = 2600+ Canvas 연산/프레임
- **수정**:
  - 단일 `Path`에 모든 edge 누적 후 한 번에 stroke
  - 렌더링 빈도 5fps로 제한
  - 가시 영역 edge만 사전 계산 (백그라운드 스레드)

### 5.3 분석 타이머 backpressure 추가
- **파일**: `Core/PostureEngine.swift:983-993`
- **문제**: 이전 분석 완료와 무관하게 0.33초마다 타이머 발화 → 불필요한 CPU 소모
- **수정**: 분석 완료 후 다음 타이머 스케줄링 (completion-triggered)

---

## Phase 6: Medium Priority (P2 — v1.0.1 패치 가능)

| 항목 | 파일 | 설명 |
|------|------|------|
| UserDefaults 값 범위 검증 | PostureEngine | inactiveTimeout 등 읽기 시 bounds clamp |
| 소켓 프레임 사이즈 검증 | MediaPipeClient | Swift 측에서도 10MB 제한 체크 |
| 로그 privacy 분류 | MediaPipeClient:763 | 경로 등 `.private`로 변경 |
| CalibrationData 손상 복구 | CalibrationManager:80 | 디코딩 실패 시 clearSaved() 호출 |
| Python print() → logging 전환 | pose_server.py | 13개 print문 → logging 모듈 |
| 환경변수 경로 검증 | MediaPipeClient:439-453 | Python 런타임 경로 존재 확인 |

---

## Execution Order

```
Week 1: Phase 1 (보안) + Phase 2 (크래시 방지)
  - 소켓 권한, 예외 노출, 디버그 로그, 배열 OOB, 프로세스 정리, 타이머 race
  - 빌드 + 스모크 테스트

Week 2: Phase 3 (성능 P0) + Phase 4 (안정성 P1)
  - JPEG 비동기화, Thread.sleep 제거, 소켓 타임아웃
  - 카메라 해제 감지, 슬립 대응, deinit 정리
  - 빌드 + 성능 프로파일링

Week 3: Phase 5 (성능 P1) + Phase 6 선택
  - UI cascade 최적화, mesh 렌더링, 타이머 backpressure
  - 최종 빌드 + clean-user 설치 테스트 + 공증
```

---

## Validation Checklist

- [ ] 릴리즈 빌드에 `print()` / debug log 없음 확인
- [ ] `/tmp/pt_turtle.sock` 퍼미션 600 확인
- [ ] 앱 종료 후 Python 프로세스 잔존 없음 확인
- [ ] 카메라 분리 시 graceful 처리 확인
- [ ] 스크린 슬립 시 CPU 사용량 0% 근접 확인
- [ ] Activity Monitor에서 idle 시 CPU < 5% 확인
- [ ] 30분 연속 사용 시 메모리 증가 < 10MB 확인
- [ ] clean macOS 유저 설치 → 시작 → 10분 사용 시나리오 통과
