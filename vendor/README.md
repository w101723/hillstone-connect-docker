Place both official Debian packages in this directory. They are architecture-specific and selected automatically from Docker BuildKit's `TARGETARCH`.

| Architecture | Package | Version | SHA-256 |
|---|---|---|---|
| amd64 | `hillstonesecureconnect_5.5.0.12175_amd64.deb` | 5.5.0.12175 | `fe0cb6176a67c0fb682138aee9965486e085b498375fff97c0a52b99d9dbaf3e` |
| arm64 | `hillstonesecureconnect_5.5.0.12186_arm64.deb` | 5.5.0.12186 | `0e3428449537653fb07d6dadf06bb08b07db64b4c99c730d60731b3edf08bcca` |

The Dockerfile verifies the selected package and extracts it with `dpkg-deb --extract`. It deliberately does not execute package maintainer scripts because their `postinst` invokes systemd. The service is managed by Supervisor inside the container.
