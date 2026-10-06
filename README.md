# NoctisENIX

Script Roblox untuk **MAFIA [V2.3] - ACT II** (Topline Studios Inc). Satu file, tanpa library eksternal, tanpa Drawing API, dan semua fungsi khusus executor dijaga pengecekan nil supaya aman di **Xeno**.

## Cara pakai

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/caelnoctis/robx/claude/roblox-mafia-noctissenix-1t79fn/NoctisENIX.lua"))()
```

Setelah branch di-merge, ganti segmen `claude/roblox-mafia-noctissenix-1t79fn` dengan `main`. Kalau repo berstatus private, raw URL akan 404. Jadikan repo public, atau paste isi `NoctisENIX.lua` langsung ke executor.

Menu dibuka atau ditutup dengan **RightShift** (bisa diganti di tab Settings). Eksekusi ulang otomatis meng-unload instance lama.

## Fitur

| Tab | Isi |
| --- | --- |
| ESP | Highlight dan name tag berwarna sesuai role (merah Mafia, biru Detective, hijau Doctor), jarak, HP, notifikasi saat role terdeteksi, memori role |
| Player | Walk speed, jump power, infinite jump, noclip, fly, custom FOV |
| Players | Daftar pemain beserta role, tombol teleport dan spectate |
| World | Fullbright, no fog, instant interact (hold = 0), anti AFK |
| Dev Tools | Scan remote, dump info pemain, remote logger (FireServer / InvokeServer), semuanya bisa di-copy ke clipboard |
| Settings | Ganti toggle key, cek game, rejoin, unload |

## Cara kerja deteksi role

Role pemain lain tidak selalu dikirim ke client oleh game, jadi script membaca sinyal yang memang terlihat, dengan urutan berikut:

1. Attribute (`Role`, `Team`, dst) di Player atau Character
2. Value object bernama `Role` di Player atau Character
3. Nama Team
4. Tool yang sedang dipegang (pisau, pistol, suntik, dst). Backpack pemain lain tidak terlihat dari client, jadi tool baru terbaca saat di-equip.

Role yang sudah terdeteksi disimpan (latch) sampai karakter respawn atau tombol **Clear role memory** ditekan. Daftar kata kunci ada di `Config.Roles` pada bagian atas file dan bisa diedit.

## Kalibrasi di map asli

Nama tool dan struktur role di map ini belum bisa diperiksa dari luar game. Kalau ada pemain yang role-nya tidak terbaca:

1. Masuk match, buka tab **Dev Tools**.
2. Tekan **Dump all players** dan **Scan remotes**, hasilnya otomatis masuk clipboard.
3. Aktifkan **Log remote calls**, lakukan aksi di game (vote, pakai skill), lalu **Copy remote log**.
4. Dari hasil itu kata kunci role dan fitur yang menembak remote bisa disesuaikan.

## Catatan keamanan dan risiko

* Script referensi `04Jordn/SUMMIT` di-obfuscate dengan Luraph V15, jadi isinya tidak bisa diaudit dan tidak dipakai sebagai dasar kode. NoctisENIX ditulis dari nol dan seluruh kodenya terbaca.
* Script ini tidak melakukan request jaringan keluar. Satu-satunya pemanggilan layanan Roblox di luar gameplay adalah `MarketplaceService:GetProductInfo` untuk mengecek nama game.
* Menjalankan script di executor melanggar Terms of Use Roblox dan berisiko akun terkena ban. Pakai akun alt.
