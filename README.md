# Kafka 및 Spark 클러스터 구성

Windows 11과 WSL2에서 네트워크, SSH, Spark, Kafka KRaft를 설정하는 안내와 스크립트 모음이다. 이 README는 전체 진행 순서를 안내하고, 각 영역 README는 실제 설정 절차를 설명한다.

## 실행 환경과 문서 구조

- **Windows 11 관리자 PowerShell**: WSL mirrored 네트워크 모드와 Windows·Hyper-V 방화벽을 설정한다.
- **WSL2 Debian/Ubuntu 계열**: Bash, `apt-get`, `systemctl`을 사용해 SSH·Spark·Kafka를 설정한다.
- **클러스터 노드**: Kafka는 `node1`~`node4` 네 노드로 구성한다. Spark에는 노드별 미러링 IPv4가 필요하고, Kafka에는 공통 클러스터 ID와 노드별 UUID·주소가 필요하다.

| 영역 | 설정 안내 | 라우팅 문서 | 담당 기능 |
|---|---|---|---|
| Windows | [Windows README](setting/docs/window/README.md) | [Windows 라우팅](setting/docs/window/setting-routing/ROUTING-README.md) | WSL mirrored 네트워크, Windows·Hyper-V 방화벽 |
| WSL | [WSL README](setting/docs/wsl/README.md) | [WSL 라우팅](setting/docs/wsl/setting-routing/ROUTING-README.md) | UFW 비활성화, OpenSSH Server 설치·실행 |
| Spark | [Spark README](setting/docs/spark/README.MD) | [Spark 라우팅](setting/docs/spark/setting-routing/ROUTING-README.md) | Spark 4.2.0·Java 17 설치 및 실행 환경 설정 |
| Kafka | [Kafka README](setting/docs/kafka/README.md) | [Kafka 라우팅](setting/docs/kafka/setting-routing/ROUTING-README.md) | Kafka 4.1.2 설치와 노드별 KRaft 설정 파일 생성 |

문서는 설정 절차(`setting/docs/<영역>/README.md`), 스크립트 책임과 호출 구조(`setting-routing/ROUTING-README.md`), 개별 스크립트 상세(`setting-routing/files/`), 실제 실행 코드(`setting/srcs/`)로 나뉜다.

## 권장 진행 순서

1. 각 Windows 노드에서 mirrored 네트워크와 방화벽을 설정한다.
2. 각 WSL 노드에서 SSH 서버를 설치하고 실행한다.
3. 각 WSL 노드에서 Spark를 설치하고 해당 노드의 미러링 IP를 설정한다.
4. 네 노드의 공통 클러스터 ID, 노드별 UUID와 주소를 준비한 뒤 Kafka 설정을 생성한다.
5. 새 Kafka 클러스터를 처음 구성하는 경우에만 각 노드의 스토리지를 포맷하고 Kafka를 시작한다.

## 1. Windows 네트워크 설정

저장소 루트에서 관리자 권한 PowerShell을 열고 실행한다. `-ClusterIPs`에는 이 컴퓨터로 들어오는 클러스터 통신을 허용할 상대 노드의 IPv4 주소를 포트 없이 넣는다. 아래 예시는 현재 노드가 `192.168.0.11`일 때의 명령이며, 각 Windows 노드에서 자기 주소를 제외한 상대 노드 주소 목록을 사용한다.

```powershell
.\setting\srcs\window\setup-window-network.ps1 -ClusterIPs '192.168.0.12','192.168.0.13','192.168.0.14'
```

스크립트는 `.wslconfig`에서 WSL2 네트워크 모드를 `mirrored`로 설정하고, Windows 및 Hyper-V 방화벽을 갱신한 다음 `wsl.exe --shutdown`을 실행한다. SSH `TCP/22`는 현재 모든 원격 주소에 허용되며, `-ClusterIPs`에 지정한 원격 주소는 모든 프로토콜과 포트로 인바운드 통신할 수 있다. 이 스크립트는 포트 포워딩을 설정하지 않는다. 세부 내용은 [Windows README](setting/docs/window/README.md)를 참고한다.

## 2. WSL SSH 설정

각 WSL 노드에서 저장소 루트를 기준으로 실행한다. 스크립트는 root 권한으로 동작하며 WSL 내부 UFW를 비활성화하고 OpenSSH Server를 설치·활성화한다.

```bash
sudo bash setting/srcs/wsl/setup-wsl-ssh.sh
```

## 3. 각 WSL 노드의 Spark 설정

각 노드에서 `ip -4 -br addr`로 IPv4 주소를 확인하고, 해당 노드의 미러링 LAN 주소를 인자로 전달한다. 스크립트가 그 IP가 WSL에 실제 할당되어 있는지 확인하고, Spark 4.2.0·Java 17 및 환경 변수를 설정한다. Spark Master나 Worker 프로세스는 시작하지 않는다.

```bash
bash setting/srcs/spark/setup-spark.sh 192.168.0.11
```

## 4. 각 WSL 노드의 Kafka 설정 파일 생성

Kafka 설정 전에 모든 노드에서 사용할 공통 `CLUSTER_ID`, 노드별 `DIRECTORY_1`~`DIRECTORY_4` UUID, 포트가 없는 `GAME_NODE_1_ADDRESS`~`GAME_NODE_4_ADDRESS` 미러링 IPv4 또는 DNS 이름을 준비한다. `CLUSTER_ID`는 한 번 생성해 네 노드에 공유하고, 각 `DIRECTORY_N`은 해당 노드에서 생성해 네 노드에 공유한다. 생성 방법과 환경 변수 입력 예시는 [Kafka README](setting/docs/kafka/README.md)에 있다. `GAME_LOG_DIR`은 선택 사항이며, 지정하지 않으면 Kafka 설치 경로의 `logs` 디렉터리를 사용한다.

각 WSL 노드에서 자기 노드 이름에 해당하는 명령 하나를 실행한다. 스크립트는 Kafka 4.1.2를 준비하고 `~/.bashrc`에 클러스터 값을 등록한 뒤 해당 노드의 `config/game/nodeN.properties`를 생성한다.

```bash
bash setting/srcs/kafka/setup-kafka.sh --node node1
bash setting/srcs/kafka/setup-kafka.sh --node node2
bash setting/srcs/kafka/setup-kafka.sh --node node3
bash setting/srcs/kafka/setup-kafka.sh --node node4
```

옵션은 다음 명령으로 확인할 수 있다.

```bash
bash setting/srcs/kafka/setup-kafka.sh --help
```

## 5. 새 Kafka 클러스터 포맷 및 실행

설정 파일을 만든 뒤 새 클러스터를 처음 시작할 때 각 노드에서 아래 명령을 실행한다. `node1.properties`는 해당 노드 이름으로 바꾼다. 스토리지 포맷은 Kafka 메타데이터를 초기화하므로 이미 사용 중인 클러스터에서 다시 실행하지 않는다.

```bash
source ~/.bashrc
cd ~/kafka/kafka_2.13-4.1.2
bin/kafka-storage.sh format --cluster-id "$GAME_CLUSTER_ID" --config config/game/node1.properties --initial-controllers "$GAME_INITIAL_CONTROLLERS"
bin/kafka-server-start.sh config/game/node1.properties
```
