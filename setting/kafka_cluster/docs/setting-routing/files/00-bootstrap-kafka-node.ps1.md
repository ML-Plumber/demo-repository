# kafka_setting/srcs/00-bootstrap-kafka-node.ps1

## 책임

- Windows PowerShell에서 WSL Ubuntu, Linux 사용자, JDK 17, Kafka 4.3.1을 한 번에 준비한다.
- WSL 설치에 재시작이 필요하면 RunOnce에 재개 명령을 등록한다.
- Kafka 바이너리 kafka_2.13-4.3.1.tgz를 Linux 사용자의 홈에 설치하고 ~/kafka 링크를 만든다.
- 클러스터 인벤토리, 네트워크 포워딩, KRaft 설정·포맷·기동은 처리하지 않는다.

## 입력

| 파라미터 | 기본값 | 용도 |
| --- | --- | --- |
| Distribution | Ubuntu | 설치할 WSL 배포판 |
| LinuxUser | 정제한 Windows 사용자명 | Kafka 파일을 소유할 Linux 사용자 |
| RestartIfRequired | 해제 | WSL 설치 뒤 자동 재시작 여부 |
| ResumeAfterRestart | 내부 사용 | RunOnce 재개 상태값 |

## 호출 구조

\`\`\`text
PowerShell 시작
  -> 관리자 권한 확인과 UAC 재실행
  -> Ensure-Wsl
       -> wsl --install --distribution Ubuntu
       -> 재시작 필요 시 RunOnce 등록
  -> Invoke-WslKafkaInstall
       -> root: Linux 사용자 생성, JDK 17 설치
       -> 일반 사용자: Kafka 4.3.1 다운로드·검증·설치
  -> RunOnce 재개 항목 제거
\`\`\`

## WSL 내부 처리

\`\`\`text
1. Java 17 실행 파일을 찾고 JAVA_HOME을 계산한다.
2. kafka_2.13-4.3.1.tgz와 공식 SHA-512 파일을 내려받는다.
3. 해시값이 다르면 즉시 종료한다.
4. ~/kafka_2.13-4.3.1에 압축을 해제하고 ~/kafka 링크를 만든다.
5. ~/.kafka-env에 JAVA_HOME, KAFKA_HOME, PATH를 기록한다.
6. ~/.bashrc에 source ~/.kafka-env를 없을 때만 추가한다.
7. Java와 kafka-storage.sh를 실행해 경로를 확인한다.
\`\`\`

## 실행

\`\`\`powershell
# 관리자 권한 요청과 필요 시 재시작 뒤 자동 재개까지 수행합니다.
.\00-bootstrap-kafka-node.ps1 -RestartIfRequired
\`\`\`

Windows 재시작은 열려 있는 작업을 종료할 수 있다. RestartIfRequired 없이 실행하면 재개 명령만 등록하고 재시작 필요 사실을 표시한다. 재시작 후 로그인하면 같은 파일이 자동으로 다시 실행된다.
