# Kafka 및 Spark 클러스터 구성

Windows 11과 WSL 환경에서 네트워크·SSH·Spark·Kafka KRaft 클러스터를 순서대로 설정하는 문서와 스크립트 모음입니다. 각 영역의 README는 실행자가 따라 할 설정 절차를, 라우팅 문서는 스크립트의 호출 구조와 책임을 설명합니다.

## 실행 환경

- **Windows 11 관리자 PowerShell**: WSL 미러링 네트워크와 Windows·Hyper-V 방화벽을 설정합니다.
- **WSL의 Debian/Ubuntu 계열 셸**: `apt-get`, `systemctl`, Bash를 사용해 SSH·Spark·Kafka를 설정합니다.
- **클러스터 노드**: Spark는 각 노드의 미러링 IP를, Kafka는 node1~node4의 주소·클러스터 ID·노드 UUID를 알아야 합니다.

## 문서와 코드 구조

```text
README.md
├─ setting/docs/<영역>/README.md
│  └─ 실제 설치·설정 순서와 운영 명령
├─ setting/docs/<영역>/setting-routing/ROUTING-README.md
│  └─ 스크립트 책임, 호출 구조, 주요 함수·변수
├─ setting/docs/<영역>/setting-routing/files/...
│  └─ 개별 스크립트의 입력값, 생성 파일, 외부 호출
└─ setting/srcs/<영역>/...
   └─ 실제 실행 스크립트
```

| 영역 | 수행 기능 | 상세 문서 |
|---|---|---|
| WSL | UFW를 끄고 OpenSSH Server를 설치·활성화합니다. | [WSL README](setting/docs/wsl/README.md) |
| Windows | WSL 미러링 네트워크와 Windows·Hyper-V 방화벽 규칙을 설정합니다. | [Windows README](setting/docs/window/README.md) |
| Spark | Spark 4.2.0·Java 17을 준비하고 Spark 실행 환경 변수를 설정합니다. | [Spark README](setting/docs/spark/README.MD) |
| Kafka | Kafka 4.1.2 설치와 노드별 KRaft 설정 파일 생성을 수행합니다. | [Kafka README](setting/docs/kafka/README.md) |

## 권장 진행 순서

1. Windows에서 WSL 미러링 네트워크와 방화벽을 설정합니다.
2. WSL에서 SSH 실행 환경을 설정합니다.
3. 각 WSL 노드에서 Spark를 설정합니다.
4. 클러스터 ID·노드 UUID·노드 주소를 준비한 뒤 각 WSL 노드에서 Kafka를 설정합니다.

## 상황별 실행 명령

### 1. 새 Windows 노드에서 네트워크 설정

관리자 PowerShell에서 실행합니다. `-ClusterIPs` 뒤에는 통신을 허용할 클러스터 노드 IP를 하나 이상 지정합니다.

```powershell
.\setting\srcs\window\setup-wsl-network.ps1 -ClusterIPs '192.168.0.11','192.168.0.12','192.168.0.13','192.168.0.14'
```

클러스터 노드 IP가 바뀌거나 추가되면 새 IP 목록을 넣어 같은 명령을 다시 실행합니다.

### 2. WSL에서 SSH 준비

WSL 셸에서 실행합니다. 이 스크립트는 별도 `--` 인자를 받지 않으며 관리자 권한이 필요합니다.

```bash
sudo bash setting/srcs/wsl/setup-wsl-ssh.sh
```

### 3. WSL 노드에 Spark 설치

WSL 셸에서 실행합니다. 스크립트 뒤의 값은 이 노드에 할당된 미러링 IP입니다.

```bash
bash setting/srcs/spark/setup-spark.sh 192.168.0.11
```

### 4. WSL 노드에 Kafka 설정 파일 생성

Kafka는 노드 이름을 반드시 `--node` 뒤에 지정합니다. 실행 전에 `CLUSTER_ID`, `DIRECTORY_1`~`DIRECTORY_4`, `GAME_NODE_1_ADDRESS`~`GAME_NODE_4_ADDRESS`를 설정해야 합니다. 상세한 환경 변수 준비 방법은 [Kafka README](setting/docs/kafka/README.md)를 따릅니다.

```bash
bash setting/srcs/kafka/setup-kafka.sh --node node1
```

다른 노드에서는 마지막 값만 바꿉니다.

```bash
bash setting/srcs/kafka/setup-kafka.sh --node node2
bash setting/srcs/kafka/setup-kafka.sh --node node3
bash setting/srcs/kafka/setup-kafka.sh --node node4
```

Kafka 인자 목록은 다음 명령으로 확인할 수 있습니다.

```bash
bash setting/srcs/kafka/setup-kafka.sh --help
```

> `--node`는 Kafka 스크립트의 옵션입니다. WSL SSH 스크립트에는 옵션이 없고, Spark는 IP를 위치 인자로 받으며, Windows PowerShell 스크립트는 `-ClusterIPs` 매개 변수를 사용합니다.

## Kafka 포맷과 실행

Kafka 스크립트는 설정 파일만 만들고 포맷·서버 시작은 자동으로 하지 않습니다. 새 Kafka 클러스터를 처음 만들 때 각 노드에서 다음을 실행합니다. `node1.properties`는 현재 노드 이름에 맞게 바꿉니다.

```bash
source ~/.bashrc
cd ~/kafka/kafka_2.13-4.1.2
bin/kafka-storage.sh format --cluster-id "$GAME_CLUSTER_ID" --config config/game/node1.properties --initial-controllers "$GAME_INITIAL_CONTROLLERS"
bin/kafka-server-start.sh config/game/node1.properties
```
