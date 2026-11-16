"""The cat-shaped meow, start to finish. Python version of catwaveform.m.

Reads examples/cat/input and writes to examples/cat/output (or --out DIR):
    cat-shape-meow.wav                 the shaped audio
    cat_signal.svg (+ _dark)           full plot, lead-in and lead-out included
    cat_signal_cropped.svg (+ _dark)   just the cat
    cat_signal_cropped.png             just the cat, high resolution for zooming
then shows the plots and the Fourier transform of the cat.
"""

import argparse
from pathlib import Path

import matplotlib.pyplot as plt

from image_shaped_audio import plot_shaped_audio, plot_spectrum, shape_audio

CAT = Path(__file__).resolve().parent.parent / "examples" / "cat"


def main():
    parser = argparse.ArgumentParser(description="Build the cat-shaped meow.")
    parser.add_argument(
        "--out",
        type=Path,
        default=CAT / "output",
        help="output folder (default: examples/cat/output)",
    )
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    # Pour the meow into the cat. The meow itself is samples 6499:37200 of the
    # mp3 (MATLAB's 6500:37200). Leave segment out and shape_audio finds it on
    # its own by trimming the silence.
    meow = shape_audio(
        CAT / "input" / "cat_silhouette.jpg",
        CAT / "input" / "cat-meow.mp3",
        segment=(6499, 37200),
    )
    meow.write(
        args.out / "cat-shape-meow.wav", title="Cat Shaped Meow", artist="James Wang"
    )

    # Draw it: full and cropped, plus light-outline versions for dark mode
    dark_outline = "#e6edf3"
    plot_shaped_audio(meow, args.out / "cat_signal.svg")
    plt.close(
        plot_shaped_audio(meow, args.out / "cat_signal_dark.svg", outline_color=dark_outline)
    )

    plot_shaped_audio(meow, args.out / "cat_signal_cropped.svg", crop=True)
    plt.close(
        plot_shaped_audio(
            meow, args.out / "cat_signal_cropped_dark.svg", crop=True, outline_color=dark_outline
        )
    )
    plt.close(plot_shaped_audio(meow, args.out / "cat_signal_cropped.png", crop=True))

    # Bonus: the Fourier transform of a cat
    _, ax = plot_spectrum(meow)
    ax.set_title("Fourier Transform of Cat")

    print(f"Wrote cat-shape-meow.wav and the cat_signal figures to {args.out}")
    plt.show()


if __name__ == "__main__":
    main()
