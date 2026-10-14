default:
    @just --list

# Compile the Canvas browser demo with Emscripten.
web:
    bash web/build.sh

# Build the native Lua module that the tests load.
module:
    cargo build --release --features module,luajit --target-dir target

# The Lua specs under tests; filters pick tests by name, like `just test list`.
test *filters: module
    luajit tests/run.lua {{filters}}

# Everything CI would run.
check: module
    cargo fmt --all --check
    cargo clippy --all-targets --features luajit52,vendored --target-dir target -- -D warnings
    cargo clippy --all-targets --features module,luajit --target-dir target -- -D warnings
    cargo clippy --all-targets --features canvas,lua54,vendored --target-dir target -- -D warnings
    cargo clippy -p ito-web --target-dir target -- -D warnings
    stylua --check lua tests
    luacheck lua tests
    selene lua
    selene --config .config/selene/tests.toml tests
    luajit tests/run.lua
    cargo test --features canvas,lua54,vendored --target-dir target
    cargo test -p ito-web --target-dir target
