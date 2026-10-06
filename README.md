# NoctisENIX

Script Roblox untuk **MAFIA [V2.3] - ACT II** (Topline Studios Inc), ditargetkan untuk executor **Xeno**. Tanpa library eksternal, tanpa Drawing API, tanpa request keluar. Semua fungsi khusus executor dicek dulu dan dibungkus `pcall`; fitur yang butuh fungsi yang tidak ada di Xeno akan mati sendiri tanpa merusak fitur lain.

## Cara pakai

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/caelnoctis/robx/claude/roblox-mafia-noctissenix-1t79fn/NoctisENIX.lua"))()
```

Menu: **RightShift** (bisa diganti di Settings). Eksekusi ulang otomatis meng-unload instance lama.

## Inspector (buat kalibrasi)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/caelnoctis/robx/claude/roblox-mafia-noctissenix-1t79fn/NoctisENIX_Inspector.lua"))()
```

1. Jalankan **saat sudah di dalam match**, lalu tekan **Snapshot**. Section **GAME NETWORK** memanggil getter baca-saja milik game (role, teamMembers, gamePhase, dan sejenisnya) untuk melihat format balasannya. Remote aksi seperti `onStab` tidak pernah dipanggil Inspector. Section **DECOMPILE** membaca kode modul role client (tanpa menjalankannya) supaya argumen asli `onStab` / `onHeal` kelihatan.
2. Tekan **Start live log**, lalu main satu ronde penuh: malam, ada yang ditusuk, ada yang di-heal, meeting, voting. Kalau bisa, sekali jadi Mafia dan sekali jadi role lain.
3. Tekan **Save**. Hasilnya tersimpan di folder `workspace/NoctisENIX/` milik Xeno (dan ikut tersalin ke clipboard).
4. Kirim file `.txt` itu. Isinya struktur modul game, config role, attribute, animasi, remote, dan log kejadian selama ronde, jadi deteksi role dan fitur aksi bisa dicocokkan dengan nama-nama asli game.

## Fitur

| Tab | Isi |
| --- | --- |
| ESP | Highlight warna tim (merah Evil, emas Veil, hijau Town, ungu Neutral, abu-abu = belum pasti), baris `EVIL TEAM` / nama / `[ROLE]`, nama asli di balik disguise, status DOWNED / DETAINED / SILENCED / IN LOCKER, jarak, HP. Default cuma role yang **pasti**; tebakan bisa dinyalakan lewat "Show guesses too" |
| Roles | Role kamu, daftar role yang sudah ketahuan beserta alasannya, kill feed dan log bukti, notifikasi role, alert saat ada yang vote kamu, reset ronde |
| Deception | Fake crawl, fake stab (`KnifeSwing`), fake gunshot (`Glock`), ghost, **Escape meeting seat**, **Stand on the table** (semuanya bisa diberi keybind) |
| Teleport | Pilih target, ke target / ke yang downed / ke yang detained, Teleport-Stab-Return (Mafia), Bring target, Teleport-Heal-Return (Doctor) |
| Player | Walk speed, jump power, infinite jump, noclip, fly, FOV |
| Players | Daftar pemain + role, tombol target, teleport, spectate |
| World | Fullbright, no fog, instant interact, anti AFK |
| Dev Tools | Scan remote, dump pemain, remote logger |
| Settings | Toggle key, cek game, rejoin, unload |

## Catatan penting (v2.1)

* **Tombol stab / tembak (T / F) tidak muncul?** Ada dua penyebab yang terlihat di log game:
  1. Kamu sedang **Detained** (dipenjara Detainer). Selama itu game memang mematikan aksi Mafia.
  2. Versi sebelumnya me-`require` modul controller game. Di Xeno, hal itu menjalankan ulang kode controller dan bisa merusak binding tombol. Sejak v2.1, NoctisENIX dan Inspector **tidak pernah** me-`require` modul client; yang di-require cuma config data (`shared.configurations`).
* Tutup menu (RightShift) saat membidik tusukan atau tembakan. Selama menu terbuka, mouse dilepas supaya UI bisa diklik, sehingga game tidak bisa membidik.
* Role call ketat: chat pemain di game ini lewat jalur pesan sistem, dan dulu sempat terbaca sebagai pengumuman. Sekarang chat pemain diabaikan, animasi serangan dikunci ke ID asli (`KnifeSwing`, `Glock`), dan yang tampil default cuma role yang pasti.

## Cara kerja deteksi role

Game ini **tidak menyimpan role pemain lain di client**. Dump attribute dari game asli mengonfirmasi hal itu: yang ada cuma `DisguiseName`, status seperti `Downed`, dan attribute `<Role>Boosters` (booster peluang dapat role, **bukan** role yang sedang dipegang, jadi sengaja diabaikan). Karena itu role dikumpulkan dari beberapa sumber, dengan tingkat keyakinan `confirmed`, `likely` (`?`), dan `suspect` (`??`):

* **Jaringan game** (`ReplicatedStorage.ServiceNetworks` dan `RoleNetworks`):
  * Role kamu sendiri dari `roleService.role`, plus `getRoleNetwork`.
  * Rekan setim dari `teamService.teamMembers` dan `teamMembers` milik role Evil (Mafia, Witch, Bodyguard).
  * Pengungkapan role dari `gameService.revealRoles`, cutscene kematian, `chatService.onSystemMessage`, dan `announcementService.show`.
  * Fase dari `gameService.gamePhase` dan `setTopbarText`.
* **Bukti aksi**: animasi tusuk atau tembak saat malam (Mafia), tembakan siang (Vigilante), korban kena silence (Witch), pintu dikunci atau banana (Saboteur), pintu dibuka atau bersih-bersih (Janitor), korban bangun dari downed atau sembuh dari racun (Doctor). Kalau ada beberapa kandidat, kandidat dipersempit dari kejadian ke kejadian.
* **Pengumuman sistem**, termasuk alur tebakan Harbinger.

Role yang dikenali: Mafia, Witch, Bodyguard (Evil), Saboteur, Mirage (Veil), Detective, Doctor, Vigilante, Janitor, Detainer (Town), serta Poisoner, Phantom, Harbinger, Judge, Suppressor, Jester, dan Snow Spirit (tim dibaca dari config game kalau bisa).

Bentuk argumen remote (misalnya apa yang dikirim `revealRoles`, atau argumen `onStab`) belum terlihat langsung, jadi parser-nya dibuat toleran terhadap beberapa bentuk. Hasil Inspector (section **GAME NETWORK** dan live log) dipakai untuk mengunci format pastinya.

## Struktur repo

```
src/main.lua            UI, ESP, movement, wiring
src/modules/*.lua       ui (library UI), game_api (akses internal game), net (jaringan game),
                        intel (deteksi role), actions (deception + teleport)
src/inspector.lua       Inspector
tools/build.py          rakit src/ jadi NoctisENIX.lua dan NoctisENIX_Inspector.lua
tests/                  harness Luau (luau-web) dengan mock Roblox
```

Setelah mengubah `src/`: `python3 tools/build.py`, lalu jalankan tes di `tests/` (lihat `tests/README.md`).

## Catatan keamanan dan risiko

* Script referensi `04Jordn/SUMMIT` di-obfuscate (Luraph). Kode NoctisENIX tidak diambil dari sana. Yang dipakai hanya nama-nama internal game yang terbaca dari tabel konstantanya, dan semua nama itu tetap dicek ulang saat runtime.
* NoctisENIX tidak melakukan request jaringan keluar. Inspector hanya menulis file lokal di folder workspace executor.
* Fitur seperti ghost dan teleport bisa dideteksi server game. Menjalankan script di executor melanggar Terms of Use Roblox dan berisiko akun terkena ban. Pakai akun alt.
