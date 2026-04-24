# 프로젝트 컨텍스트

## 목적

이 프로젝트는 Envoy AI Gateway v0.4에서 v0.5로 넘어가는 과정과, 그 위에서 session-based short-term memory PoC를 구현하기 위한 재현 가능한 문서와 스크립트를 만드는 작업이다.

Envoy AI Gateway 자체는 대화 메모리를 내장하지 않는다. 따라서 Memory 기능은 Gateway의 확장 지점과 외부 저장소를 조합해서 직접 설계하고 검증해야 한다.

## 멘토 Q&A 기반 프로젝트 범위

### 포함 범위

- **검증 완료**: Envoy AI Gateway v0.4 baseline 로컬 재현
- **계획**: Envoy AI Gateway v0.4에서 v0.5로의 마이그레이션 시나리오 정리
- **계획**: v0.5 주요 변경점 확인
  - GatewayConfig
  - `schema.version`에서 `schema.prefix`로의 전환
  - Body Mutation
  - Header Mutation
  - ExtProc 연계 지점
- **계획**: session-based short-term memory PoC 설계 및 구현
- **계획**: Redis 기반 session memory 저장소 검토
- **계획**: 기본 기능 검증과 성능/지연 시간의 기초 측정

### 제외 범위

- 실제 사내 서비스 전체 마이그레이션
- 실제 사용자 데이터 연동
- 프로덕션 배포 자동화 완성
- Long-term memory와 semantic memory 본격 구현
- MCP 기반 memory 구현
- Agent Gateway 확장

MCP는 optional이다. 이번 핵심 범위는 Envoy AI Gateway v0.5 마이그레이션과 Memory 기능 구현이며, MCP는 Agent 도구 연동 관점의 후속 확장 후보로만 본다.

Agent Gateway는 이번 범위에서 제외한다. 현재 목표는 특정 agent runtime을 확장하는 것이 아니라, 플랫폼 레벨의 Inference API에 범용 memory capability를 추가할 수 있는지 확인하는 것이다.

## 평가 기준

평가 기준은 단순 기능 구현만이 아니라 다음 항목을 함께 포함한다.

- 기능 구현 가능성
- 아키텍처 설계의 타당성
- v0.4에서 v0.5로 넘어가는 리서치와 변경점 정리
- 기본 검증 절차의 재현성
- 성능 또는 지연 시간에 대한 기초 관찰
- 문서화 품질과 troubleshooting 가능성

## 플랫폼 차원의 범용 Inference API 관점

이 PoC는 특정 앱이나 특정 도메인에 종속된 memory 기능을 목표로 하지 않는다. 사내 플랫폼이 Inference API 형태로 여러 서비스에 제공된다고 가정하고, 클라이언트가 최소한의 공통 계약만 지키면 memory 기능을 사용할 수 있는 구조를 지향한다.

기본 계약 초안:

- 클라이언트는 `x-session-id` 헤더를 전달한다.
- 요청 body는 OpenAI 호환 `/v1/chat/completions` 형태를 우선 가정한다.
- Gateway 또는 Memory layer는 세션별 최근 대화를 조회해 요청 context에 주입한다.
- 응답 이후 사용자 메시지와 assistant 메시지를 저장한다.
- session TTL과 최대 history 길이를 플랫폼 정책으로 제한한다.

## Memory 기능 집중

Memory PoC의 핵심은 다음이다.

- LLM API가 stateless라는 전제를 보완한다.
- session 단위로 최근 대화 history를 저장한다.
- 다음 요청에 history를 주입한다.
- Redis TTL과 sliding window로 저장 범위를 제한한다.
- 플랫폼이 특정 앱의 업무 도메인을 알지 않아도 사용할 수 있는 형태로 만든다.

## 상태 표기 규칙

이 레포의 문서는 다음 표기를 명확히 구분한다.

- **검증 완료**: 실제 로컬 환경에서 실행하고 성공을 확인한 내용
- **계획**: 앞으로 수행할 작업 순서 또는 설계 방향
- **검토 필요**: 공식 문서, 실제 클러스터, manifest 적용으로 추가 확인이 필요한 내용
