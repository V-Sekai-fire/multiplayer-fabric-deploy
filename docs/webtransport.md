# WebTransport platform support (modules/http3)

Native backends leveraging picoquic + picotls + mbedtls across all major desktop platforms. **Web support is explicitly excluded** in favor of native performance and strict certificate pinning.

| Platform       | Backend         | Role                                  |
| -------------- | --------------- | ------------------------------------- |
| `linux`        | picoquic native | Server / Client                       |
| `linux-pcvr`   | picoquic native | Client — PCVR on Steam Frame          |
| `macos`        | picoquic native | Client — Native ARM64/x86_64          |
| `windows-pcvr` | picoquic native | Client — Native x86_64 / Windows-PCVR |
