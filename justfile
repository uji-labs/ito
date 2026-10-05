default:
    @just --list

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
    stylua --check lua tests
    luacheck lua tests
    luajit tests/run.lua
