# Images

`Image` presents an image. `ImageViewer` adds keyboard and optional wheel controls. Both inherit Ito's view modifiers and work inside stacks, grids, scroll views, overlays, and user-defined `ito.view` functions.

## Enable graphics

```lua
local screen, input = ito.open()
screen:configure_images({ protocol = "kitty" })
```

Graphics default to `off`. `kitty` is an explicit assertion that the terminal supports Kitty **Unicode placeholders**, introduced in Kitty 0.28. Basic Kitty graphics support alone is insufficient. Ito does not inspect stdin or send capability probes. The application decides whether to enable graphics, so an unsupported terminal can use the fallback without receiving graphics commands.

Cell dimensions come from the terminal's window-size ioctl when available. Otherwise Ito uses 8 × 16 pixels. Supply both dimensions when the host knows them:

```lua
screen:configure_images({
    protocol = "kitty",
    cell_width = 10,
    cell_height = 20,
    tmux = false,
})
```

Explicit dimensions stay fixed until reconfigured. Automatically measured dimensions update when the screen size is read, including after font changes. `screen:image_capabilities()` returns the configured protocol, cell dimensions, and tmux setting; it is not a probe result.

`tmux = true` wraps graphics in tmux passthrough sequences. The user must enable passthrough in tmux, and the terminal must support placeholders. Ito does not change tmux settings. SSH uses direct image bytes and needs no shared filesystem with the terminal.

## Sources

```lua
local photo = ito.ImageSource.file("photo.jpg")
local uploaded = ito.ImageSource.bytes(png_or_jpeg_bytes)
local pixels = ito.ImageSource.rgba(width, height, rgba_bytes)
```

Files and encoded bytes load asynchronously. Only static PNG and JPEG are decoded; EXIF orientation is applied before cropping. Raw RGBA data must contain exactly `width * height * 4` bytes. Sources are immutable and reusable across views. Creating a new source explicitly reloads a file.

`source:status()` returns `{ phase = "loading" }`, `{ phase = "ready", width = ..., height = ... }`, or `{ phase = "failed", error = ... }`. Dimensions are in pixels after EXIF orientation.

Keep resources outside frequently recomposed functions, or use `ito.remember`:

```lua
local Photo = ito.view(function(props)
    local source = ito.remember(function()
        return ito.ImageSource.file(props.path)
    end, props.path)
    return ito.Image(source):alt(props.description)
end)
```

The application owns fetching URLs, saving, copying, and opening external applications. Supply callbacks through ordinary view props and `:on_tap(handler)`.

## Presentation and placement

```lua
ito.Image(photo)
    :content_mode(ito.ImageMode.fill)
    :content_alignment(ito.Alignment.top)
    :crop({ x = 100, y = 50, width = 400, height = 300 })
    :rotate(90)
    :opacity(0.8)
    :sampling(ito.ImageSampling.linear)
    :width(40)
    :height(12)
    :align(ito.Alignment.leading)
    :padding(1)
```

| Setting | Behavior |
| --- | --- |
| `ImageMode.fit` | Default. Preserve proportions and show the entire image, with transparent unused space. |
| `ImageMode.fill` | Preserve proportions and crop to fill the allocated rectangle. |
| `ImageMode.stretch` | Fill the rectangle without preserving proportions. |
| `ImageMode.original` | One source pixel per terminal pixel, clipped to the rectangle. |
| `content_alignment` | Position the image within its rectangle, including which edge remains visible when cropped. |
| `crop` | A nonempty rectangle inside the oriented source, measured in pixels. `nil` removes it. |
| `rotate` | Clockwise multiples of 90 degrees, applied after cropping. |
| `opacity` | A number from 0 to 1, multiplied by source alpha. |
| `ImageSampling.linear` | Default. Bilinear interpolation with premultiplied alpha. |
| `ImageSampling.nearest` | Preserve hard pixel edges for pixel art. |

`width`, `height`, `padding`, and layout positions use terminal **cells**. `align` positions the view within its parent. `content_alignment` positions pixels within the image view. Cell proportions are included when measuring natural height. Explicit dimensions reserve stable space during loading.

Transforms belong to the view and never mutate the source. The same source can appear as a cropped thumbnail and an uncropped preview. Identical prepared images share an upload. Scrolling clips the original rectangle and preserves its image coordinates; it does not fit the image again to the visible fragment.

Image cells replace earlier text cells. Later text or opaque overlays cover those cells. Text styling cannot overwrite the colors used for image identity. Text selection, `screen:text`, styled snapshots, and virtual-terminal frames contain spaces for image cells, never protocol characters. Copying image pixels is an application action.

## Loading and fallback views

```lua
ito.Image(photo)
    :height(12)
    :alt("Mountain at sunset")
    :placeholder(ito.Text("Loading image…"))
    :fallback(function(status)
        return ito.Text("Could not load image")
    end)
    :unsupported(ito.Text("Image preview unavailable"))
```

Each handler accepts a view or a function returning one. Functions receive `{ phase, error, source }`. Loading covers decoding and preparation for the current size or transform. `fallback` handles failures and is also used for unsupported graphics when no `unsupported` view is supplied. The default in every phase is the alt text, initially `Image`.

When changing a transform, the view keeps its previous ready image visible until the replacement is prepared, provided the source and rectangle size are unchanged and the previous variant remains cached. Changing sources uses the loading view so unrelated image content is never retained.

Visible pending images request a frame through `frame.wake`, also available as `window.wake`. The host event loop must honor that deadline, as with `Spinner`. Loading and encoding happen on a worker; terminal writes remain serialized with frame presentation. Large uploads can take time over slow terminal connections.

## Interactive viewer

```lua
local viewport = ito.ImageViewport()

ito.ImageViewer(photo)
    :state(viewport)
    :focused()
    :content_mode(ito.ImageMode.fit)
    :wheel(ito.ImageWheel.zoom)
    :on_change(function(state)
        -- Update application controls or labels.
    end)
    :grow()
```

Without `state`, the viewer remembers its own viewport through recomposition. A supplied viewport can be shared by multiple viewers or driven by toolbar callbacks:

```lua
viewport:zoom_to(2)
viewport:zoom_by(1.25)
viewport:pan_to(0, 0.5)
viewport:pan_by(0.1, 0)
viewport:reset()
```

Zoom is relative to the selected content mode and clamped to 0.1–64. Pan coordinates range from -1 to 1 and shift the alignment across the available image/viewport difference; zero preserves `content_alignment`. Positive values move the viewed region right or down for overflowing images. Read `zoom`, `x`, and `y` for toolbar labels. Like `ScrollState`, external mutations require the host to request a redraw.

| Input | Action |
| --- | --- |
| `+` or `=` | Zoom in |
| `-` | Zoom out |
| Arrow keys | Pan |
| `0` or Home | Reset zoom and pan |

Ctrl, Alt, and Meta combinations are left to the application. `ImageWheel.pass` is the default, preserving parent scrolling. `ImageWheel.zoom` and `ImageWheel.pan` capture the wheel only inside the visible viewer, within its focus scope. Mouse dragging continues to use Ito's text-selection behavior.

Custom view functions accept image-specific choices through props and apply them to their returned image. General modifiers such as `:height`, `:padding`, and `:overlay` also work on the custom view's call.

## Bounds and lifecycle

- Encoded input: at most 16 MiB. Source dimensions: at most 8192 per side and 16 megapixels total.
- Each prepared placement: at most 4 megapixels and 297 cells per axis, the placeholder coordinate-table limit.
- A screen caches at most 64 prepared variants within a conservative 64 MiB budget. Offscreen variants are evicted first. Sources retained by the application have their own lifetime.
- One worker and eight queued jobs bound concurrent processing. A full queue defers work until a subsequent frame/status check. Dropped requests are skipped before processing when possible.
- Uploads are generated from the final composed cells. Covered images are not uploaded. Every cell includes explicit image coordinates, so partial clipping and overlays do not depend on neighboring placeholders.
- Commands use direct bytes, payload chunks of at most 4096 base64 bytes, and quiet mode. They do not generate terminal replies.
- Suspend, close, screen reclamation, and cache eviction delete only Ito-owned image IDs. Resume and failed writes invalidate upload state. Resources can then be uploaded again.

The implementation follows the [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/), including its published Unicode coordinate table. Unicode placeholder compatibility and tmux passthrough should be checked in each terminal supported by the embedding application.
