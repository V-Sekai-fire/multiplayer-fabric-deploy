# WebTransport platform support (modules/http3)

Three backends — `web` uses the browser JS API; `linux` uses picoquic + picotls + mbedtls; `linux-pcvr` uses the same picoquic stack as a native client on Steam Link and Linux distros.

| Platform     | Backend                 | Role                             |
| ------------ | ----------------------- | -------------------------------- |
| `web`        | JS (`quic_web_glue.js`) | Primary — browser client + WebXR |
| `linux`      | picoquic native         | Server                           |
| `linux-pcvr` | picoquic native         | Client — PCVR on Steam Link and Linux distros |
