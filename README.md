# Ito

A declarative terminal UI kit in Lua, shipped as embeddable Rust source and a native Lua module.

Views compose through stacks, grids, custom layouts, and modifiers. Images use the same layout and interaction conventions as text.

```lua
local ito = require("ito")
local source = ito.ImageSource.file("photo.jpg")

local Photo = ito.view(function(props)
    return ito.Image(props.source)
        :content_mode(ito.ImageMode.fit)
        :alt("Mountain at sunset")
end)

local content = ito.VStack({
    ito.Text("Photo"),
    Photo({ source = source }):height(16):padding(1),
})
```

Image graphics are opt-in. Enable Kitty Unicode placeholders on the screen with `screen:configure_images({ protocol = "kitty" })`; otherwise the image shows its text or custom fallback. See [image configuration, resources, and viewer controls](docs/images.md).

To try the interactive image viewer in a compatible terminal:

```sh
cargo build --release --features module,luajit
luajit examples/images.lua photo.jpg
```

`just test` builds the native module and runs the Lua specs. `just check` also runs formatting and lint checks. Rust image tests run with `cargo test --features luajit52,vendored`.
