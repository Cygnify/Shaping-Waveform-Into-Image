"""Reshape audio so its waveform traces a silhouette.

Python version of imageShapedAudio.m and plotShapedAudio.m. Same steps, same
defaults, no MATLAB needed.

Command line:

    python image_shaped_audio.py shape.png sound.wav --wav out.wav --plot out.svg

From Python:

    from image_shaped_audio import shape_audio, plot_shaped_audio
    result = shape_audio("shape.png", "sound.wav")
    result.write("out.wav")
    plot_shaped_audio(result, "out.svg")

Sample indices are 0-based with an exclusive stop, like Python slices, so
MATLAB's Segment=[6500 37200] is segment=(6499, 37200) here.
"""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import soundfile as sf
from PIL import Image
from scipy import ndimage
from scipy.interpolate import CubicSpline
from scipy.signal import find_peaks

VECTOR_FORMATS = {".svg", ".pdf", ".eps", ".ps"}


@dataclass
class ShapedAudio:
    """Output of shape_audio. All curves are in the same units as `audio`."""

    audio: np.ndarray  # (samples, channels)
    sample_rate: int
    top: np.ndarray  # outline, one value per sample
    bottom: np.ndarray
    midline: np.ndarray
    segment: tuple[int, int]  # [start, stop) samples that were shaped
    mask: np.ndarray  # the traced shape, True inside

    def write(self, path, title: str = "", artist: str = "", subtype: str = "PCM_16"):
        """Write the shaped audio to any format soundfile supports."""
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with sf.SoundFile(
            path, "w", self.sample_rate, self.audio.shape[1], subtype=subtype
        ) as f:
            if title:
                f.title = title
            if artist:
                f.artist = artist
            f.write(self.audio)


def shape_audio(
    image,
    audio,
    *,
    segment="auto",
    silence_threshold: float = 0.05,
    envelope_window: int = 50,
    shape_color: str = "auto",
    peak: float = 0.9,
) -> ShapedAudio:
    """Trace the largest solid shape in `image` and pour `audio` into it.

    segment           -- (start, stop) samples to shape, "auto" (trim leading
                         and trailing silence) or "all". Samples outside it
                         become the flat lead-in and lead-out lines.
    silence_threshold -- for "auto": level, as a fraction of the peak, that
                         counts as sound.
    envelope_window   -- peak-envelope window in samples. Bigger is smoother
                         but hugs the outline less tightly.
    shape_color       -- "dark", "light", or "auto" (whichever covers less of
                         the image). Ignored for images with transparency,
                         where the opaque part is the shape.
    peak              -- output amplitude of the outline's most extreme point.
    """
    if not 0 <= silence_threshold <= 1:
        raise ValueError("silence_threshold must be between 0 and 1")
    if envelope_window < 1:
        raise ValueError("envelope_window must be a positive integer")
    if not 0 < peak <= 1:
        raise ValueError("peak must be in (0, 1]")

    # Shape: image -> top and bottom edge of each pixel column
    mask = trace_shape(image, shape_color)
    top_px, bottom_px = column_edges(mask)
    if len(top_px) < 2:
        raise ValueError("The traced shape is only one pixel wide.")

    # Sound
    x, fs = sf.read(audio, always_2d=True, dtype="float64")
    n = len(x)
    start, stop = resolve_segment(segment, x, fs, silence_threshold)
    seg_len = stop - start
    if seg_len <= envelope_window:
        raise ValueError(
            f"The segment ({seg_len} samples) must be longer than "
            f"envelope_window ({envelope_window})."
        )

    # Outline: stretch the columns across the segment, hold the ends flat
    at = np.linspace(0, len(top_px) - 1, seg_len)
    cols = np.arange(len(top_px))
    top = _hold_ends(np.interp(at, cols, top_px), start, n - stop)
    bottom = _hold_ends(np.interp(at, cols, bottom_px), start, n - stop)

    height = top - bottom
    midline = (top + bottom) / 2

    # Start from zero so the lead-in line sits at silence.
    offset = midline[0]
    top, bottom, midline = top - offset, bottom - offset, midline - offset

    # Pour each channel into the outline
    shaped = np.empty_like(x)
    for c in range(x.shape[1]):
        wave = x[:, c].copy()

        # Flatten the segment to [-1/2, 1/2] using its own peak envelope.
        upper, lower = peak_envelope(wave[start:stop], envelope_window)
        span = upper - lower
        span = np.maximum(span, 1e-3 * span.max() + np.finfo(float).eps)
        wave[start:stop] = (wave[start:stop] - (upper + lower) / 2) / span

        # The spline envelope can dip under the signal (mostly near the
        # ends); clamp so nothing pokes outside the outline.
        wave = np.clip(wave, -0.5, 0.5)

        shaped[:, c] = midline + height * wave

    # Scale so the outline's extreme point hits `peak`
    extent = np.abs(np.concatenate([top, bottom])).max()
    if extent == 0:
        raise ValueError("The traced shape has no height.")
    scale = peak / extent

    return ShapedAudio(
        audio=shaped * scale,
        sample_rate=fs,
        top=top * scale,
        bottom=bottom * scale,
        midline=midline * scale,
        segment=(start, stop),
        mask=mask,
    )


def trace_shape(image, shape_color: str = "auto") -> np.ndarray:
    """Binary mask of the largest solid shape in the image."""
    if shape_color not in ("auto", "dark", "light"):
        raise ValueError('shape_color must be "auto", "dark" or "light"')

    img = Image.open(image)
    mask = None
    if img.mode in ("RGBA", "LA", "PA") or "transparency" in img.info:
        alpha = np.asarray(img.convert("RGBA"))[..., 3]
        if alpha.min() < alpha.max():
            # Transparent background: the opaque part is the shape.
            mask = alpha > alpha.max() / 2

    if mask is None:
        gray = np.asarray(img.convert("L"))
        mask = gray > otsu_threshold(gray)  # True = light pixels
        if shape_color == "dark" or (shape_color == "auto" and mask.mean() > 0.5):
            mask = ~mask

    mask = ndimage.binary_fill_holes(mask)

    # Keep only the largest blob (8-connected, like MATLAB's bwareafilt).
    labels, count = ndimage.label(mask, structure=np.ones((3, 3)))
    if count == 0:
        raise ValueError(f"No shape found in {image}.")
    sizes = np.bincount(labels.ravel())
    sizes[0] = 0
    return labels == sizes.argmax()


def otsu_threshold(gray: np.ndarray) -> int:
    """Otsu's threshold for an 8-bit image (same rule as MATLAB's graythresh)."""
    hist = np.bincount(gray.ravel(), minlength=256).astype(float)
    p = hist / hist.sum()
    omega = np.cumsum(p)
    mu = np.cumsum(p * np.arange(256))
    with np.errstate(divide="ignore", invalid="ignore"):
        between = (mu[-1] * omega - mu) ** 2 / (omega * (1 - omega))
    between = np.nan_to_num(between, nan=0.0, posinf=0.0)
    best = np.flatnonzero(between == between.max())
    return int(round(best.mean()))


def column_edges(mask: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Highest and lowest pixel of the shape in each column, measured upward
    from the bottom of the image."""
    h = mask.shape[0]
    cols = np.flatnonzero(mask.any(axis=0))
    sub = mask[:, cols[0] : cols[-1] + 1]
    first_row = sub.argmax(axis=0)
    last_row = h - 1 - sub[::-1].argmax(axis=0)
    return (h - first_row).astype(float), (h - last_row).astype(float)


def resolve_segment(segment, x: np.ndarray, fs: int, threshold: float):
    """Turn the segment option into (start, stop) sample indices."""
    n = len(x)
    if isinstance(segment, str):
        if segment == "all":
            return 0, n
        if segment == "auto":
            # Loudness of the loudest channel, smoothed over about 10 ms.
            level = ndimage.maximum_filter1d(
                np.abs(x).max(axis=1), size=max(1, round(0.01 * fs))
            )
            loud = np.flatnonzero(level >= threshold * level.max())
            return int(loud[0]), int(loud[-1]) + 1
        raise ValueError('segment must be (start, stop), "auto" or "all"')

    start, stop = (int(round(v)) for v in segment)
    if not 0 <= start < stop <= n:
        raise ValueError(f"segment must satisfy 0 <= start < stop <= {n}")
    return start, stop


def peak_envelope(x: np.ndarray, window: int) -> tuple[np.ndarray, np.ndarray]:
    """Upper and lower peak envelopes, like MATLAB's envelope(x, window, 'peak'):
    a spline through local maxima (minima) at least `window` samples apart."""
    n = len(x)
    t = np.arange(n)

    def through(locs):
        if len(locs) < 2:
            locs = np.unique(np.r_[0, locs, n - 1])
        return CubicSpline(locs, x[locs])(t)

    if n > window + 1:
        # MATLAB keeps peaks more than `window` apart; scipy's distance is >=.
        maxima = find_peaks(x, distance=window + 1)[0]
        minima = find_peaks(-x, distance=window + 1)[0]
    else:
        maxima = minima = np.array([], dtype=int)
    return through(maxima), through(minima)


def _hold_ends(y: np.ndarray, before: int, after: int) -> np.ndarray:
    return np.concatenate([np.full(before, y[0]), y, np.full(after, y[-1])])


def plot_shaped_audio(
    result: ShapedAudio,
    export=None,
    *,
    crop: bool = False,
    width: float = 16,
    dpi: int = 300,
    colors=("#0000ff", "#ff0000"),
    outline_color="black",
    show_outline: bool = True,
    line_width: float = 0.5,
    outline_width: float = 4,
):
    """Plot every channel with the dashed outline around it.

    export        -- save the plot here. .svg, .pdf, .eps export as vectors with
                     a transparent background; anything else (.png, .jpg) as
                     an image on white.
    crop          -- show only the shaped part: no lead-in or lead-out lines.
    width         -- figure width in inches. The height follows the shape's own
                     proportions, so the silhouette isn't stretched.
    dpi           -- resolution of image exports, so they are width * dpi
                     pixels wide (4800 by default).
    line_width    -- waveform line width in points. Thin lines on a big figure
                     keep the individual oscillations visible.
    outline_width -- dashed outline width in points.

    Every sample is drawn (matplotlib's line simplification is off), so vector
    exports keep the full waveform when you zoom in.
    """
    import matplotlib.pyplot as plt

    n = len(result.audio)
    lo, hi = result.segment if crop else (0, n)
    t = np.arange(lo, hi)

    # Make the plot as wide, relative to its height, as the shape in the image
    # (stretched further by the lead-in and lead-out when not cropping).
    rows = np.flatnonzero(result.mask.any(axis=1))
    cols = np.flatnonzero(result.mask.any(axis=0))
    shape_h = rows[-1] - rows[0] + 1
    shape_w = (cols[-1] - cols[0] + 1) * (hi - lo) / (result.segment[1] - result.segment[0])
    aspect = float(np.clip(shape_h / shape_w, 0.1, 10))

    with plt.rc_context({"path.simplify": False, "agg.path.chunksize": 20000}):
        fig = plt.figure(figsize=(width, width * aspect))
        ax = fig.add_axes((0, 0, 1, 1))
        # clip_on=False so dashes at the very edges (nose, tail tip, paws)
        # aren't cut in half by the axes.
        if show_outline:
            for edge in (result.top, result.bottom):
                ax.plot(
                    t, edge[lo:hi], "--", color=outline_color, lw=outline_width,
                    clip_on=False,
                )
        for c in range(result.audio.shape[1]):
            ax.plot(
                t, result.audio[lo:hi, c], color=colors[c % len(colors)],
                lw=line_width, clip_on=False,
            )
        ax.set_xlim(t[0], t[-1])
        ax.set_ylim(result.bottom[lo:hi].min(), result.top[lo:hi].max())
        ax.axis("off")

        if export:
            Path(export).parent.mkdir(parents=True, exist_ok=True)
            vector = Path(export).suffix.lower() in VECTOR_FORMATS
            fig.savefig(
                export,
                bbox_inches="tight",
                pad_inches=0.05,
                transparent=vector,
                facecolor="none" if vector else "white",
                dpi=dpi,
            )
            if Path(export).suffix.lower() == ".svg":
                _compact_svg(export)
    return fig


def _compact_svg(path):
    """Trim coordinates to 0.01 pt. Invisible at any zoom, about a third smaller."""
    path = Path(path)
    path.write_text(re.sub(r"(\d+\.\d\d)\d+", r"\1", path.read_text()))


def plot_spectrum(result: ShapedAudio, export=None, channel: int = 0):
    """The Fourier transform of the shaped audio (one channel)."""
    import matplotlib.pyplot as plt

    wave = result.audio[:, channel]
    n = len(wave)
    f = result.sample_rate * np.arange(n // 2 + 1) / n
    spectrum = np.abs(np.fft.rfft(wave))
    spectrum[1:-1] *= 2  # fold in negative frequencies

    fig, ax = plt.subplots(figsize=(8, 6.5))
    ax.plot(f, spectrum, lw=1.5)
    ax.set_xlabel("Frequency (Hz)")
    ax.grid(True, alpha=0.4)
    ax.set_xlim(f[0], f[-1])
    # The shape is one big slow wiggle, so the lowest frequencies tower over
    # everything else. Zoom the y-axis past them.
    ax.set_ylim(0, 1.1 * spectrum[f > 100].max())
    if export:
        fig.savefig(export, bbox_inches="tight", dpi=150)
    return fig, ax


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Reshape audio so its waveform traces a silhouette."
    )
    parser.add_argument("image", help="silhouette image (PNG, JPG, ...)")
    parser.add_argument("audio", help="sound file (WAV, MP3, FLAC, ...)")
    parser.add_argument("--wav", metavar="FILE", help="write the shaped audio here")
    parser.add_argument(
        "--plot",
        metavar="FILE",
        action="append",
        default=[],
        help="save the plot (.svg/.pdf vector, .png image); repeatable",
    )
    parser.add_argument(
        "--segment",
        nargs="+",
        default=["auto"],
        metavar="X",
        help='"auto" (default), "all", or START STOP samples (0-based, stop exclusive)',
    )
    parser.add_argument("--silence-threshold", type=float, default=0.05)
    parser.add_argument("--envelope-window", type=int, default=50)
    parser.add_argument("--shape-color", choices=["auto", "dark", "light"], default="auto")
    parser.add_argument("--peak", type=float, default=0.9)
    parser.add_argument(
        "--crop", action="store_true", help="plot only the shape: no lead-in/lead-out lines"
    )
    parser.add_argument("--outline-color", default="black")
    parser.add_argument("--title", default="")
    parser.add_argument("--artist", default="")
    args = parser.parse_args(argv)

    if len(args.segment) == 1 and args.segment[0] in ("auto", "all"):
        segment = args.segment[0]
    elif len(args.segment) == 2:
        segment = tuple(int(v) for v in args.segment)
    else:
        parser.error('--segment takes "auto", "all", or START STOP')

    result = shape_audio(
        args.image,
        args.audio,
        segment=segment,
        silence_threshold=args.silence_threshold,
        envelope_window=args.envelope_window,
        shape_color=args.shape_color,
        peak=args.peak,
    )
    start, stop = result.segment
    print(
        f"Shaped samples {start}:{stop} of {len(result.audio)} "
        f"({result.audio.shape[1]} channel(s), {result.sample_rate} Hz)"
    )

    if args.wav:
        result.write(args.wav, title=args.title, artist=args.artist)
        print(f"Wrote {args.wav}")
    for path in args.plot:
        plot_shaped_audio(result, path, crop=args.crop, outline_color=args.outline_color)
        print(f"Wrote {path}")


if __name__ == "__main__":
    main()
