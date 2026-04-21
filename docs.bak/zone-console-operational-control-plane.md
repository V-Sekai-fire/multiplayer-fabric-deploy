# Zone Console: Operational Control Plane

The Zone Console has evolved from a debugging interface into the authoritative operational control plane for the Multiplayer Fabric zone network. While primarily residing in the `zone-console` module for implementation, its architectural significance is defined within the `deploy` orchestration layer.

## Architectural Role
## Orchestration Model
The orchestration of the zone network has shifted from manual process management to an elastic, **FLAME-driven** model:
- **Control Plane (Uro):** Acts as the FLAME Parent, managing the desired state of the zone network and the [ephemeral baking pipeline](ephemeral-asset-bake-microservice.md).
- **Worker Nodes (Zones):** Implemented as runners within a `FLAME.Pool`. When a new shard or zone is required, Uro triggers a FLAME placement using the production `editor=no` binary.
- **Baking Nodes (Editors):** Implemented as a separate `FLAME.Pool` using the SCons `editor=yes` binary. These are ephemeral, disconnected from the grid, and used strictly for asset transformation.
- **Global Distribution:** Leveraging `FLAME.FlyBackend` allows for instant deployment of double-precision physics zones in target regions (Montreal, Toronto) without pre-provisioning dedicated hardware.
- **Lifecycle Management:** Zones are monitored via the BEAM's distribution. If a zone node fails, the FLAME supervisor triggers a re-plan and re-spawn, ensuring high availability of the Hilbert grid.

## WebTransport Interface

The console utilizes WebTransport (HTTP/3) for low-latency, bidirectional communication with zone servers.

- **Unreliable Streams:** Used for high-frequency telemetry and heartbeats.
- **Reliable Streams:** Used for authoritative command execution and configuration pushes.
- **Congestion Control:** Leverages QUIC's inherent benefits to prevent head-of-line blocking during rapid zone transitions.

## Security Model

## Security Model
Operational security is enforced through the project's native certificate-based trust model:
- **Pinned Certificate Hashes:** Zone servers generate and print their WebTransport certificate hashes upon initialization. The `zone-console` uses these hashes to establish a pinned, secure connection.
- **Mutual TLS:** The console presents a project-signed operational certificate for two-way verification.
- **Verification:** Zone servers verify the physical certificate presented by the console against the internal Operator CA, ensuring authoritative control without external auth dependencies.

## Developer Ergonomics

The console is designed for CLI-first workflows, removing the overhead of the standard Godot UI in favor of:

- **Typed Commands:** Leveraging the `taskweft` library for consistent command parsing.
- **REPL Environment:** A real-time environment for monitoring desyncs and managing adversarial physics scenarios.
- **Raw Telemetry:** Direct access to the E-Graph symbolic regression outputs for real-time performance tuning.

## Operational Capabilities

- **Zone Migration:** Manual and automated triggering of zone handoffs.
- **Bandwidth Shaping:** Real-time adjustment of packet priorities based on Derived Exact Algebraic Bounds.
- **State Inspection:** Direct query of the predictive_bvh state without interrupting the hot-path physics loop.

This documentation captures the transition of the Zone Console into a critical infrastructure component, ensuring that the deployment module retains the authoritative context for how the network is operated.
