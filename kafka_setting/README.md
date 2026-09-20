# Kafka 기본 클러스터 구성 계획

## 목적과 현재 상태

동일한 셸 스크립트를 각 서버에서 실행해 Kafka KRaft 클러스터를 기동하고, 노드 간 연결과 broker 등록까지 확인한다. 토픽 생성, 파티션 수, 복제 계수, 보존 정책, 프로듀서·컨슈머 설정은 이번 범위에 포함하지 않는다.

이 문서는 구현 계획이다. 실제 서버 주소·접속 정보가 제공되지 않아 서버의 포트 개방, WSL 모드, 클러스터 기동은 아직 검증하지 않았다. 아래 명령도 문서 작성 과정에서 실행하지 않았다.

실행 순서는 **역할·포트 계획 → 네트워크 모드 적용·주소 확인 → 포워딩·방화벽 준비 → 인벤토리 확정 → Kafka 설정 생성 → 초기화·기동 → 원격 연결·등록 검사**다. Kafka의 실제 포트 바인딩은 설정을 읽고 프로세스가 시작할 때 일어난다.

## 1. 서버 수와 역할

서버 수는 3대 이상으로 가변이며 4대로 고정하지 않는다. 동일 스크립트가 공통 인벤토리를 읽어 현재 서버에 배정된 프로세스를 구성한다. controller leader는 Kafka가 선출하므로 특정 서버를 영구 leader로 지정하지 않는다.

역할을 서버별로 분리한 1 controller + 2 broker도 기본 기동이 가능하다. 단, 그 controller가 중단되면 metadata quorum을 유지하지 못한다.

| 배치 방식 | 서버 3대 예시 | 의미 |
| --- | --- | --- |
| 서버별 역할 분리 | controller 전용 1대 + broker 전용 2대 | 서버마다 하나의 역할을 실행하며 기본 기동 가능 |
| 서버마다 별도 프로세스로 역할 분리 | 각 서버에서 controller 1개와 broker 1개 실행 | controller 3개 + broker 3개, 프로세스별 ID·설정·저장소 필요 |

스크립트는 인벤토리의 프로세스 행을 기준으로 구성하고, 서버 하나에 여러 행을 허용해 두 배치를 모두 표현한다. 자동으로 역할을 선택하지 않는다. `process.roles=broker,controller` 결합 프로세스는 이 계획에서 사용하지 않는다.

controller 3개 또는 5개는 장애 허용을 위한 일반적인 선택이지 기본 기동의 절대 최소 조건이 아니다. controller 수가 짝수라는 이유만으로 설정 오류로 판단하지 않는다. 가용성에는 과반수의 controller가 필요하다. [Kafka KRaft 역할과 quorum](https://kafka.apache.org/42/operations/kraft/)

각 역할의 로컬 포트와 외부 접속 포트를 먼저 계획한다. 기본 예시는 broker TCP 9092, controller TCP 9093이며, 이후 네트워크 준비 결과로 실제 주소를 확정한다.

## 2. 네트워크 모드 적용과 포워딩·방화벽 준비

실행 환경을 `native-linux`, `wsl-nat`, `wsl-mirrored` 중 하나로 확인한다. native Linux는 WSL 절차를 건너뛰고 서버 주소·라우팅·방화벽을 준비한다. WSL에서는 NAT와 mirrored 중 적용할 방식을 정한 뒤 아래 절차를 진행한다.

Windows 호스트에서 먼저 상태를 읽는다.

```powershell
# 배포판 이름, WSL 버전, 설정 및 포워딩을 확인한다.
wsl --version
wsl --list --verbose
Get-Content -LiteralPath "$env:USERPROFILE\.wslconfig" -ErrorAction SilentlyContinue
netsh interface portproxy show all
Get-Service iphlpsvc
Get-NetFirewallProfile
```

지원되는 WSL에서는 내부에서 `wslinfo --networking-mode`로 적용 모드를 확인한다. 명령이 없으면 WSL 버전·설정·실제 원격 접속 결과로 확인하고, 파일에 적힌 설정만으로 적용 완료라 보고하지 않는다.

### WSL2 NAT를 사용하는 경우

연결 경로는 `다른 서버 → Windows LAN IP:공개 포트 → WSL IP:바인드 포트`다. broker 광고 주소와 controller voter 주소는 다른 서버에서 도달 가능한 Windows LAN 주소를 사용한다. WSL 프로세스는 `0.0.0.0` 또는 WSL 로컬 주소에 바인드한다.

Windows 관리자 PowerShell에서 아래 형태로 필요한 포트만 전달한다. 변수는 실제 값으로 먼저 지정해야 한다.

```powershell
# 해당 배포판의 주소 중 전달 대상 IPv4를 확인해 선택한다.
wsl -d Ubuntu -- hostname -I

# 변수에는 Windows LAN IP, 선택한 WSL IP, 외부 포트와 내부 포트를 넣는다.
netsh interface portproxy add v4tov4 listenaddress=$windowsLanIp listenport=$publicPort connectaddress=$wslIp connectport=$bindPort

# 허용할 peer IP 목록으로 Windows 인바운드 규칙을 제한한다.
New-NetFirewallRule -DisplayName "Kafka-$publicPort" -Direction Inbound -Action Allow -Protocol TCP -LocalAddress $windowsLanIp -LocalPort $publicPort -RemoteAddress $peerIps
```

같은 규칙이 이미 있으면 새 규칙을 반복 생성하지 않고 대상 주소·포트를 비교해 갱신한다. WSL 재시작 뒤 IP가 바뀌면 포워딩도 갱신해야 한다. IP Helper 서비스, Windows 방화벽, WSL 내부 방화벽을 함께 확인한다. 같은 Windows 호스트 안의 프로세스에서도 Kafka 기동 후 광고 endpoint로 접속되는지 검사한다.

### WSL mirrored 모드를 사용하는 경우

지원 조건을 확인한 뒤 기존 `%UserProfile%\.wslconfig`의 다른 설정을 보존하면서 다음 항목을 반영한다.

```ini
[wsl2]
networkingMode=mirrored
```

적용을 위한 `wsl --shutdown`은 해당 Windows의 모든 WSL 작업을 중단시키므로 네트워크 준비 단계에서 수행한다. 다시 시작한 후 적용 모드·주소·라우팅을 확인한다. 포트 접속 검사는 Kafka 기동 후 수행한다. mirrored 모드에서 NAT용 portproxy를 새로 추가하지 않는다.

Windows/Hyper-V 방화벽에서 필요한 TCP 포트와 출발지 IP를 허용한다. Hyper-V 규칙의 예시 형태는 다음과 같다.

```powershell
# 관리자 PowerShell에서 실제 역할 포트와 peer IP 목록만 허용한다.
New-NetFirewallHyperVRule -Name "Kafka-$publicPort" -DisplayName "Kafka-$publicPort" -Direction Inbound -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -Protocol TCP -LocalPorts $publicPort -RemoteAddresses $peerIps
```

이 모드는 Windows 11 22H2 이상에서 지원되며 설치된 WSL 버전도 확인해야 한다. 포트 포워딩과 미러 네트워킹은 서로 다른 방법이다. [Microsoft WSL 네트워킹](https://learn.microsoft.com/en-us/windows/wsl/networking)

Windows 설정은 관리자 권한의 호스트 작업이다. Linux 셸 스크립트는 이 선행 조건을 점검하고 부족한 항목을 출력한다. 셸 실행만으로 Windows 방화벽까지 설정되었다고 처리하지 않는다.

## 3. 주소·포트 사전 점검

셸 스크립트는 실행 환경을 `native-linux`, `wsl-nat`, `wsl-mirrored` 중 하나로 입력받고 감지 결과와 대조한다. WSL이라는 사실만으로 mirrored 모드라고 추정하지 않는다.

Linux/WSL 내부에서 다음을 확인한다.

```bash
# 주소·라우팅·수신 소켓을 확인한다. Kafka 기동 전에는 Kafka 포트가 없어도 정상이다.
hostname -f
ip -br address
ip route
ss -lntp

# 실제 peer DNS 이름으로 교체해 이름 해석을 확인한다.
getent ahostsv4 controller-1.example.internal
```

방화벽은 해당 서버에서 실제로 사용하는 관리자(UFW, firewalld, nftables 등)로 점검한다. 클라우드라면 보안 그룹·네트워크 ACL도 포함한다. 예를 들어 UFW 사용 서버에서는 `sudo ufw status verbose`로 확인하고, 필요한 peer IP별로 해당 역할의 TCP 포트만 허용한다. 접속 실패를 방화벽 문제로 단정하지 않고 리스닝 여부 → 주소·DNS → 라우팅 → 방화벽 순서로 구분한다.

이 단계에서는 로컬 주소 존재 여부, DNS, 라우팅, 포트 충돌, 포워딩 대상, 방화벽 규칙을 확인한다. 대상 Kafka가 아직 수신하지 않으므로 TCP 접속 성공을 통과 조건으로 요구하지 않는다. 사전 종단 간 검사가 필요한 경우에만 임시 TCP 수신 프로그램을 사용하며, 검사 후 종료하고 포트가 해제되었는지 확인한다. 일반 연결 검사는 7절에서 수행한다.

## 4. 공통 인벤토리 확정과 자동 감지

스크립트 구현 시 Kafka의 정확한 버전, 해당 버전이 지원하는 Java 버전, 설치 경로를 고정한다. 아래는 **정적 quorum을 사용하는 기본 구성안**이다. 동적 quorum의 bootstrap·format 옵션을 혼합하지 않는다. 버전이 아직 선택되지 않았으므로 현재 문서를 즉시 실행 가능한 설치 스크립트로 취급하지 않는다.

네트워크 준비 후 확인한 로컬 주소와 외부 접속 주소·포트를 아래 필드에 확정한다. 모든 서버에 동일한 스크립트, 동일한 인벤토리, 동일한 cluster ID를 제공한다. 표는 입력 필드 정의이며 실제 IP 예시를 기본값으로 배포하지 않는다.

| 필드 | 값과 용도 |
| --- | --- |
| server_key | 현재 hostname/FQDN 또는 사전에 정한 로컬 IP와 정확히 매칭할 서버 식별자 |
| role | `controller` 또는 `broker` |
| node_id | 모든 프로세스 사이에서 고유한 고정 정수. 행 순서·IP 끝자리로 생성하지 않음 |
| bind_host / bind_port | 프로세스가 실제 수신할 로컬 주소와 포트 |
| reachable_host / reachable_port | 다른 노드에서 접근할 DNS/IP와 포트. NAT에서는 호스트 측 주소 |
| data_dir | 해당 프로세스 전용 영구 저장소 |

hostname 우선으로 매칭하고, IP를 사용할 경우 지정 NIC/주소와 대조한다. 결과가 없거나 여러 서버와 매칭되면 중단한다. 같은 서버에 배정된 여러 프로세스 행은 정상이다. 포트와 데이터 경로 충돌은 별도로 검사한다.

동일 서버의 controller와 broker도 서로 다른 node ID와 저장소를 사용한다. 전체 프로세스 ID 중복, 외부 endpoint 충돌, controller 또는 broker 목록이 비어 있는 입력은 거부한다.

## 5. 확정한 인벤토리로 Kafka 설정 생성

4절의 인벤토리를 입력으로 프로세스별 설정 파일을 생성한다. 이후 초기화와 기동은 이 파일을 사용한다. 네트워크 준비가 완료되지 않았으면 이 단계로 진행하지 않는다.

기본 예시 포트는 broker TCP 9092, controller TCP 9093이다. 실제 설정·방화벽·포워딩·검사는 모두 인벤토리 값을 사용한다.

| 출발지 | 목적지 | 목적지 포트 예시 |
| --- | --- | --- |
| controller | 다른 controller | TCP 9093 |
| broker | controller | TCP 9093 |
| controller | broker | TCP 9092 |
| broker | 다른 broker | TCP 9092 |
| 검사 도구 또는 향후 클라이언트 | 모든 broker | TCP 9092 |

`listeners`는 로컬 바인드 주소다. `advertised.listeners`와 controller voter endpoint는 다른 노드가 접근할 주소다. NAT 외부 IP를 로컬 `listeners`에 넣지 않는다. broker 하나에 접속한 뒤 반환받는 모든 broker 주소에도 접근할 수 있어야 한다.

예시는 신뢰 가능한 내부망의 PLAINTEXT 통신을 전제로 한다. controller 포트는 클러스터 노드에, broker 포트는 클러스터 노드와 필요한 검사 호스트에만 허용한다. 인터넷 전체에 개방하지 않는다.

### Controller 전용 프로세스 설정 템플릿

```properties
# 로컬에서 수신하고 외부 통신에는 공통 voter 목록을 사용한다.
process.roles=controller
node.id=<controller_id>
listeners=CONTROLLER://<bind_host>:<bind_port>
controller.listener.names=CONTROLLER
controller.quorum.voters=<id@reachable_host:reachable_port 목록>
listener.security.protocol.map=CONTROLLER:PLAINTEXT,BROKER:PLAINTEXT
inter.broker.listener.name=BROKER
metadata.log.dir=<controller_data_dir>
```

controller의 `BROKER` 이름은 broker로 나가는 통신에 사용한다. controller가 BROKER listener를 열도록 설정하지 않는다.

### Broker 전용 프로세스 설정 템플릿

```properties
# 바인드 주소와 다른 노드에게 알리는 주소를 구분한다.
process.roles=broker
node.id=<broker_id>
listeners=BROKER://<bind_host>:<bind_port>
advertised.listeners=BROKER://<reachable_host>:<reachable_port>
inter.broker.listener.name=BROKER
controller.listener.names=CONTROLLER
controller.quorum.voters=<controller와 동일한 voter 목록>
listener.security.protocol.map=CONTROLLER:PLAINTEXT,BROKER:PLAINTEXT
log.dirs=<broker_data_dir>
```

리스너 이름의 프로토콜 매핑을 명시한다. [Kafka listener 설정](https://kafka.apache.org/42/security/listener-configuration/)

## 6. 초기화·기동·재실행

1. 2~3절의 네트워크 준비와 사전 점검, 4절의 인벤토리 확정, 5절의 설정 파일 생성을 완료했는지 확인한다. 모든 서버의 Kafka/Java 버전과 설정을 대조하고 저장 경로·권한을 검증한다.
2. 공통 cluster ID는 `bin/kafka-storage.sh random-uuid`로 한 번 생성해 전 노드에 배포한다. 노드마다 새 ID를 만들지 않는다.
3. 정적 quorum을 지원하는 선택 버전에서 신규 저장소만 `bin/kafka-storage.sh format -t <cluster_id> -c <설정파일>`로 포맷한다. 동적 quorum으로 전환하면 초기화 절차를 별도로 설계한다.
4. 기존 저장소는 cluster ID·node ID와 경로를 검증하고 포맷하지 않는다. 비어 있지 않은데 metadata가 없거나 일부 디렉터리만 초기화된 상태는 자동 복구하지 않고 중단한다.
5. 각 controller를 시작한다. 한 서버에서 전체 quorum 성공을 무한 대기해 다른 서버 시작을 막지 않도록 `prepare`, `start`, `check` 단계를 분리한다.
6. controller 로그와 선택 버전에서 지원하는 controller 직접 조회로 leader 선출과 quorum 구성을 확인한 뒤 broker를 시작한다. 예를 들어 지원 버전에서는 `kafka-metadata-quorum.sh --bootstrap-controller <controller_endpoint> describe --status`를 사용한다. 아직 시작하지 않은 broker를 통한 조회를 이 단계의 필수 조건으로 삼지 않는다. 프로세스별 로그·PID 또는 systemd unit을 분리하고 이미 실행 중인 프로세스를 중복 실행하지 않는다.
7. 모든 서버에서 포트 연결을 검사하고 Kafka 수준의 상태 검사를 수행한다. 제한 시간 내 실패는 실패 대상으로 남긴다.

서버 수가 가변이라는 것은 최초 인벤토리 크기가 가변이라는 뜻이다. 정적 quorum의 controller 수를 실행 중 자동으로 변경하는 기능까지 포함하지 않는다. 동적 quorum의 controller 추가 명령을 정적 quorum에 그대로 적용하지 않는다.

## 7. 기동 후 원격 연결 검사와 완료 판정

각 대상 프로세스의 로컬 수신 상태를 `ss -lntp`로 확인한 뒤, 5절 연결 표의 각 출발 노드에서 다음 원격 검사를 수행한다. `nc`가 설치되어 있어야 한다.

```bash
# 실제 대상 주소·포트로 교체한다. 대상 Kafka 기동 후 실행한다.
nc -vz -w 3 controller-1.example.internal 9093
nc -vz -w 3 broker-1.example.internal 9092
```

Windows의 별도 서버에서 확인할 때는 실제 대상 주소로 실행한다.

```powershell
# 다른 서버에서의 접근을 검사해야 한다. localhost 성공만으로 노드 간 연결을 판정하지 않는다.
Test-NetConnection -ComputerName controller-1.example.internal -Port 9093
Test-NetConnection -ComputerName broker-1.example.internal -Port 9092
```

검사는 위 연결 표의 각 출발 노드에서 각 대상에 수행한다. TCP 접속 성공은 Kafka 등록 성공과 별개이므로 마지막 Kafka 검사도 필요하다.


```bash
# 실제 broker endpoint로 교체한다. 토픽을 생성하거나 수정하지 않는 조회 명령이다.
bin/kafka-metadata-quorum.sh --bootstrap-server broker-1.example.internal:9092 describe --status
bin/kafka-metadata-quorum.sh --bootstrap-server broker-1.example.internal:9092 describe --replication
bin/kafka-broker-api-versions.sh --bootstrap-server broker-1.example.internal:9092
```

선택한 Kafka 버전의 CLI 도움말로 옵션을 확인한다. 다음을 모두 확인해야 완료다.

- 보고된 cluster ID가 공통 입력과 일치하고 controller leader가 존재한다.
- voter 목록이 의도한 controller 목록과 일치하고 follower가 metadata를 따라간다.
- API 조회에서 확인되는 broker ID와 endpoint가 인벤토리 전체와 일치하고 모두 응답한다.
- 필요한 모든 peer 간 TCP 경로가 통과한다. Windows localhost 검사만으로 대체하지 않는다.
- 재실행 시 기존 데이터와 ID가 유지되고 중복 프로세스·방화벽 규칙이 생기지 않는다.

토픽·내부 토픽의 복제 설정은 변경하지 않는다. broker 수가 적으면 이후 consumer group이나 transaction 기능의 기본 복제 조건을 만족하지 못할 수 있다. 이번 완료 판정은 클러스터 기동·등록에 한정한다.

## 8. 실제 점검 결과 기록 양식

| 서버 | 역할/ID | 실행 환경/WSL 모드 | 로컬 리스닝 | 원격 peer TCP 검사 | Kafka 등록/quorum | 재실행 | 판정 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 실제 서버 입력 필요 | 미확인 | 미확인 | 미실행 | 미실행 | 미실행 | 미실행 | 미검증 |

각 검사에는 실행 위치, 시각, 대상 주소·포트, 종료 코드와 핵심 출력을 기록한다. 문서 작성 완료와 실제 서버 구성 완료를 구분한다.
