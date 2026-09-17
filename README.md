# NSS Open5GS Docker (v2.8.0)

5G Core Network (Open5GS v2.8.0) แบบ Docker Compose สำหรับ NSS Lab — build จาก source เอง (ไม่ใช่ image สำเร็จรูป) พร้อม NAT/iptables fix สำหรับ UE ที่จะออก internet ได้จริง

โปรเจกต์นี้เป็นส่วนหนึ่งของโครงการวิจัย **5G Private Network จาก Open Source** โดย NSS-Network ร่วมกับ KMUTNB , Five Access Systems Co,Ltd.

> หมายเหตุ: repo นี้มีเฉพาะส่วน **5G Core** เท่านั้น ยังไม่รวม RAN (OAI/OCUDU CU-CP/CU-UP/DU) ซึ่งต้องมีฮาร์ดแวร์ SDR จริงถึงจะรันได้ครบ

## สถาปัตยกรรม

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
                     │  NRF(.10)  ◀── ทุก NF ลงทะเบียนที่นี่       │
                     │  WebUI(.3) :3000  ◀── จัดการ subscriber   │
                     └─────────────────────────────────────────┘
```

| NF | IP | หน้าที่ |
|---|---|---|
| NRF | 10.10.0.10 | Network Repository — NF discovery |
| AMF | 10.10.0.1 | Access & Mobility Management (N2/NGAP, port 38412) |
| AUSF | 10.10.0.11 | Authentication |
| UDM | 10.10.0.12 | Unified Data Management |
| UDR | 10.10.0.13 | Unified Data Repository (เชื่อม MongoDB) |
| PCF | 10.10.0.14 | Policy Control |
| NSSF | 10.10.0.15 | Network Slice Selection |
| BSF | 10.10.0.16 | Binding Support |
| SMF | 10.10.0.21 | Session Management |
| UPF | 10.10.0.22 | User Plane (N3/GTP-U, NAT ออก internet) |
| MongoDB | 10.10.0.2 | Subscriber database |
| WebUI | 10.10.0.3 | หน้าเว็บจัดการ subscriber (port 3000) |

**PLMN**: MCC=001, MNC=01 · **TAC**: 1 · **UE Subnet**: `10.45.0.0/16` (internet), `10.46.0.0/16` (ims)

## Prerequisites

- Docker Engine + Docker Compose plugin (`docker compose version` ใช้ได้)
- Linux host ที่รองรับ `iptables`, `ip tuntap` (สำหรับ UPF สร้าง TUN interface และตั้ง NAT)
- สิทธิ์ `sudo`/root บนเครื่อง host (UPF container รันแบบ `privileged: true`)
- เปิด port 38412/sctp และ 3000/tcp บน firewall (ถ้ามี)

## วิธีติดตั้งและใช้งาน

```bash
git clone https://github.com/NSS-Network/nss-open5gs-docker.git
cd nss-open5gs-docker
docker compose up -d
```

รอสักครู่แล้วเช็คว่าทุก container ขึ้น `Up`:

```bash
docker compose ps
```

ควรเห็น NF ทั้งหมด (nrf, ausf, udm, udr, pcf, nssf, bsf, amf, smf, upf, mongo, webui) สถานะ `Up` หรือ `running`

### เพิ่ม Subscriber

เปิดเบราว์เซอร์ไปที่ `http://<host-ip>:3000`

```
Username: admin
Password: 1423
```

กด **+ (Add Subscriber)** แล้วกรอก:

| Field | ค่า |
|---|---|
| IMSI | 001010000000001 |
| Subscriber Key (K) | 465B5CE8B199B49FAA5F0A2EE238A6BC |
| Operator Key (OPc) | E8ED289DEBA952E4283B54E88E6183CA |
| APN/DNN | internet |
| SST | 1 |
| SD | ffffff (หรือค่าที่ต้องการ ต้องตรงกับฝั่ง gNB) |

> ค่า K/OPc ด้านบนเป็นค่า default สำหรับทดสอบเท่านั้น ต้องตรงกับ SIM/UE simulator ที่ใช้จริง

### เชื่อมต่อ gNB

ชี้ AMF ของ gNB (OAI, srsRAN หรืออื่นๆ) มาที่:

```
AMF N2/NGAP: <host-ip>:38412 (SCTP)
PLMN: MCC=001, MNC=01
TAC: 1
```

## Config Files

Config ของแต่ละ NF อยู่ที่ `config/open5gs/*.yaml` แก้ไขได้ตรงๆ แล้ว restart container ที่เกี่ยวข้อง:

```bash
docker compose restart <service-name>
```

`config/open5gs/entrypoint_open5gs.sh` เป็น script ที่รันก่อน NF ทุกตัว — สำหรับ UPF จะสร้าง TUN interface (`ogstun`, `ogstun2`) และตั้ง NAT (MASQUERADE) ให้ UE ออก internet ได้อัตโนมัติ **ไม่ต้องตั้ง iptables เองเพิ่ม**

## Troubleshooting

| อาการ | สาเหตุที่เป็นไปได้ | วิธีตรวจสอบ |
|---|---|---|
| Container ไม่ขึ้น / restart loop | NF พึ่งพา NRF/dependency อื่นที่ยังไม่พร้อม | `docker compose logs <service>` |
| UE ต่อไม่ได้ (No route to AMF) | Firewall บล็อก 38412/sctp | `nc -zv <host-ip> 38412` |
| UE attach ไม่ผ่าน | IMSI/K/OPc ไม่ตรงกับที่ตั้งใน WebUI | เช็ค subscriber ใน WebUI ให้ตรงกับ UE/SIM |
| UE ได้ IP แต่ออก internet ไม่ได้ | UPF container ไม่มีสิทธิ์สร้าง TUN/iptables | เช็คว่า UPF รันแบบ `privileged: true` และ host รองรับ `iptables`/`tuntap` |
| WebUI เข้าไม่ได้ | Port 3000 ถูกบล็อก หรือ mongo ยังไม่พร้อม | `docker compose logs webui mongo` |

เช็ค log ของ NF ที่ต้องการ:

```bash
docker compose logs -f amf
docker compose logs -f upf
```

## License & Credits

Build จาก [Open5GS](https://github.com/open5gs/open5gs) v2.8.0 (Apache-2.0)

จัดทำโดย NSS Network — โครงการวิจัย 5G Private Network 
