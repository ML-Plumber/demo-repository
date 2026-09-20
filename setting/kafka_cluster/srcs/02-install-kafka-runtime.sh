#!/usr/bin/env bash
# WSL 사용자 홈 디렉터리에 Kafka 4.3.1 실행 환경을 설치한다.
set -Eeuo pipefail

KAFKA_VERSION="4.3.1"
KAFKA_SCALA_VERSION="2.13"
KAFKA_ARCHIVE="kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}.tgz"
KAFKA_URL="https://downloads.apache.org/kafka/${KAFKA_VERSION}/${KAFKA_ARCHIVE}"
KAFKA_PACKAGE_DIR="${HOME}/packages"
KAFKA_VERSION_DIR="${HOME}/kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}"
KAFKA_HOME="${HOME}/kafka"
KAFKA_ENV_FILE="${HOME}/.kafka-env"
ENV_MARKER="# Managed by 02-install-kafka-runtime.sh"

die() {
  echo "오류: $*" >&2
  exit 1
}

on_error() {
  local exit_code=$?
  echo "오류: ${BASH_SOURCE[1]}:${BASH_LINENO[0]}에서 설치에 실패했습니다. (종료 코드: ${exit_code})" >&2
  exit "$exit_code"
}

trap on_error ERR

java_major_version() {
  local java_bin="$1"
  "$java_bin" -version 2>&1 | awk -F '[".]' '/version/ { print $2; exit }'
}

resolve_java17_binary() {
  # apt 설치 뒤 기본 java가 17 미만일 때 JDK 17 대안을 직접 선택한다.
  update-alternatives --list java 2>/dev/null \
    | grep -E '/java-17-[^/]*/bin/java$' \
    | head -n 1 \
    || true
}

install_or_resolve_java() {
  local candidate=""
  local major_version="0"

  if command -v java >/dev/null 2>&1; then
    candidate="$(readlink -f "$(which java)")"
    major_version="$(java_major_version "$candidate")"
    "$candidate" -version
  fi

  if [[ ! "$major_version" =~ ^[0-9]+$ ]] || (( major_version < 17 )); then
    sudo apt update
    sudo apt install -y openjdk-17-jdk
    candidate="$(resolve_java17_binary)"
    [[ -n "$candidate" ]] || die "JDK 17 실행 파일을 찾지 못했습니다."
    candidate="$(readlink -f "$candidate")"
    major_version="$(java_major_version "$candidate")"
  fi

  [[ "$major_version" =~ ^[0-9]+$ ]] && (( major_version >= 17 )) \
    || die "Java 17 이상이 필요합니다. 현재 버전: ${major_version}"

  JAVA_HOME="${candidate%/bin/java}"
  [[ -x "${JAVA_HOME}/bin/java" ]] || die "JAVA_HOME이 올바르지 않습니다: ${JAVA_HOME}"
  export JAVA_HOME
}

download_and_verify_kafka() {
  local archive_path="${KAFKA_PACKAGE_DIR}/${KAFKA_ARCHIVE}"
  local checksum_path="${archive_path}.sha512"
  local expected_sha512
  local actual_sha512

  mkdir -p "$KAFKA_PACKAGE_DIR"

  if [[ ! -f "$archive_path" ]]; then
    curl -fL "$KAFKA_URL" -o "${archive_path}.part"
    mv "${archive_path}.part" "$archive_path"
  fi

  curl -fL "${KAFKA_URL}.sha512" -o "${checksum_path}.part"
  mv "${checksum_path}.part" "$checksum_path"

  # Apache의 공백으로 나뉜 SHA-512 표현을 하나의 128자리 해시로 만든다.
  expected_sha512="$(grep -Eo '[A-Fa-f0-9]{8}' "$checksum_path" | tr -d '\n')"
  actual_sha512="$(sha512sum "$archive_path" | awk '{ print toupper($1) }')"

  [[ ${#expected_sha512} -eq 128 ]] || die "공식 SHA-512 파일 형식이 올바르지 않습니다."
  [[ "$actual_sha512" == "$expected_sha512" ]] \
    || die "${KAFKA_ARCHIVE} SHA-512 검증에 실패했습니다."
}

install_kafka_distribution() {
  if [[ ! -d "$KAFKA_VERSION_DIR" ]]; then
    tar -xzf "${KAFKA_PACKAGE_DIR}/${KAFKA_ARCHIVE}" -C "$HOME"
  fi

  [[ -x "${KAFKA_VERSION_DIR}/bin/kafka-storage.sh" ]] \
    || die "Kafka 4.3.1 설치 디렉터리가 올바르지 않습니다: ${KAFKA_VERSION_DIR}"

  # 일반 디렉터리를 심볼릭 링크로 덮어쓰지 않는다.
  if [[ -e "$KAFKA_HOME" && ! -L "$KAFKA_HOME" ]]; then
    die "${KAFKA_HOME}가 심볼릭 링크가 아닌 경로로 이미 존재합니다."
  fi

  ln -sfn "$KAFKA_VERSION_DIR" "$KAFKA_HOME"
}

write_environment_file() {
  local temporary_env_file

  # 사용자가 직접 만든 환경 파일을 덮어쓰지 않는다.
  if [[ -f "$KAFKA_ENV_FILE" ]] && ! grep -qF "$ENV_MARKER" "$KAFKA_ENV_FILE"; then
    die "${KAFKA_ENV_FILE}는 스크립트가 관리하는 파일이 아닙니다. 내용을 확인한 뒤 다시 실행하세요."
  fi

  temporary_env_file="$(mktemp "${HOME}/.kafka-env.XXXXXX")"
  {
    printf '%s\n' "$ENV_MARKER"
    printf 'export JAVA_HOME=%q\n' "$JAVA_HOME"
    printf 'export KAFKA_HOME=%q\n' "$KAFKA_HOME"
    printf 'export PATH="\$JAVA_HOME/bin:\$KAFKA_HOME/bin:\$PATH"\n'
  } > "$temporary_env_file"
  mv "$temporary_env_file" "$KAFKA_ENV_FILE"

  touch "${HOME}/.bashrc"
  if ! grep -qF 'source ~/.kafka-env' "${HOME}/.bashrc"; then
    printf '\nsource ~/.kafka-env\n' >> "${HOME}/.bashrc"
  fi
}

verify_installation() {
  # 현재 실행 프로세스에도 생성한 환경 변수를 적용한다.
  # shellcheck disable=SC1090
  source "$KAFKA_ENV_FILE"

  "$JAVA_HOME/bin/java" -version
  echo "KAFKA_HOME=$KAFKA_HOME"
  "$KAFKA_HOME/bin/kafka-storage.sh" random-uuid >/dev/null
  echo "Kafka ${KAFKA_VERSION} 설치와 환경 변수 설정을 완료했습니다."
}

main() {
  install_or_resolve_java
  download_and_verify_kafka
  install_kafka_distribution
  write_environment_file
  verify_installation
}

main "$@"
