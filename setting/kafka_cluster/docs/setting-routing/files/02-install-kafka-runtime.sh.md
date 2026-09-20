# `kafka_setting/srcs/02-install-kafka-runtime.sh`

## 책임

- WSL Linux 사용자의 홈 디렉터리에 Java 17 이상과 Apache Kafka 4.3.1을 준비한다.
- `kafka_2.13-4.3.1.tgz` 다운로드의 SHA-512을 검증한 뒤에만 압축을 해제한다.
- `~/kafka` 심볼릭 링크와 `~/.kafka-env`를 생성하고, `.bashrc`에 환경 파일을 한 번만 연결한다.
- Kafka 클러스터 설정, KRaft 저장소 포맷, 네트워크·방화벽 변경, Kafka 프로세스 기동은 담당하지 않는다.

## 호출 구조

```text
main
  -> install_or_resolve_java
  -> download_and_verify_kafka
  -> install_kafka_distribution
  -> write_environment_file
  -> verify_installation
```

## 주요 상수와 경로

| 항목 | 값 | 용도 |
| --- | --- | --- |
| `KAFKA_VERSION` | `4.3.1` | 설치할 Kafka 버전 |
| `KAFKA_SCALA_VERSION` | `2.13` | 바이너리 아카이브 식별자 |
| `KAFKA_ARCHIVE` | `kafka_2.13-4.3.1.tgz` | 공식 다운로드·검증 대상 |
| `KAFKA_PACKAGE_DIR` | `~/packages` | 다운로드 아카이브와 체크섬 파일 경로 |
| `KAFKA_VERSION_DIR` | `~/kafka_2.13-4.3.1` | 압축 해제된 Kafka 경로 |
| `KAFKA_HOME` | `~/kafka` | Kafka 실행에 사용하는 고정 심볼릭 링크 |
| `KAFKA_ENV_FILE` | `~/.kafka-env` | `JAVA_HOME`, `KAFKA_HOME`, `PATH` 환경 파일 |

## 처리 의사코드

```text
main()
  install_or_resolve_java()
    기본 java의 실제 경로를 readlink -f와 which java로 확인한다.
    Java가 없거나 17 미만이면 openjdk-17-jdk를 설치한다.
    JDK 17 실행 파일을 찾아 JAVA_HOME으로 계산하고 17 이상인지 검증한다.

  download_and_verify_kafka()
    ~/packages에 kafka_2.13-4.3.1.tgz를 내려받는다.
    공식 .sha512 파일에서 기대 해시를 읽는다.
    sha512sum 결과가 기대값과 다르면 오류를 출력하고 종료한다.

  install_kafka_distribution()
    ~/kafka_2.13-4.3.1이 없을 때만 아카이브를 ~/에 압축 해제한다.
    ~/kafka가 일반 디렉터리면 종료한다.
    ~/kafka를 버전별 설치 경로로 가리키는 심볼릭 링크로 만든다.

  write_environment_file()
    기존 ~/.kafka-env가 스크립트 관리 파일인지 검사한다.
    JAVA_HOME, KAFKA_HOME, PATH를 ~/.kafka-env에 원자적으로 기록한다.
    ~/.bashrc에 source ~/.kafka-env가 없을 때만 추가한다.

  verify_installation()
    ~/.kafka-env를 현재 세션에 적용한다.
    Java 버전, KAFKA_HOME, kafka-storage.sh 실행 가능 여부를 확인한다.
```

## 실패 처리

- `set -Eeuo pipefail`과 오류 trap으로 명령 실패 시 종료한다.
- 다운로드 중인 임시 파일은 `.part` 확장자를 사용하므로 중간 실패 결과를 아카이브로 사용하지 않는다.
- 체크섬 길이 또는 값이 다르면 압축을 해제하지 않는다.
- 사용자가 만든 `~/.kafka-env`와 `~/kafka` 일반 디렉터리를 자동으로 덮어쓰지 않는다.
