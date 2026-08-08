# Hillstone Secure Connect Docker 多架构运行环境

本项目在 `debian:bookworm-slim` 容器中运行官方 Hillstone Secure Connect Linux 客户端，并提供：

- amd64 与 arm64 多架构镜像；
- TigerVNC + flwm 最小图形桌面；
- 可直接使用浏览器访问的 noVNC 登录界面；
- Supervisor 管理的 Hillstone 后台服务和 GUI；
- 仅在 VPN 隧道可用时开放的 TCP SOCKS5 代理；
- 基于 nftables 的 fail-closed 出站保护；
- nginx HTTPS + Basic Auth 保护入口；
- 容器健康检查和运行状态诊断脚本。

## 1. 软件包与架构

Dockerfile 使用 BuildKit 自动参数 `TARGETARCH` 选择对应的厂商 Debian 软件包：

| 镜像架构 | Hillstone 版本 | 软件包 | SHA-256 |
|---|---:|---|---|
| amd64 | 5.5.0.12175 | `hillstonesecureconnect_5.5.0.12175_amd64.deb` | `fe0cb6176a67c0fb682138aee9965486e085b498375fff97c0a52b99d9dbaf3e` |
| arm64 | 5.5.0.12186 | `hillstonesecureconnect_5.5.0.12186_arm64.deb` | `0e3428449537653fb07d6dadf06bb08b07db64b4c99c730d60731b3edf08bcca` |

两个架构使用的厂商 patch 版本不同，但会发布为同一项目的对应架构镜像。

构建过程中会完成以下检查：

1. 校验软件包 SHA-256；
2. 使用 `dpkg-deb -f` 校验包架构与 `TARGETARCH` 一致；
3. 使用 `dpkg-deb --extract` 将文件解压到镜像；
4. 验证 GUI、后台服务和厂商启动脚本存在且可执行。

厂商包的维护脚本会调用 `systemctl enable/start`。容器中不执行 `dpkg -i` 或厂商 `postinst`，后台服务统一交给 Supervisor 管理。

软件安装根目录为：

```text
/opt/apps/hillstonesecureconnect/files
```

主要程序：

```text
/opt/apps/hillstonesecureconnect/files/bin/HillstoneSecureConnect
/opt/apps/hillstonesecureconnect/files/bin/HillstoneSecureConnect.sh
/opt/apps/hillstonesecureconnect/files/bin/HillstoneSecureConnectService
```

更详细的软件包验证结果见 [docs/package-validation.md](docs/package-validation.md)。

## 2. 已解决的关键运行问题

### 2.1 GUI 因 locale 为空而崩溃

在 `LANG`、`LANGUAGE` 和 `LC_ALL` 为空时，厂商 GUI 会在以下函数中发生 SIGSEGV：

```text
hillstonesecureconnect::ui::GetCurrentSystemDiaplayLanguage()
```

因此镜像会生成 `zh_CN.UTF-8`，并在镜像、Supervisor 后台服务和桌面会话中固定：

```text
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:zh
LC_ALL=zh_CN.UTF-8
```

这属于功能性要求，不只是界面语言偏好。容器入口脚本也会检查 locale 是否真实存在。

### 2.2 GUI 必须等待后台服务

GUI 通过 TCP loopback 与 `HillstoneSecureConnectService` 通信。正常启动顺序为：

1. system D-Bus；
2. `HillstoneSecureConnectService`；
3. 等待服务监听 `127.0.0.1:35421`；
4. 原子写入 `/run/hillstone-vpn/service-ready`；
5. 启动 TigerVNC、flwm 和 Hillstone GUI；
6. 启动 noVNC、nginx、SOCKS 和 route guard。

桌面启动脚本会同时检查 readiness 文件和 `35421` 监听端口。GUI 不会在后台服务尚未准备好时提前启动。

### 2.3 后台服务进程名被 Linux 截断

`HillstoneSecureConnectService` 超过 Linux `comm` 字段的 15 字符限制，实际显示为：

```text
HillstoneSecure
```

如果使用 `pgrep -x HillstoneSecureConnectService` 或 `pkill -x`，无法识别已有进程，会导致 Supervisor 重启后累积多个服务实例，依次监听：

```text
127.0.0.1:35421
127.0.0.1:35422
127.0.0.1:35423
...
```

当前 wrapper 改为按完整可执行文件路径识别和清理服务。经过持续运行验证，容器内只保留一个后台服务实例，并且只监听 `127.0.0.1:35421`。

### 2.4 TUN 是隧道建立的硬性要求

已验证 VPN 认证、TLS、密钥交换和服务端路由下发可以成功。容器缺少 `/dev/net/tun` 时，会在虚拟网卡设置阶段失败：

```text
VNIC_ERR_IP_SET_FAILED (41021)
Failed to open device /dev/net/tun
Failed to set vnic ip: No such device
```

运行时必须提供：

```yaml
cap_add:
  - NET_ADMIN
  - NET_RAW
devices:
  - /dev/net/tun:/dev/net/tun
```

不需要使用 `privileged: true`，也不需要 host network。

### 2.5 SOCKS 和 nftables fail-closed

Dante SOCKS5 以独立的 `socksproxy` 用户运行。route guard 对该用户应用出站限制：

- 未发现 VPN 接口时，只允许 loopback 和已建立连接；
- 其他出站流量全部拒绝；
- 发现有效 VPN 接口后，只允许通过该接口出站；
- 隧道消失后删除接口 marker、停止 SOCKS 并恢复锁定规则；
- SOCKS 重启失败时保持锁定状态。

原 nftables interval set 方案在目标主机的容器环境中创建失败，出现 `Numerical result out of range`。当前实现将每个 `SOCKS_ALLOWED_CIDRS` 生成为独立允许规则，避免依赖动态 interval set。

## 3. 网络入口与安全边界

容器内部端口：

| 端口 | 用途 | 说明 |
|---:|---|---|
| 5901 | TigerVNC | 仅监听容器内 `127.0.0.1`，不发布到宿主机 |
| 6080 | noVNC HTTP | 适合受信 LAN，默认应绑定明确地址 |
| 8443 | nginx HTTPS | Basic Auth 保护的 noVNC 入口 |
| 1080 | Dante SOCKS5 | 没有协议级认证，必须限制绑定地址和来源 CIDR |
| 35421 | Hillstone Service IPC | 仅监听容器 loopback |

安全注意事项：

- 不要将 HTTP noVNC 或 SOCKS 直接暴露到互联网；
- SOCKS 没有用户名/密码认证，应同时限制宿主机绑定地址和 `SOCKS_ALLOWED_CIDRS`；
- HTTPS noVNC 使用 nginx Basic Auth；
- `/healthz` 不要求认证，仅返回健康状态，不暴露桌面内容；
- VNC 原生端口不会发布到宿主机；
- SOCKS 仅支持 TCP CONNECT，不提供 UDP ASSOCIATE、ICMP 或透明三层路由。

## 4. 配置

复制环境变量模板：

```bash
cp .env.example .env
```

至少检查以下配置：

```dotenv
HILLSTONE_IMAGE=hillstonenet-hillstone-vpn:bookworm
HILLSTONE_CONTAINER_NAME=hillstone-vpn

NOVNC_HTTP_BIND_IP=192.168.1.10
NOVNC_HTTP_PORT=6080
NOVNC_HTTPS_BIND_IP=192.168.1.10
NOVNC_HTTPS_PORT=8443
SOCKS_BIND_IP=192.168.1.10
SOCKS_PORT=1080

SOCKS_ALLOWED_CIDRS=192.168.1.0/24
VPN_DOCKER_SUBNET=172.30.50.0/24
VPN_CONTAINER_IP=172.30.50.2
VPN_TUN_REGEX=^(tun|tap|ppp|hsc|sc)[0-9_-]*$
HILLSTONE_AUTO_MINIMIZE=false
```

`HILLSTONE_AUTO_MINIMIZE=false` 会在 GUI 启动前将 `AppConfig.ini` 中的 `AutoMinimize` 固定为 `false`，避免 VPN 连接成功后厂商客户端自动隐藏主窗口。在 noVNC/flwm 会话中没有常规桌面托盘，自动隐藏后只能通过手动点击窗口区域或重新启动 GUI 找回，因此本项目默认禁用该行为。若希望恢复厂商默认的连接后最小化行为，可将其设为 `true`。

如果有一个只有 VPN 连接后才可访问的企业 IP，建议配置：

```dotenv
VPN_PROBE_HOST=10.0.0.10
```

接口检测器随后会要求该目标的路由确实经过候选 VPN 接口，降低误识别风险。

### 4.1 持久化目录

Compose 使用项目目录下的相对路径保存 Hillstone 配置和运行数据：

```yaml
volumes:
  - ./data/hillstone-config:/home/desktop/.config/HillstoneSecureConnect
  - ./data/hillstone-data:/home/desktop/.local/share/HillstoneSecureConnect
  - ./certs:/certs:ro
```

以 Compose 文件所在目录为基准，宿主机数据位于：

```text
./data/hillstone-config/AppConfig.ini
./data/hillstone-data/
```

`AppConfig.ini` 包含 VPN 网关、用户名、认证类型以及可能的记住密码信息，应视为敏感文件，不要提交到 Git 或公开分发。

首次部署前可以创建目录并设置为容器内 `desktop` 用户 UID/GID：

```bash
mkdir -p data/hillstone-config data/hillstone-data
chown -R 1000:1000 data/hillstone-config data/hillstone-data
chmod 700 data/hillstone-config data/hillstone-data
```

在远程部署目录 `/dubhe/hs` 中，对应的绝对路径为：

```text
/dubhe/hs/data/hillstone-config
/dubhe/hs/data/hillstone-data
```

### 4.2 生成 HTTPS 证书

```bash
mkdir -p certs
openssl req -x509 -newkey rsa:3072 -nodes -days 365 \
  -keyout certs/tls.key \
  -out certs/tls.crt \
  -subj '/CN=hillstone-vpn.local'
```

### 4.3 生成 Basic Auth 文件

```bash
docker run --rm httpd:2.4-alpine \
  htpasswd -nbB admin 'replace-this-password' > certs/htpasswd
```

私钥和认证文件应限制权限：

```bash
chmod 600 certs/tls.key certs/htpasswd
chmod 644 certs/tls.crt
```

## 5. 构建镜像

### 5.1 使用 Compose 构建当前宿主机架构

```bash
docker compose build
docker compose up -d
```

### 5.2 显式构建 amd64

```bash
docker buildx build \
  --platform linux/amd64 \
  -t hillstonenet-hillstone-vpn:bookworm-amd64 \
  --load .
```

### 5.3 显式构建 arm64

```bash
docker buildx build \
  --platform linux/arm64 \
  -t hillstonenet-hillstone-vpn:bookworm-arm64 \
  --load .
```

### 5.4 镜像内部检查

```bash
docker run --rm --platform linux/amd64 \
  --entrypoint /bin/bash \
  hillstonenet-hillstone-vpn:bookworm-amd64 -lc '
    set -eu
    dpkg --print-architecture
    locale -a | grep -i "^zh_CN.utf8$"
    file "$HILLSTONE_HOME/bin/HillstoneSecureConnect"
    ! ldd "$HILLSTONE_HOME/bin/HillstoneSecureConnect" | grep "not found"
    ! ldd "$HILLSTONE_HOME/bin/HillstoneSecureConnectService" | grep "not found"
  '
```

## 6. 启动和 Web 登录

启动：

```bash
docker compose up -d
```

直接 HTTP noVNC：

```text
http://<NOVNC_HTTP_BIND_IP>:<NOVNC_HTTP_PORT>/vnc.html?autoconnect=1&resize=scale
```

HTTPS noVNC：

```text
https://<NOVNC_HTTPS_BIND_IP>:<NOVNC_HTTPS_PORT>/vnc.html?autoconnect=1&resize=scale
```

打开页面后应自动连接 VNC，并显示 `Hillstone Secure Connect` 主窗口。用户在 GUI 中填写网关、账号、密码及 MFA 信息。

## 7. 运行状态检查

### 7.1 Compose 和健康状态

```bash
docker compose ps
docker inspect hillstone-vpn --format '{{.State.Status}} {{.State.Health.Status}}'
docker compose logs -f hillstone-vpn
```

### 7.2 Supervisor 服务

```bash
docker compose exec hillstone-vpn supervisorctl status
```

正常情况下以下服务应为 `RUNNING`：

```text
dbus
desktop
hillstone-service
nginx
novnc
route-guard
socks
```

注意：未连接 VPN 时，`socks` 的 wrapper 可以处于运行状态，但 Dante 本身不会监听 `1080`。

### 7.3 后台服务唯一性

```bash
docker compose exec hillstone-vpn bash -lc '
  pgrep -af "^/opt/apps/hillstonesecureconnect/files/bin/HillstoneSecureConnectService($| )"
  ss -lntp | grep 127.0.0.1:35421
  cat /run/hillstone-vpn/service-ready
'
```

预期结果：

- 只有一个 `HillstoneSecureConnectService`；
- 只监听 `127.0.0.1:35421`；
- readiness 文件包含该服务 PID。

### 7.4 GUI 窗口

```bash
docker compose exec -u desktop hillstone-vpn \
  env DISPLAY=:1 xwininfo -root -tree
```

应能看到类似：

```text
"Hillstone Secure Connect" 960x650
```

### 7.5 TUN、路由和接口 marker

```bash
docker compose exec hillstone-vpn test -c /dev/net/tun
docker compose exec hillstone-vpn ip -br address
docker compose exec hillstone-vpn ip route show table all
docker compose exec hillstone-vpn cat /run/hillstone-vpn/interface
```

成功连接后，接口 marker 通常为 `tun0`，实际名称以客户端创建的设备为准。

### 7.6 route guard

```bash
docker compose exec hillstone-vpn nft list table inet hillstone_guard
```

未连接 VPN 时，`socksproxy` 用户只允许 loopback 和已建立连接，其余出站被拒绝。

## 8. SOCKS5 使用和验证

VPN 成功连接并检测到接口后，Dante 才会监听：

```text
socks5h://<SOCKS_BIND_IP>:<SOCKS_PORT>
```

必须使用代理端 DNS 解析，推荐 `socks5h`：

```bash
curl --proxy socks5h://<SOCKS_BIND_IP>:<SOCKS_PORT> https://ifconfig.me
```

访问企业内部目标：

```bash
curl --proxy socks5h://<SOCKS_BIND_IP>:<SOCKS_PORT> http://internal.example
```

通过 SOCKS 使用 SSH：

```bash
ssh -o 'ProxyCommand=nc -X 5 -x <SOCKS_BIND_IP>:<SOCKS_PORT> %h %p' \
  user@internal-host
```

未连接 VPN 时，以下请求必须失败：

```bash
curl --max-time 5 \
  --proxy socks5h://<SOCKS_BIND_IP>:<SOCKS_PORT> \
  https://example.com
```

## 9. 断线防泄漏测试

建议完整执行以下测试：

1. 未登录 VPN 时请求 SOCKS，确认连接失败；
2. 登录 VPN，确认出现 VPN 接口和 `/run/hillstone-vpn/interface`；
3. 确认 Dante 开始监听 `1080`；
4. 通过 `socks5h` 访问允许的企业目标；
5. 在容器中使用 `tcpdump -ni eth0` 观察普通接口；
6. 主动断开 VPN 或停止 Hillstone 服务；
7. 确认接口 marker 被删除且 Dante 停止监听；
8. 再次执行 SOCKS 请求，必须失败；
9. 确认代理目标流量没有从 `eth0` 泄漏；
10. 重新连接 VPN，确认接口重新发现、规则重新开放且 SOCKS 恢复。

## 10. amd64 远程部署实测记录

以下测试于 2026-08-07 在原生 x86_64 Docker 主机 `10.193.2.8` 完成。

### 10.1 部署信息

| 项目 | 值 |
|---|---|
| 远程目录 | `/dubhe/hs` |
| 镜像 | `hillstonenet-hillstone-vpn:bookworm-amd64` |
| 镜像 ID | `sha256:19e9c91f198084dd5741ac0ef44eb80e9271f2fbb98fff85085f12d0ac6a226e` |
| 镜像归档 | `/dubhe/hs/hillstonenet-hillstone-vpn-bookworm-amd64.tar` |
| 归档 SHA-256 | `12a6a3c0cc7d739dd19a84ae6dd87fea87f37c187604a710b07381badc30eff1` |
| Compose 项目 | `hs-bookworm-amd64` |
| 候选容器 | `hillstone-vpn-bookworm-amd64` |
| Docker 网络 | `172.26.50.0/24` |
| 容器地址 | `172.26.50.2` |

该候选部署使用独立的容器名、网络、端口和数据卷，没有覆盖已有的 `hillstone-vpn` 或 `hillstone-vpn-u20-flwm` 容器。

### 10.2 测试入口

```text
HTTP noVNC:  http://10.193.2.8:36080/vnc.html?autoconnect=1&resize=scale
HTTPS noVNC: https://10.193.2.8:38443/vnc.html?autoconnect=1&resize=scale
SOCKS5:      10.193.2.8:31080
```

### 10.3 已验证项目

- 远程宿主机和 Docker 均为 x86_64/amd64；
- 宿主机 `/dev/net/tun` 可用；
- 本地和远程镜像 ID 完全一致；
- 容器状态为 `running`；
- Docker 健康状态为 `healthy`；
- `zh_CN.UTF-8` 已生成；
- `LANG`、`LANGUAGE`、`LC_ALL` 设置正确；
- GUI 和 Service 的 `ldd` 无 `not found`；
- D-Bus、desktop、Hillstone Service、noVNC、nginx 和 route guard 正常运行；
- 只存在一个 Hillstone Service 实例；
- Service 只监听 `127.0.0.1:35421`；
- GUI 与 Service 建立 loopback TCP 连接；
- noVNC 页面可从外部浏览器访问；
- 实际 VNC 画面显示 Hillstone 登录窗口；
- X11 窗口树中存在 `Hillstone Secure Connect` 960x650 主窗口；
- HTTPS `/healthz` 返回 `200`；
- 未认证访问 HTTPS 根路径返回 `401`；
- 未登录 VPN 时 SOCKS 不监听，外部 SOCKS 请求失败；
- 未连接 VPN 时 nftables 保持 fail-closed 规则。

### 10.4 当前候选容器状态

候选容器已经运行，但重建最终修复镜像后尚未在新容器中重新填写 VPN 信息并完成登录。因此当前预期状态为：

```text
VPN interface marker: 不存在
Dante 1080 listener: 不存在
SOCKS external request: 失败
```

这是正常的 fail-closed 状态，不代表容器启动失败。

访问 noVNC 完成登录后，应继续验证：

```bash
ssh root@10.193.2.8

docker exec hillstone-vpn-bookworm-amd64 ip -br address
docker exec hillstone-vpn-bookworm-amd64 ip route show table all
docker exec hillstone-vpn-bookworm-amd64 cat /run/hillstone-vpn/interface
docker exec hillstone-vpn-bookworm-amd64 ss -lntp | grep :1080
docker exec hillstone-vpn-bookworm-amd64 nft list table inet hillstone_guard

curl --proxy socks5h://10.193.2.8:31080 https://ifconfig.me
```

### 10.5 远程部署和更新命令

导出并上传镜像：

```bash
docker save hillstonenet-hillstone-vpn:bookworm-amd64 | gzip -1 | \
  ssh root@10.193.2.8 \
  'gzip -dc > /dubhe/hs/hillstonenet-hillstone-vpn-bookworm-amd64.tar'
```

远程导入镜像：

```bash
ssh root@10.193.2.8 \
  'docker load -i /dubhe/hs/hillstonenet-hillstone-vpn-bookworm-amd64.tar'
```

重建候选容器：

```bash
ssh root@10.193.2.8 '
  cd /dubhe/hs
  docker compose -p hs-bookworm-amd64 up -d --no-build --force-recreate
'
```

查看状态：

```bash
ssh root@10.193.2.8 '
  docker inspect hillstone-vpn-bookworm-amd64 \
    --format "status={{.State.Status}} health={{.State.Health.Status}} image={{.Image}}"
  docker exec hillstone-vpn-bookworm-amd64 supervisorctl status
  docker logs --tail 200 hillstone-vpn-bookworm-amd64
'
```

## 11. 健康检查说明

镜像健康检查会验证：

- HTTP noVNC 页面可访问；
- HTTPS `/healthz` 可访问；
- 核心 Supervisor 程序为 `RUNNING`；
- Hillstone Service 监听 `127.0.0.1:35421`；
- TigerVNC 监听 `127.0.0.1:5901`；
- 若 VPN interface marker 存在，其对应接口必须仍然存在。

健康状态只说明容器控制面和 Hillstone GUI/Service 可用，不代表用户已经成功登录 VPN。VPN 和 SOCKS 状态必须单独检查。

## 12. 限制

- 本项目提供应用层 TCP SOCKS5 代理，不是透明三层路由器；
- SOCKS 不支持 UDP ASSOCIATE、ICMP 和任意非 TCP 协议；
- amd64 和 arm64 使用不同的厂商 patch 版本；
- Hillstone 的实际认证、MFA、VPN 地址和服务端路由取决于目标 VPN 网关；
- 最终发布前，应分别在原生 amd64 和原生 arm64 主机完成真实登录、DNS、路由、企业目标、SOCKS 和断线防泄漏测试；
- 直接 HTTP noVNC 和无认证 SOCKS 不得暴露到互联网。
