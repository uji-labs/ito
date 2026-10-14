#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v emcc >/dev/null && [[ -f target/emsdk/emsdk_env.sh ]]; then
    EMSDK_QUIET=1 source target/emsdk/emsdk_env.sh >/dev/null
fi
command -v emcc >/dev/null || { echo 'Install Emscripten and source emsdk_env.sh first.' >&2; exit 1; }

# Use the rustup compiler that owns the installed target, even when a system
# Cargo happens to come first on PATH (for example in an npm script).
ito_cargo=(cargo)
if command -v rustup >/dev/null; then
    ito_toolchain="${ITO_RUST_TOOLCHAIN:-stable}"
    ito_cargo=("$(rustup which --toolchain "$ito_toolchain" cargo)")
    export RUSTC="$(rustup which --toolchain "$ito_toolchain" rustc)"
fi
"${ito_cargo[@]}" rustc --locked --release -p ito-web --bin ito-web --target wasm32-unknown-emscripten -- \
    -C link-arg=-sMODULARIZE=1 -C link-arg=-sEXPORT_ES6=1 \
    -C link-arg=-sEXPORT_NAME=createIto -C link-arg=-sENVIRONMENT=web,worker \
    -C link-arg=-sALLOW_MEMORY_GROWTH=1 -C link-arg=-sSTACK_SIZE=2097152 \
    -C link-arg=-sEXPORTED_FUNCTIONS=_main,_ito_call \
    -C link-arg=-sEXPORTED_RUNTIME_METHODS=ccall -C link-arg=-sNO_EXIT_RUNTIME=1
mkdir -p target/web
cp target/wasm32-unknown-emscripten/release/ito-web.js target/web/ito-web.js
cp target/wasm32-unknown-emscripten/release/ito_web.wasm target/web/ito_web.wasm
cp web/index.html web/canvas.js web/renderer.js web/demo.lua target/web/
echo 'Built target/web. Preview with: python3 -m http.server 8080 --directory target/web'
