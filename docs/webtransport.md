# WebTransport platform support (modules/http3)

Two native backends — `linux` and `linux-pcvr` use picoquic + picotls + mbedtls. **Web support is explicitly excluded** in favor of native picoquic performance and tighter certificate pinning across all platforms.

| Platform     | Backend                 | Role                             |
| ------------ | ----------------------- | -------------------------------- |
| `linux`      | picoquic native         | Server                           |
| `linux-pcvr` | picoquic native         | Client — PCVR on Steam Frame and Linux distros |
