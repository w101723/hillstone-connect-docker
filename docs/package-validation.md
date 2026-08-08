# Hillstone package validation

Validated on 2026-08-07.

| Architecture | Version | Package | SHA-256 | Installed root |
|---|---|---|---|---|
| amd64 | 5.5.0.12175 | `hillstonesecureconnect_5.5.0.12175_amd64.deb` | `fe0cb6176a67c0fb682138aee9965486e085b498375fff97c0a52b99d9dbaf3e` | `/opt/apps/hillstonesecureconnect/files` |
| arm64 | 5.5.0.12186 | `hillstonesecureconnect_5.5.0.12186_arm64.deb` | `0e3428449537653fb07d6dadf06bb08b07db64b4c99c730d60731b3edf08bcca` | `/opt/apps/hillstonesecureconnect/files` |

Both packages install:

- `bin/HillstoneSecureConnect`
- `bin/HillstoneSecureConnect.sh`
- `bin/HillstoneSecureConnectService`
- bundled Qt libraries and XCB plugins
- a Polkit policy and systemd service description

The packages declare no Debian runtime dependencies. The image therefore installs the required X11/XCB, locale, networking and service packages explicitly. It extracts the package filesystem with `dpkg-deb --extract`; it does not execute `postinst`, which calls `systemctl enable/start` and is unsuitable for a Supervisor container.

## Verified runtime findings

- With empty `LANG`, `LANGUAGE`, and `LC_ALL`, the ARM GUI crashes in `hillstonesecureconnect::ui::GetCurrentSystemDiaplayLanguage()`.
- Generating `zh_CN.UTF-8` and exporting `LANG=zh_CN.UTF-8`, `LANGUAGE=zh_CN:zh`, and `LC_ALL=zh_CN.UTF-8` allows the GUI to create and keep its 960x650 main window.
- The GUI communicates with `HillstoneSecureConnectService` over TCP loopback. The service must listen on `127.0.0.1:35421` before GUI startup.
- Authentication, TLS, key exchange, server route delivery and IPsec transport startup were observed successfully on arm64.
- A container created without `/dev/net/tun` failed at virtual-interface setup with `VNIC_ERR_IP_SET_FAILED (41021)`, `Failed to open device /dev/net/tun`, and `Failed to set vnic ip: No such device`.
- The client invokes compatibility commands including `ifconfig`, `route`, `ip`, `sudo`, `dnsmasq`, and `sysctl`; the Bookworm image installs their required packages.

Full release validation still requires running the final image with `/dev/net/tun`, `NET_ADMIN`, and `NET_RAW`, completing login on each native architecture, and verifying tunnel routes, DNS, SOCKS egress and disconnect leak protection.
