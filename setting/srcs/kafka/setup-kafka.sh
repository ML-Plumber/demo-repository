#!/usr/bin/env bash
set -Eeuo pipefail

# 실패한 명령과 종료 코드를 출력하고 즉시 종료한다.
trap 'exit_code=$?; printf "설정 실패: %s 명령 실행 중 오류가 발생했습니다. (종료 코드: %d)\n" "$BASH_COMMAND" "$exit_code" >&2; exit "$exit_code"' ERR

usage() {
    printf '%s\n' \
        '사용법: ./setup-kafka.sh --node node1' \
        '' \
        '환경 변수:' \
        '  CLUSTER_ID                  모든 노드에서 같은 Kafka 클러스터 ID' \
        '  DIRECTORY_1 ... DIRECTORY_4 각 노드의 kafka-storage.sh random-uuid 결과' \
        '  GAME_NODE_1_ADDRESS ... GAME_NODE_4_ADDRESS' \
        '                              노드별 미러링 IP 또는 DNS 이름' \
        '  GAME_LOG_DIR                선택 사항. 기본값은 ~/kafka/kafka_2.13-4.1.2/logs'
}

set_export() {
    local file=$1
    local key=$2
    local value=$3
    local escaped_value
    local line

    # .bashrc에서 해석 가능한 큰따옴표 export 문으로 값을 한 항목만 갱신한다.
    escaped_value=${value//\\/\\\\}
    escaped_value=${escaped_value//\"/\\\"}
    line="export ${key}=\"${escaped_value}\""

    if grep -Fxq "$line" "$file"; then
        return 0
    fi

    if grep -q "^export ${key}=" "$file"; then
        sed -i "s|^export ${key}=.*|${line}|" "$file"
    else
        printf '\n%s\n' "$line" >> "$file"
    fi
}

require_value() {
    local key=$1
    local value=$2

    if [[ -z "$value" ]]; then
        printf '설정 실패: %s 환경 변수를 설정해야 합니다.\n' "$key" >&2
        exit 1
    fi
}

validate_address() {
    local key=$1
    local value=$2

    # controller.quorum.bootstrap.servers에 쓸 IPv4 또는 DNS 이름만 허용한다.
    if [[ ! "$value" =~ ^[A-Za-z0-9.-]+$ ]]; then
        printf '설정 실패: %s에는 포트 없이 IPv4 또는 DNS 이름을 넣어야 합니다.\n' "$key" >&2
        exit 1
    fi
}

NODE_NAME=''
while [[ $# -gt 0 ]]; do
    case "$1" in
        --node)
            [[ $# -ge 2 ]] || { usage >&2; exit 1; }
            NODE_NAME=$2
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf '설정 실패: 알 수 없는 인자입니다: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ ! "$NODE_NAME" =~ ^node[1-4]$ ]]; then
    printf '설정 실패: --node에는 node1, node2, node3, node4 중 하나를 지정해야 합니다.\n' >&2
    usage >&2
    exit 1
fi

NODE_ID=${NODE_NAME#node}
KAFKA_BASE="$HOME/kafka"
KAFKA_VERSION='4.1.2'
KAFKA_HOME="$KAFKA_BASE/kafka_2.13-${KAFKA_VERSION}"
KAFKA_ARCHIVE="$KAFKA_BASE/kafka_2.13-${KAFKA_VERSION}.tgz"
KAFKA_URL="https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_2.13-${KAFKA_VERSION}.tgz"
# 설치 버전이 바뀌어도 로그 경로가 항상 같은 Kafka 홈을 따르게 한다.
LOG_DIR="${GAME_LOG_DIR:-$KAFKA_HOME/logs}"
BASHRC="$HOME/.bashrc"
CONFIG_DIR="$KAFKA_HOME/config/game"
CONFIG_FILE="$CONFIG_DIR/${NODE_NAME}.properties"

# 기존 문서의 CLUSTER_ID도 받고, format 명령용 GAME_CLUSTER_ID를 우선 지원한다.
GAME_CLUSTER_ID="${GAME_CLUSTER_ID:-${CLUSTER_ID:-}}"
require_value 'CLUSTER_ID 또는 GAME_CLUSTER_ID' "$GAME_CLUSTER_ID"

declare -a NODE_ADDRESSES=()
declare -a DIRECTORY_IDS=()
for id in 1 2 3 4; do
    address_key="GAME_NODE_${id}_ADDRESS"
    directory_key="DIRECTORY_${id}"
    address="${!address_key:-}"
    directory_id="${!directory_key:-}"

    require_value "$address_key" "$address"
    require_value "$directory_key" "$directory_id"
    validate_address "$address_key" "$address"

    NODE_ADDRESSES[$id]=$address
    DIRECTORY_IDS[$id]=$directory_id
done

CONTROLLER_BOOTSTRAP_SERVERS=''
GAME_INITIAL_CONTROLLERS=''
for id in 1 2 3 4; do
    controller_endpoint="${NODE_ADDRESSES[$id]}:9093"
    controller_entry="${id}@${controller_endpoint}:${DIRECTORY_IDS[$id]}"

    CONTROLLER_BOOTSTRAP_SERVERS+="${CONTROLLER_BOOTSTRAP_SERVERS:+,}${controller_endpoint}"
    GAME_INITIAL_CONTROLLERS+="${GAME_INITIAL_CONTROLLERS:+,}${controller_entry}"
done

mkdir -p "$KAFKA_BASE" "$LOG_DIR"
if [[ ! -x "$KAFKA_HOME/bin/kafka-storage.sh" ]]; then
    curl -fL "$KAFKA_URL" -o "$KAFKA_ARCHIVE"
    tar -xzf "$KAFKA_ARCHIVE" -C "$KAFKA_BASE"
fi

# 다음 로그인 셸에서도 동일한 클러스터 정보를 사용할 수 있게 .bashrc에 저장한다.
touch "$BASHRC"
set_export "$BASHRC" CLUSTER_ID "$GAME_CLUSTER_ID"
for id in 1 2 3 4; do
    set_export "$BASHRC" "DIRECTORY_${id}" "${DIRECTORY_IDS[$id]}"
    set_export "$BASHRC" "GAME_NODE_${id}_ADDRESS" "${NODE_ADDRESSES[$id]}"
done
set_export "$BASHRC" INITIAL_CONTROLLERS "$GAME_INITIAL_CONTROLLERS"
set_export "$BASHRC" GAME_CLUSTER_ID "$GAME_CLUSTER_ID"
set_export "$BASHRC" GAME_INITIAL_CONTROLLERS "$GAME_INITIAL_CONTROLLERS"

mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" <<EOF
process.roles=broker,controller
node.id=${NODE_ID}
controller.quorum.bootstrap.servers=${CONTROLLER_BOOTSTRAP_SERVERS}
listeners=PLAINTEXT://${NODE_ADDRESSES[$NODE_ID]}:9092,CONTROLLER://${NODE_ADDRESSES[$NODE_ID]}:9093
advertised.listeners=PLAINTEXT://${NODE_ADDRESSES[$NODE_ID]}:9092
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT
inter.broker.listener.name=PLAINTEXT
controller.listener.names=CONTROLLER
log.dirs=${LOG_DIR}
num.partitions=3
default.replication.factor=3
min.insync.replicas=2
offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2
auto.create.topics.enable=false
group.initial.rebalance.delay.ms=0
EOF

printf '설정 완료: %s\n' "$CONFIG_FILE"
printf '%s\n' "다음 명령으로 포맷하고 실행합니다: cd \"$KAFKA_HOME\" && bin/kafka-storage.sh format --cluster-id \"\$GAME_CLUSTER_ID\" --config config/game/${NODE_NAME}.properties --initial-controllers \"\$GAME_INITIAL_CONTROLLERS\" && bin/kafka-server-start.sh config/game/${NODE_NAME}.properties"
