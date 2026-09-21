# `setting/spark/srcs/setup-spark.sh`

## 책임

Spark 4.2.0 설치, Java 17 확인·설치, `.bashrc` 환경 변수 설정, `spark-env.sh` 환경 변수 설정을 담당한다. Spark 마스터·워커 실행은 담당하지 않는다.

## 호출 구조

```text
setup-spark.sh <미러링_IP>
├─ 미러링 IP 확인
├─ Spark 4.2.0 설치 여부 확인
├─ find_java17_home
├─ set_export (.bashrc)
├─ source ~/.bashrc
├─ set_export (spark-env.sh)
└─ spark-env.sh 실행 권한 설정
```

## 입력값

### `<미러링_IP>`

- 값: WSL에 미러링된 현재 노드의 IPv4 주소
- 사용처: `SPARK_LOCAL_IP`
- 검증: WSL의 IPv4 주소 목록에 존재해야 한다.

## 함수와 메서드

### `find_java17_home()`

```text
처리:
  /usr/lib/jvm/java-17-* 경로에서 Java 17 실행 파일 탐색
  Java 17 홈 경로 출력
  없으면 실패 반환
외부 호출:
  java -version
  readlink -f
```

### `set_export(file, key, value)`

```text
입력: 대상 파일, 환경 변수 이름, 환경 변수 값
처리:
  동일한 export 문이 있으면 건너뜀
  같은 키의 값이 다르면 해당 줄 갱신
  키가 없으면 export 문 추가
외부 호출:
  grep
  sed
```

## 변수와 상수

- `SPARK_HOME`: `$HOME/spark-4.2.0`
- `SPARK_ARCHIVE`: `$HOME/spark-4.2.0-bin-hadoop3.tgz`
- `SPARK_URL`: Spark 4.2.0 Hadoop 3 배포 파일 주소
- `JAVA_HOME`: 탐색하거나 설치한 Java 17 홈 경로
- `PYSPARK_PYTHON`: `python3` 실행 파일 경로
- `SPARK_LOCAL_IP`: 실행 인자로 전달한 미러링 IP
- `WORKER_CORES`: `nproc` 결과
- `WORKER_MEMORY`: 전체 메모리에서 1GiB를 제외한 값
- `SPARK_DAEMON_MEMORY`: `1g`

## 외부 호출

- `curl`, `tar`, `mv`: Spark 설치 파일 다운로드와 압축 해제
- `sudo apt-get`: Java 17 설치
- `source ~/.bashrc`: 현재 셸 환경 변수 반영
- `cp`, `chmod`: `spark-env.sh` 생성과 실행 권한 설정
