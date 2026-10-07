// luau-web dimuat lewat sini supaya flag V8 sudah terpasang sebelum WASM-nya dikompilasi.
// Node 22 + luau-web: dynamic tier-up WASM bisa bikin main thread macet di futex setelah run Luau
// yang panjang (tes lolos, tapi proses nggak pernah exit dan run_all.sh ikut menunggu selamanya).
// Tanpa dynamic tiering hasilnya sama dan prosesnya keluar normal.
import v8 from "node:v8";
v8.setFlagsFromString("--no-wasm-dynamic-tiering");
const { LuauState } = await import("luau-web");
export { LuauState };
