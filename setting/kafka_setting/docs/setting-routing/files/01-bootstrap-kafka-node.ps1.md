# kafka_setting/srcs/01-bootstrap-kafka-node.ps1

## 책임

- Windows PowerShell에서 WSL Ubuntu, Linux 사용자, JDK 17, Kafka 4.3.1을 한 번에 준비한다.
- WSL 설치에 재시작이 필요하면 로그인 트리거 작업 스케줄러에 재개 명령을 등록한다.
- Kafka 바이너리 kafka_2.13-4.3.1.tgz를 Linux 사용자의 홈에 설치하고 ~/kafka 링크를 만든다.
- 클러스터 인벤토리, 네트워크 포워딩, KRaft 설정·포맷·기동은 처리하지 않는다.

## 입력

| 파라미터 | 기본값 | 용도 |
| --- | --- | --- |
| Distribution | Ubuntu | 설치할 WSL 배포판 |
| LinuxUser | 정제한 Windows 사용자명 | Kafka 파일을 소유할 Linux 사용자 |
| RestartIfRequired | 해제 | WSL 설치 뒤 자동 재시작 여부 |
| ResumeAfterRestart | 내부 사용 | 재시작 뒤 작업 스케줄러 재개 상태값 |

## 호출 구조

\`\`\`text
PowerShell 시작
  -> 관리자 권한 확인과 UAC 재실행
  -> Ensure-Wsl
       -> --no-launch 지원 여부 확인
       -> wsl --install --distribution Ubuntu --no-launch
       -> root 명령으로 WSL 준비 상태 확인
       -> 재시작 필요 시 로그인 트리거 작업 등록
  -> Invoke-WslKafkaInstall
       -> root: Linux 사용자 생성, JDK 17 설치
       -> 일반 사용자: Kafka 4.3.1 다운로드·검증·설치
  -> 재개 작업 제거
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

새 Ubuntu 설치에서는 `--no-launch`를 사용하므로 사용자명·비밀번호를 묻는 대화형 셸을 열지 않는다. root 설치 단계가 `LinuxUser`를 만들거나 기존 계정을 재사용한다. 현재 WSL이 `--no-launch`를 지원하지 않으면 대화형 셸을 열어 PowerShell 흐름을 막는 대신, WSL 업데이트가 필요하다는 오류를 표시하고 중단한다.

## 실행

\`\`\`powershell
# 저장소 루트에서 관리자 권한 요청과 필요 시 재시작 뒤 자동 재개까지 수행합니다.
.\setting\kafka_setting\srcs\01-bootstrap-kafka-node.ps1 -RestartIfRequired
\`\`\`

`wsl --list`에 Ubuntu가 보이는 것만으로는 설치가 끝난 것이 아니다. 이 스크립트는 root Linux 명령이 실행될 때만 Kafka 설치를 진행한다. 재시작이 필요한 경우 로그인 트리거 작업을 먼저 등록한다.

Windows 재시작은 열려 있는 작업을 종료할 수 있다. `RestartIfRequired` 없이 실행하면 재개 작업만 등록하고 재시작 필요 사실을 표시한다. Windows를 재시작한 뒤 같은 계정으로 로그인하면 관리자 권한으로 Kafka 설치가 자동 재개된다. 재개 전에는 스크립트의 위치를 변경하거나 삭제하지 않는다.

이전 `00-bootstrap-kafka-node.ps1`로 Ubuntu 사용자 생성 화면이 이미 열린 상태라면 그 셸에서 `exit`으로 PowerShell로 돌아온 뒤, 위 `01` 스크립트를 다시 실행한다. 이미 만든 Ubuntu 계정을 Kafka 파일 소유자로 계속 사용할 경우에는 `-LinuxUser <만든_사용자명>`을 함께 지정한다.
