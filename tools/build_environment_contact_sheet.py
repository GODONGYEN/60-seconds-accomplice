#!/usr/bin/env python3
"""Build a deterministic 15-room visual-review contact sheet."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOMS = (
    ("yard", "EXTERNAL YARD"),
    ("reception", "RECEPTION"),
    ("staff", "STAFF OFFICE"),
    ("locker", "LOCKER ROOM"),
    ("security", "SECURITY"),
    ("cctv", "CCTV CONTROL"),
    ("electrical", "ELECTRICAL"),
    ("server", "SERVER ROOM"),
    ("research", "RESEARCH LAB"),
    ("guard_break", "GUARD BREAK"),
    ("laser", "LASER CORRIDOR"),
    ("vault_antechamber", "VAULT ENTRY"),
    ("vault", "CHRONOS VAULT"),
    ("maintenance", "MAINTENANCE"),
    ("extraction", "EXTRACTION"),
)


def build_sheet(
    input_directory: Path,
    output_path: Path,
    mode: str,
    size: str,
) -> None:
    source_paths = [
        input_directory / f"operation_{mode}_{room_id}_{size}.png"
        for room_id, _label in ROOMS
    ]
    missing = [path for path in source_paths if not path.is_file()]
    if missing:
        raise FileNotFoundError(f"Missing environment captures: {missing}")

    cell_width = 256
    source_width, source_height = (int(value) for value in size.split("x", 1))
    image_height = round(source_height * cell_width / source_width)
    label_height = 22
    columns = 5
    rows = 3
    background = (5, 13, 22, 255)
    sheet = Image.new(
        "RGBA",
        (cell_width * columns, (image_height + label_height) * rows),
        background,
    )
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()

    for index, ((room_id, label), source_path) in enumerate(zip(ROOMS, source_paths)):
        with Image.open(source_path) as source:
            rgba = source.convert("RGBA")
            if rgba.size != (source_width, source_height):
                raise ValueError(
                    f"Capture {source_path.name} is {rgba.size}, expected {(source_width, source_height)}"
                )
            thumbnail = rgba.resize((cell_width, image_height), Image.Resampling.NEAREST)
        column = index % columns
        row = index // columns
        x = column * cell_width
        y = row * (image_height + label_height)
        sheet.alpha_composite(thumbnail, (x, y))
        draw.rectangle(
            (x, y + image_height, x + cell_width - 1, y + image_height + label_height - 1),
            fill=(7, 17, 29, 255),
            outline=(34, 104, 128, 255),
        )
        draw.text(
            (x + 7, y + image_height + 6),
            f"{index + 1:02d}  {label}",
            fill=(115, 226, 232, 255),
            font=font,
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_path, optimize=False)
    print(f"[environment-contact-sheet] wrote {output_path} ({sheet.width}x{sheet.height})")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--mode",
        choices=("art_clean", "gameplay_initial", "gameplay_late"),
        required=True,
    )
    parser.add_argument("--size", default="1280x720")
    args = parser.parse_args()
    build_sheet(args.input_dir, args.output, args.mode, args.size)


if __name__ == "__main__":
    main()
