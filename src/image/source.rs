use std::cell::RefCell;
use std::fs::File;
use std::io::{Cursor, Read};
use std::rc::Rc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};

use image::{DynamicImage, ImageDecoder, ImageReader, Limits, RgbaImage};
use mlua::{UserData, UserDataMethods};

use super::worker;

const MAX_BYTES: usize = 16 * 1024 * 1024;
const MAX_PIXELS: u64 = 16 * 1024 * 1024;
const MAX_SIDE: u32 = 8192;
static NEXT_ID: AtomicU64 = AtomicU64::new(1);

type Pixels = Result<Arc<RgbaImage>, String>;

pub(crate) struct Source {
    pub(crate) id: u64,
    pixels: Arc<OnceLock<Pixels>>,
    pending: Rc<RefCell<Option<worker::Job>>>,
}

fn dimensions(width: u32, height: u32) -> Result<(), String> {
    if width == 0
        || height == 0
        || width > MAX_SIDE
        || height > MAX_SIDE
        || u64::from(width) * u64::from(height) > MAX_PIXELS
    {
        return Err("image exceeds the limit of 8192 pixels per side or 16 megapixels".into());
    }
    Ok(())
}

fn decode(data: &[u8]) -> Result<RgbaImage, String> {
    let mut reader = ImageReader::new(Cursor::new(data))
        .with_guessed_format()
        .map_err(|error| error.to_string())?;
    let mut limits = Limits::default();
    limits.max_image_width = Some(MAX_SIDE);
    limits.max_image_height = Some(MAX_SIDE);
    limits.max_alloc = Some(128 * 1024 * 1024);
    reader.limits(limits);
    let mut decoder = reader.into_decoder().map_err(|error| error.to_string())?;
    let (width, height) = decoder.dimensions();
    dimensions(width, height)?;
    if decoder.total_bytes() > 128 * 1024 * 1024 {
        return Err("decoded image exceeds 128 MiB".into());
    }
    let orientation = decoder.orientation().map_err(|error| error.to_string())?;
    let mut image = DynamicImage::from_decoder(decoder).map_err(|error| error.to_string())?;
    image.apply_orientation(orientation);
    Ok(image.into_rgba8())
}

impl Source {
    fn with(pixels: Arc<OnceLock<Pixels>>, pending: Option<worker::Job>) -> Self {
        Self {
            id: NEXT_ID.fetch_add(1, Ordering::Relaxed),
            pixels,
            pending: Rc::new(RefCell::new(pending)),
        }
    }

    fn new() -> Self {
        Self::with(Arc::new(OnceLock::new()), None)
    }

    fn loading(load: impl FnOnce() -> Result<RgbaImage, String> + Send + 'static) -> Self {
        let (pixels, job) = worker::lazy(move || load().map(Arc::new));
        let source = Self::with(pixels, Some(job));
        source.start();
        source
    }

    fn start(&self) {
        let Some(job) = self.pending.borrow_mut().take() else {
            return;
        };
        if let Err((problem, job)) = worker::submit(job) {
            match problem {
                worker::Unavailable::Full => *self.pending.borrow_mut() = Some(job),
                problem => {
                    let _ = self.pixels.set(Err(problem.to_string()));
                }
            }
        }
    }

    pub(crate) fn file(path: String) -> Self {
        Self::loading(move || {
            let metadata = std::fs::metadata(&path).map_err(|error| error.to_string())?;
            if !metadata.is_file() {
                return Err("image source must be a regular file".into());
            }
            if metadata.len() > MAX_BYTES as u64 {
                return Err("encoded image exceeds 16 MiB".into());
            }
            let file = File::open(path).map_err(|error| error.to_string())?;
            let mut bytes = Vec::new();
            file.take(MAX_BYTES as u64 + 1)
                .read_to_end(&mut bytes)
                .map_err(|error| error.to_string())?;
            if bytes.len() > MAX_BYTES {
                return Err("encoded image exceeds 16 MiB".into());
            }
            decode(&bytes)
        })
    }

    pub(crate) fn bytes(bytes: &[u8]) -> mlua::Result<Self> {
        if bytes.len() > MAX_BYTES {
            return Err(mlua::Error::runtime("encoded image exceeds 16 MiB"));
        }
        let bytes = bytes.to_vec();
        Ok(Self::loading(move || decode(&bytes)))
    }

    pub(crate) fn rgba(width: u32, height: u32, bytes: &[u8]) -> mlua::Result<Self> {
        dimensions(width, height).map_err(mlua::Error::runtime)?;
        if bytes.len() as u64 != u64::from(width) * u64::from(height) * 4 {
            return Err(mlua::Error::runtime(
                "RGBA data must contain exactly width * height * 4 bytes",
            ));
        }
        let image = RgbaImage::from_raw(width, height, bytes.to_vec())
            .ok_or_else(|| mlua::Error::runtime("invalid RGBA dimensions"))?;
        let source = Self::new();
        let _ = source.pixels.set(Ok(Arc::new(image)));
        Ok(source)
    }

    pub(crate) fn pixels(&self) -> Option<&Pixels> {
        self.start();
        self.pixels.get()
    }
}

impl UserData for Source {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method("status", |lua, source, ()| {
            let status = lua.create_table()?;
            match source.pixels() {
                None => status.set("phase", "loading")?,
                Some(Err(error)) => {
                    status.set("phase", "failed")?;
                    status.set("error", error.clone())?;
                }
                Some(Ok(pixels)) => {
                    status.set("phase", "ready")?;
                    status.set("width", pixels.width())?;
                    status.set("height", pixels.height())?;
                }
            }
            Ok(status)
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{ImageEncoder, RgbImage};

    #[test]
    fn validates_before_allocating() {
        assert!(Source::rgba(0, 1, &[]).is_err());
        assert!(Source::rgba(u32::MAX, u32::MAX, &[]).is_err());
        assert!(Source::rgba(2, 2, &[0; 4]).is_err());
        assert!(decode(b"not an image").is_err());
    }

    #[test]
    fn decodes_png_and_jpeg_pixels() {
        let pixels = RgbImage::from_pixel(8, 4, image::Rgb([255, 0, 0]));
        let mut png = Vec::new();
        image::codecs::png::PngEncoder::new(&mut png)
            .write_image(pixels.as_raw(), 8, 4, image::ExtendedColorType::Rgb8)
            .unwrap();
        let decoded = decode(&png).unwrap();
        assert_eq!(decoded.dimensions(), (8, 4));
        assert_eq!(decoded.get_pixel(3, 2).0, [255, 0, 0, 255]);
        let mut jpeg = Vec::new();
        image::codecs::jpeg::JpegEncoder::new(&mut jpeg)
            .encode_image(&pixels)
            .unwrap();
        let decoded = decode(&jpeg).unwrap();
        assert_eq!(decoded.dimensions(), (8, 4));
        assert!(decoded.get_pixel(3, 2)[0] > 240);
        assert_eq!(decoded.get_pixel(3, 2)[3], 255);
    }
}
