# Rencana Deployment `game-coop` (RomM + EmulatorJS)

**Status:** `Planned — belum di-deploy`
**Target Domain:** `https://play.andresptr.site`
**Lokasi Proyek:** `/opt/apps/game-coop`

Dokumen ini adalah rencana teknis lengkap untuk men-deploy **RomM + EmulatorJS** sebagai portal *story single-player* dan *couple duo co-op* via browser laptop di VPS `VM-14-216-ubuntu` secara aman tanpa mengganggu layanan produksi yang sudah berjalan.

---

## 1. Ringkasan & Baseline Audit VPS

Hasil audit live server (`VM-14-216-ubuntu`) yang menjadi dasar rencana ini:

| Parameter | Kondisi Terverifikasi | Catatan Implementasi |
| --- | --- | --- |
| **DNS Subdomain** | `play.andresptr.site` → `43.156.91.169` (sama dengan `andresptr.site`) | Siap untuk penerbitan SSL ACME via 1Panel OpenResty |
| **CPU** | `2 vCPU` Intel Xeon Platinum 8255C @ `2.50 GHz` (tanpa GPU) | Emulasi berjalan di browser laptop; beban CPU VPS rendah |
| **RAM** | `7.5 GiB` total, **`5.6 GiB` tersedia** | Headroom lega untuk batas container `1024 MiB` |
| **Disk (`/dev/vda2`)** | `79 GiB` total, `31 GiB` terpakai (41%), **`45 GiB` tersedia** | Alokasi library game ditargetkan `15–20 GiB` (jaga ≥20 GiB free) |
| **PostgreSQL Existing** | Container `1Panel-postgresql-3oWY` (`postgres:18.7-alpine`) di network `1panel-network` (`172.18.0.2`), port `127.0.0.1:5432`, RAM `23.9 MiB` | Dipakai bersama dengan isolasi database & role khusus `romm` |
| **Port Terpakai Host** | `22`, `80`, `443`, `3000–3003`, `3088`, `3089`, `4000`, `5000`, `5432`, `5678`, `18495` | Port RomM dipilih **`127.0.0.1:8085`** (`-> 8080/tcp`) |

---

## 2. Evaluasi Keamanan Numpang PostgreSQL Existing (`1Panel-postgresql-3oWY`)

**Kesimpulan: AMAN untuk di-host bersama, dengan isolasi database & role yang ketat serta disiplin backup sebelum upgrade.**

### Mengapa Aman & Menguntungkan
1. **Dukungan Resmi RomM**: RomM secara resmi mendukung PostgreSQL (`ROMM_DB_DRIVER=postgresql` via `postgresql+psycopg`, direkomendasikan PG 16+).
2. **Isolasi Data & Privilege**: Dengan membuat database khusus `romm` dan role khusus `romm` (non-superuser) yang **hanya memiliki hak penuh atas database `romm`**, container RomM tidak bisa membaca, mengubah, atau menghapus database milik layanan lain di `1Panel-postgresql-3oWY`.
3. **Hemat Resource Signifikan**: Menghindari penambahan container `mariadb:11` baru menghemat **`~250–350 MiB` RAM**. Selain itu, RomM memiliki Redis/Valkey *embedded* bawaan untuk task queue skala kecil, sehingga seluruh stack RomM cukup berjalan sebagai **1 container tambahan saja**.

### Catatan Jujur & Mitigasi Teknis
- **Driver Utama RomM adalah MariaDB 11**: Sebagian besar pengguna dan pengujian CI RomM memakai MariaDB 11. Di rilis terdahulu sempat ada beberapa *edge case* migrasi Alembic khusus PostgreSQL (misalnya *enum strictness* saat upgrade atau error *insufficient privilege* pada role non-owner di migrasi tertentu seperti isu `#5262` / migrasi `0073`).
- **4 Mitigasi Wajib**:
  1. Pastikan role `romm` menjadi **`OWNER` penuh** atas database `romm` dan schema `public` (`ALTER DATABASE romm OWNER TO romm; ALTER SCHEMA public OWNER TO romm;`).
  2. **Pin tag versi image RomM secara eksplisit** di `.env` (`ROMM_IMAGE_TAG`), jangan memakai tag `:latest` yang mengambang.
  3. Wajib jalankan `pg_dump` database `romm` ke `backups/` **sebelum setiap upgrade versi RomM**.
  4. **Jalur Fallback 5 Menit**: Jika saat boot pertama migrasi Alembic mengalami ketidakcocokan terhadap PostgreSQL `18.7-alpine`, kita bisa langsung beralih ke container terpisah `mariadb:11` (`--memory=512m`) tanpa memengaruhi database atau layanan lain di VPS.

---

## 3. Arsitektur Target & Budget Resource

```text
  [Laptop Anda]                    [Laptop Pasangan]
   Browser + Gamepad                Browser + Gamepad
         \                                /
          \--- WebRTC P2P / TURN Relay --/  (Netplay beda Wi-Fi)
          |                              |
          +------- HTTPS / WSS (443) ----+
                         |
                         v
          1Panel OpenResty (`1Panel-openresty-NKAT`)
            - Domain: play.andresptr.site (ACME TLS)
            - Headers: COOP=same-origin, COEP=require-corp
            - WebSocket Upgrade + client_max_body_size 0
                         |
                         v  (127.0.0.1:8085 -> 8080/tcp)
          Container `romm` (`rommapp/romm:<pinned>`)
            - Limits: 1.0 vCPU, 1024 MiB RAM/Swap
            - Embedded Valkey/Redis + EmulatorJS Assets
            - Storage: /opt/apps/game-coop/data/{library,assets,resources,redis}
                         |
                         v  (Docker network: 1panel-network)
          `1Panel-postgresql-3oWY` (:5432)
            - Dedicated DB: `romm` | Role: `romm` (non-superuser)
```

### Budget Resource & Storage
- **Container `romm` Cap**: `cpus: "1.0"`, `mem_limit: 1024m`, `memswap_limit: 1024m` (mencegah *memory spike* saat hashing/scanning ROM mengganggu `bubu`, `n8n`, `waha`, `rekapal`, `aet-api`, atau `postgresql`).
- **Target Pemakaian Disk**: `15 – 20 GiB` (agar ruang kosong `/dev/vda2` tetap di atas `~20 GiB`).
- **Format ROM yang Disarankan**:
  - Konsol 8/16/32-bit ringan (NES, SNES, GBA, Genesis): `.zip` (ukuran 1–32 MB).
  - Konsol CD/optical (PS1, Sega CD): konversi ke **`.chd`** (`chdman`) — menghemat ~40–60% ruang disk dan jauh lebih cepat diunduh browser saat game dibuka.
  - PSP: format terkompresi **`.cso`** atau **`.chd`**.

---

## 4. Strategi Netplay Beda Wi-Fi (STUN/TURN)

Karena Anda dan pasangan bermain dari **Wi-Fi yang berbeda**, koneksi WebRTC EmulatorJS sering terhalang NAT simetris router/ISP. Konfigurasi Netplay RomM (v4.5+) diatur di `/opt/apps/game-coop/config/config.yml` pada blok `emulatorjs.netplay`.

### Opsi A — Eksternal Free TURN (Direkomendasikan Pertama)
- Menggunakan layanan TURN gratis seperti **Metered Free TURN** atau **Cloudflare Calls TURN**.
- **Kelebihan**: **Tidak perlu membuka port baru** di Tencent Cloud Security Group/Lighthouse Firewall, tidak ada beban bandwidth/proses tambahan di VPS.
- **Kekurangan**: Kuota bandwidth bulanan gratis (untuk 2 pemain 2D/SNES/PS1 sangat mencukupi — umumnya beberapa GB/bulan).

### Opsi B — Self-Hosted `coturn` di VPS (Fallback jika Opsi A lambat/kuota habis)
- Menjalankan container ringan `coturn/coturn` (`~30 MiB` RAM) di VPS.
- **Konsekuensi Firewall**: Wajib membuka port **`3478/TCP+UDP`** dan rentang port relay UDP kecil (mis. **`49152-49200/UDP`**) di Tencent Cloud Firewall.
- Gunakan Opsi B hanya jika hasil uji coba Netplay dengan Opsi A mengalami kendala koneksi.

---

## 5. Tahapan Eksekusi Deployment (Phase 1–6)

### Phase 1: Persiapan Database di 1Panel PostgreSQL
1. Masuk ke **1Panel → Databases → PostgreSQL** (`1Panel-postgresql-3oWY`), buat:
   - **Database**: `romm`
   - **Username / Role**: `romm` dengan password acak kuat (simpan hanya di `.env`).
2. Pastikan kepemilikan penuh (agar migrasi Alembic RomM berjalan tanpa error privilege):
   ```sql
   ALTER DATABASE romm OWNER TO romm;
   \c romm
   ALTER SCHEMA public OWNER TO romm;
   ```
3. Verifikasi role `romm` **tidak** memiliki atribut `SUPERUSER` dan tidak diberi akses ke database lain.

### Phase 2: Konfigurasi Lokal, Direktori Data & Kredensial Pendukung
1. Buat struktur direktori runtime di `/opt/apps/game-coop`:
   ```bash
   mkdir -p /opt/apps/game-coop/data/{library,assets,resources,redis} /opt/apps/game-coop/backups
   ```
2. Salin template konfigurasi dan ketatkan permission:
   ```bash
   cp /opt/apps/game-coop/.env.example /opt/apps/game-coop/.env
   cp /opt/apps/game-coop/config/config.example.yml /opt/apps/game-coop/config/config.yml
   chmod 600 /opt/apps/game-coop/.env /opt/apps/game-coop/config/config.yml
   ```
3. Isi `.env`:
   - Tentukan tag rilis stabil terbaru di `ROMM_IMAGE_TAG` (cek rilis resmi `rommapp/romm`).
   - Generate `ROMM_AUTH_SECRET_KEY` dengan `openssl rand -hex 32`.
   - Isi `DB_PASSWD` sesuai Phase 1.
   - *(Opsional tapi sangat disarankan)* Isi `IGDB_CLIENT_ID` & `IGDB_CLIENT_SECRET` (gratis via Twitch Developer Console) agar RomM otomatis menarik cover art & sinopsis cerita.
4. Isi `config/config.yml` dengan STUN/TURN `ice_servers` (Opsi A).

### Phase 3: Setup `docker-compose.yml` & Uji Boot Awal
Tambahkan `/opt/apps/game-coop/docker-compose.yml` dengan referensi berikut:

```yaml
services:
  romm:
    image: rommapp/romm:${ROMM_IMAGE_TAG}
    container_name: romm
    restart: unless-stopped
    env_file:
      - .env
    volumes:
      - ./data/resources:/romm/resources
      - ./data/redis:/redis-data
      - ./data/library:/romm/library
      - ./data/assets:/romm/assets
      - ./config:/romm/config
    ports:
      - "127.0.0.1:8085:8080"
    networks:
      - 1panel-network
    cpus: "1.0"
    mem_limit: 1024m
    memswap_limit: 1024m
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8080/api/heartbeat || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 45s

networks:
  1panel-network:
    external: true
```

Jalankan dan pantau log migrasi database pada PostgreSQL 18.7:
```bash
cd /opt/apps/game-coop
docker compose config --quiet
docker compose up -d
docker compose logs -f --tail=100 romm
```
*(Pastikan Alembic selesai mengeksekusi semua migrasi tanpa error. Jika muncul error kompatibilitas PG 18.7, langsung jalankan prosedur Fallback MariaDB di Bagian 6.)*

### Phase 4: Reverse Proxy 1Panel OpenResty + SSL + Header Wajib
1. Di **1Panel → Websites → Create Website** (Reverse Proxy):
   - Domain: `play.andresptr.site`
   - Proxy target: `http://127.0.0.1:8085`
   - Terbitkan sertifikat SSL **ACME / Let's Encrypt** dan aktifkan Force HTTPS.
2. Gabungkan aturan dari [deploy/openresty-play.andresptr.site.conf.example](./deploy/openresty-play.andresptr.site.conf.example) ke `/opt/1panel/apps/openresty/openresty/conf/conf.d/play.andresptr.site.conf`:
   - `client_max_body_size 0;`
   - Header **Cross-Origin Isolation** di level `server` (`Cross-Origin-Opener-Policy "same-origin" always;` dan `Cross-Origin-Embedder-Policy "require-corp" always;`) — wajib agar `SharedArrayBuffer` aktif untuk core threaded seperti PSP (`ppsspp`).
   - Header WebSocket (`Upgrade` & `Connection "upgrade"`) + `proxy_read_timeout 3600s;`.
3. Validasi & reload OpenResty tanpa downtime:
   ```bash
   docker exec 1Panel-openresty-NKAT openresty -t
   docker exec 1Panel-openresty-NKAT openresty -s reload
   ```

### Phase 5: Onboarding Akun Privat & Uji Coba Duo Lintas Wi-Fi
1. Buka `https://play.andresptr.site` → buat **akun admin** Anda lalu **matikan registrasi publik** (`Disable registration`) agar portal tetap privat.
2. Buat **akun kedua** untuk pasangan Anda melalui menu admin.
3. Unggah 1 ROM homebrew/gratis legal (mis. *Micro Mages* demo NES atau *2048* / *Goodboy Galaxy* demo GBA/SNES) dan uji:
   - Single-player + pembuatan Save State → reload halaman → pastikan save tersimpan di server.
   - Uji **Netplay** dari 2 laptop pada **2 jaringan Wi-Fi berbeda** (satu bisa pakai tethering HP): Player 1 *Create Room* berpassword → Player 2 *Join Room* → verifikasi video, audio, dan input gamepad/keyboard sinkron.

### Phase 6: Verifikasi Akhir, Backup Otomatis & Sinkronisasi Inventaris
1. Jalankan seluruh checklist verifikasi:
   - `ss -tlnp | grep 8085` → hanya `127.0.0.1:8085` (bukan `0.0.0.0`).
   - `docker stats --no-stream` → `romm` dan layanan produksi lain stabil dalam batas wajar.
   - `curl -fsSI https://play.andresptr.site` → status `200`/`302`, header `Cross-Origin-Opener-Policy: same-origin` dan `Cross-Origin-Embedder-Policy: require-corp` muncul.
   - Di DevTools Console browser pada halaman game: `self.crossOriginIsolated === true`.
2. Tambahkan skrip backup harian di `scripts/backup.sh` (disimpan ke `backups/`, rotasi 7–14 hari):
   - `pg_dump` database `romm` dari `1Panel-postgresql-3oWY`.
   - Arsip `data/assets/` (berisi **saves & save states** milik Anda & pasangan) dan `config/config.yml`.
3. Setelah semua live & terverifikasi, sinkronkan inventaris sistem:
   - Tambahkan `play.andresptr.site` (port `127.0.0.1:8085`) ke tabel layanan di `~/.gemini/GEMINI.md`.
   - Tambahkan `[projects."/opt/apps/game-coop"]` (`trust_level = "trusted"`) di `~/.codex/config.toml`.

---

## 6. Rencana Rollback & Fallback

- **Rollback Bersih (Batal Hosting)**:
  1. `cd /opt/apps/game-coop && docker compose down`
  2. Hapus site `play.andresptr.site` di 1Panel OpenResty.
  3. Drop database `romm` dan role `romm` di 1Panel PostgreSQL (layanan lain tidak tersentuh).
- **Fallback Database ke MariaDB 11 (Jika Migrasi PG 18.7 Bermasalah)**:
  1. `docker compose down`
  2. Tambah service `romm-db` (`image: mariadb:11`, `--memory=512m`, network internal compose) dan ubah `.env` menjadi `ROMM_DB_DRIVER=mariadb`, `DB_HOST=romm-db`, `DB_PORT=3306`.
  3. Jalankan ulang `docker compose up -d` dan drop database `romm` di PostgreSQL.
