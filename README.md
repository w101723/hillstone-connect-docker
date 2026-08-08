# Hillstone Secure Connect Docker

在 `debian:bookworm-slim` 容器中运行 Hillstone Secure Connect，通过浏览器访问 noVNC 图形界面登录 VPN，并在 VPN 连接成功后提供 SOCKS5 代理。

## 功能

- 支持 `linux/amd64` 和 `linux/arm64`
- TigerVNC + flwm 最小桌面
- noVNC 浏览器访问
- Supervisor 管理后台服务和 GUI
- VPN 连接后自动开放 SOCKS5
- VPN 断开后自动关闭 SOCKS5 出站
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

devices:
  - /dev/net/tun:/dev/net/tun
```

不需要使用 `privileged: true` 或 host network。

## 快速开始

### 1. 准备配置

```bash
cp .env.example .env
```

编辑 `.env`，至少设置宿主机绑定地址和允许访问 SOCKS 的来源网络：

```dotenv
HILLSTONE_IMAGE=ghcr.io/w101723/hillstone-connect:latest
HILLSTONE_CONTAINER_NAME=hillstone-vpn

NOVNC_HTTP_BIND_IP=192.168.1.10
NOVNC_HTTP_PORT=6080

SOCKS_BIND_IP=192.168.1.10
SOCKS_PORT=1080
SOCKS_ALLOWED_CIDRS=192.168.1.0/24

VPN_DOCKER_SUBNET=172.30.50.0/24
VPN_CONTAINER_IP=172.30.50.2
VPN_TUN_REGEX=^(tun|tap|ppp|hsc|sc)[0-9_-]*$

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
| `SOCKS_ALLOWED_CIDRS` | 允许连接 SOCKS5 的 IPv4 CIDR，多个值用逗号分隔 |
| `VPN_DOCKER_SUBNET` | Compose bridge 网络段 |
| `VPN_CONTAINER_IP` | 容器固定地址 |
| `VPN_TUN_REGEX` | VPN 接口名称匹配规则 |
| `VPN_PROBE_HOST` | 可选，仅通过 VPN 可达的探测地址 |
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

SOCKS5 仅在检测到有效 VPN 接口后开始监听。

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

VPN 未连接或已经断开时，SOCKS 请求应失败。

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
route-guard
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
docker compose exec hillstone-vpn cat /run/hillstone-vpn/interface
```

### SOCKS 监听状态

```bash
docker compose exec hillstone-vpn ss -lntp | grep :1080
```

### nftables 规则

```bash
docker compose exec hillstone-vpn \
  nft list table inet hillstone_guard
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
- 使用防火墙限制 noVNC 和 SOCKS5 来源地址；
- 将 `SOCKS_ALLOWED_CIDRS` 限制到实际客户端网络；
- 妥善保护 `AppConfig.ini`；
- 不要将 `.env` 或 `data/` 提交到 Git；
- SOCKS5 只提供 TCP CONNECT，不支持 UDP ASSOCIATE、ICMP 或透明三层路由。
