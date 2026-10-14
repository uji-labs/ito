use std::sync::{Arc, OnceLock};

use image::{ImageEncoder, Rgba, RgbaImage};
use serde::Deserialize;

use super::{Source, worker};

#[derive(Clone, Copy, Default, Deserialize, Hash, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Mode {
    #[default]
    Fit,
    Fill,
    Stretch,
    Original,
}

#[derive(Clone, Copy, Default, Deserialize, Hash, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Sampling {
    Nearest,
    #[default]
    Linear,
}

#[derive(Clone, Copy, Deserialize, Hash, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub(crate) struct Crop {
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
}

#[derive(Clone, Copy, Deserialize, Hash, PartialEq, Eq)]
#[serde(default, deny_unknown_fields)]
pub(crate) struct Options {
    pub mode: Mode,
    pub sampling: Sampling,
    pub crop: Option<Crop>,
    pub rotation: u16,
    pub opacity: u8,
    pub align_x: u16,
    pub align_y: u16,
    pub zoom: u32,
    pub pan_x: i16,
    pub pan_y: i16,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            mode: Mode::Fit,
            sampling: Sampling::Linear,
            crop: None,
            rotation: 0,
            opacity: 255,
            align_x: 500,
            align_y: 500,
            zoom: 1000,
            pan_x: 0,
            pan_y: 0,
        }
    }
}

impl Options {
    pub(crate) fn validate(&self) -> Result<(), String> {
        if !self.rotation.is_multiple_of(90)
            || self.rotation >= 360
            || self.align_x > 1000
            || self.align_y > 1000
            || !(100..=64000).contains(&self.zoom)
            || self.pan_x.unsigned_abs() > 1000
            || self.pan_y.unsigned_abs() > 1000
        {
            return Err("invalid image transform".into());
        }
        Ok(())
    }
}

pub(crate) struct Encoded {
    pub png: Vec<u8>,
    pub width: u32,
    pub height: u32,
}

const MEGAPIXELS: u64 = 4 * 1024 * 1024;

fn checked(width: u32, height: u32) -> Result<(), String> {
    if width == 0 || height == 0 || u64::from(width) * u64::from(height) > MEGAPIXELS {
        return Err("image placement exceeds 4 megapixels".into());
    }
    Ok(())
}

// The pixel size a placement of this many cells is prepared at.
pub(super) fn placement(
    cols: u16,
    rows: u16,
    cell_width: u16,
    cell_height: u16,
) -> Result<(u32, u32), String> {
    let width = u32::from(cols) * u32::from(cell_width);
    let height = u32::from(rows) * u32::from(cell_height);
    checked(width, height)?;
    Ok((width, height))
}

pub(crate) struct Prepared(Arc<OnceLock<Result<Encoded, String>>>);

fn encode(image: &RgbaImage, width: u32, height: u32) -> Result<Encoded, String> {
    let mut png = Vec::new();
    image::codecs::png::PngEncoder::new(&mut png)
        .write_image(
            image.as_raw(),
            width,
            height,
            image::ExtendedColorType::Rgba8,
        )
        .map_err(|error| error.to_string())?;
    Ok(Encoded { png, width, height })
}

impl Prepared {
    // `None` means the work could not start yet: the source is still decoding,
    // or the worker queue is full. Ask again on a later frame.
    pub(crate) fn new(
        source: &Source,
        options: Options,
        width: u32,
        height: u32,
    ) -> Result<Option<Self>, String> {
        options.validate()?;
        checked(width, height)?;
        let Some(Ok(pixels)) = source.pixels() else {
            return Ok(None);
        };
        let pixels = Arc::clone(pixels);
        let (result, job) = worker::lazy(move || {
            render(&pixels, &options, width, height).and_then(|image| encode(&image, width, height))
        });
        match worker::submit(job) {
            Ok(()) => Ok(Some(Self(result))),
            Err((worker::Unavailable::Full, _)) => Ok(None),
            Err((problem, _)) => Err(problem.to_string()),
        }
    }

    pub(crate) fn get(&self) -> Option<&Result<Encoded, String>> {
        self.0.get()
    }
}

#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
fn rounded(value: f64) -> u32 {
    value.round() as u32
}

#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
fn floored(value: f64) -> u32 {
    value.floor() as u32
}

#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
fn channel(value: f64) -> u8 {
    value.round() as u8
}

fn byte(value: u16) -> u8 {
    u8::try_from(value).unwrap_or(u8::MAX)
}

// Sampling in the destination bounds avoids allocating an enormous intermediate
// image when a small source is zoomed. Interpolation uses premultiplied alpha.
fn sample(source: &RgbaImage, x: f64, y: f64, sampling: Sampling) -> Rgba<u8> {
    let x = x.clamp(0.0, f64::from(source.width() - 1));
    let y = y.clamp(0.0, f64::from(source.height() - 1));
    if sampling == Sampling::Nearest {
        return *source.get_pixel(rounded(x), rounded(y));
    }
    let (left, top) = (floored(x), floored(y));
    let (right, bottom) = (
        (left + 1).min(source.width() - 1),
        (top + 1).min(source.height() - 1),
    );
    let (dx, dy) = (x - f64::from(left), y - f64::from(top));
    let mut channels = [0.0; 4];
    for (px, py, weight) in [
        (left, top, (1.0 - dx) * (1.0 - dy)),
        (right, top, dx * (1.0 - dy)),
        (left, bottom, (1.0 - dx) * dy),
        (right, bottom, dx * dy),
    ] {
        let pixel = source.get_pixel(px, py);
        let alpha = f64::from(pixel[3]) * weight;
        for channel in 0..3 {
            channels[channel] += f64::from(pixel[channel]) * alpha;
        }
        channels[3] += alpha;
    }
    if channels[3] <= 0.0 {
        return Rgba([0; 4]);
    }
    Rgba([
        channel(channels[0] / channels[3]),
        channel(channels[1] / channels[3]),
        channel(channels[2] / channels[3]),
        channel(channels[3]),
    ])
}

fn render(
    source: &RgbaImage,
    opts: &Options,
    width: u32,
    height: u32,
) -> Result<RgbaImage, String> {
    let crop = opts.crop.unwrap_or(Crop {
        x: 0,
        y: 0,
        width: source.width(),
        height: source.height(),
    });
    if crop.width == 0
        || crop.height == 0
        || crop.x.saturating_add(crop.width) > source.width()
        || crop.y.saturating_add(crop.height) > source.height()
    {
        return Err("crop must be a nonempty rectangle inside the source image".into());
    }
    let (sw, sh) = if opts.rotation.is_multiple_of(180) {
        (crop.width, crop.height)
    } else {
        (crop.height, crop.width)
    };
    let (sw, sh) = (f64::from(sw), f64::from(sh));
    let (dw, dh) = (f64::from(width), f64::from(height));
    let (sx, sy) = (dw / sw, dh / sh);
    let (sx, sy) = match opts.mode {
        Mode::Fit => (sx.min(sy), sx.min(sy)),
        Mode::Fill => (sx.max(sy), sx.max(sy)),
        Mode::Original => (1.0, 1.0),
        Mode::Stretch => (sx, sy),
    };
    let (sx, sy) = (
        sx * f64::from(opts.zoom) / 1000.0,
        sy * f64::from(opts.zoom) / 1000.0,
    );
    let anchor = |align: u16, pan: i16| {
        (f64::from(align) / 1000.0 + f64::from(pan) / 2000.0).clamp(0.0, 1.0)
    };
    let (ox, oy) = (
        (dw - sw * sx) * anchor(opts.align_x, opts.pan_x),
        (dh - sh * sy) * anchor(opts.align_y, opts.pan_y),
    );
    let mut output = RgbaImage::new(width, height);
    for (x, y, pixel) in output.enumerate_pixels_mut() {
        let (u, v) = (
            (f64::from(x) + 0.5 - ox) / sx,
            (f64::from(y) + 0.5 - oy) / sy,
        );
        if u < 0.0 || v < 0.0 || u >= sw || v >= sh {
            continue;
        }
        let (u, v) = (u - 0.5, v - 0.5);
        let (u, v) = match opts.rotation {
            90 => (v, f64::from(crop.height) - 1.0 - u),
            180 => (
                f64::from(crop.width) - 1.0 - u,
                f64::from(crop.height) - 1.0 - v,
            ),
            270 => (f64::from(crop.width) - 1.0 - v, u),
            _ => (u, v),
        };
        // Clamp to the crop before interpolation so adjacent source pixels do
        // not bleed through the edge of a cropped image.
        let u = u.clamp(0.0, f64::from(crop.width - 1)) + f64::from(crop.x);
        let v = v.clamp(0.0, f64::from(crop.height - 1)) + f64::from(crop.y);
        *pixel = sample(source, u, v, opts.sampling);
        pixel[3] = byte((u16::from(pixel[3]) * u16::from(opts.opacity) + 127) / 255);
    }
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fit_letterboxes_and_fill_crops_without_distortion() -> Result<(), String> {
        let source = RgbaImage::from_pixel(4, 2, Rgba([255, 0, 0, 255]));
        let fit = render(&source, &Options::default(), 4, 4)?;
        assert_eq!(fit.get_pixel(0, 0)[3], 0);
        assert_eq!(fit.get_pixel(0, 1)[3], 255);
        let fill = render(
            &source,
            &Options {
                mode: Mode::Fill,
                ..Options::default()
            },
            4,
            4,
        )?;
        assert!(fill.pixels().all(|pixel| pixel[3] == 255));
        Ok(())
    }

    #[test]
    fn rotation_and_opacity_do_not_change_shared_pixels() -> Result<(), String> {
        let source = RgbaImage::from_fn(2, 1, |x, _| {
            if x == 0 {
                Rgba([255, 0, 0, 255])
            } else {
                Rgba([0, 0, 255, 255])
            }
        });
        let opts = Options {
            rotation: 90,
            opacity: 128,
            ..Options::default()
        };
        let rotated = render(&source, &opts, 1, 2)?;
        assert_eq!(*rotated.get_pixel(0, 0), Rgba([255, 0, 0, 128]));
        assert_eq!(*rotated.get_pixel(0, 1), Rgba([0, 0, 255, 128]));
        assert_eq!(source.get_pixel(0, 0)[3], 255);
        Ok(())
    }

    #[test]
    fn interpolation_does_not_leak_transparent_colors() {
        let source = RgbaImage::from_fn(2, 1, |x, _| {
            if x == 0 {
                Rgba([255, 0, 0, 255])
            } else {
                Rgba([0, 255, 0, 0])
            }
        });
        assert_eq!(
            sample(&source, 0.5, 0.0, Sampling::Linear),
            Rgba([255, 0, 0, 128])
        );
    }
}
