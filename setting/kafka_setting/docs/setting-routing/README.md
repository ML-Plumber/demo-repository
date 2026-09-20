# Kafka 설정 스크립트 라우팅

## 1. 문서 목적

이 문서는 `setting/kafka_setting/README.md`의 클러스터 구성 계획을 실제 실행 파일로 나눌 때 사용하는 통합 라우팅 문서다. 이 문서만 읽어도 다음 내용을 구분할 수 있어야 한다.

- 현재 실제로 구현된 스크립트와 아직 계획만 있는 스크립트
- Windows PowerShell, WSL/Linux, Kafka 계층별 책임
- 전체 실행 순서와 단계 사이에 전달되는 값
- 각 스크립트가 알아야 하는 범위와 알지 않아야 하는 범위
- `srcs` 실행 파일과 `docs/setting-routing/files` 문서의 1:1 대응 관계

상위 계획의 범위는 WSL과 Kafka 실행 환경 준비, 네트워크 준비, 인벤토리 검증, KRaft 설정 생성, 저장소 초기화, 프로세스 기동, 원격 연결 및 등록 검사까지다. 토픽 생성, 파티션·복제 계수, 보존 정책, 프로듀서·컨슈머 설정은 포함하지 않는다.

## 2. 현재 구현 상태

현재 실제 실행 가능한 파일은 `srcs/01-bootstrap-kafka-node.ps1` 하나다. 이 파일은 WSL Ubuntu, Linux 사용자, Java 17, Kafka 4.3.1 설치까지만 담당한다. 네트워크 포워딩, 방화벽, 클러스터 인벤토리, Kafka 설정 생성, 저장소 포맷, controller·broker 기동과 클러스터 검사는 아직 구현되지 않았다.

따라서 현재 상태에서 `01-bootstrap-kafka-node.ps1` 실행 성공은 **Kafka 런타임 준비 완료**를 뜻하며, **Kafka 클러스터 구성 완료**를 뜻하지 않는다.

파일 내부 예시와 대응 문서는 실제 파일명인 `01-bootstrap-kafka-node.ps1`로 일치한다.

## 3. 파일과 문서의 1:1 규칙

모든 `srcs` 파일은 다음 규칙으로 문서 하나와 정확히 대응한다.

```text
srcs/<실행 파일 상대경로>
<->
docs/setting-routing/files/<실행 파일 상대경로>.md
```

예시:

```text
srcs/01-bootstrap-kafka-node.ps1
<->
docs/setting-routing/files/01-bootstrap-kafka-node.ps1.md
```

실행 파일을 추가·이동·삭제하면 같은 작업에서 대응 문서도 추가·이동·삭제한다. 통합 README는 전체 순서와 단계 간 계약만 설명하고, 함수 내부의 세부 의사코드는 해당 파일 문서에 둔다.

## 4. 목표 파일 구성과 구현 순서

아래 순서는 상위 README의 실행 순서를 기능별 스크립트로 나눈 목표 구조다. `구현됨`으로 표시된 항목만 현재 저장소에 존재한다.

| 순서 | 실행 파일 | 대응 문서 | 상태 | 책임 |
| --- | --- | --- | --- | --- |
| 00 | `srcs/00-run-kafka-node-setup.ps1` | `files/00-run-kafka-node-setup.ps1.md` | 계획 | 한 번의 Windows 실행으로 전체 단계를 순서대로 호출하고 재시작 후 이어서 실행 |
| 01 | `srcs/01-bootstrap-kafka-node.ps1` | `files/01-bootstrap-kafka-node.ps1.md` | 구현됨 | WSL, Linux 사용자, Java 17, Kafka 4.3.1 설치와 경로 고정 |
| 02 | `srcs/02-prepare-kafka-network.ps1` | `files/02-prepare-kafka-network.ps1.md` | 구현됨 | WSL 네트워크 모드 확인·적용, NAT 포트 전달, Windows·Hyper-V 방화벽 준비 |
| 03 | `srcs/03-validate-kafka-inventory.sh` | `files/03-validate-kafka-inventory.sh.md` | 계획 | 현재 서버 식별, 역할·ID·주소·포트·데이터 경로 검증, 로컬 프로세스 행 선택 |
| 04 | `srcs/04-render-kafka-config.sh` | `files/04-render-kafka-config.sh.md` | 계획 | 검증된 인벤토리로 controller·broker별 Kafka 설정 파일 생성 |
| 05 | `srcs/05-format-kafka-storage.sh` | `files/05-format-kafka-storage.sh.md` | 계획 | 공통 cluster ID 검증과 신규 저장소의 안전한 1회 포맷 |

계획 파일은 해당 실행 파일을 실제로 만들 때 같은 작업에서 대응 문서를 생성한다. 통합 README에 이름이 있다는 이유만으로 구현된 것으로 취급하지 않는다.

## 5. 전체 계층과 호출 구조

```text
사용자: Windows PowerShell에서 00 실행
  -> 통합 실행 계층: 00-run-kafka-node-setup.ps1
       -> 현재 단계와 재시작 상태만 관리
       -> 01-bootstrap-kafka-node.ps1
            -> Windows/WSL 런타임 계층
            -> WSL + Java 17 + Kafka 4.3.1 준비
       -> 02-prepare-kafka-network.ps1
            -> Windows/WSL 네트워크 계층
            -> 외부 도달 주소와 포트 경로 준비
       -> WSL에서 03-validate-kafka-inventory.sh
            -> 클러스터 입력 계층
            -> 공통 인벤토리 검증 + 현재 노드 행 선택
       -> WSL에서 04-render-kafka-config.sh
            -> Kafka 설정 계층
            -> 프로세스별 server.properties 생성
       -> WSL에서 05-format-kafka-storage.sh
            -> Kafka 저장소 계층
            -> cluster ID 대조 + 신규 저장소 포맷
       -> WSL에서 06-manage-kafka-processes.sh
            -> Kafka 실행 계층
            -> controller/broker prepare + start + status
       -> WSL에서 07-check-kafka-cluster.sh
            -> 검증 계층
            -> TCP + quorum + broker 등록 검사
```

각 계층은 바로 이전 단계의 출력과 자신의 입력만 안다. 예를 들어 네트워크 계층은 Kafka properties 파일 형식을 알지 않고, 설정 생성 계층은 Windows 방화벽 명령을 실행하지 않으며, 검증 계층은 토픽이나 데이터를 변경하지 않는다.

## 6. 단계 사이의 공통 값

| 이름 | 값 또는 출처 | 사용하는 단계 |
| --- | --- | --- |
| `Distribution` | 사용자 입력, 기본값 `Ubuntu` | 00, 01, 02 |
| `LinuxUser` | 사용자 입력 또는 정제한 Windows 사용자명 | 00, 01 |
| `KAFKA_VERSION` | 고정값 `4.3.1` | 01, 04~07 |
| `KAFKA_ARCHIVE` | `kafka_2.13-4.3.1.tgz` | 01 |
| `JAVA_HOME` | WSL에서 선택한 Java 17 이상 실제 경로 | 01이 `~/.kafka-env`에 저장, 04~07이 사용 |
| `KAFKA_HOME` | WSL 사용자 홈의 `~/kafka` 심볼릭 링크 | 01이 생성, 04~07이 사용 |
| `InventoryPath` | 사용자가 모든 노드에 동일하게 배포한 인벤토리 경로 | 00, 02~07 |
| `EnvironmentMode` | 사용자 입력과 감지 결과를 대조한 `wsl-nat` 또는 `wsl-mirrored` | 02, 03, 07 |
| `ClusterIdPath` | 한 번 생성한 공통 cluster ID 파일 경로 | 00, 05~07 |
| `GeneratedConfigDir` | 04가 생성한 프로세스별 설정 디렉터리 | 04~07 |
| `StatePath` | 00이 재시작 전후 진행 단계를 기록하는 Windows 로컬 상태 파일 | 00 |

`node_id`, 역할, 바인드 주소, 외부 도달 주소, 포트와 데이터 경로는 자동 계산하지 않고 공통 인벤토리에서 읽는다. IP 끝자리나 파일 행 순서로 ID를 만들지 않는다.

## 7. 파일별 라우팅 명세

### 7.1 `00-run-kafka-node-setup.ps1` — 통합 실행 계층

상태: 계획.

책임:

- 사용자가 직접 실행하는 단일 Windows 진입점이다.
- 기능 스크립트를 01부터 07까지 순서대로 호출한다.
- WSL 또는 네트워크 모드 적용에 Windows 재시작이 필요하면 현재 단계를 저장하고 로그인 후 같은 단계부터 재개한다.
- 하위 스크립트의 설치·검증 로직을 직접 구현하지 않는다.

주요 값:

| 이름 | 값 또는 출처 |
| --- | --- |
| `InventoryPath` | 필수 사용자 입력 |
| `Distribution` | 사용자 입력, 기본값 `Ubuntu` |
| `LinuxUser` | 선택 사용자 입력 |
| `RestartIfRequired` | 자동 Windows 재시작 허용 여부 |
| `StatePath` | `%ProgramData%` 아래 이 스크립트 전용 상태 파일 |
| `CurrentStep` | 상태 파일에서 읽거나 최초 실행 시 `01` |

함수 의사코드:

```text
main(InventoryPath, Distribution="Ubuntu", LinuxUser=null, RestartIfRequired=false)
  입력 경로와 관리자 권한 검사
  state = Load-State(StatePath)
  FOR step IN state.CurrentStep .. 07
    result = Invoke-Step(step, 공통 입력)
    IF result.RestartRequired
      Save-State(StatePath, step)
      Register-ResumeTask(현재 스크립트, 동일 파라미터)
      RestartIfRequired이면 Restart-Computer 호출
      종료
    IF result.Failed
      실패 단계와 종료 코드를 보존하고 종료
    Save-State(StatePath, step + 1)
  Remove-ResumeTask()
  Remove-State()

Load-State(StatePath) -> 진행 단계와 입력 해시
  상태 파일이 없으면 최초 상태 반환
  상태 파일의 인벤토리 경로·입력 해시가 현재 실행과 다르면 중단
  외부 호출 없음

Invoke-Step(StepNumber, CommonArguments) -> StepResult
  단계 번호에 대응하는 실제 스크립트 경로 확인
  PowerShell 단계는 powershell.exe로 호출
  Linux 단계는 wsl.exe -d <Distribution> --user <LinuxUser> -- bash로 호출
  종료 코드와 재시작 필요 상태 반환

Register-ResumeTask(ScriptPath, Arguments)
  로그인 트리거와 최고 권한으로 Windows 작업 스케줄러 등록
  외부 호출: New-ScheduledTaskAction, New-ScheduledTaskTrigger,
             New-ScheduledTaskPrincipal, Register-ScheduledTask
```

다음 단계로 전달: 배포판, Linux 사용자, 인벤토리 경로, 재시작 이후 이어갈 단계.

### 7.2 `01-bootstrap-kafka-node.ps1` — WSL·런타임 계층

상태: 구현됨.

책임:

- WSL 배포판을 확인하고 없으면 설치한다.
- 새 배포판은 `--no-launch`로 설치해 Ubuntu 최초 사용자 설정 셸이 PowerShell 흐름을 붙잡지 않게 한다.
- WSL이 이미 설치되고 root 명령 실행이 가능하면 WSL 설치를 건너뛴다.
- Linux 사용자를 준비하고 Java 17과 Kafka 4.3.1을 설치한다.
- `~/kafka`, `~/.kafka-env`, `~/.bashrc`를 준비한다.
- 클러스터 인벤토리, 포트 전달, Kafka 설정·포맷·기동은 알지 않는다.

입력 파라미터:

| 시그니처 | 기본값 | 의미 |
| --- | --- | --- |
| `Distribution: string` | `Ubuntu` | 사용할 WSL 배포판 |
| `LinuxUser: string` | 정제한 Windows 사용자명 | Kafka 파일 소유 Linux 사용자 |
| `RestartIfRequired: switch` | 해제 | 필요한 경우 Windows 자동 재시작 |
| `ResumeAfterRestart: switch` | 해제 | 작업 스케줄러가 사용하는 내부 재개 상태 |

주요 상수·변수:

| 이름 | 값 또는 출처 |
| --- | --- |
| `$resumeTaskName` | `KafkaBootstrapResume` |
| `kafka_version` | `4.3.1` |
| `kafka_scala_version` | `2.13` |
| `kafka_archive` | `kafka_2.13-4.3.1.tgz` |
| `kafka_url` | Apache 다운로드 서버 |
| `java_home` | `update-alternatives`와 `readlink -f` 결과 |
| `target_home` | `getent passwd <LinuxUser>` 결과 |

함수 의사코드:

```text
Test-Administrator() -> bool
  현재 Windows identity가 Administrators 역할인지 반환
  외부 호출 없음

Get-DefaultLinuxUser() -> string
  Windows USERNAME을 소문자로 바꾸고 Linux 사용자명 허용 문자만 유지
  값이 비면 "kafka" 반환

Assert-LinuxUser(Name)
  Name이 Linux 사용자명 규칙과 맞지 않으면 예외
  외부 호출 없음

Test-WslDistribution(Name) -> bool
  wsl.exe --list --quiet 결과에 Name이 있는지 확인
  외부 호출: wsl.exe

Assert-WslInstallSupportsNoLaunch()
  wsl.exe --help 출력의 NUL 문자를 제거한 뒤 --no-launch 옵션이 있는지 확인
  정상 도움말에도 -1을 반환할 수 있으므로 종료 코드 대신 도움말 내용만 판정
  없으면 대화형 최초 실행을 피할 수 없으므로 WSL 업데이트 안내와 함께 중단
  외부 호출: wsl.exe

Test-WslReady(Name, RetryCount=36, RetryDelaySeconds=5) -> bool
  root로 /bin/sh -c "exit 0" 실행
  실패하면 지정 횟수만큼 대기 후 재시도
  외부 호출: wsl.exe, Start-Sleep

Register-Resume(ScriptPath, DistroName, TargetLinuxUser)
  동일 인자를 포함한 PowerShell 재개 명령 생성
  로그인 시 최고 권한으로 실행되는 작업 등록
  외부 호출: Windows ScheduledTasks cmdlet

Remove-Resume()
  KafkaBootstrapResume 작업이 있으면 제거
  외부 호출: Unregister-ScheduledTask

Request-WslRestart(DistroName, TargetLinuxUser)
  재개 작업 등록
  RestartIfRequired이면 Windows 재시작, 아니면 수동 재시작 안내
  외부 호출: Register-Resume, Restart-Computer

Ensure-Wsl(DistroName, TargetLinuxUser) -> bool
  배포판 존재 + root 명령 성공이면 true
  배포판이 없으면 --no-launch 지원을 확인하고
  wsl.exe --install --distribution <이름> --no-launch 실행
  즉시 준비되지 않으면 재개 작업을 등록하고 false
  외부 호출: Test-WslDistribution, Assert-WslInstallSupportsNoLaunch, Test-WslReady,
             Register-Resume, Request-WslRestart, wsl.exe

Invoke-WslKafkaInstall(DistroName, TargetLinuxUser)
  PowerShell here-string의 CRLF를 LF로 정규화한 Bash 입력을 root WSL에 전달
  root Bash로 Linux 사용자 생성과 apt 패키지 설치
  Java 17 실제 경로 계산
  일반 사용자 Bash로 Kafka 다운로드, Apache SHA-512의 8자리 블록을 128자리 값으로 합쳐 검증, 압축 해제
  ~/kafka 링크와 환경 파일 생성 후 kafka-storage.sh 실행 확인
  외부 호출: wsl.exe, bash, apt-get, curl, sha512sum, tar,
             useradd, runuser, update-alternatives

script-main()
  LinuxUser 기본값 계산과 검증
  관리자가 아니면 UAC로 같은 스크립트 재실행
  Ensure-Wsl이 true일 때만 Invoke-WslKafkaInstall 실행
  성공하면 재개 작업 제거
```

다음 단계로 전달: 실행 가능한 WSL 배포판, Linux 사용자, `JAVA_HOME`, `KAFKA_HOME=~/kafka`.

통합 실행 전 필요한 변경: 현재 01이 자체 재개 작업을 소유하고 종료 코드 `0`으로 중단될 수 있으므로, 00이 전체 단계를 정확히 재개하려면 재시작 필요 상태를 명시적으로 반환하도록 계약을 조정해야 한다. 재개 작업 소유자는 최종적으로 00 한 곳으로 모은다.

### 7.3 `02-prepare-kafka-network.ps1` — Windows·WSL 네트워크 계층

상태: 구현됨.

책임:

- 기본 `mirrored` 또는 사용자가 지정한 `nat`를 `.wslconfig`에 적용하고 실제 적용 모드를 비교한다.
- `nat`이면 기본 Kafka 포트의 portproxy와 Windows 방화벽을 준비한다.
- `mirrored`이면 기존 `.wslconfig`를 보존하면서 Windows·Hyper-V 방화벽을 준비한다.
- Kafka 설정 파일을 만들거나 프로세스를 시작하지 않는다.

주요 입력·값:

| 이름 | 값 또는 출처 |
| --- | --- |
| `NetworkingMode` | 기본 `mirrored`; `--networking-mode nat` 또는 `-NetworkingMode nat`로 변경 |
| `Distribution` | 사용자 입력, 기본 `Ubuntu` |
| `KafkaPorts` | 기본 broker/controller 포트 `9092, 9093` |
| `PeerIps` | 기본 `LocalSubnet`; 확정 후 peer IPv4 또는 CIDR로 제한 |
| `WindowsLanIp` | 지정 NIC 또는 명시적 사용자 입력 |
| `WslIp` | `wsl -d <Distribution> -- hostname -I` 결과 중 검증된 IPv4 |
| `ResultPath` | 기본 `%ProgramData%\KafkaCluster\network-result.json` |

함수 의사코드:

```text
Resolve-GnuNetworkingMode(CurrentMode, Arguments) -> mode
  --networking-mode <mode>와 --networking-mode=<mode> 해석
  mirrored 또는 nat가 아니면 중단

Assert-MirroredModeSupport()
  Windows build 22621 이상과 Hyper-V 방화벽 cmdlet 확인
  외부 호출: Windows registry, Get-Command

Set-WslNetworkingMode(ConfigPath, Mode) -> changed
  기존 .wslconfig의 다른 값 보존
  [wsl2] networkingMode만 추가 또는 교체
  최초 변경 시 백업하고 임시 파일을 원자적으로 교체

Get-WslNetworkingMode(Distribution) -> mode
  WSL 내부 wslinfo --networking-mode 결과 반환
  조회 실패나 요청 모드 불일치 시 중단
  외부 호출: wsl.exe, wslinfo

Get-WindowsLanIpv4(RequestedAddress) -> IPv4
  명시 주소를 검증하거나 기본 gateway가 있는 활성 인터페이스에서 감지
  외부 호출: Get-NetIPAddress, Get-NetIPConfiguration

Get-WslIpv4(Distribution) -> IPv4
  기본 IPv4 route의 src 주소를 NAT 전달 대상으로 반환
  외부 호출: wsl.exe, ip route

Resolve-PeerAddresses(Addresses, LanIp) -> addresses
  LocalSubnet을 Windows LAN IP와 prefix에서 계산한 실제 CIDR로 변환
  외부 호출: Get-NetIPAddress

Ensure-WindowsFirewallRule(Port, LocalAddress, RemoteAddresses)
  스크립트 소유 이름의 규칙을 중복 없이 생성·갱신
  외부 호출: Get/Remove/New-NetFirewallRule

Ensure-HyperVFirewallRule(Port, RemoteAddresses)
  mirrored 모드의 WSL Hyper-V 규칙 생성·갱신
  외부 호출: Get/Remove/New-NetFirewallHyperVRule

Ensure-NatPortProxy(ListenAddress, ListenPort, ConnectAddress, ConnectPort)
  nat 모드의 v4tov4 규칙을 정확한 WSL 주소로 재생성
  외부 호출: netsh interface portproxy delete/add

Write-NetworkResult(Path, Mode, ReportedMode, LanIp, LinuxIp)
  적용 결과를 임시 JSON에 쓴 뒤 최종 경로로 이동

script-main()
  GNU 인자와 일반 PowerShell 인자 해석
  필요 시 같은 인자로 UAC 재실행
  .wslconfig 변경 시 wsl --shutdown
  실제 적용 모드 확인
  Windows 방화벽 공통 적용
  mirrored면 Hyper-V 방화벽, nat면 IP Helper와 portproxy 적용
  03이 읽을 network-result.json 저장
```

다음 단계로 전달: `network-result.json`의 실제 모드, Windows LAN 주소, NAT의 WSL 주소, 포트, peer 범위와 portproxy 매핑.

### 7.4 `03-validate-kafka-inventory.sh` — 인벤토리 계층

상태: 계획.

책임:

- 모든 노드에 동일하게 배포된 인벤토리 전체를 검증한다.
- hostname/FQDN 또는 명시적 로컬 주소로 현재 서버를 하나만 선택한다.
- 현재 서버에 controller와 broker 행이 여러 개 있어도 각각 독립 프로세스로 반환한다.
- Kafka properties를 생성하거나 저장소를 포맷하지 않는다.

주요 입력·값:

| 이름 | 값 또는 출처 |
| --- | --- |
| `inventory_path` | 00에서 전달 |
| `local_hostname` | `hostname -f` 결과 |
| `local_addresses` | `ip -br address` 결과 |
| `controller_rows` | role이 `controller`인 전체 행 |
| `broker_rows` | role이 `broker`인 전체 행 |
| `local_rows` | 현재 서버와 정확히 일치한 행 목록 |

함수 의사코드:

```text
load_inventory(inventory_path) -> rows
  입력 형식과 필수 필드 검사
  외부 호출: 선택한 JSON/YAML 파서

detect_local_server(rows, hostname, addresses) -> server_key
  hostname 우선, 명시적 IP 보조로 정확히 한 서버 매칭
  0개 또는 2개 이상이면 중단

validate_global_uniqueness(rows)
  node_id, reachable endpoint, 프로세스 키 중복 검사
  controller와 broker 목록이 각각 하나 이상인지 검사

validate_local_resources(local_rows)
  bind 주소 존재, 포트 범위·충돌, data_dir 중복과 권한 검사
  외부 호출: ip, ss, test

build_controller_voters(controller_rows) -> voter_string
  controller의 node_id@reachable_host:reachable_port를 고정 순서로 생성

main(--inventory inventory_path, --network-result path)
  전체·로컬 검증 실행
  local_rows와 controller voter 문자열을 후속 단계 입력으로 저장
```

다음 단계로 전달: 검증된 현재 서버 행, 공통 controller voter 문자열, 검증된 경로·포트.

### 7.5 `04-render-kafka-config.sh` — Kafka 설정 계층

상태: 계획.

책임:

- 03이 검증한 현재 서버의 각 프로세스 행마다 Kafka 설정 파일 하나를 생성한다.
- controller와 broker를 분리된 `process.roles`와 별도 `node.id`, 저장소로 구성한다.
- 설정 생성만 담당하고 저장소 포맷이나 프로세스 기동은 하지 않는다.

주요 입력·값:

| 이름 | 값 또는 출처 |
| --- | --- |
| `local_rows_path` | 03의 검증 결과 |
| `controller_voters` | 03이 생성한 전체 controller 목록 |
| `KAFKA_HOME` | `~/.kafka-env` |
| `config_dir` | 사용자 입력 또는 00의 공통 작업 경로 |
| `listener_protocol_map` | `CONTROLLER:PLAINTEXT,BROKER:PLAINTEXT` |

함수 의사코드:

```text
render_controller_config(row, controller_voters, output_path)
  process.roles=controller와 CONTROLLER listener 생성
  metadata.log.dir에 controller 전용 data_dir 지정
  advertised.listeners와 BROKER listener는 만들지 않음

render_broker_config(row, controller_voters, output_path)
  process.roles=broker와 BROKER listener 생성
  advertised.listeners에 reachable endpoint 지정
  log.dirs에 broker 전용 data_dir 지정

validate_rendered_config(row, output_path)
  필수 키, 역할, ID, 포트, 저장 경로가 입력 행과 같은지 확인

main(--local-rows path, --output-dir config_dir)
  source ~/.kafka-env
  각 local row의 역할에 맞는 render 함수 호출
  임시 파일에 작성 후 검증 성공 시 최종 파일로 이동
```

다음 단계로 전달: 프로세스 키와 Kafka 설정 파일 경로의 매핑.

### 7.6 `05-format-kafka-storage.sh` — 저장소 계층

상태: 계획.

책임:

- 모든 노드가 같은 cluster ID를 사용하는지 확인한다.
- 완전히 신규인 프로세스 저장소만 한 번 포맷한다.
- 기존 `meta.properties`가 있으면 cluster ID와 node ID를 대조하고 다시 포맷하지 않는다.
- 손상 또는 부분 초기화 상태를 자동 복구하지 않는다.

주요 입력·값:

| 이름 | 값 또는 출처 |
| --- | --- |
| `cluster_id` | 공통 cluster ID 파일 |
| `config_map_path` | 04의 프로세스별 설정 파일 매핑 |
| `node_id` | 검증된 인벤토리 행 |
| `data_dir` | 프로세스 전용 저장소 경로 |
| `meta.properties` | 기존 저장소의 Kafka 메타데이터 |

함수 의사코드:

```text
read_cluster_id(cluster_id_path) -> cluster_id
  값 형식과 단일 값 여부 검사

inspect_storage(data_dir) -> NEW | FORMATTED | UNSAFE
  빈 디렉터리는 NEW
  meta.properties가 정상 존재하면 FORMATTED
  데이터가 있으나 metadata가 없거나 일부 경로만 초기화됐으면 UNSAFE

assert_existing_metadata(meta_path, expected_cluster_id, expected_node_id)
  기존 cluster.id와 node.id가 입력과 다르면 중단

format_new_storage(cluster_id, config_path)
  신규 저장소에만 Kafka storage format 실행
  외부 호출: $KAFKA_HOME/bin/kafka-storage.sh format

main(--cluster-id path, --config-map path)
  각 로컬 프로세스의 저장소 상태 검사
  NEW만 포맷, FORMATTED는 검증, UNSAFE는 중단
```

다음 단계로 전달: 포맷 또는 기존 메타데이터 검증을 통과한 프로세스 목록.

### 7.7 `06-manage-kafka-processes.sh` — 프로세스 실행 계층

상태: 계획.

책임:

- 프로세스별 준비, 시작, 로컬 상태 확인을 분리한다.
- controller를 먼저 시작하고 broker는 controller 확인 이후 시작한다.
- 한 노드가 전체 quorum을 무한 대기해 다른 노드 실행을 막지 않게 제한 시간을 둔다.
- 이미 실행 중인 동일 프로세스를 중복 시작하지 않는다.

주요 입력·값:

| 이름 | 값 또는 출처 |
| --- | --- |
| `action` | `prepare`, `start`, `status` 중 하나 |
| `config_map_path` | 04의 출력 |
| `formatted_state_path` | 05의 출력 |
| `pid_dir` | 프로세스별 PID 파일 디렉터리 |
| `log_dir` | 프로세스별 로그 디렉터리 |
| `timeout_seconds` | 사용자 입력 또는 문서화된 기본 제한 시간 |

함수 의사코드:

```text
prepare_process(process_key, config_path)
  설정·저장소·로그·PID 경로와 포트 충돌 재검사

is_running(process_key) -> bool
  PID 파일과 실제 프로세스 명령행이 모두 일치할 때만 true
  외부 호출: ps, kill -0

start_process(process_key, role, config_path)
  이미 실행 중이면 유지
  역할별 로그·PID를 분리해 Kafka 서버 시작
  외부 호출: $KAFKA_HOME/bin/kafka-server-start.sh

status_process(process_key, bind_host, bind_port) -> status
  프로세스 생존과 로컬 리스닝을 제한 시간 내 확인
  외부 호출: ps, ss

main(action, --config-map path, --timeout seconds)
  action에 해당하는 함수만 실행
  controller와 broker 결과를 구분해 반환
```

다음 단계로 전달: 시작된 프로세스 키, 역할, PID, 로컬 리스닝 결과와 로그 경로.

### 7.8 `07-check-kafka-cluster.sh` — 검증 계층

상태: 계획.

책임:

- 인벤토리에 정의한 출발지·목적지 조합의 TCP 도달성을 검사한다.
- controller leader, voter 복제 상태와 전체 broker 등록을 읽기 전용으로 확인한다.
- 토픽을 생성·수정하거나 클러스터 설정을 변경하지 않는다.
- 실제 실행 위치, 대상, 시각, 종료 코드와 핵심 결과를 기록한다.

주요 입력·값:

| 이름 | 값 또는 출처 |
| --- | --- |
| `inventory_path` | 03에서 검증한 공통 인벤토리 |
| `process_state_path` | 06의 실행 결과 |
| `cluster_id` | 05에서 검증한 공통 ID |
| `controller_endpoints` | controller 인벤토리 행 |
| `broker_endpoints` | broker 인벤토리 행 |
| `timeout_seconds` | 연결별 제한 시간 |
| `result_path` | 현재 서버의 점검 결과 파일 |

함수 의사코드:

```text
check_local_listener(process_row) -> result
  기대 bind 주소·포트가 실제 수신 중인지 확인
  외부 호출: ss

check_peer_tcp(source_context, target_host, target_port, timeout) -> result
  현재 노드가 연결해야 하는 각 peer endpoint 검사
  외부 호출: nc

check_metadata_quorum(controller_or_broker_endpoint) -> result
  cluster ID, leader, voter와 follower 상태 조회
  외부 호출: kafka-metadata-quorum.sh describe

check_broker_registration(broker_endpoint) -> result
  모든 broker ID와 advertised endpoint가 응답하는지 조회
  외부 호출: kafka-broker-api-versions.sh

write_result(result_path, checks)
  실행 위치·시각·대상·종료 코드·판정을 기록

main(--inventory path, --process-state path, --cluster-id path)
  로컬 리스닝 -> peer TCP -> quorum -> broker 등록 순서로 검사
  하나라도 실패하면 클러스터 완료로 판정하지 않음
```

최종 출력: 현재 노드 점검 결과와 클러스터 완료 판정에 필요한 증거. 여러 서버의 결과를 모아 모든 노드가 통과했을 때만 전체 완료로 판단한다.

## 8. 전체 실행 순서와 중단 조건

| 단계 | 시작 조건 | 성공 조건 | 중단 조건 |
| --- | --- | --- | --- |
| 01 런타임 | Windows에서 스크립트 실행 가능 | WSL root 명령, Java 17, Kafka 4.3.1 확인 | WSL 설치 실패, Java/Kafka 검증 실패 |
| 02 네트워크 | 역할·주소·포트 후보 존재 | 실제 WSL 모드와 포워딩·방화벽 결과 확인 | 모드 불일치, 주소 모호, 권한 또는 규칙 적용 실패 |
| 03 인벤토리 | 모든 노드에 동일 입력 배포 | 현재 서버 1개 매칭, 전역·로컬 충돌 없음 | ID·endpoint·포트·경로 충돌, 역할 누락 |
| 04 설정 | 03 검증 결과 존재 | 모든 로컬 행의 설정 파일 검증 | 필수 속성 누락 또는 입력과 출력 불일치 |
| 05 저장소 | 공통 cluster ID와 04 출력 존재 | 신규 포맷 또는 기존 metadata 일치 | 기존 ID 불일치, 부분 초기화, 불명확한 데이터 |
| 06 기동 | 05 통과 | 프로세스 생존과 로컬 포트 수신 | 중복 프로세스, 제한 시간 초과, 프로세스 종료 |
| 07 검사 | 대상 프로세스 기동 | peer TCP, quorum, broker 등록 모두 통과 | 도달 실패, leader 없음, ID·endpoint 불일치 |

단계 실패 시 이후 단계로 진행하지 않는다. 재실행은 성공한 외부 상태를 보존하고 현재 단계의 멱등성 검사를 다시 수행한다. 기존 Kafka 데이터나 사용자가 작성한 네트워크 설정은 자동 삭제하지 않는다.

## 9. 현재 실행 방법과 한계

현재는 통합 진입점 `00`과 클러스터 단계 `03~07`이 없다. 런타임 설치 후 네트워크 준비까지 각각 실행할 수 있다.

```powershell
.\setting\kafka_setting\srcs\01-bootstrap-kafka-node.ps1 -RestartIfRequired

# 기본 mirrored 모드
.\setting\kafka_setting\srcs\02-prepare-kafka-network.ps1

# NAT 모드
.\setting\kafka_setting\srcs\02-prepare-kafka-network.ps1 --networking-mode nat
```

두 단계가 성공하면 각 노드에서 Java 17과 Kafka 4.3.1을 사용할 수 있고 WSL 네트워크 경로와 Windows 방화벽이 준비된 것이다. controller나 broker는 아직 구성·기동되지 않는다. 실제 서버 주소와 역할 인벤토리를 확정한 뒤 03부터 순서대로 구현하고 검증해야 한다.

## 10. 완료 판정

문서 작업 완료와 실제 클러스터 구성 완료를 구분한다.

- 라우팅 문서 완료: 실제 파일과 대응 문서가 1:1이고, 각 단계의 입력·출력·외부 호출이 기록됨
- 구현 완료: 00~07 실행 파일과 대응 문서가 모두 존재하고 정적 검증을 통과함
- 노드 준비 완료: 각 서버에서 01~06이 성공하고 재실행 시 ID·데이터·규칙이 유지됨
- 클러스터 완료: 모든 노드의 07 결과에서 동일 cluster ID, controller leader, 전체 voter와 broker 등록, 필요한 peer TCP 연결이 확인됨

현재 상태는 **01 런타임·02 네트워크 스크립트 구현**, **03~07 및 통합 실행기 계획**, **실제 클러스터 미검증**이다.
