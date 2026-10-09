# NoctisENIX

Script Roblox untuk **MAFIA [V2.3] - ACT II** (Topline Studios Inc), ditargetkan untuk executor **Xeno**. Tanpa library eksternal, tanpa Drawing API, tanpa request keluar. Semua fungsi khusus executor dicek dulu dan dibungkus `pcall`; fitur yang butuh fungsi yang tidak ada di Xeno akan mati sendiri tanpa merusak fitur lain.

## Cara pakai

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/caelnoctis/robx/claude/roblox-mafia-noctissenix-1t79fn/NoctisENIX.lua"))()
```

Menu: **RightShift** (bisa diganti di Settings). Eksekusi ulang otomatis meng-unload instance lama.

**Keybind** tersimpan otomatis di `workspace/NoctisENIX/settings.json` (folder workspace milik Xeno) dan dimuat lagi setiap script dijalankan. Klik chip lalu tekan tombol untuk mengikat; klik kanan chip (atau Backspace saat chip bertuliskan PRESS) untuk menghapus; tombol **Clear all keybinds** di Settings menghapus semuanya kecuali menu key. Satu tombol keyboard cuma bisa dipakai satu fitur.

## Inspector (buat kalibrasi)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/caelnoctis/robx/claude/roblox-mafia-noctissenix-1t79fn/NoctisENIX_Inspector.lua"))()
```

1. Jalankan **saat sudah di dalam match**, lalu tekan **Snapshot**. Section **GAME NETWORK** memanggil getter baca-saja milik game (role, teamMembers, gamePhase, dan sejenisnya) untuk melihat format balasannya. Remote aksi seperti `onStab` tidak pernah dipanggil Inspector. Section **DECOMPILE** membaca kode modul role client (tanpa menjalankannya) supaya argumen asli `onStab` / `onHeal` kelihatan.
2. Tekan **Start live log**, lalu main satu ronde penuh: malam, ada yang ditusuk, ada yang di-heal, meeting, voting. Kalau bisa, sekali jadi Mafia dan sekali jadi role lain.
3. Tekan **Save**. Hasilnya tersimpan di folder `workspace/NoctisENIX/` milik Xeno (dan ikut tersalin ke clipboard).
4. Kalau layar tetap gelap waktu EMP walaupun Fullbright nyala: **Start live log**, tunggu sampai ada EMP, lalu **Save**. Section **LIGHTING** dan baris `LIGHT` di live log menunjukkan apa saja yang diubah EMP (property Lighting, efek di Lighting / Camera, ScreenGui `EmpInk` / `EmpAfterimage`, lampu). Bagian ini cuma membaca, tidak menulis apa pun ke game.
5. Kirim file `.txt` itu. Isinya struktur modul game, config role, attribute, animasi, remote, dan log kejadian selama ronde, jadi deteksi role dan fitur aksi bisa dicocokkan dengan nama-nama asli game.

## Fitur

| Tab | Isi |
| --- | --- |
| ESP | Highlight warna tim (merah Evil, emas Veil, hijau Town, ungu Neutral, abu-abu = belum pasti), baris `EVIL TEAM` / **nama karakter in-game** / `[ROLE]` dengan **warna role asli game** (@username Roblox opsional), status DOWNED / DETAINED / SILENCED / IN LOCKER, jarak, HP. Teks langsung di atas kepala tanpa kotak gelap (kotaknya bisa dinyalakan lagi lewat "Text background"). Default cuma role yang **pasti**; tebakan bisa dinyalakan lewat "Show guesses too" |
| Votes (di tab Visuals) | "Penglihatan Judge" untuk role apa pun. **Vote tags**: `VOTES → nama` atau `VOTES → SKIP` di atas kepala pemilih dan `N VOTES` di atas orang yang di-vote. **Vote lasers**: garis tembus tembok dari tangan pemilih ke orang yang dia vote, merah kalau yang di-vote itu kamu. Jalan walaupun ESP mati |
| Roles | Role kamu, daftar **siapa vote siapa** + tally (hasil voting terakhir tetap tampil 2 menit), daftar role yang sudah ketahuan beserta alasannya, kill feed dan log bukti, notifikasi role, alert saat ada yang vote kamu, reset ronde |
| Deception | Fake crawl, fake stab (`KnifeSwing`), fake gunshot (`Glock`), ghost, **Escape meeting seat**, **Stand on the table** (semuanya bisa diberi keybind) |
| Teleport | Pilih target, ke target / ke yang downed / ke yang detained, Teleport-Stab-Return (Mafia), Bring target, Teleport-Heal-Return (Doctor) |
| Player | Walk speed, jump power, infinite jump, noclip, fly, FOV |
| Players | Daftar pemain + role, tombol target, teleport, spectate |
| World | Fullbright, no fog, instant interact, anti AFK |
| Dev Tools | Scan remote, dump pemain, remote logger |
| Settings | Menu key, keybind (simpan / hapus), **hotkey game kamu** (T / G / R / Q / E / F atau yang sudah kamu ganti), kursor, cek game, rejoin, unload |

## Catatan penting (v2.1)

* **Tombol stab / tembak (T / F) tidak muncul?** Ada dua penyebab yang terlihat di log game:
  1. Kamu sedang **Detained** (dipenjara Detainer). Selama itu game memang mematikan aksi Mafia.
  2. Versi sebelumnya me-`require` modul controller game. Di Xeno, hal itu menjalankan ulang kode controller dan bisa merusak binding tombol. Sejak v2.1, NoctisENIX dan Inspector **tidak pernah** me-`require` modul client; yang di-require cuma config data (`shared.configurations`).
* Tutup menu (RightShift) saat membidik tusukan atau tembakan. Selama menu terbuka, mouse dilepas supaya UI bisa diklik, sehingga game tidak bisa membidik.
* Role call ketat: chat pemain di game ini lewat jalur pesan sistem, dan dulu sempat terbaca sebagai pengumuman. Sekarang chat pemain diabaikan, animasi serangan dikunci ke ID asli (`KnifeSwing`, `Glock`), dan yang tampil default cuma role yang pasti.

## Catatan v2.3 (kalibrasi dari capture lobby)

* **Ability nggak keluar waktu tombolnya ditekan?** Tombol ability di game ini bisa diganti pemain, dan pilihannya tersimpan di attribute `Hotkeys` (contoh `{"ability2":"F","flashlight":"G"}`). Bawaannya Main ability **T**, Second ability **G**, Third ability **R**, perk **Q**, interact **E**, flashlight **F**. Settings > **Game hotkeys** sekarang menampilkan tombol yang benar-benar aktif di akun kamu (tanda `*` = sudah kamu ganti).
* Kalau keybind NoctisENIX dipasang di tombol yang sama dengan ability game, muncul peringatan, karena sekali tekan dua-duanya jalan.
* Game punya tombol **Free cursor** sendiri (bawaan **P**). Kalau kursor kekunci di luar menu, tombol itu yang melepasnya.
* Warna role di ESP diambil dari `roleColorsConfig` game, jadi persis sama dengan warna di UI game.

## Cara kerja Vote ESP (v2.4)

Di game ini cuma **Judge** yang bisa melihat siapa vote siapa ("No ballot is secret in your court"): game memasang tag `judgeBallotTag` ("VOTES TO SKIP" / "ACCUSES Nora") dan laser `judgeBallotLaser` khusus untuk Judge. NoctisENIX memberi tampilan yang sama ke role apa pun. Data vote diambil dari jaringan game, semuanya cuma dibaca (urut dari yang paling dipercaya):

1. Tag `judgeBallotTag` di layar kamu, kalau kamu sendiri Judge.
2. `RoleNetworks.judge.observedBallots`: getter ballot milik Judge, ditanya tiap 2,5 detik **hanya selama voting**. Kalau server cuma mengisinya untuk Judge, hasilnya kosong dan sumber lain yang dipakai.
3. `gameService.talliedVotes`: tally vote.
4. `gameService.votePlayer`, kalau server menyiarkannya.
5. `pointingService.updateArmPointing`: lengan setiap pemain yang menunjuk orang yang dia vote. Event ini dikirim ke semua client. Bentuk aslinya (dari capture Act II): `{ ["<UserId>"] = {...} }`, dan `"r"` berarti lengan diturunkan. Isi `{...}` dibaca toleran: pemain, karakter, part tubuh, UserId, nama karakter, posisi, arah, atau kata "skip".
6. Attribute `talliedVotes` / `playerVotes` sebagai cadangan.

Kalau ada vote yang nggak muncul, jalankan Inspector 1.3.0 dengan **Start live log** selama satu voting lalu kirim hasilnya. Versi ini menulis isi `updateArmPointing` sampai 4 tingkat dan ikut men-decompile modul Judge serta `pointingController`.

## Cara kerja deteksi role

Game ini **tidak menyimpan role pemain lain di client**. Dump attribute dari game asli mengonfirmasi hal itu: yang ada cuma `DisguiseName`, status seperti `Downed`, dan attribute `<Role>Boosters` (booster peluang dapat role, **bukan** role yang sedang dipegang, jadi sengaja diabaikan). Karena itu role dikumpulkan dari beberapa sumber, dengan tingkat keyakinan `confirmed`, `likely` (`?`), dan `suspect` (`??`):

* **Jaringan game** (`ReplicatedStorage.ServiceNetworks` dan `RoleNetworks`):
  * Role kamu sendiri dari `roleService.role`, plus `getRoleNetwork`.
  * Rekan setim dari `teamService.teamMembers` dan `teamMembers` milik role kamu.
  * Pengungkapan role dari `gameService.revealRoles`, cutscene kematian, `chatService.onSystemMessage`, dan `announcementService.show`.
  * Fase dari `gameService.gamePhase` dan `setTopbarText`.
* **Bukti aksi**: animasi tusuk atau tembak saat malam (Mafia), tembakan siang (Vigilante), korban kena silence (Witch), pintu dikunci atau banana (Saboteur), pintu dibuka atau bersih-bersih (Janitor), korban bangun dari downed atau sembuh dari racun (Doctor). Kalau ada beberapa kandidat, kandidat dipersempit dari kejadian ke kejadian.
* **Pengumuman sistem**, termasuk alur tebakan Harbinger.

Role dan tim (dibaca dari `teamsConfig` game saat di dalam match; cadangannya disalin dari capture Inspector):

| Tim | Role |
| --- | --- |
| Evil (Mafia) | Mafia, Witch |
| Veil | Saboteur, Mirage, Poisoner, Harbinger |
| Town | Civilian, Detective, Doctor, Vigilante, Janitor, Detainer, Judge, Suppressor |
| Neutral | Jester, Bodyguard |

Bodyguard itu netral, tapi sisinya ikut orang yang dia jaga. Kalau dia muncul di daftar `teamMembers` Mafia, ESP menampilkan `EVIL TEAM` + `[BODYGUARD]`. Phantom dan Snow Spirit adalah role musiman; selama `seasonalRolesConfig` mematikannya, keduanya tidak ikut dicocokkan.

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
