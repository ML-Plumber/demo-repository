#!/usr/bin/env bash
set -Eeuo pipefail

# 실패한 명령과 종료 코드를 출력하고 즉시 종료한다.
trap 'exit_code=$?; printf "설정 실패: %s 명령 실행 중 오류가 발생했습니다. (종료 코드: %d)\n" "$BASH_COMMAND" "$exit_code" >&2; exit "$exit_code"' ERR

if [[ $# -ne 1 ]]; then
    printf '설정 실패: 미러링 IP 주소 하나를 전달해야 합니다.\n' >&2
    exit 1
fi

SPARK_LOCAL_IP=$1
if ! ip -4 addr show | grep -q "inet ${SPARK_LOCAL_IP}/"; then
    printf '설정 실패: 전달한 미러링 IP 주소를 WSL에서 찾을 수 없습니다.\n' >&2
    exit 1
fi

find_java17_home() {
    local candidate

    for candidate in /usr/lib/jvm/java-17-*; do
        [[ -x "${candidate}/bin/java" ]] || continue

        if "${candidate}/bin/java" -version 2>&1 | grep -q '"17\.'; then
            readlink -f "$candidate"
            return 0
        fi
    done

    return 1
}

set_export() {
    local file=$1
    local key=$2
    local value=$3
    local line="export ${key}=${value}"

    # 같은 값이 있으면 변경하지 않고, 없거나 값이 다르면 해당 항목만 갱신한다.
    if grep -Fxq "$line" "$file"; then
        return 0
    fi

    if grep -q "^export ${key}=" "$file"; then
        sed -i "s|^export ${key}=.*|${line}|" "$file"
    else
        printf '\n%s\n' "$line" >> "$file"
    fi
}

SPARK_HOME="$HOME/spark-4.2.0"
SPARK_ARCHIVE="$HOME/spark-4.2.0-bin-hadoop3.tgz"
SPARK_URL='https://archive.apache.org/dist/spark/spark-4.2.0/spark-4.2.0-bin-hadoop3.tgz'

if [[ ! -d "$SPARK_HOME" ]]; then
    curl -fL "$SPARK_URL" -o "$SPARK_ARCHIVE"
    tar -xzf "$SPARK_ARCHIVE" -C "$HOME"
    mv "$HOME/spark-4.2.0-bin-hadoop3" "$SPARK_HOME"
fi

if ! JAVA_HOME="$(find_java17_home)"; then
    sudo apt-get update
    sudo apt-get install -y openjdk-17-jdk
    JAVA_HOME="$(find_java17_home)"
fi

BASHRC="$HOME/.bashrc"
touch "$BASHRC"
set_export "$BASHRC" JAVA_HOME "$JAVA_HOME"
set_export "$BASHRC" PATH '$JAVA_HOME/bin:$PATH'
source "$BASHRC"

PYSPARK_PYTHON="$(command -v python3)"
SPARK_ENV="$SPARK_HOME/conf/spark-env.sh"

if [[ ! -f "$SPARK_ENV" ]]; then
    cp "$SPARK_HOME/conf/spark-env.sh.template" "$SPARK_ENV"
fi

WORKER_CORES="$(nproc)"
TOTAL_MEMORY_MIB="$(awk '/MemTotal/ { print int($2 / 1024) }' /proc/meminfo)"
if (( TOTAL_MEMORY_MIB <= 1024 )); then
    printf '설정 실패: Spark 워커 메모리를 계산할 수 없습니다.\n' >&2
    exit 1
fi
WORKER_MEMORY="$((TOTAL_MEMORY_MIB - 1024))m"

set_export "$SPARK_ENV" JAVA_HOME "$JAVA_HOME"
set_export "$SPARK_ENV" PYSPARK_PYTHON "$PYSPARK_PYTHON"
set_export "$SPARK_ENV" PYSPARK_DRIVER_PYTHON '"$PYSPARK_PYTHON"'
set_export "$SPARK_ENV" SPARK_LOCAL_IP "$SPARK_LOCAL_IP"
set_export "$SPARK_ENV" SPARK_WORKER_CORES "$WORKER_CORES"
set_export "$SPARK_ENV" SPARK_WORKER_MEMORY "$WORKER_MEMORY"
set_export "$SPARK_ENV" SPARK_DAEMON_MEMORY '1g'

chmod +x "$SPARK_ENV"
