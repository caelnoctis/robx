# Tests

A Luau harness based on [luau-web](https://www.npmjs.com/package/luau-web) with a simple Roblox mock
(`prelude.lua`). The mock only proves that the Lua logic runs; whether the Roblox API usage and the real
game behavior are correct still has to be checked in the game (with the Inspector).

```
cd tests && npm install      # once
bash run_all.sh              # build + every test
```

| File | Contents |
| --- | --- |
| `check.mjs` | Luau compile check |
| `lint.mjs` | finds undefined globals (variable typos) |
| `modtest.mjs` | runs one module (`Name=path`) + a test file with a fake `ctx` (`ctx_mock.lua`) |
| `smoke.mjs` | runs the whole `NoctisENIX.lua` + scenarios (`smoke_main.lua` for the UI with stub modules, `smoke_real.lua` + `smoke_world.lua` for the real modules and a fake game network) |
| `modules/` | per-module tests |
| `stubs/` | fake intel/actions for the UI tests (`python3 tools/build.py --stub`) |
