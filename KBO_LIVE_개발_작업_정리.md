# KBO LIVE iOS 앱 개발 작업 정리

## 1. 프로젝트 개요

**앱명**: KBO LIVE  
**플랫폼**: iOS  
**기술 스택**: Swift, SwiftUI, URLSession, Swift Concurrency, Swift Testing  
**목표**: KBO 실시간 스코어 모니터링과 향후 서버 기반 푸시 알림까지 연결 가능한 iOS 앱 구축

핵심 방향은 아래 3가지로 정리했습니다.

- 사용자가 **1초 안에 경기 상황을 파악**할 수 있어야 함
- 사용자가 **마이팀 중심으로 경기와 일정을 추적**할 수 있어야 함
- 현재는 **앱 구조와 데이터 경계**를 먼저 안정화하고, 이후 **서버 감시 + APNs** 구조로 확장할 수 있어야 함

---

## 2. 제품 방향 및 UX 원칙

초기 설계 단계에서 아래 원칙으로 앱 방향을 고정했습니다.

- 커뮤니티형 앱이 아니라 **실시간 정보 확인형 앱**
- iOS 네이티브 스타일 유지
- **4탭 구조**
  - 홈
  - 마이팀
  - 알림
  - 설정
- 공통 진입 화면
  - 경기 상세
- 정보 우선순위
  1. 경기 상태
  2. 점수
  3. 이닝/주자/아웃
  4. 최근 이벤트
  5. 부가 정보

Stitch AI로 홈, 마이팀, 알림, 설정, 경기 상세 시안을 여러 차례 정리했고,  
최종적으로는 **한국어 기반 refined 시안**을 기준으로 SwiftUI 구현 방향을 확정했습니다.

---

## 3. UI/UX 설계 및 화면 구조 확정

### 탭별 역할
- **홈**: 오늘 경기 전체 모니터링
- **마이팀**: 응원 팀 중심 경기/일정 추적
- **알림**: 받은 알림 내역 확인
- **설정**: 응원 팀, 알림, 표시 설정 관리

### 경기 상세 화면
- 점수판
- 상태 배지
- 구장
- 이닝 / 주자 / 아웃
- 타임라인
- 라이브 액티비티 / 공유 버튼

### refined 단계에서 확정한 UI 보정 방향
- 홈 상단 요약 영역 축소
- 경기 카드 밀도 증가
- 라이브/예정/종료 대비 강화
- 마이팀 탭에서 오늘 경기 우선 배치
- 알림 탭의 unread/read 구분 강화
- 상세 화면의 이닝/주자/아웃 가독성 강화
- 전체 한국어 로컬라이징 기준 정리

---

## 4. 1차 Codex 작업: MVP 앱 셸 구축

### 목표
프로젝트 생성 직후 상태에서 **앱의 기본 셸과 mock 기반 MVP UI**를 구축

### 구현 내용
- `TabView + NavigationStack` 구조 적용
- 홈 / 마이팀 / 알림 / 설정 / 경기 상세 구현
- mock 데이터 기반 모델 및 리포지토리 추가
- 재사용 컴포넌트 추가
  - 경기 카드
  - 상태 배지
  - 필터 칩
  - 알림 카드
  - 빈 상태 뷰
- 한국어 샘플 데이터 추가
- Swift Testing 기반 단위 테스트 2개 추가

### 대표 파일 그룹
- `ContentView.swift`, `kboScoreApp.swift`
- `Team.swift`, `GameModels.swift`, `NotificationModels.swift`, `AppSettings.swift`
- `Repository.swift`, `MockKBORepository.swift`
- `AppModel.swift`
- `HomeView.swift`, `MyTeamView.swift`, `NotificationsView.swift`, `SettingsView.swift`, `GameDetailView.swift`
- `GameCardView.swift`, `NotificationCardView.swift`, `StatusBadge.swift`, `FilterChip.swift`, `EmptyStateView.swift`

### 검증
- 앱 빌드 성공

---

## 5. 2차 Codex 작업: UI 밀도/계층/영속화 polish

### 목표
1차 구조는 유지하고, 화면 밀도와 시각적 계층을 개선

### 주요 개선점
- 홈
  - 카드 높이 및 간격 축소
  - 라이브 경기 강조 강화
  - 요약 헤더와 필터 칩 컴팩트화
- 마이팀
  - 오늘 경기 우선순위 강화
  - 빈 상태 문구 개선
- 알림
  - unread/read 대비 강화
  - 중요 알림 타입 시각 구분 강화
- 경기 상세
  - 점수판 계층 재정리
  - 이닝 / 주자 / 아웃 표시 개선
  - 타임라인 압축
- 설정
  - UserDefaults 기반 로컬 영속화 추가
  - 응원 팀 / 알림 토글 / 화면 모드 저장

### 대표 변경 파일
- `AppModel.swift`
- `AppSettings.swift`
- `BrandStyles.swift`
- `GameCardView.swift`
- `NotificationCardView.swift`
- `HomeView.swift`
- `MyTeamView.swift`
- `NotificationsView.swift`
- `GameDetailView.swift`
- `SettingsView.swift`

### 검증
- 앱 빌드 성공

---

## 6. 3차 Codex 작업: 데이터 경계 정리

### 목표
mock 기반 UI를 유지하면서 **실데이터 연결 준비를 위한 데이터 경계 정리**

### 구현 내용
- 리포지토리 책임 분리
  - `KBOGameDataSource`
  - `KBONotificationDataSource`
- DTO / mapper 계층 추가
- mock 데이터도 동일한 mapping 경로를 타도록 정리
- `refreshable` 지원 추가
- 상태값 정규화 강화
  - live / upcoming / final / rain-delay / cancelled
- mapper/리포지토리 안정성 관련 테스트 추가

### 대표 변경 파일
- `Repository.swift`
- `KBOLiveDTOs.swift`
- `MockKBORepository.swift`
- `AppModel.swift`
- `HomeView.swift`
- `MyTeamView.swift`
- `NotificationsView.swift`
- `kboScoreTests.swift`

### 검증
- 앱 빌드 성공
- 단위 테스트 번들 컴파일 성공

---

## 7. 4차 Codex 작업: Live Repository + fallback 구조

### 목표
기존 DTO → mapper → domain → UI 흐름을 유지한 채,  
실제 네트워크 소스를 꽂을 수 있는 live repository 추가

### 구현 내용
- `LiveKBORepository` 추가
- `URLSession + async/await` 기반 네트워크 구조 추가
- `/bootstrap`, `/games`, `/notifications`, `/teams` 경로 지원
- `KBORepositoryConfiguration`, `KBORepositoryFactory` 추가
- 환경변수 / Info.plist 기반 설정 지원
  - `KBO_LIVE_API_BASE_URL`
  - `KBO_LIVE_API_TIMEOUT`
  - `KBO_LIVE_USE_MOCK_FALLBACK`
- `FallbackKBORepository` 추가
  - live 실패 시 mock fallback
- unit-test 전용 scheme 추가
  - `kboScore-UnitTests.xcscheme`

### 대표 변경 파일
- `LiveKBORepository.swift`
- `KBOLiveDTOs.swift`
- `kboScoreApp.swift`
- `kboScoreTests.swift`
- `kboScore.xcscheme`
- `kboScore-UnitTests.xcscheme`

### 검증
- 앱 빌드 성공
- unit-test build-for-testing 성공

---

## 8. 5차 Codex 작업: 외부 응답 정규화 어댑터

### 목표
실제 외부 JSON 응답이 내부 DTO 계약과 다를 때,  
그 혼란을 UI 밖에서 정리하는 adapter 계층 추가

### 구현 내용
- `LiveKBOResponseAdapter.swift` 추가
- 외부 JSON 정규화 처리
  - nested payload
  - alternate keys
  - string/number 혼용
  - split date/time
  - partial metadata
  - irregular status text
- Debug 전용 repository 상태 가시성 추가
  - active source
  - base URL
- Settings 하단 debug visibility 추가
- Swift isolation 관련 저위험 경고 정리
- adapter / fallback 안정성 테스트 추가

### 대표 변경 파일
- `LiveKBOResponseAdapter.swift`
- `LiveKBORepository.swift`
- `KBOLiveDTOs.swift`
- `AppModel.swift`
- `kboScoreApp.swift`
- `SettingsView.swift`
- `AppSettings.swift`
- `GameModels.swift`
- `NotificationModels.swift`
- `kboScoreTests.swift`

### 검증
- 앱 빌드 성공
- unit-test build-for-testing 성공

---

## 9. 6차 Codex 작업: 캐시 / stale 상태 / refresh 안정화

### 목표
실제 데이터가 들어와도 앱이 과하게 흔들리지 않도록  
refresh 정책, cache, stale 표시 정리

### 구현 내용
- `CachedKBORepository` 추가
- bootstrap / games / notifications short TTL 메모리 캐시
- 동일 요청 중복 방지(in-flight task 공유)
- 만료된 캐시라도 refresh 실패 시 stale cache 유지
- `AppModel`에서 다음 상황을 구분
  - 첫 로드 실패 + 데이터 없음
  - refresh 실패 + 기존 데이터 있음
- stale 상태 및 마지막 성공 시각 추적
- stale banner 추가
  - 홈
  - 마이팀
  - 알림
- Settings debug 영역에 표시 확장
  - displayed source
  - last refresh time
  - stale state

### 대표 변경 파일
- `LiveKBORepository.swift`
- `AppModel.swift`
- `DataStatusBannerView.swift`
- `HomeView.swift`
- `MyTeamView.swift`
- `NotificationsView.swift`
- `SettingsView.swift`
- `kboScoreTests.swift`

### 검증
- 앱 빌드 성공
- unit-test build-for-testing 성공

---

## 10. 7차 Codex 작업: 2026 시범경기 기반 fixture 현실화

### 목표
generic mock/sample 데이터를 줄이고  
**2026 KBO 시범경기 기반 fixture**로 테스트와 샘플 품질 향상

### 구현 내용
- `MockKBORepository.swift`를 2026 시범경기 기준으로 정리
- 실제 한국어 팀명, 구장명, 일정 반영
- mock 날짜는 `Date.now` 기준으로 상대화하여 앱 UX 유지
- test fixture는 고정된 2026년 3월 날짜 사용
- fixture 추가
  - `2026-preseason-bootstrap.json`
  - `2026-preseason-external-response.json`
- live / rain-delay / irregular payload 등 unsupported edge case는 synthetic 유지
- fixture 기반 decoding/mapping 테스트로 전환

### 대표 변경 파일
- `MockKBORepository.swift`
- `kboScoreTests.swift`
- `2026-preseason-bootstrap.json`
- `2026-preseason-external-response.json`

### 검증
- 앱 빌드 성공
- unit-test build-for-testing 성공

---

## 11. 8차 Codex 작업: 실제 KBO 공식 JSON 샘플 검증

### 목표
공식 KBO JSON 샘플을 실제로 넣어서 adapter가 공식 응답을 먹는지 검증

### 구현 내용
- 공식 KBO JSON fixture 추가
  - `2026-kbo-official-game-list-20260323.json`
  - `2026-kbo-official-schedule-list-202603.json`
- official payload 정규화 강화
  - root game array 응답
  - rows 기반 schedule 응답
  - uppercase field
    - `G_DT`
    - `G_TM`
    - `AWAY_ID`
    - `HOME_ID`
    - `T_SCORE_CN`
    - `B_SCORE_CN`
    - `GAME_STATE_SC`
- 공식 팀 코드 정규화
  - `WO -> kiwoom`
  - `SK -> ssg`
  - `HH -> hanwha`
- source-specific parsing은 adapter 내부에만 격리
- real fixture 기반 테스트 추가
  - raw official payload normalization
  - game-list payload mapping
  - schedule-row normalization

### 대표 변경 파일
- `LiveKBOResponseAdapter.swift`
- `kboScoreTests.swift`
- `2026-kbo-official-game-list-20260323.json`
- `2026-kbo-official-schedule-list-202603.json`

### 검증
- 앱 빌드 성공
- unit-test build-for-testing 성공
- 전체 test run은 환경 노이즈로 clean completed report 확보 실패

---

## 12. 디자인 및 브랜딩 자산 정리

### 팀 디자인 문서 업로드 완료
아래 10개 구단 디자인 문서를 확보했습니다.

- NC
- 두산
- 한화
- 키움
- KIA
- SSG
- LG
- 롯데
- 삼성
- KT

### 실팀 로고 자산 업로드 완료
10개 구단 로고 이미지를 모두 확보했습니다.

### 이 자산을 바탕으로 확정한 추가 작업
1. **팀 아이콘(실로고) 추가**
2. **마이팀 월간 일정 캘린더 추가**
3. **팀별 테마 추가**
   - 마이팀 선택 시 팀 메인컬러 기반 accent/theme 적용

---

## 13. 추가 요구사항 및 다음 적용 예정 작업

### A. 팀 아이콘 추가
목표:
- 실제 로고 asset을 앱 전반에 적용

반영 대상:
- 홈 경기 카드
- 마이팀 헤더
- 마이팀 오늘/다음/최근 경기 카드
- 알림
- 경기 상세 점수판
- 일정 캘린더 행

원칙:
- 실제 로고 asset 우선 사용
- asset 누락 시에만 fallback badge 사용

---

### B. 마이팀 월간 일정 캘린더 추가
목표:
- Apple Calendar 연동이 아닌 **앱 내 월간 캘린더** 제공

필수 표시 항목:
- 월간 grid
- 경기 있는 날짜 marker
- 선택일 경기 리스트
- 상대 팀 로고
- 상대 팀명
- 홈/원정 여부
- 시작 시간
- 상태
- 가능하면 구장

추가 확정 사항:
- mock 파생 캘린더가 아니라 **KBO 실제 월별 일정 데이터로 채우기**
- 시범경기 3/12–3/24
- 정규시즌 3/28 개막 이후 일정까지 확장 가능하게 구성

---

### C. 팀별 테마 추가
목표:
- 현재 구조는 유지하면서 팀별 brand token만 적용

적용 범위:
- app accent/highlight
- summary/header accent
- selected chip
- primary button
- live/status accent 일부
- 마이팀 헤더
- 일정 캘린더 highlight
- active tab tint

원칙:
- 전체 화면을 팀별로 다르게 뜯지 않음
- token-driven 방식으로만 적용
- readability / contrast 우선

---

## 14. 현재 아키텍처 요약

```text
Raw External Source
-> LiveKBOResponseAdapter
-> DTO Layer
-> Mapper
-> Domain Models
-> Repository Boundary
-> AppModel
-> SwiftUI Views
```

### 현재 repository 구성
- `MockKBORepository`
- `LiveKBORepository`
- `FallbackKBORepository`
- `CachedKBORepository`

### 현재 상태 처리
- first load failure
- refresh failure with usable data
- stale cache fallback
- debug-only repository state visibility

---

## 15. 검증 상태 요약

### 성공한 항목
- 앱 빌드 성공
- unit-test 전용 scheme 분리
- build-for-testing 성공
- fixture 기반 decoding/mapping 테스트 추가

### 아직 남은 검증 이슈
- 전체 simulator test run은 환경 이슈로 clean 완료 로그 확보 실패
- 연결된 passcode-locked iPhone 때문에 Xcode 노이즈 경고 발생
- 일부 저위험 Swift 6 isolation warning 정리 여지 존재

---

## 16. 현재 남은 TODO

### 앱 내부 우선 TODO
1. 팀 로고 asset 등록 및 실제 로고 렌더링 연결
2. 팀별 테마 token 추가
3. 마이팀 월간 일정 캘린더 구현
4. 월간 캘린더를 실제 KBO 공식 일정으로 채우기
5. 캘린더용 월 단위 fetch/cache/grouping 추가
6. 팀별 theme lookup / calendar grouping 관련 저위험 테스트 추가

### 데이터/운영 TODO
7. production용 최종 KBO live base URL 확정
8. 최종 운영 피드 raw sample fixture 추가
9. 실제 운영 source edge case 재검증

### 이후 큰 작업
10. device token 등록 구조
11. 알림 권한 흐름
12. notification payload routing
13. 서버 감시 + score diff engine
14. APNs 발송
15. Live Activity / 딥링크

---

## 17. 다음 작업 권장 우선순위

### 바로 다음 패스
1. **실팀 로고 asset 반영**
2. **팀별 테마 적용**
3. **마이팀 월간 일정 캘린더 추가**
4. **월간 캘린더 실제 KBO 일정 연결**

### 그 다음
5. production source 확정 및 추가 fixture 검증
6. 서버 기반 푸시 구조 설계

---

## 18. 한 줄 요약

현재 KBO LIVE iOS 앱은  
**UI 구조, 데이터 경계, live/mock/fallback, official KBO adapter, cache/stale handling, 2026 preseason/official fixture 검증까지 완료된 상태**입니다.

다음 핵심 작업은  
**팀 로고 + 팀별 테마 + 마이팀 월간 일정 캘린더 + 실제 KBO 월간 일정 연결**입니다.

---

## 19. 10차 Codex 작업: 운영 KBO 월간 일정 요청 계약 고정

### 이번 패스 목표
1. 검증된 운영 KBO 월간 일정 요청 계약을 코드에 고정
2. source-specific 월간 일정 요청 규칙을 live repository 내부에 격리
3. 요청 생성 규칙에 대한 저위험 테스트 추가

### 실제 구현 내용
- `LiveKBORepository`의 운영 KBO 월간 일정 요청을 실제 계약으로 고정
  - `POST /ws/Schedule.asmx/GetScheduleList`
  - `application/x-www-form-urlencoded; charset=UTF-8`
  - `X-Requested-With: XMLHttpRequest`
  - `teamId=` 항상 포함
- 운영 KBO 전용 월간 일정 요청 규칙을 `OfficialKBOMonthlyScheduleRequestContract`로 분리
- 월별 series 규칙 고정
  - 3월: `srIdList=0,9`
  - 비3월: `srIdList=0`
- 테스트를 내부 helper 직접 참조 대신 실제 생성된 `URLRequest` 캡처 검증으로 정리
  - form-urlencoded body 생성
  - `teamId=` 포함 여부
  - 3월 / 비3월 `srIdList` 규칙
  - 운영 호스트 헤더 적용
- adapter / DTO / mapper / domain / UI 흐름은 변경하지 않음
- 기존 cache / fallback 동작 유지

### 변경 파일
- `kboScore/Data/LiveKBORepository.swift`
- `kboScoreTests/kboScoreTests.swift`

### 검증 결과
- KBO 운영 페이지 스크립트에서 실제 호출 계약 확인
- 운영 KBO 엔드포인트 직접 검증
  - `teamId=` 포함 시 정상 응답
  - `teamId` 누락 시 500 가능성 확인
  - 2026년 3월 `srIdList=0,9`에서 시범경기 + 개막 직후 rows 확인
- 빌드 검증
  - `xcodebuild -scheme kboScore ... build` 성공
  - `xcodebuild -scheme kboScore-UnitTests ... build-for-testing` 성공

### 남은 TODO
- 실제 앱 실행 환경에서 production base URL 설정 후 end-to-end 수동 검증
- 3월 외 월별 `srIdList` 예외 규칙이 추가로 있는지 시즌 중 재검증

### 다음 권장 작업
1. production base URL을 실제 앱 설정에 연결
2. 마이팀 월간 일정의 live path를 실기기/시뮬레이터에서 수동 확인
3. 이후 push/APNs 준비 전, 실운영 fixture를 한 번 더 캡처해 regression test에 추가
