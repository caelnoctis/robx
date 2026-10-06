# Tests

Harness Luau berbasis [luau-web](https://www.npmjs.com/package/luau-web) dengan mock Roblox sederhana
(`prelude.lua`). Mock cuma membuktikan logika Lua berjalan; kebenaran API Roblox dan perilaku game asli
tetap harus dicek di game (pakai Inspector).

```
cd tests && npm install      # sekali
bash run_all.sh              # build + semua tes
```

| File | Isi |
| --- | --- |
| `check.mjs` | compile check Luau |
| `lint.mjs` | cari global yang tidak terdefinisi (typo variabel) |
| `modtest.mjs` | jalankan satu modul (`Name=path`) + test file dengan `ctx` palsu (`ctx_mock.lua`) |
| `smoke.mjs` | jalankan `NoctisENIX.lua` utuh + skenario (`smoke_main.lua` untuk UI dengan modul stub, `smoke_real.lua` + `smoke_world.lua` untuk modul asli dan jaringan game palsu) |
| `modules/` | tes per modul |
| `stubs/` | intel/actions palsu untuk tes UI (`python3 tools/build.py --stub`) |
