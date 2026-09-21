# Spark 라우팅

## 책임

WSL에 Spark 실행 환경을 설치하고 설정하는 파일별 문서로 연결한다.

## 계층별 호출 구조

```text
Spark 설정
└─ setup-spark.sh <미러링_IP>
   ├─ Spark 4.2.0 설치
   ├─ Java 17 확인 및 설치
   ├─ 사용자 셸 환경 변수 설정
   └─ Spark 실행 환경 변수 설정
```

- [setup-spark.sh 파일 문서](files/srcs/setup-spark.sh.md)

## 함수와 메서드

### `find_java17_home()`

```text
입력: 없음
처리: Java 17 설치 경로를 찾아 반환하고 없으면 실패 반환
외부 호출: java, readlink
```

### `set_export(file, key, value)`

```text
입력: 대상 파일, 환경 변수 이름, 환경 변수 값
처리: 같은 값은 유지하고 다른 값은 갱신하며 없는 값은 추가
외부 호출: grep, sed
```

## 변수와 상수

- `SPARK_HOME`: 사용자 홈을 기준으로 한 `spark-4.2.0` 경로다.
- `SPARK_ARCHIVE`: 사용자 홈을 기준으로 한 Spark 압축 파일 경로다.
- `SPARK_URL`: Spark 4.2.0 Hadoop 3 배포 파일 주소다.
- `JAVA_HOME`: Java 17 탐색 또는 설치 결과에서 가져온 경로다.
- `PYSPARK_PYTHON`: 시스템의 `python3` 실행 파일에서 가져온 경로다.
- `SPARK_LOCAL_IP`: 실행 인자로 전달받은 미러링 IP다.
- `WORKER_CORES`: `nproc` 결과에서 가져온 코어 수다.
- `WORKER_MEMORY`: 시스템 전체 메모리에서 1GiB를 제외한 값이다.
- `SPARK_DAEMON_MEMORY`: `1g` 값을 가진다.
