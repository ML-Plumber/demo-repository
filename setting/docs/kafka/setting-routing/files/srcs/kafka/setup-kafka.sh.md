# `setting/srcs/kafka/setup-kafka.sh`

## 책임

`--node node1`~`--node node4` 인자를 받아 Kafka 4.1.2를 설치하고, 지정 노드의 KRaft 설정 파일과 로그인 셸 환경 변수를 생성한다. Kafka 스토리지 포맷과 서버 시작은 실행하지 않고 필요한 명령만 출력한다.

## 호출 구조

```text
setup-kafka.sh --node <node1|node2|node3|node4>
├─ usage / 인자 검증
├─ require_value / validate_address
├─ Kafka 설치 파일 확인 또는 curl·tar 실행
├─ set_export (~/.bashrc)
├─ config/game/nodeN.properties 생성
└─ format·server-start 명령 출력
```

## 입력값

### `--node <node1|node2|node3|node4>`

- 값: 현재 설정할 Kafka 노드 이름
- 사용처: `node.id`와 `config/game/nodeN.properties` 파일명 결정
- 검증: 네 값 이외의 노드 이름과 알 수 없는 인자는 실패 처리한다.

### 환경 변수

- `CLUSTER_ID` 또는 `GAME_CLUSTER_ID`: 모든 노드에서 공유하는 클러스터 ID다.
- `DIRECTORY_1`~`DIRECTORY_4`: `kafka-storage.sh random-uuid`로 얻은 각 노드 UUID다.
- `GAME_NODE_1_ADDRESS`~`GAME_NODE_4_ADDRESS`: 포트가 없는 IPv4 또는 DNS 이름이다.
- `GAME_LOG_DIR`: 선택 사항이며 미지정 시 `$KAFKA_HOME/logs`를 사용한다.

## 함수와 메서드

### `set_export(file, key, value)`

`~/.bashrc`의 특정 `export` 항목만 추가하거나 최신 값으로 바꾼다. 값이 같으면 파일을 바꾸지 않는다.

### `require_value(key, value)`

필수 환경 변수가 비어 있으면 어떤 값이 누락됐는지 오류로 알리고 종료한다.

### `validate_address(key, value)`

주소가 Kafka 포트를 중복 포함하거나 공백·쉼표를 포함하지 않도록 IPv4·DNS 이름 형식을 제한한다.

## 생성·변경 파일

- `$HOME/kafka/kafka_2.13-4.1.2`: Kafka 압축 해제 경로다.
- `$HOME/kafka/kafka_2.13-4.1.2/logs`: 기본 로그 저장 경로다.
- `$HOME/.bashrc`: 클러스터 ID, 디렉터리 UUID, 노드 주소, initial controllers 관련 export 항목을 갱신한다.
- `$HOME/kafka/kafka_2.13-4.1.2/config/game/nodeN.properties`: 지정 노드의 Kafka 브로커·컨트롤러 설정 파일이다.

## 외부 호출

- `curl`, `tar`: Kafka 설치 파일 다운로드와 압축 해제
- `grep`, `sed`: `.bashrc`의 export 항목 검색과 갱신
- `mkdir`, `touch`: 설치·로그·설정 디렉터리와 `.bashrc` 생성
