# Kafka KRaft 클러스터 설정

[`setup-kafka.sh`](../../srcs/kafka/setup-kafka.sh)는 `--node node1`처럼 지정한 노드의 Kafka 설치, `~/.bashrc` 환경 변수 등록, `config/game/node1.properties` 생성을 수행합니다. 포맷과 서버 실행은 데이터 초기화 여부를 사용자가 확인할 수 있도록 자동 실행하지 않고 마지막에 명령으로 안내합니다.

## 1. Kafka 다운로드 및 압축 해제

각 노드에서 `~/kafka`에 Kafka 2.13-4.1.2를 내려받고 압축을 해제합니다. 이후 스크립트도 같은 설치 경로를 사용하며, 이미 설치되어 있으면 다시 다운로드하지 않습니다.

```bash
mkdir -p ~/kafka
cd ~/kafka
curl -fLO https://downloads.apache.org/kafka/4.1.2/kafka_2.13-4.1.2.tgz
tar -xzf kafka_2.13-4.1.2.tgz
```

## 2. 사전 준비: 클러스터 값 결정

모든 노드는 같은 클러스터 ID와 네 노드의 UUID·미러링 주소 전체를 알아야 합니다. 각 노드는 아래 명령으로 자신의 UUID를 하나 생성합니다. 클러스터 ID는 한 노드에서 한 번만 생성합니다. 생성한 값은 네 노드 모두에 동일하게 배포합니다.

```bash
cd ~/kafka/kafka_2.13-4.1.2
bin/kafka-storage.sh random-uuid # 한 번만 실행: CLUSTER_ID
bin/kafka-storage.sh random-uuid # 각 노드에서 한 번 실행: 자신의 DIRECTORY_N
```

## 3. 노드별 환경 변수 입력

각 노드의 현재 셸에 아래 값을 설정합니다. `GAME_NODE_N_ADDRESS`에는 포트를 제외한 미러링 IPv4 주소 또는 DNS 이름을 넣습니다.

```bash
export CLUSTER_ID="공통 클러스터 ID"
export DIRECTORY_1="node1 UUID"
export DIRECTORY_2="node2 UUID"
export DIRECTORY_3="node3 UUID"
export DIRECTORY_4="node4 UUID"

export GAME_NODE_1_ADDRESS="node1 미러링 주소"
export GAME_NODE_2_ADDRESS="node2 미러링 주소"
export GAME_NODE_3_ADDRESS="node3 미러링 주소"
export GAME_NODE_4_ADDRESS="node4 미러링 주소"
```

> `GAME_LOG_DIR`을 지정하지 않으면 로그 경로는 설치 경로를 기준으로 한 `~/kafka/kafka_2.13-4.1.2/logs`입니다. 다른 위치에 로그를 둘 때만 `GAME_LOG_DIR`을 지정합니다.

## 4. 지정 노드 설정 파일 생성

WSL에서 스크립트를 실행합니다. `node1`만 바꿔 각 노드에서 한 번씩 실행합니다.

```bash
chmod +x setting/srcs/kafka/setup-kafka.sh
setting/srcs/kafka/setup-kafka.sh --node node1
```

스크립트는 다음 작업을 수행합니다.

1. `~/kafka`에 `kafka_2.13-4.1.2.tgz`를 다운로드하고 압축을 해제합니다.
2. `~/kafka/kafka_2.13-4.1.2/logs`를 만듭니다.
3. `~/.bashrc`에 `CLUSTER_ID`, `DIRECTORY_1`~`DIRECTORY_4`, `INITIAL_CONTROLLERS`, `GAME_CLUSTER_ID`, `GAME_INITIAL_CONTROLLERS`를 등록합니다.
4. 지정 노드에 맞는 `~/kafka/kafka_2.13-4.1.2/config/game/nodeN.properties`를 생성합니다.

`node1`의 설정 파일에는 다음과 같은 값이 들어갑니다. `node.id`, 리스너 주소, 컨트롤러 주소는 실행 시 입력한 노드 값으로 바뀝니다.

```properties
process.roles=broker,controller
node.id=1
controller.quorum.bootstrap.servers=NODE1_ADDRESS:9093,NODE2_ADDRESS:9093,NODE3_ADDRESS:9093,NODE4_ADDRESS:9093
listeners=PLAINTEXT://NODE1_ADDRESS:9092,CONTROLLER://NODE1_ADDRESS:9093
advertised.listeners=PLAINTEXT://NODE1_ADDRESS:9092
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT
inter.broker.listener.name=PLAINTEXT
controller.listener.names=CONTROLLER
log.dirs=/home/USER/kafka/kafka_2.13-4.1.2/logs
num.partitions=3
default.replication.factor=3
min.insync.replicas=2
offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2
auto.create.topics.enable=false
group.initial.rebalance.delay.ms=0
```

## 5. 스토리지 포맷 및 Kafka 실행

각 노드에서 생성된 환경 변수를 다시 읽고, 해당 노드의 설정으로 포맷한 뒤 서버를 시작합니다. 포맷은 기존 Kafka 메타데이터를 초기화할 수 있으므로 새 클러스터를 처음 구성할 때만 실행합니다.

```bash
source ~/.bashrc
cd ~/kafka/kafka_2.13-4.1.2
bin/kafka-storage.sh format --cluster-id "$GAME_CLUSTER_ID" --config config/game/node1.properties --initial-controllers "$GAME_INITIAL_CONTROLLERS"
bin/kafka-server-start.sh config/game/node1.properties
```
