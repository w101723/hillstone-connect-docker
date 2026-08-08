# Hillstone Secure Connect Docker

在 `debian:bookworm-slim` 容器中运行 Hillstone Secure Connect，通过浏览器访问 noVNC 图形界面登录 VPN，并在 VPN 连接成功后提供 SOCKS5 代理。

## 功能

- 支持 `linux/amd64` 和 `linux/arm64`
- TigerVNC + flwm 最小桌面
- noVNC 浏览器访问
- Supervisor 管理后台服务和 GUI
- GOST SOCKS5 服务始终保持监听并以容器默认用户运行
- SOCKS5 出站直接服从容器路由表，不进行用户或 VPN 接口防火墙限制
- 默认启用 IPv4 转发，并对容器转发流量执行 `POSTROUTING MASQUERADE`
- 配置和应用数据使用相对路径持久化

## 支持的客户端版本

| 镜像架构 | Hillstone 版本 | 软件包 |
|---|---:|---|
| amd64 | 5.5.0.12175 | `hillstonesecureconnect_5.5.0.12175_amd64.deb` |
| arm64 | 5.5.0.12186 | `hillstonesecureconnect_5.5.0.12186_arm64.deb` |

软件安装目录：

```text
/opt/apps/hillstonesecureconnect/files
```

## 运行要求

宿主机需要：

- Docker Engine
- Docker Compose v2
- `/dev/net/tun`
- 支持添加 `NET_ADMIN` 和 `NET_RAW` capability

检查 TUN：

```bash
test -c /dev/net/tun && echo "TUN available"
```

Compose 已配置：

```yaml
cap_add:
  - NET_ADMIN
  - NET_RAW

sysctls:
  net.ipv4.ip_forward: "1"

devices:
  - /dev/net/tun:/dev/net/tun
```

`NET_ADMIN` 用于建立 VPN 接口、配置 iptables 和转发规则。Compose 默认启用容器网络命名空间的 IPv4 forwarding；直接使用 `docker run` 时需要同时传入 `--cap-add NET_ADMIN --sysctl net.ipv4.ip_forward=1`。

不需要使用 `privileged: true` 或 host network。

## 快速开始

### 1. 准备配置

```bash
cp .env.example .env
```

编辑 `.env`，至少设置宿主机绑定地址：

```dotenv
HILLSTONE_IMAGE=ghcr.io/w101723/hillstone-connect:latest
HILLSTONE_CONTAINER_NAME=hillstone-vpn

NOVNC_HTTP_BIND_IP=192.168.1.10
NOVNC_HTTP_PORT=6080

SOCKS_BIND_IP=192.168.1.10
SOCKS_PORT=1080

VPN_DOCKER_SUBNET=172.30.50.0/24
VPN_CONTAINER_IP=172.30.50.2

HILLSTONE_AUTO_MINIMIZE=false
```

配置说明：

| 变量 | 说明 |
|---|---|
| `HILLSTONE_IMAGE` | 使用的容器镜像 |
| `NOVNC_HTTP_BIND_IP` | noVNC HTTP 在宿主机上的绑定地址 |
| `NOVNC_HTTP_PORT` | noVNC HTTP 端口 |
| `SOCKS_BIND_IP` | SOCKS5 在宿主机上的绑定地址 |
| `SOCKS_PORT` | SOCKS5 端口 |
| `VPN_DOCKER_SUBNET` | Compose bridge 网络段 |
| `VPN_CONTAINER_IP` | 容器固定地址 |
| `HILLSTONE_AUTO_MINIMIZE` | 是否在连接后自动最小化 GUI，noVNC 环境建议设为 `false` |

不要将服务绑定到不受信任的公网地址。

### 2. 准备持久化目录

```bash
mkdir -p data/hillstone-config data/hillstone-data
chown -R 1000:1000 data/hillstone-config data/hillstone-data
chmod 700 data/hillstone-config data/hillstone-data
```

Compose 使用以下相对路径：

```yaml
volumes:
  - ./data/hillstone-config:/home/desktop/.config/HillstoneSecureConnect
  - ./data/hillstone-data:/home/desktop/.local/share/HillstoneSecureConnect
```

主要数据：

```text
data/hillstone-config/AppConfig.ini
data/hillstone-data/log/uisecureconnect.log
data/hillstone-data/oauth/
data/hillstone-data/portal/
data/hillstone-data/resourceList/
```

`AppConfig.ini` 可能包含 VPN 网关、用户名和记住密码信息，应作为敏感文件保存，不要提交到 Git。

### 3. 拉取并启动

```bash
docker compose pull
docker compose up -d
```

查看状态：

```bash
docker compose ps
docker compose logs -f hillstone-vpn
```

## 访问 noVNC

noVNC：

```text
http://<NOVNC_HTTP_BIND_IP>:<NOVNC_HTTP_PORT>/vnc.html?autoconnect=1&resize=scale
```

打开页面后：

1. 等待 Hillstone Secure Connect 窗口显示；
2. 填写 VPN 网关；
3. 输入账号、密码及 MFA 信息；
4. 点击连接；
5. 等待 VPN 接口建立。

建议保留：

```dotenv
HILLSTONE_AUTO_MINIMIZE=false
```

这样连接成功后主窗口会继续显示在 noVNC 桌面中。

## 使用 SOCKS5

SOCKS5 由 GOST 提供并始终监听配置的端口。GOST 以容器默认用户 root 运行，不再通过 owner 规则或 VPN 接口名称限制出站。VPN 连接前、连接后以及断开后，代理请求都直接服从容器当时的路由表。

VPN 连接后，Hillstone 下发的目标路由会自动用于相应的 SOCKS 请求。全隧道 VPN 可能改变默认出口；分流 VPN 只会让指定网段经过 VPN，其余目标仍可能通过 `eth0`。是否经过 VPN 应以 `ip route get <目标地址>` 和实际出口测试为准。

SOCKS5 不启用账号密码或来源 CIDR 限制，所有能够访问绑定地址和端口的客户端均可连接。仅应将 `SOCKS_BIND_IP` 绑定到受信内网地址，并使用宿主机防火墙控制访问范围。

代理地址：

```text
socks5h://<SOCKS_BIND_IP>:<SOCKS_PORT>
```

推荐使用 `socks5h`，使 DNS 查询也通过代理处理。

测试公网出口：

```bash
curl --proxy socks5h://192.168.1.10:1080 https://ifconfig.me
```

访问内部 HTTP 服务：

```bash
curl --proxy socks5h://192.168.1.10:1080 http://internal.example
```

通过 SOCKS5 使用 SSH：

```bash
ssh -o 'ProxyCommand=nc -X 5 -x 192.168.1.10:1080 %h %p' \
  user@internal-host
```

VPN 未连接或已经断开时，SOCKS5 仍会通过容器普通默认路由访问目标，不具备 VPN kill switch 或 fail-closed 保护。

## 作为转发网关

容器启动时默认执行以下等效配置：

```bash
sysctl -w net.ipv4.ip_forward=1
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -A POSTROUTING -j MASQUERADE
```

因此，连接到容器网络并将默认路由指向该容器的下游设备或容器，可以使用它转发 IPv4 流量。无条件 `MASQUERADE` 会对容器转发的所有 IPv4 出站流量进行源地址伪装，实际出口由容器当前路由表决定。

通用转发/NAT 与 GOST SOCKS5 相互独立：MASQUERADE 作用于经容器转发的流量；GOST 发起的是本机 `OUTPUT` 流量，直接按照容器路由表选路。容器不再创建 GOST 专用防火墙链，也不会将 SOCKS5 端口变成透明代理。

## 查看运行状态

### 容器健康状态

```bash
docker inspect hillstone-vpn \
  --format 'status={{.State.Status}} health={{.State.Health.Status}}'
```

### Supervisor 服务

```bash
docker compose exec hillstone-vpn supervisorctl status
```

正常运行时会看到：

```text
dbus
desktop
hillstone-service
novnc
socks
```

### Hillstone 后台服务

```bash
docker compose exec hillstone-vpn bash -lc '
  pgrep -af "^/opt/apps/hillstonesecureconnect/files/bin/HillstoneSecureConnectService($| )"
  ss -lntp | grep 127.0.0.1:35421
  cat /run/hillstone-vpn/service-ready
'
```

### VPN 接口和路由

```bash
docker compose exec hillstone-vpn ip -br address
docker compose exec hillstone-vpn ip route show table all
docker compose exec hillstone-vpn ip route get <目标地址>
```

### SOCKS 监听状态

```bash
docker compose exec hillstone-vpn ss -lntp | grep :1080
```

### iptables 和转发状态

```bash
docker compose exec hillstone-vpn sysctl net.ipv4.ip_forward
docker compose exec hillstone-vpn iptables -S
docker compose exec hillstone-vpn iptables -L FORWARD -n -v
docker compose exec hillstone-vpn iptables -t nat -S POSTROUTING
docker compose exec hillstone-vpn iptables -t nat -L POSTROUTING -n -v
```

### GUI 窗口

```bash
docker compose exec -u desktop hillstone-vpn \
  env DISPLAY=:1 xwininfo -root -tree
```

## 更新镜像

```bash
docker compose pull
docker compose up -d --force-recreate
```

相对路径中的配置和运行数据会保留：

```text
./data/hillstone-config
./data/hillstone-data
```

更新后检查：

```bash
docker compose ps
docker compose exec hillstone-vpn supervisorctl status
docker compose logs --tail 200 hillstone-vpn
```

## 停止和删除

停止容器：

```bash
docker compose stop
```

删除容器和网络，但保留相对路径数据：

```bash
docker compose down
```

如需删除保存的 VPN 配置和应用数据，必须手动删除：

```bash
rm -rf data/hillstone-config data/hillstone-data
```

执行前请先备份 `AppConfig.ini`。

## 备份和恢复

备份：

```bash
tar -czf hillstone-data-backup.tar.gz \
  data/hillstone-config \
  data/hillstone-data
```

恢复：

```bash
tar -xzf hillstone-data-backup.tar.gz
chown -R 1000:1000 data/hillstone-config data/hillstone-data
docker compose up -d
```

## 安全建议

- 不要将 HTTP noVNC 或 SOCKS5 直接暴露到互联网；
- 使用宿主机防火墙限制 noVNC 和 SOCKS5 来源地址；
- 妥善保护 `AppConfig.ini`；
- 不要将 `.env` 或 `data/` 提交到 Git；
- 容器内不提供 SOCKS5 的 VPN kill switch 或出站接口限制，VPN 断开后代理会继续服从普通路由；
- 默认的无条件 MASQUERADE 会伪装所有经容器转发的 IPv4 出站流量，应只把受信网络接入该网关；
- SOCKS5 只提供 TCP CONNECT，不支持 UDP ASSOCIATE、ICMP 或透明三层路由。
