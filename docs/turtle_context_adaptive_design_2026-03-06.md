# TurtleNeckCoach Context-Adaptive Scoring Design
Date: 2026-03-06
Owner: PT_turtle experiment session

## 1. 문서 목적
이 문서는 아래 두 가지를 하나로 통합한다.
1. 지금까지 수집한 로그/캡처 데이터 기반의 사실 정리
2. 해당 데이터를 바탕으로 한 설계안(모니터 비회귀 보장 포함)과 사용자 시나리오

## 2. 이번 세션 데이터 범위
데이터 소스:
- `/tmp/turtle_cvadebug.log`
- `/tmp/turtle_manual_snapshots/*`

수집 특성:
- 환경: 랩탑 카메라 중심
- 거리 변화: D0, D1, D2 수집 (D3는 얼굴 프레이밍 불량으로 제외)
- 캡처 세트: Good/FWD 반복 세트 + mild/severe FWD 혼합
- 이미지 수: 총 78장 (13 폴더 x 6장)

## 3. 사실 기반 관찰 결과
### 3.1 Good vs FWD 분리(랩탑 환경)
집계 결과:
- GOOD_POSTURE
  - score: min/med/max = 94 / 98 / 98 (avg 97.714)
  - rawCVA: min/med/max = 62 / 65 / 65 (avg 64.786)
  - faceY median = 0.480
  - faceH(faceSize) median = 0.368
- FORWARD_HEAD
  - score: min/med/max = 24 / 83.5 / 98 (avg 74.667)
  - rawCVA: min/med/max = 26 / 56.85 / 65 (avg 52.305)
  - faceY median = 0.431
  - faceH(faceSize) median = 0.459

해석:
- FWD에서는 대체로 faceY가 낮아지고(프레임 상단 쪽), faceSize가 커진다.
- severe FWD는 안정적으로 분리되지만 mild FWD는 good 경계와 겹친다.

### 3.2 점수와 피처 결합 강도
Forward 샘플 기준:
- corr(faceSize, score) = -0.739
- corr(cvaDrop, score) = -0.943

해석:
- faceSize(거리/구도 proxy) 영향도 크지만, 실제 점수는 cvaDrop에 훨씬 강하게 종속됨.

### 3.3 거리 변화(D0~D2)에서 나타난 패턴
관찰:
- Good은 대체로 안정적(대부분 96~98)
- FWD는 감지는 되지만, 거리/구도 변화 시 초반 점수 하락이 늦거나 완만해지는 세트가 존재
- 사용자 체감의 "랩탑 포지션에서 상향 평준화" 관찰과 로그가 일치

핵심 결론:
- 문제의 중심은 severe FWD 미검출이 아님
- 핵심은 mild FWD 민감도의 일관성 저하(카메라 기하 변화 영향)

### 3.4 모니터 vs 랩탑 비교 가능 범위
현재 확정 가능한 것:
- 랩탑 데이터에서는 카메라 기하 변화가 mild 민감도에 영향을 줌

현재 확정 불가한 것:
- 외부 모니터(상단 웹캠)와의 정량 비교는 동일 프로토콜 데이터가 아직 없음

결론:
- 이번 문서 설계는 모니터 데이터가 들어와도 그대로 확장 가능하게 구성함

## 4. 제품 목표(합의된 해석)
1. 시스템이 현재 카메라 컨텍스트를 `desktop monitor` vs `laptop`으로 구분한다.
2. 해당 컨텍스트 기반으로 calibration/scoring을 분리 적용한다.
3. laptop 틸트/거리 변화는 상위 컨텍스트(`laptop`) 아래 하위 분류로 처리한다.

## 5. 설계 원칙
1. 모니터 경로 비회귀가 최우선이다.
2. 자동 분류 확신이 낮으면 기존 로직으로 즉시 fallback 한다.
3. 컨텍스트 적응은 laptop 경로에서만 단계적으로 활성화한다.
4. 점수 로직 변경 전, log-only 모드로 먼저 검증한다.

## 6. 제안 아키텍처
### 6.1 컨텍스트 계층
런타임 상태:
- `cameraContext`: `desktop | laptop | unknown`
- `contextConfidence`: 0.0 ~ 1.0
- `contextSource`: `auto | manual`
- `laptopSubcontext`: `neutral | tilt_back | too_near | too_far`

### 6.2 캘리브레이션 프로파일 분리
저장 단위:
- `desktopProfile`
- `laptopProfile`

프로파일 포함 값:
- baseline CVA
- baseline faceSize
- baseline faceY
- 품질 지표(프레이밍 안정도)
- 마지막 갱신 시각

### 6.3 점수 계산 파이프라인
1. 프레이밍 품질 게이트 평가
2. 컨텍스트 추론(자동 또는 사용자 override)
3. 해당 컨텍스트 프로파일 로드
4. 상대 변화 계산
5. severity 판단 + 히스테리시스 적용
6. UI/알림 상태 반영

핵심:
- `desktop` 또는 `unknown(low confidence)`는 기존 스코어러 그대로 사용
- `laptop(high confidence)`에서만 보정 스코어러 적용

## 7. 분류/보정 로직 제안
### 7.1 context 추론
입력 후보:
- faceY 통계
- faceSize 통계
- 프레임 내 얼굴 박스 위치 안정성
- 카메라 장치 메타(가능하면)

정책:
- confidence 높음: 자동 결정
- confidence 낮음: `unknown` 처리 후 기존 로직 유지
- 사용자 수동 선택 시 manual 우선

### 7.2 laptop 하위 분류
신호:
- baseline 대비 faceSize 변화
- baseline 대비 faceY 변화
- 짧은 시간 창(1~2초) 안정성

출력:
- `tilt_back` 또는 `too_far` 탐지 시 mild 임계값 민감도 보정
- 프레이밍 이탈이면 posture 판단 보류 + 재정렬 안내

### 7.3 점수 보정(개념)
- 기존 raw score를 완전히 대체하지 않고 보정 계층으로 추가
- 예시 개념:
  - `effectiveDrop = cvaDrop - k1*distanceBias - k2*viewpointBias`
  - `distanceBias`는 faceSize 기반
  - `viewpointBias`는 faceY 기반
- mild 구간에서만 보정 강도 크게, severe 구간은 보정 최소화

### 7.4 히스테리시스
- 진입 임계값과 해제 임계값 분리
- 경계 구간 score 흔들림에서 UI 상태 토글 억제

## 8. 모니터 비회귀 보장 전략
1. feature flag: `adaptive_scoring_v1` 기본 OFF
2. `desktop` 경로는 기존 계산식 그대로 유지
3. 모니터 리플레이 로그에서 기존 대비 차이 허용치 정의
4. 허용치 초과 시 adaptive 즉시 비활성 fallback

## 9. 단계별 적용 계획
Phase 1 (log-only):
- 컨텍스트/하위컨텍스트 추론 결과만 로그 저장
- 사용자 노출 점수는 기존과 동일

Phase 2 (laptop-only scoring):
- laptop + high confidence에서만 보정 적용
- desktop/unknown은 기존 유지

Phase 3 (quality gate + recalibration):
- 프레이밍 불량 시 posture 판단 보류
- 자동 재캘리브레이션 유도

## 10. 사용자 시나리오
### 시나리오 A: 데스크탑 모니터 고정 사용자
- 흐름: 기존처럼 캘리브레이션 후 사용
- 시스템: `cameraContext=desktop`, 기존 스코어러 유지
- 기대 결과: 업데이트 전후 체감 차이 최소, 회귀 없음

### 시나리오 B: 랩탑 기본 사용자
- 흐름: 랩탑 카메라 캘리브레이션 후 Good/FWD 반복
- 시스템: `cameraContext=laptop`, laptopProfile 기반 계산
- 기대 결과: mild FWD 분리 안정성 개선

### 시나리오 C: 랩탑 각도/거리 자주 변경 사용자
- 흐름: 사용 중 화면 틸트/거리 변화
- 시스템: `laptopSubcontext` 전환 감지, 민감도 보정 또는 재보정 요청
- 기대 결과: 점수 튐 감소, 잘못된 상향 평준화 완화

### 시나리오 D: 모니터/랩탑 번갈아 사용하는 사용자
- 흐름: 장치 전환 반복
- 시스템: 컨텍스트별 프로파일 자동 전환, 필요 시 빠른 재캘리브레이션
- 기대 결과: 장치 바뀌어도 점수 기준 일관성 유지

### 시나리오 E: 자동 판정 불확실 사용자
- 흐름: 조명/구도 불안정
- 시스템: confidence 낮으면 `unknown` + 기존 로직 유지, 수동 선택 제안
- 기대 결과: 잘못된 자동 보정으로 성능 붕괴 방지

### 시나리오 F: 얼굴 프레이밍 불량 사용자
- 흐름: 너무 멀거나 얼굴 일부만 프레임에 존재
- 시스템: quality gate 동작, 점수 업데이트 보류 + 위치 가이드
- 기대 결과: 노이즈 기반 오탐/미탐 감소

### 시나리오 G: 회귀 민감 모니터 사용자
- 흐름: 기존 모니터 환경에서 업데이트 적용
- 시스템: desktop 경로 고정 + regression guard
- 기대 결과: "모니터에서 잘 되던 것" 유지

## 11. 검증 지표
필수 지표:
- desktop 데이터에서 기존 대비 점수 편차
- laptop 데이터에서 mild FWD 분리도 개선폭
- severe FWD recall 유지 또는 개선
- state flicker(초당 상태 전환 빈도) 감소

권장 합격 기준(초안):
- desktop 평균 score 편차 절대값 <= 2
- laptop mild FWD median score gap( good - mild ) >= 10
- severe FWD miss rate 0에 근접

## 12. 즉시 실행 항목
1. Phase 1(log-only) 구현
2. 분석 스크립트 자동화(세션별 분리도, 지연 프레임, 권장 임계값)
3. 동일 프로토콜의 외부 모니터 데이터 1세트 확보
4. 모니터 비회귀 리플레이 테스트 추가

## 13. 최종 요약
- 현재 데이터로 확인된 문제는 "랩탑 카메라 기하 변화에서 mild FWD 일관성 저하"다.
- 설계 방향은 `상위 컨텍스트(desktop/laptop) + 하위 laptop 상태(tilt/distance)` 구조가 맞다.
- 모니터 경로는 기존 로직 고정과 단계적 롤아웃으로 보호한다.

## 14. UI 반영 상태 (2026-03-06 구현)
이번 반영은 Phase 1 범위(log-only) 내에서 사용자 가시성을 확보하는 데 목적이 있다.

적용 위치:
1. Settings > Camera 섹션
2. Menu bar popover 배지

추가된 UX 요소:
1. `Context Mode` 선택기
- `Auto (Recommended)`
- `Desktop (Manual)`
- `Laptop (Manual)`

2. `Detected Context` 표시
- 예: `Laptop (Auto, 82%)`
- 자동/수동 source와 confidence를 함께 노출

3. `Laptop State` 표시
- `Neutral`, `Tilt Back`, `Too Near`, `Too Far`
- laptop이 아닌 경우 `—`

4. Menu bar 배지
- `Desktop A`, `Laptop M` 형태로 현재 컨텍스트를 짧게 표시
- `A`=Auto, `M`=Manual

비회귀 보장:
1. score/severity 계산식은 변경하지 않음
2. 컨텍스트는 표시/로그 용도로만 반영 (log-only)
3. 기존 모니터 경로의 posture scoring 동작은 유지
