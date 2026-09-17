 Open5GS Docker (v2.8.0)

A 5G Core Network (Open5GS v2.8.0) Docker Compose deployment for the NSS Lab — built from source (not a pre-built image), with a NAT/iptables fix so UEs can reach the internet.

This project is part of the **5G Private Network from Open Source** research project by NSS-Network , in collaboration with KMUTNB, Five Access Systems Co ,Ltd.

> Note: this repo covers the **5G Core** only. It does not include the RAN (OAI/OCUDU CU-CP/CU-UP/DU), which requires real SDR hardware to run.

## Architecture

```
                     ┌─────────────────────────────────────────┐
                     │        br-core-ran (10.10.0.0/24)        │
                     │                                           │
   gNB/UE ──38412──▶ │  AMF(.1) ── AUSF(.11) ── UDM(.12)        │
   (external)        │    │            │           │             │
                     │    │         UDR(.13) ── MongoDB(.2)      │
                     │    ▼                                      │
                     │  SMF(.21) ── PCF(.14) ── NSSF(.15)        │
                     │    │                        BSF(.16)      │
                     │    ▼                                      │
                     │  UPF(.22) ──▶ ogstun (10.45.0.0/16) ──▶ internet
                     │                                           │
                     │  NRF(.10)  ◀── every NF registers here    │
                     │  WebUI(.3) :3000  ◀── subscriber management│
                     └─────────────────────────────────────────┘
```

| NF | IP | Role |
|---|---|---|
| NRF | 10.10.0.10 | Network Repository — NF discovery |
| AMF | 10.10.0.1 | Access & Mobility Management (N2/NGAP, port 38412) |
| AUSF | 10.10.0.11 | Authentication |
| UDM | 10.10.0.12 | Unified Data Management |
| UDR | 10.10.0.13 | Unified Data Repository (connects to MongoDB) |
| PCF | 10.10.0.14 | Policy Control |
| NSSF | 10.10.0.15 | Network Slice Selection |
| BSF | 10.10.0.16 | Binding Support |
| SMF | 10.10.0.21 | Session Management |
| UPF | 10.10.0.22 | User Plane (N3/GTP-U, NAT to internet) |
| MongoDB | 10.10.0.2 | Subscriber database |
| WebUI | 10.10.0.3 | Web console for subscriber management (port 3000) |

**PLMN**: MCC=001, MNC=01 · **TAC**: 1 · **UE Subnet**: `10.45.0.0/16` (internet), `10.46.0.0/16` (ims)

## Requesting Access

The container images (`ghcr.io/nss-network/...`) used by this repo are currently **private**. To `docker pull` or `docker compose up`, you need read access to the NSS-Network GitHub Container Registry.

Please contact us to request access:

- **Email**: th2026.opensource@gmail.com
- **Tel**: +66 81 597 0262

Once access is granted, log in to the registry before pulling:

```bash
docker login ghcr.io -u <your-github-username>
```

## Prerequisites

- Docker Engine + Docker Compose plugin (`docker compose version` works)
- A Linux host that supports `iptables` and `ip tuntap` (needed by UPF to create a TUN interface and set up NAT)
- `sudo`/root access on the host (the UPF container runs as `privileged: true`)
- Port 38412/sctp and 3000/tcp open on any firewall in front of the host

## Getting Started

This repo ships two deployment options:

| File | Layout | Best for |
|---|---|---|
| `docker-compose.yml` | Each NF is a separate image (`nss-amf`, `nss-smf`, ...) | Pulling only the NFs you need; image names map clearly to each NF |
| `docker-compose.single-image.yml` | Every NF shares one image (`nss-open5gs-v2.8.0`), differing only by `command:` | Pulling once to save disk space; updating every NF's version in one place |

Both files are built from the same Open5GS v2.8.0 source and use the same config directory (`config/open5gs/`). Behavior is identical — only image management differs.

**Option A — one image per NF (default):**

```bash
git clone https://github.com/NSS-Network/nss-open5gs-docker.git
cd nss-open5gs-docker
docker compose up -d
```

**Option B — single shared image for all NFs:**

```bash
git clone https://github.com/NSS-Network/nss-open5gs-docker.git
cd nss-open5gs-docker
docker compose -f docker-compose.single-image.yml up -d
```

Wait a moment, then check that every container is `Up`:

```bash
docker compose ps
```

You should see nrf, ausf, udm, udr, pcf, nssf, bsf, amf, smf, upf, mongo, and webui all `Up`/`running`.

### Adding a Subscriber

Open a browser to `http://<host-ip>:3000`

```
Username: admin
Password: 1423
```

Click **+ (Add Subscriber)** and fill in:

| Field | Value |
|---|---|
| IMSI | 001010000000001 |
| Subscriber Key (K) | 465B5CE8B199B49FAA5F0A2EE238A6BC |
| Operator Key (OPc) | E8ED289DEBA952E4283B54E88E6183CA |
| APN/DNN | internet |
| SST | 1 |
| SD | ffffff (or your own value — must match the gNB side) |

> The K/OPc values above are default test values only. They must match the SIM or UE simulator you actually use.

### Connecting a gNB

Point your gNB's AMF address (OAI, srsRAN, or others) to:

```
AMF N2/NGAP: <host-ip>:38412 (SCTP)
PLMN: MCC=001, MNC=01
TAC: 1
```

## Config Files

Per-NF configuration lives under `config/open5gs/*.yaml`. Edit directly, then restart the affected service:

```bash
docker compose restart <service-name>
```

`config/open5gs/entrypoint_open5gs.sh` runs before every NF starts. For UPF specifically, it creates the TUN interfaces (`ogstun`, `ogstun2`) and sets up NAT (MASQUERADE) so UEs can reach the internet automatically — **no manual iptables setup needed**.

## Troubleshooting

| Symptom | Likely cause | How to check |
|---|---|---|
| Container won't start / restart loop | NF depends on NRF or another service that isn't ready yet | `docker compose logs <service>` |
| UE can't attach (No route to AMF) | Firewall blocking 38412/sctp | `nc -zv <host-ip> 38412` |
| UE attach fails | IMSI/K/OPc mismatch with WebUI | Check the subscriber entry in WebUI matches your UE/SIM |
| UE gets an IP but has no internet | UPF container lacks permission to create TUN/iptables rules | Verify UPF runs `privileged: true` and the host supports `iptables`/`tuntap` |
| Can't reach WebUI | Port 3000 blocked, or mongo isn't ready | `docker compose logs webui mongo` |

Check logs for a specific NF:

```bash
docker compose logs -f amf
docker compose logs -f upf
```

## License & Credits

Built from [Open5GS](https://github.com/open5gs/open5gs) v2.8.0 (Apache-2.0)

Maintained by NSS Network — Email: th2026.opensource@gmail.com, Tel: +66 81 597 0262 — 5G Private Network research project
