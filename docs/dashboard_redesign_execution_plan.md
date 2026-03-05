# Turtleneck Coach Dashboard Redesign 실행 계획

> 작성일: 2026-03-04  
> 기준 PRD: "Turtleneck Coach Dashboard Redesign PRD"

## 1) 현재 코드베이스 분석 요약

### 현재 Dashboard 구조 (사실 기반)
- 상단 4개 카드가 `Monitored`, `Good Posture`, `Average Score`, `Slouch Alerts`로 구성되어 있음.
  - 참조: [DashboardView.swift](/Users/ilwonyoon/Documents/Turtle_neck_detector-dashboard-update/TurtleneckCoach/Views/DashboardView.swift#L72)
- 메인 차트는 `Score Trend`(점수 기반 라인/에어리어) 중심.
  - 참조: [DashboardView.swift](/Users/ilwonyoon/Documents/Turtle_neck_detector-dashboard-update/TurtleneckCoach/Views/DashboardView.swift#L114)
- 보조 차트는 `Compliance`(Good/Bad 비율 스택 바)로 일/주/월 표시.
  - 참조: [DashboardView.swift](/Users/ilwonyoon/Documents/Turtle_neck_detector-dashboard-update/TurtleneckCoach/Views/DashboardView.swift#L209)

### 현재 저장/집계 데이터 구조
- 세션 레코드: `duration`, `averageScore`, `goodPosturePercent`, `averageCVA`, `slouchEventCount`.
  - 참조: [PostureDataStore.swift](/Users/ilwonyoon/Documents/Turtle_neck_detector-dashboard-update/TurtleneckCoach/Core/PostureDataStore.swift#L3)
- 일간 집계: `totalMonitoredMinutes`, `averageScore`, `goodPosturePercent`, `sessionCount`.
  - 참조: [PostureDataStore.swift](/Users/ilwonyoon/Documents/Turtle_neck_detector-dashboard-update/TurtleneckCoach/Core/PostureDataStore.swift#L14)
- 시간대 집계: 이미 `goodMinutes`, `badMinutes`를 제공함.
  - 참조: [PostureDataStore.swift](/Users/ilwonyoon/Documents/Turtle_neck_detector-dashboard-update/TurtleneckCoach/Core/PostureDataStore.swift#L25)

### 현재 엔진 계측 상태
- `Slouch Alerts` 카운트는 심각도 전환 시 `sessionSlouchEventCount`를 증가시키는 방식.
  - 참조: [PostureEngine.swift](/Users/ilwonyoon/Documents/Turtle_neck_detector-dashboard-update/TurtleneckCoach/Core/PostureEngine.swift#L766)
- `Resets`, `Longest Slouch`를 직접 계산하는 세션 필드는 아직 없음.
  - 참조: [PostureEngine.swift](/Users/ilwonyoon/Documents/Turtle_neck_detector-dashboard-update/TurtleneckCoach/Core/PostureEngine.swift#L780)

## 2) PRD 대비 갭 분석

### 맞는 부분
- `Good Posture %`는 이미 계산/노출 가능.
- 시간대 Good/Bad 분해(`HourlyAggregate`)가 있어 Posture Timeline으로 전환하기 유리함.
- 일간 집계가 있어 Weekly Trend 구현 기반 존재.

### 부족한 부분
- PRD 필수 지표 중 `Bad Posture Time`은 UI에 1순위로 노출되지 않음.
- `Resets`는 현재 데이터 모델에 없음.
- `Longest Slouch`는 현재 데이터 모델에 없음(세션 내 bad streak 길이 계측 부재).
- `Score Trend`, `Average Score`, `Slouch Alerts`가 아직 주요 UI에 남아 있음.
- Dashboard 내 일부 색 표현이 red를 포함(점수 그래디언트), PRD 원칙과 충돌.

## 3) 실행 전략

### 전략 원칙
- 분석형 점수 중심 UI를 행동 중심 UI로 전환한다.
- 기존 데이터 스토어를 최대한 재사용하되, PRD 핵심 지표에 필요한 최소 필드만 확장한다.
- 기존 사용자 데이터와 호환되도록 `Codable` optional/default 전략으로 마이그레이션한다.

### 단계별 실행 계획

1. 데이터 모델 확장 (Phase A)
- `SessionRecord`에 아래 필드 추가:
  - `badPostureSeconds: TimeInterval`
  - `resetCount: Int`
  - `longestSlouchSeconds: TimeInterval`
- `DailyAggregate`에 아래 필드 추가:
  - `totalBadPostureMinutes: Double`
  - `resetCount: Int`
  - `longestSlouchMinutes: Double`
- 기존 JSON과 하위 호환:
  - 디코딩 시 누락 필드는 `0`으로 보정.

2. 엔진 계측 추가 (Phase B)
- `PostureEngine` 세션 추적에 아래 상태 추가:
  - 현재 bad streak 시작 시각
  - 세션 누적 bad posture 초
  - 세션 최장 bad streak 초
  - 세션 reset 카운트
- 전환 규칙:
  - bad streak 시작: severity가 `.bad`/`.away`로 진입 시점
  - bad streak 종료: `.bad`/`.away`에서 벗어날 때
  - reset 증가: `.bad`/`.away` -> `.good` 전환 시 +1
- `buildSessionRecord`에서 신규 필드를 함께 저장.

3. 집계 로직 업데이트 (Phase C)
- `PostureDataStore.computeDailyAggregate`에서 신규 필드 가중/합산:
  - `totalBadPostureMinutes`: 세션 합계 기반
  - `resetCount`: 세션 합계
  - `longestSlouchMinutes`: 당일 세션 최대값
- `loadHourlyAggregates`는 기존 `goodMinutes/badMinutes` 재활용(추가 변경 최소화).

4. Dashboard UI 재구성 (Phase D)
- 상단 핵심 카드 4개로 교체:
  - `Bad Posture Time` (Primary)
  - `Good Posture %`
  - `Resets`
  - `Longest Slouch`
- 제거:
  - `Monitored`, `Average Score`, `Slouch Alerts`
- 차트 교체:
  - `Score Trend` 제거
  - `Posture Timeline` 추가 (시간대별 good vs bad, day 범위)
  - `Weekly Trend` 추가 (요일별 bad posture time, week 범위 기본)
- 색상:
  - Green(good), Orange(bad)만 사용
  - Dashboard 화면에서 red 미사용

5. 카피/UX 톤 조정 (Phase E)
- 라벨을 행동 중심 문구로 통일:
  - 예: `Bad Posture Today`, `Resets Today`, `Longest Slouch`
- 죄책감 유발 용어 제거(`alerts`, `score` 중심 표현 축소).

6. 검증/QA (Phase F)
- 단위 테스트:
  - 세션 전환 시 `resetCount`, `longestSlouchSeconds`, `badPostureSeconds` 계산 검증
  - 일간 집계 합산/최대 계산 검증
- 수동 QA:
  - 3초 내 이해성(지표 가독성) 체크
  - 10초 이내 점검 플로우(열기→Bad Posture Time 확인→행동) 확인
  - 기존 데이터 파일 로드 호환성 확인

## 4) 파일 단위 변경 계획

- `TurtleneckCoach/Core/PostureEngine.swift`
  - 세션 계측 필드/전환 로직/레코드 생성 확장
- `TurtleneckCoach/Core/PostureDataStore.swift`
  - 모델 확장, 집계 계산 확장, 디코드 호환 처리
- `TurtleneckCoach/Views/DashboardView.swift`
  - 상단 카드 교체, Score Trend 제거, Timeline + Weekly Trend 추가
- `TurtleneckCoach/DesignSystem/DesignTokens.swift` (필요 시)
  - Dashboard 전용 색 토큰(orange/green 중심) 보강
- `test_*.swift` 또는 신규 테스트 파일
  - 집계/전환 로직 검증 추가

## 5) 완료 기준 (Definition of Done)

- PRD 핵심 지표 4개가 상단에 노출된다.
- `Score Trend`, `Average Score`, `Slouch Alerts`, `Monitored`가 주요 Dashboard에서 제거된다.
- Timeline이 시간대별 Good/Bad를 직관적으로 보여준다.
- Weekly Trend가 일자별 bad posture time을 보여준다.
- Dashboard에서 red 색상 미사용을 보장한다.
- 기존 사용자 데이터(sessions/daily_aggregates JSON) 로딩이 깨지지 않는다.

## 6) 리스크 및 대응

- 리스크: `Resets` 정의 해석 차이
  - 대응: 1차는 `.bad/.away -> .good` 전환으로 명확 정의, 이후 AB 테스트로 조정
- 리스크: 구버전 JSON 디코딩 실패
  - 대응: 커스텀 `init(from:)`로 기본값 보정
- 리스크: 실시간 세션 + 저장 세션 중복 집계
  - 대응: 기존 `currentSessionSnapshot()` 병합 로직 유지 + 신규 필드 동일 기준 적용

## 7) 구현 순서 제안 (작업 단위)

1. 모델/엔진 계측 확장 (A-B)
2. 데이터스토어 집계 확장 + 호환 처리 (C)
3. Dashboard UI 교체 (D-E)
4. 테스트/QA/미세 조정 (F)

