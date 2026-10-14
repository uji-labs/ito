# Browser build

Ito's Lua components run inside WebAssembly, with a Canvas 2D renderer for its
styled cell buffer. The browser owns input, resizing, and frame scheduling.
The native terminal remains the default on desktop targets.

The sibling website's `/ito` playground uses this same Canvas backend with
a light host theme. It provides a small terminal host for Lua view functions;
there is no separate DOM control renderer.

## Build

Install the Rust target and [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html).
This branch was built with Rust 1.96.1, Emscripten 4.0.21, and vendored Lua 5.4.

```sh
rustup target add wasm32-unknown-emscripten
git clone --depth 1 https://github.com/emscripten-core/emsdk.git target/emsdk
target/emsdk/emsdk install 4.0.21
target/emsdk/emsdk activate 4.0.21
just web
python3 -m http.server 8080 --bind 127.0.0.1 --directory target/web
```

The SDK installer needs Python 3.10 or newer. If the system `python3` is older,
invoke `emsdk.py` with a newer Python. `web/build.sh` automatically uses the SDK
under `target/emsdk` when `emcc` is absent from `PATH`. An existing SDK works too,
after sourcing its `emsdk_env.sh`.

Open `http://127.0.0.1:8080`. The standalone output is `target/web/`, including
`ito_web.wasm`, its JavaScript loader, the Canvas adapter, and the demo. Serve
these files over HTTP. No server executes the application, and no WebSocket
connection is required.

## Embed

Give the canvas a CSS width and height, then mount a Lua source string:

```js
import { mount } from './canvas.js';

const app = await mount(document.querySelector('canvas'), luaSource, {
  fontSize: 16,
  foreground: '#dce4e1',
  background: '#111916',
  onError: console.error,
});

// Request another frame after an external change, or release the instance.
app.redraw();
app.close();
```

Each mount creates its own Wasm/Lua instance. A Lua chunk returns a function
that drains `input:poll()`, updates its state, renders, and calls
`screen:flush()`. Return a delay in seconds for the next animation frame, or
nil to wait for input. See `demo.lua` for a complete example using the existing
`Window`, `TextField`, `VStack`, and `Spinner` components.

The host supplies a monotonic clock and Unicode display widths through
`ito.setup`. `input:poll()` returns the same event tables as native input.
Keyboard, paste, focus, pointer, wheel, and resize events cross the Wasm bridge.
The renderer supports RGB/indexed colors, text modifiers, wide cells, links,
and block/bar/underline cursors. It sizes the backing canvas for device pixel
ratio. Links open only for HTTP, HTTPS, and mailto destinations.

## Scope

This is an initial Canvas backend with complete frame snapshots. It does not
interpret raw ANSI writes, provide a shell/filesystem host, run LuaJIT, or allow
blocking `input:read()`. Use the frame callback to keep the browser responsive.
Canvas does not expose the drawn controls as semantic DOM elements. The
standalone demo does not include mobile keyboard transport or clipboard
selection copying; the playground adds text
input transport and a readable text fallback. Load trusted application code.

## Playground host

`web/playground.lua` runs a returned Ito view function inside a real `Window`.
It drains input through `Window:event`, runs shared terminal layout and drawing,
and exposes the cell frame plus focus rectangles to the browser. Browser CSS
supplies the fixed palette and framing. The original nonblocking Canvas host
API remains available for applications that own their event loop.

Send `load` with `view: true`, `source`, dimensions, `now`, and a `palette` to
use the playground host. Subsequent `event`, `resize`, and `frame` requests
use the ordinary Canvas bridge. Responses contain `frame`, `interaction`,
`wake`, or `error`. Coordinates and dimensions are terminal cells.

Shared focus supports `:focused(condition)`, pointer activation, Tab/Backtab,
and scoped controls. TextField adds `:on_cancel(fn)` and accepts paste as one
edit. `:on_key(fn)` handles keys left unhandled by the active control. Every
input event is followed by a render so the next event sees the new focus.
The terminal and browser run the same state transitions. Browser text entry
uses one transport for mobile keyboards and IME, with the buffer owned by Lua.

Every browser VM has a 64 MiB Lua allocation limit and instruction budget.
The website runs it in a Worker; invalid edits preserve the accepted VM.
The playground bounds frames to 160 columns and 120 rows. Its Canvas has a text
fallback, but does not offer individual native HTML control semantics.

`npm run bundle:ito` in the sibling website copies the compiled runtime,
Canvas painter, and `web/examples/*.lua`. The input-flow example is exercised
through both the terminal test host and compiled browser runtime.

## Checks

```sh
cargo test -p ito --features canvas,lua54,vendored --test canvas
cargo test -p ito-web
cargo clippy -p ito --all-targets --features canvas,lua54,vendored -- -D warnings
cargo clippy -p ito-web -- -D warnings
just test
```

With the demo served and Playwright installed, `node web/smoke.mjs` checks the
actual Wasm in Chromium, including text entry, paste, clicks, animation, wide
text, links, HiDPI sizing, narrow viewport resizing, and disposal. Set
`ITO_DEMO_URL` to override port 8080. `PLAYWRIGHT_MODULE` can point to an existing
Playwright module and `CHROMIUM_PATH` to an existing Chromium executable.
Screenshots are saved to `target/canvas-desktop.png` and `target/canvas-mobile.png`.
