# Kafka 라우팅

## 책임

네 노드 KRaft Kafka 클러스터의 설치와 노드별 설정 파일 생성을 담당하는 실행 스크립트의 파일별 문서로 연결한다.

## 계층별 호출 구조

```text
Kafka 설정
└─ setup-kafka.sh --node node1|node2|node3|node4
   ├─ 환경 변수와 노드 이름 검증
   ├─ Kafka 4.1.2 다운로드·압축 해제
   ├─ ~/.bashrc export 항목 갱신
   ├─ logs 디렉터리 생성
   └─ config/game/nodeN.properties 생성
```

- [setup-kafka.sh 파일 문서](files/srcs/kafka/setup-kafka.sh.md)

## 함수와 메서드

### `usage()`

```text
입력: 없음
처리: 실행 인자와 필수 환경 변수를 안내한다.
```

### `set_export(file, key, value)`

```text
입력: 대상 셸 설정 파일, 환경 변수 이름, 환경 변수 값
처리: 같은 export 문은 유지하고, 다른 값 또는 없는 키는 갱신·추가한다.
외부 호출: grep, sed
```

### `require_value(key, value)`, `validate_address(key, value)`

```text
입력: 환경 변수 이름과 값
처리: 필수 값 누락과 포트가 포함된 잘못된 노드 주소를 거부한다.
```

## 변수와 상수

- `KAFKA_HOME`: `$HOME/kafka/kafka_2.13-4.1.2` 설치 경로다.
- `LOG_DIR`: 기본값은 `$KAFKA_HOME/logs`이며 `GAME_LOG_DIR`로 변경할 수 있다.
- `GAME_CLUSTER_ID`: `CLUSTER_ID` 또는 동일 이름의 환경 변수에서 가져오는 공통 클러스터 ID다.
- `DIRECTORY_1`~`DIRECTORY_4`: initial controller 목록에 사용하는 노드별 UUID다.
- `GAME_NODE_1_ADDRESS`~`GAME_NODE_4_ADDRESS`: 포트를 제외한 노드별 미러링 주소다.
- `GAME_INITIAL_CONTROLLERS`: 주소와 UUID로 조합해 만든 Kafka `--initial-controllers` 값이다.
