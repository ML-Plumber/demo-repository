# Spark 세팅

1. `~/spark-4.2.0`에 Spark 4.2.0을 다운로드하고 압축을 해제한다.
2. Java 17을 확인한다.
3. Java가 없으면 설치하고, 있으면 Java 17 경로를 `~/.bashrc`의 `JAVA_HOME`, `PATH`에 지정한다.
4. `source ~/.bashrc`를 실행한다.
5. `conf/spark-env.sh`에 아래 값을 지정한다.

   - `JAVA_HOME`
   - `PYSPARK_PYTHON`
   - `PYSPARK_DRIVER_PYTHON`
   - `SPARK_LOCAL_IP`
   - `SPARK_WORKER_CORES`
   - `SPARK_WORKER_MEMORY`
   - `SPARK_DAEMON_MEMORY`

6. 스크립트화할 경우 실패한 명령과 원인만 출력하고 즉시 종료한다.
