#!/usr/bin/env python3
"""Build deterministic, visual-only HELIX facility tiles for Godot 4.

The generated TileSet deliberately has no collision or occlusion layers. The
mission blueprint and the original facility TileSet remain authoritative for
gameplay geometry, LOS, navigation and stable-object placement.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, Iterable

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SPEC_PATH = ROOT / "assets/source/environment/facility_environment_spec.json"
BLUEPRINT_PATH = ROOT / "resources/maps/operation_black_minute_blueprint.json"
PROCESSED_DIR = ROOT / "assets/processed/environment/authored"
PROCESSED_ATLAS = PROCESSED_DIR / "facility_environment_atlas.png"
MANIFEST_PATH = PROCESSED_DIR / "facility_environment_manifest.json"
PREVIEW_PATH = PROCESSED_DIR / "facility_environment_preview.png"
PALETTE_PREVIEW_PATH = PROCESSED_DIR / "facility_palette_preview.png"
RUNTIME_ATLAS = ROOT / "assets/sprites/environment/facility_environment_atlas.png"
TILESET_PATH = ROOT / "resources/tilesets/facility_environment_art.tres"
CATALOG_PATH = ROOT / "resources/environment/facility_environment_catalog.gd"

TILE_SIZE = 32
ATLAS_GRID = (16, 10)

FAMILY_ORDER = ("yard", "corporate", "systems", "research", "vault", "service", "neutral")
FLOOR_COORDS = {
    family: {"base": (index * 2, 0), "alternate": (index * 2 + 1, 0)}
    for index, family in enumerate(FAMILY_ORDER)
}
DETAIL_COORDS = {
    family: {"a": (index * 2, 1), "b": (index * 2 + 1, 1)}
    for index, family in enumerate(FAMILY_ORDER[:6])
}

PROP_COORDS = {
    "desk_left": (0, 4), "desk_middle": (1, 4), "desk_right": (2, 4),
    "locker_left": (3, 4), "locker_middle": (4, 4), "locker_right": (5, 4),
    "office_left": (6, 4), "office_right": (7, 4),
    "table_left": (8, 4), "table_right": (9, 4),
    "cctv_top_left": (10, 4), "cctv_top_right": (11, 4),
    "cctv_bottom_left": (12, 4), "cctv_bottom_right": (13, 4),
    "security_left": (14, 4), "security_middle_left": (15, 4),
    "security_middle_right": (0, 5), "security_right": (1, 5),
    "electrical_top": (2, 5), "electrical_middle": (3, 5), "electrical_bottom": (4, 5),
    "server_top": (5, 5), "server_middle": (6, 5), "server_bottom": (7, 5),
    "bench_left": (8, 5), "bench_middle": (9, 5), "bench_right": (10, 5),
    "machine_top_left": (11, 5), "machine_top_right": (12, 5),
    "machine_middle_left": (13, 5), "machine_middle_right": (14, 5),
    "machine_bottom_left": (15, 5), "machine_bottom_right": (0, 6),
}

MOTIF_TILES = {
    "reception_desk": (
        PROP_COORDS["desk_left"], PROP_COORDS["desk_middle"], PROP_COORDS["desk_right"],
    ),
    "locker_bank": (
        PROP_COORDS["locker_left"], PROP_COORDS["locker_middle"], PROP_COORDS["locker_right"],
    ),
    "office_desk": (PROP_COORDS["office_left"], PROP_COORDS["office_right"]),
    "break_table": (PROP_COORDS["table_left"], PROP_COORDS["table_right"]),
    "cctv_monitor_bank": (
        PROP_COORDS["cctv_top_left"], PROP_COORDS["cctv_top_right"],
        PROP_COORDS["cctv_bottom_left"], PROP_COORDS["cctv_bottom_right"],
    ),
    "security_desk": (
        PROP_COORDS["security_left"], PROP_COORDS["security_middle_left"],
        PROP_COORDS["security_middle_right"], PROP_COORDS["security_right"],
    ),
    "electrical_cabinet": (
        PROP_COORDS["electrical_top"], PROP_COORDS["electrical_middle"],
        PROP_COORDS["electrical_bottom"],
    ),
    "server_rack": (
        PROP_COORDS["server_top"], PROP_COORDS["server_middle"], PROP_COORDS["server_bottom"],
    ),
    "research_bench": (
        PROP_COORDS["bench_left"], PROP_COORDS["bench_middle"], PROP_COORDS["bench_right"],
    ),
    "maintenance_machine": (
        PROP_COORDS["machine_top_left"], PROP_COORDS["machine_top_right"],
        PROP_COORDS["machine_middle_left"], PROP_COORDS["machine_middle_right"],
        PROP_COORDS["machine_bottom_left"], PROP_COORDS["machine_bottom_right"],
    ),
}

VAULT_RING_COORDS = {
    (x, y): (x + y * 3, 8)
    for y in range(3)
    for x in range(3)
}


def _read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def _rgba(hex_color: str, alpha: int = 255) -> tuple[int, int, int, int]:
    value = hex_color.removeprefix("#")
    if len(value) != 6:
        raise ValueError(f"Expected #RRGGBB color, got {hex_color!r}")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4)) + (alpha,)


def _lighten(color: tuple[int, int, int, int], amount: int) -> tuple[int, int, int, int]:
    return tuple(min(255, component + amount) for component in color[:3]) + (color[3],)


def _darken(color: tuple[int, int, int, int], amount: int) -> tuple[int, int, int, int]:
    return tuple(max(0, component - amount) for component in color[:3]) + (color[3],)


def _paste(atlas: Image.Image, tile: Image.Image, coordinates: tuple[int, int]) -> None:
    atlas.alpha_composite(tile, (coordinates[0] * TILE_SIZE, coordinates[1] * TILE_SIZE))


def _draw_floor(family: str, family_spec: dict[str, str], alternate: bool) -> Image.Image:
    base = _rgba(family_spec["alternate" if alternate else "base"])
    seam = _rgba(family_spec["seam"])
    accent = _rgba(family_spec["accent"])
    tile = Image.new("RGBA", (TILE_SIZE, TILE_SIZE), base)
    draw = ImageDraw.Draw(tile)
    draw.line((0, 0, 31, 0), fill=_lighten(base, 8))
    draw.line((0, 31, 31, 31), fill=seam)
    draw.line((31, 0, 31, 31), fill=seam)
    draw.rectangle((2, 2, 29, 29), outline=_darken(base, 5))

    if family == "yard":
        for point in ((6, 8), (21, 5), (13, 22), (27, 17), (4, 27)):
            draw.point(point, fill=_lighten(base, 10))
        if alternate:
            draw.line((5, 18, 13, 16, 18, 22, 27, 20), fill=_darken(base, 18), width=1)
    elif family == "corporate":
        draw.line((15, 3, 15, 28), fill=_darken(base, 5))
        if alternate:
            draw.line((3, 15, 28, 15), fill=_lighten(base, 5))
            draw.point((4, 4), fill=_darken(accent, 30))
    elif family == "systems":
        for y in range(7, 27, 5):
            for x in range(7, 27, 5):
                draw.point((x, y), fill=_darken(base, 11))
        if alternate:
            draw.line((5, 26, 11, 20, 25, 20), fill=_darken(accent, 35))
    elif family == "research":
        if alternate:
            draw.line((4, 7, 4, 4, 7, 4), fill=_darken(accent, 55))
            draw.line((24, 27, 27, 27, 27, 24), fill=_darken(accent, 55))
            draw.rectangle((12, 12, 19, 19), outline=_lighten(base, 9))
    elif family == "vault":
        if alternate:
            draw.line((16, 4, 16, 10), fill=_darken(accent, 50))
            draw.line((16, 22, 16, 28), fill=_darken(accent, 50))
            draw.rectangle((8, 8, 23, 23), outline=_darken(accent, 45))
    elif family == "service":
        draw.point((5, 5), fill=_lighten(base, 18))
        draw.point((26, 26), fill=_lighten(base, 18))
        if alternate:
            draw.line((4, 25, 12, 17, 20, 25, 28, 17), fill=_darken(accent, 35))
    else:
        if alternate:
            draw.line((4, 16, 28, 16), fill=_lighten(base, 5))
    return tile


def _draw_detail(family: str, family_spec: dict[str, str], variant: str) -> Image.Image:
    seam = _rgba(family_spec["seam"], 205)
    accent = _rgba(family_spec["accent"], 180)
    tile = Image.new("RGBA", (TILE_SIZE, TILE_SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tile)
    if family == "yard":
        if variant == "a":
            draw.rectangle((8, 8, 23, 23), fill=(8, 14, 17, 220), outline=accent)
            for x in range(10, 23, 4):
                draw.line((x, 10, x, 21), fill=(45, 55, 57, 210))
        else:
            draw.line((3, 24, 10, 17, 16, 19, 23, 10, 29, 12), fill=seam)
    elif family == "corporate":
        if variant == "a":
            draw.line((5, 16, 27, 16), fill=accent, width=2)
            draw.rectangle((3, 13, 5, 19), fill=accent)
        else:
            for point in ((5, 5), (26, 5), (5, 26), (26, 26)):
                draw.rectangle((point[0] - 1, point[1] - 1, point[0] + 1, point[1] + 1), fill=seam)
    elif family == "systems":
        if variant == "a":
            draw.rectangle((5, 6, 26, 25), fill=(5, 12, 18, 205), outline=accent)
            for y in range(9, 24, 4):
                draw.line((8, y, 23, y), fill=(35, 57, 67, 220))
        else:
            draw.line((3, 22, 10, 22, 10, 9, 22, 9, 22, 16, 29, 16), fill=accent, width=1)
            for point in ((10, 22), (10, 9), (22, 9), (22, 16)):
                draw.rectangle((point[0] - 1, point[1] - 1, point[0] + 1, point[1] + 1), fill=accent)
    elif family == "research":
        if variant == "a":
            draw.polygon(((16, 4), (27, 16), (16, 27), (5, 16)), outline=accent)
            draw.rectangle((13, 13, 19, 19), outline=accent)
        else:
            draw.line((4, 8, 12, 8, 12, 16, 20, 16, 20, 24, 28, 24), fill=accent)
    elif family == "vault":
        if variant == "a":
            draw.ellipse((7, 7, 24, 24), outline=accent, width=2)
            draw.ellipse((12, 12, 19, 19), outline=accent)
        else:
            draw.line((16, 3, 16, 29), fill=accent)
            draw.line((3, 16, 29, 16), fill=accent)
            for point in ((6, 16), (26, 16), (16, 6), (16, 26)):
                draw.rectangle((point[0] - 1, point[1] - 1, point[0] + 1, point[1] + 1), fill=accent)
    else:
        if variant == "a":
            for x in range(-8, 40, 10):
                draw.polygon(((x, 26), (x + 5, 26), (x - 1, 31), (x - 6, 31)), fill=accent)
        else:
            draw.line((4, 25, 12, 17, 17, 20, 27, 8), fill=seam, width=2)
    return tile


def _draw_wall(mask: int, variant: int, palette: dict[str, str]) -> Image.Image:
    dark = _rgba(palette["wall_dark"])
    face = _rgba(palette["wall_face"])
    middle = _rgba(palette["wall_mid"])
    top = _rgba(palette["wall_top"])
    cyan_dim = _rgba(palette["cyan_dim"])
    tile = Image.new("RGBA", (TILE_SIZE, TILE_SIZE), dark)
    draw = ImageDraw.Draw(tile)
    draw.rectangle((2, 2, 29, 29), fill=face, outline=middle)
    draw.line((3, 3, 28, 3), fill=top)
    draw.line((3, 28, 28, 28), fill=_darken(dark, 3))
    if variant:
        draw.rectangle((7, 8, 24, 23), outline=_darken(middle, 7))
        draw.point((6, 6), fill=top)
        draw.point((25, 25), fill=top)
    else:
        draw.line((15, 7, 15, 24), fill=_darken(middle, 6))

    # Bit order: up, right, down, left. These edges border walkable floor.
    if mask & 1:
        draw.rectangle((0, 0, 31, 3), fill=top)
        draw.line((0, 4, 31, 4), fill=_lighten(middle, 7))
    if mask & 2:
        draw.rectangle((28, 0, 31, 31), fill=top)
        draw.line((27, 0, 27, 31), fill=_lighten(middle, 6))
    if mask & 4:
        draw.rectangle((0, 23, 31, 31), fill=_darken(face, 4))
        draw.line((0, 23, 31, 23), fill=top, width=2)
        draw.line((5, 26, 26, 26), fill=_darken(cyan_dim, 35))
    if mask & 8:
        draw.rectangle((0, 0, 3, 31), fill=top)
        draw.line((4, 0, 4, 31), fill=_lighten(middle, 6))
    return tile


def _blank_prop_canvas(size: tuple[int, int]) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def _draw_props(palette: dict[str, str]) -> dict[str, Image.Image]:
    outline = _rgba(palette["outline"])
    dark = _rgba(palette["wall_dark"])
    face = _rgba(palette["wall_face"])
    mid = _rgba(palette["wall_mid"])
    top = _rgba(palette["wall_top"])
    steel = _rgba(palette["steel"])
    steel_light = _rgba(palette["steel_light"])
    cyan = _rgba(palette["cyan"])
    cyan_dim = _rgba(palette["cyan_dim"])
    amber = _rgba(palette["amber"])
    violet = _rgba(palette["violet"])
    warm = _rgba(palette["warm"])
    composites: list[tuple[Image.Image, tuple[str, ...], int]] = []

    desk, draw = _blank_prop_canvas((96, 32))
    draw.rectangle((1, 6, 94, 28), fill=outline)
    draw.rectangle((2, 4, 93, 24), fill=steel, outline=top)
    draw.rectangle((4, 7, 91, 11), fill=steel_light)
    draw.rectangle((39, 8, 57, 17), fill=dark, outline=cyan_dim)
    draw.line((7, 25, 88, 25), fill=cyan_dim, width=2)
    composites.append((desk, ("desk_left", "desk_middle", "desk_right"), 3))

    locker, draw = _blank_prop_canvas((96, 32))
    draw.rectangle((1, 2, 94, 29), fill=outline)
    for x in range(3, 94, 15):
        draw.rectangle((x, 3, min(x + 12, 93), 28), fill=mid, outline=top)
        draw.line((x + 3, 8, min(x + 9, 91), 8), fill=dark)
        draw.rectangle((min(x + 9, 91), 15, min(x + 10, 92), 17), fill=steel_light)
    composites.append((locker, ("locker_left", "locker_middle", "locker_right"), 3))

    office, draw = _blank_prop_canvas((64, 32))
    draw.rectangle((2, 7, 61, 27), fill=outline)
    draw.rectangle((3, 5, 60, 23), fill=steel, outline=top)
    draw.rectangle((10, 7, 25, 16), fill=dark, outline=cyan_dim)
    draw.rectangle((38, 10, 50, 19), fill=_darken(warm, 80), outline=warm)
    composites.append((office, ("office_left", "office_right"), 2))

    table, draw = _blank_prop_canvas((64, 32))
    draw.rounded_rectangle((3, 5, 60, 25), radius=5, fill=outline)
    draw.rounded_rectangle((4, 3, 59, 22), radius=5, fill=steel, outline=steel_light)
    draw.rectangle((28, 8, 35, 17), fill=_darken(warm, 70), outline=warm)
    composites.append((table, ("table_left", "table_right"), 2))

    cctv, draw = _blank_prop_canvas((64, 64))
    draw.rectangle((2, 2, 61, 61), fill=outline)
    draw.rectangle((4, 4, 59, 58), fill=dark, outline=top)
    for y in (7, 27):
        for x in (7, 32):
            draw.rectangle((x, y, x + 20, y + 15), fill=(5, 21, 31, 255), outline=cyan_dim)
            draw.line((x + 3, y + 11, x + 7, y + 7, x + 11, y + 10, x + 17, y + 4), fill=cyan)
    draw.rectangle((21, 48, 43, 56), fill=face, outline=steel_light)
    composites.append((cctv, ("cctv_top_left", "cctv_top_right", "cctv_bottom_left", "cctv_bottom_right"), 2))

    security, draw = _blank_prop_canvas((128, 32))
    draw.rectangle((1, 8, 126, 29), fill=outline)
    draw.rectangle((2, 5, 125, 25), fill=steel, outline=steel_light)
    draw.line((8, 25, 119, 25), fill=amber, width=2)
    for x in (14, 48, 82, 106):
        draw.rectangle((x, 8, x + 13, 17), fill=dark, outline=amber)
    composites.append((security, ("security_left", "security_middle_left", "security_middle_right", "security_right"), 4))

    electrical, draw = _blank_prop_canvas((32, 96))
    draw.rectangle((3, 1, 28, 94), fill=outline)
    draw.rectangle((5, 2, 26, 91), fill=mid, outline=top)
    for y in (8, 34, 61):
        draw.rectangle((8, y, 23, y + 18), fill=dark, outline=amber)
        draw.line((11, y + 5, 20, y + 5), fill=amber)
        draw.rectangle((11, y + 10, 13, y + 13), fill=cyan_dim)
        draw.rectangle((18, y + 10, 20, y + 13), fill=_rgba(palette["red"]))
    composites.append((electrical, ("electrical_top", "electrical_middle", "electrical_bottom"), 1))

    server, draw = _blank_prop_canvas((32, 96))
    draw.rectangle((3, 1, 28, 94), fill=outline)
    draw.rectangle((5, 2, 26, 91), fill=dark, outline=top)
    for y in range(7, 89, 7):
        draw.rectangle((8, y, 23, y + 4), fill=face, outline=steel_light)
        draw.point((20, y + 2), fill=cyan if y % 14 else amber)
    composites.append((server, ("server_top", "server_middle", "server_bottom"), 1))

    bench, draw = _blank_prop_canvas((96, 32))
    draw.rectangle((1, 7, 94, 29), fill=outline)
    draw.rectangle((2, 4, 93, 24), fill=steel, outline=steel_light)
    for x in (13, 43, 73):
        draw.ellipse((x, 8, x + 9, 17), fill=_darken(violet, 45), outline=violet)
        draw.rectangle((x + 3, 6, x + 6, 9), fill=cyan)
    draw.line((7, 25, 88, 25), fill=violet, width=2)
    composites.append((bench, ("bench_left", "bench_middle", "bench_right"), 3))

    machine, draw = _blank_prop_canvas((64, 96))
    draw.rectangle((2, 2, 61, 93), fill=outline)
    draw.rectangle((4, 4, 59, 89), fill=steel, outline=top)
    draw.rectangle((9, 9, 53, 31), fill=dark, outline=amber)
    draw.rectangle((14, 14, 31, 25), fill=face, outline=cyan_dim)
    draw.rectangle((38, 14, 46, 22), fill=_darken(amber, 35), outline=amber)
    draw.rectangle((9, 39, 27, 72), fill=dark, outline=steel_light)
    draw.ellipse((13, 45, 24, 56), outline=amber, width=2)
    draw.rectangle((35, 40, 54, 78), fill=face, outline=steel_light)
    for y in (46, 54, 62, 70):
        draw.line((39, y, 50, y), fill=cyan_dim)
    draw.line((7, 85, 55, 85), fill=amber, width=3)
    composites.append((machine, ("machine_top_left", "machine_top_right", "machine_middle_left", "machine_middle_right", "machine_bottom_left", "machine_bottom_right"), 2))

    result: dict[str, Image.Image] = {}
    for composite, names, columns in composites:
        rows = len(names) // columns
        for index, name in enumerate(names):
            x = (index % columns) * TILE_SIZE
            y = (index // columns) * TILE_SIZE
            result[name] = composite.crop((x, y, x + TILE_SIZE, y + TILE_SIZE))
        if rows * columns != len(names):
            raise ValueError("Composite tile grid is incomplete")
    return result


def _draw_vault_ring(palette: dict[str, str]) -> dict[tuple[int, int], Image.Image]:
    image = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    violet = _rgba(palette["violet"], 185)
    cyan = _rgba(palette["cyan"], 150)
    dark_violet = _darken(violet, 60)
    for radius, color, width in ((42, dark_violet, 2), (30, violet, 2), (18, cyan, 1)):
        draw.ellipse((48 - radius, 48 - radius, 48 + radius, 48 + radius), outline=color, width=width)
    draw.line((4, 48, 92, 48), fill=dark_violet, width=1)
    draw.line((48, 4, 48, 92), fill=dark_violet, width=1)
    for point in ((7, 48), (89, 48), (48, 7), (48, 89)):
        draw.rectangle((point[0] - 2, point[1] - 2, point[0] + 2, point[1] + 2), fill=violet)
    result: dict[tuple[int, int], Image.Image] = {}
    for y in range(3):
        for x in range(3):
            result[(x, y)] = image.crop((x * 32, y * 32, x * 32 + 32, y * 32 + 32))
    return result


def _registered_tiles() -> dict[str, tuple[int, int]]:
    result: dict[str, tuple[int, int]] = {}
    for family, variants in FLOOR_COORDS.items():
        for variant, coordinates in variants.items():
            result[f"floor_{family}_{variant}"] = coordinates
    for family, variants in DETAIL_COORDS.items():
        for variant, coordinates in variants.items():
            result[f"detail_{family}_{variant}"] = coordinates
    for variant in range(2):
        for mask in range(16):
            result[f"wall_mask_{mask:02d}_variant_{variant}"] = (mask, 2 + variant)
    result.update(PROP_COORDS)
    for local, coordinates in VAULT_RING_COORDS.items():
        result[f"vault_ring_{local[0]}_{local[1]}"] = coordinates
    return result


def _build_atlas(spec: dict[str, Any]) -> tuple[Image.Image, dict[str, tuple[int, int]]]:
    atlas = Image.new("RGBA", (ATLAS_GRID[0] * TILE_SIZE, ATLAS_GRID[1] * TILE_SIZE), (0, 0, 0, 0))
    floor_families = spec["floor_families"]
    palette = spec["palette"]
    for family in FAMILY_ORDER:
        family_spec = floor_families[family]
        for variant, coordinates in FLOOR_COORDS[family].items():
            _paste(atlas, _draw_floor(family, family_spec, variant == "alternate"), coordinates)
        if family in DETAIL_COORDS:
            for variant, coordinates in DETAIL_COORDS[family].items():
                _paste(atlas, _draw_detail(family, family_spec, variant), coordinates)
    for variant in range(2):
        for mask in range(16):
            _paste(atlas, _draw_wall(mask, variant, palette), (mask, 2 + variant))
    for name, tile in _draw_props(palette).items():
        _paste(atlas, tile, PROP_COORDS[name])
    for local, tile in _draw_vault_ring(palette).items():
        _paste(atlas, tile, VAULT_RING_COORDS[local])
    return atlas, _registered_tiles()


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _pixel_sha256(image: Image.Image) -> str:
    rgba = image.convert("RGBA")
    digest = hashlib.sha256()
    digest.update(f"{rgba.width}x{rgba.height}:RGBA".encode("ascii"))
    digest.update(rgba.tobytes())
    return digest.hexdigest()


def _write_tileset(tiles: dict[str, tuple[int, int]]) -> None:
    coordinates = sorted(set(tiles.values()), key=lambda value: (value[1], value[0]))
    lines = [
        '[gd_resource type="TileSet" load_steps=3 format=3]',
        "",
        '[ext_resource type="Texture2D" path="res://assets/sprites/environment/facility_environment_atlas.png" id="1_art"]',
        "",
        '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_environment_art"]',
        'texture = ExtResource("1_art")',
        'texture_region_size = Vector2i(32, 32)',
    ]
    lines.extend(f"{x}:{y}/0 = 0" for x, y in coordinates)
    lines.extend([
        "",
        "[resource]",
        "tile_size = Vector2i(32, 32)",
        'sources/0 = SubResource("TileSetAtlasSource_environment_art")',
        "",
    ])
    TILESET_PATH.parent.mkdir(parents=True, exist_ok=True)
    TILESET_PATH.write_text("\n".join(lines), encoding="utf-8")


def _gd_string_name(value: str) -> str:
    return f'&"{value}"'


def _gd_vector(value: tuple[int, int]) -> str:
    return f"Vector2i({value[0]}, {value[1]})"


def _runtime_catalog_text(spec: dict[str, Any]) -> str:
    """Generate the exact atlas/room mapping consumed by the runtime map.

    Keeping this catalog generated makes the Python packer authoritative while
    preventing a successful rebuild from silently leaving stale GDScript tile
    coordinates behind.
    """
    lines = [
        "# Generated by tools/environment_art_pipeline.py. Do not edit by hand.",
        "class_name FacilityEnvironmentCatalog",
        "extends RefCounted",
        "",
        "const ROOM_FAMILIES: Dictionary[StringName, StringName] = {",
    ]
    for room_id, family in spec["room_families"].items():
        lines.append(f"\t{_gd_string_name(room_id)}: {_gd_string_name(family)},")
    lines.extend(["}", "", "const ROOM_SEEDS: Dictionary[StringName, int] = {"])
    for room_id, seed in spec["room_seeds"].items():
        lines.append(f"\t{_gd_string_name(room_id)}: {int(seed)},")
    lines.extend(["}", "", "const FLOOR_TILES: Dictionary[StringName, Array] = {"])
    for family in FAMILY_ORDER:
        variants = FLOOR_COORDS[family]
        lines.append(
            f"\t{_gd_string_name(family)}: "
            f"[{_gd_vector(variants['base'])}, {_gd_vector(variants['alternate'])}],"
        )
    lines.extend(["}", "", "const DETAIL_TILES: Dictionary[StringName, Array] = {"])
    for family in FAMILY_ORDER[:6]:
        variants = DETAIL_COORDS[family]
        lines.append(
            f"\t{_gd_string_name(family)}: "
            f"[{_gd_vector(variants['a'])}, {_gd_vector(variants['b'])}],"
        )
    lines.extend(["}", "", "const SEMANTIC_SOLIDS: Dictionary[StringName, StringName] = {"])
    for solid_id, motif in spec["semantic_solids"].items():
        lines.append(f"\t{_gd_string_name(solid_id)}: {_gd_string_name(motif)},")
    lines.extend(["}", "", "const MOTIF_TILES: Dictionary[StringName, Array] = {"])
    for motif, coordinates in MOTIF_TILES.items():
        packed = ", ".join(_gd_vector(value) for value in coordinates)
        lines.append(f"\t{_gd_string_name(motif)}: [{packed}],")
    lines.extend(["}", "", "const VAULT_RING_TILES: Dictionary[Vector2i, Vector2i] = {"])
    for local, coordinates in sorted(VAULT_RING_COORDS.items(), key=lambda item: (item[0][1], item[0][0])):
        lines.append(f"\t{_gd_vector(local)}: {_gd_vector(coordinates)},")
    lines.extend(["}", ""])
    return "\n".join(lines)


def _write_runtime_catalog(spec: dict[str, Any]) -> None:
    CATALOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CATALOG_PATH.write_text(_runtime_catalog_text(spec), encoding="utf-8")


def _make_preview(atlas: Image.Image, spec: dict[str, Any]) -> None:
    scaled = atlas.resize((atlas.width * 2, atlas.height * 2), Image.Resampling.NEAREST)
    preview = Image.new("RGBA", (scaled.width, scaled.height + 96), _rgba(spec["palette"]["void"]))
    preview.alpha_composite(scaled, (0, 0))
    draw = ImageDraw.Draw(preview)
    font = ImageFont.load_default()
    draw.text((12, scaled.height + 12), "HELIX ENVIRONMENT ATLAS · 32 PX · VISUAL ONLY", fill=_rgba(spec["palette"]["cyan"]), font=font)
    draw.text((12, scaled.height + 34), "ROWS 0-1 FLOORS · 2-3 WALLS · 4-6 SEMANTIC SOLIDS · 8 VAULT RING", fill=_rgba(spec["palette"]["warm"]), font=font)
    draw.text((12, scaled.height + 56), "NEAREST FILTER · NO PHYSICS · NO OCCLUSION", fill=(186, 204, 218, 255), font=font)
    preview.save(PREVIEW_PATH, optimize=False)

    palette_entries = list(spec["palette"].items())
    palette_preview = Image.new("RGBA", (640, 128), _rgba(spec["palette"]["void"]))
    palette_draw = ImageDraw.Draw(palette_preview)
    for index, (name, color) in enumerate(palette_entries):
        column = index % 8
        row = index // 8
        x = column * 80
        y = row * 58
        palette_draw.rectangle((x + 4, y + 4, x + 75, y + 31), fill=_rgba(color), outline=(220, 230, 235, 255))
        palette_draw.text((x + 5, y + 36), name[:12], fill=(210, 220, 228, 255), font=font)
    palette_preview.save(PALETTE_PREVIEW_PATH, optimize=False)


def process_all() -> None:
    spec = _read_json(SPEC_PATH)
    if int(spec.get("tile_size", 0)) != TILE_SIZE or tuple(spec.get("atlas_grid", [])) != ATLAS_GRID:
        raise ValueError("Environment spec tile size or atlas grid does not match the tool contract")
    concept_path = ROOT / str(spec["concept_reference"])
    if not concept_path.is_file():
        raise FileNotFoundError(concept_path)
    atlas, tiles = _build_atlas(spec)
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    RUNTIME_ATLAS.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(PROCESSED_ATLAS, optimize=False)
    atlas.save(RUNTIME_ATLAS, optimize=False)
    _write_tileset(tiles)
    _write_runtime_catalog(spec)
    _make_preview(atlas, spec)

    blueprint = _read_json(BLUEPRINT_PATH)
    manifest = {
        "schema_version": 1,
        "generator": "tools/environment_art_pipeline.py",
        "tile_size": [TILE_SIZE, TILE_SIZE],
        "atlas_grid": list(ATLAS_GRID),
        "atlas_size": [atlas.width, atlas.height],
        "mode": atlas.mode,
        "source_concept": {
            "path": str(spec["concept_reference"]),
            "sha256": _sha256(concept_path),
            "usage": "visual direction reference only; no runtime dependency"
        },
        "runtime_atlas": "assets/sprites/environment/facility_environment_atlas.png",
        "godot_tileset": "resources/tilesets/facility_environment_art.tres",
        "runtime_catalog": "resources/environment/facility_environment_catalog.gd",
        "collision_authority": "resources/tilesets/facility_tileset.tres",
        "room_families": spec["room_families"],
        "room_seeds": spec["room_seeds"],
        "semantic_solids": spec["semantic_solids"],
        "blueprint_solid_count": len(blueprint.get("internal_solid_rects", [])),
        "tiles": {name: list(coordinates) for name, coordinates in sorted(tiles.items())},
        "tile_counts": {
            "floor": sum(len(value) for value in FLOOR_COORDS.values()),
            "floor_detail": sum(len(value) for value in DETAIL_COORDS.values()),
            "wall": 32,
            "semantic_solid": len(PROP_COORDS),
            "vault_signature": len(VAULT_RING_COORDS),
            "total": len(tiles)
        },
        "generation_rules": {
            "filter": "nearest",
            "runtime_collision_layers": 0,
            "runtime_occlusion_layers": 0,
            "randomness": "none",
            "floor_detail_density_target": "approximately 6 percent per room before signature overlays"
        }
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"[environment-art] wrote {RUNTIME_ATLAS.relative_to(ROOT)} ({atlas.width}x{atlas.height}, RGBA)")
    print(f"[environment-art] wrote {TILESET_PATH.relative_to(ROOT)} ({len(tiles)} named tiles)")


def validate() -> None:
    spec = _read_json(SPEC_PATH)
    blueprint = _read_json(BLUEPRINT_PATH)
    manifest = _read_json(MANIFEST_PATH)
    expected_outputs = (
        PROCESSED_ATLAS, RUNTIME_ATLAS, PREVIEW_PATH, PALETTE_PREVIEW_PATH,
        TILESET_PATH, CATALOG_PATH,
    )
    for path in expected_outputs:
        if not path.is_file():
            raise FileNotFoundError(path)
    if _sha256(PROCESSED_ATLAS) != _sha256(RUNTIME_ATLAS):
        raise ValueError("Processed and runtime environment atlases differ")
    atlas = Image.open(RUNTIME_ATLAS)
    if atlas.mode != "RGBA":
        raise ValueError(f"Environment atlas must be RGBA, got {atlas.mode}")
    if atlas.size != (ATLAS_GRID[0] * TILE_SIZE, ATLAS_GRID[1] * TILE_SIZE):
        raise ValueError(f"Environment atlas size mismatch: {atlas.size}")
    if atlas.width % TILE_SIZE or atlas.height % TILE_SIZE:
        raise ValueError("Environment atlas is not aligned to the 32 px grid")
    if atlas.getchannel("A").getextrema() != (0, 255):
        raise ValueError("Environment atlas must contain both transparent and opaque pixels")
    tiles = manifest.get("tiles", {})
    expected_tiles = _registered_tiles()
    if tiles != {name: list(value) for name, value in sorted(expected_tiles.items())}:
        raise ValueError("Environment manifest tile registry is stale")
    tile_digests: dict[str, str] = {}
    for name, coordinates in expected_tiles.items():
        x, y = coordinates
        crop = atlas.crop((x * TILE_SIZE, y * TILE_SIZE, (x + 1) * TILE_SIZE, (y + 1) * TILE_SIZE))
        if crop.getbbox() is None:
            raise ValueError(f"Registered environment tile is empty: {name}")
        alpha_extrema = crop.getchannel("A").getextrema()
        if alpha_extrema is None or alpha_extrema[1] <= 0:
            raise ValueError(f"Registered environment tile has no visible pixels: {name}")
        digest = _pixel_sha256(crop)
        if digest in tile_digests:
            raise ValueError(
                f"Registered environment tiles are exact duplicates: "
                f"{tile_digests[digest]} and {name}"
            )
        tile_digests[digest] = name
    expected_atlas, _unused_registry = _build_atlas(spec)
    if _pixel_sha256(atlas) != _pixel_sha256(expected_atlas):
        raise ValueError(
            "Environment atlas pixels differ from the canonical palette/material generator"
        )
    registered_coordinates = set(expected_tiles.values())
    for y in range(ATLAS_GRID[1]):
        for x in range(ATLAS_GRID[0]):
            if (x, y) in registered_coordinates:
                continue
            padding = atlas.crop((x * TILE_SIZE, y * TILE_SIZE, (x + 1) * TILE_SIZE, (y + 1) * TILE_SIZE))
            if padding.getchannel("A").getbbox() is not None:
                raise ValueError(f"Unused atlas padding cell {(x, y)} is not transparent")
    blueprint_ids = {
        str(entry["id"])
        for entry in blueprint.get("internal_solid_rects", [])
        if isinstance(entry, dict) and "id" in entry
    }
    mapped_ids = set(spec.get("semantic_solids", {}))
    if blueprint_ids != mapped_ids:
        raise ValueError(f"Semantic solid mappings differ from blueprint: missing={sorted(blueprint_ids - mapped_ids)}, extra={sorted(mapped_ids - blueprint_ids)}")
    if set(spec.get("room_families", {})) != set(blueprint.get("rooms", {})):
        raise ValueError("Every blueprint room must have exactly one environment material family")
    tileset_text = TILESET_PATH.read_text(encoding="utf-8")
    if "physics_layer" in tileset_text or "occlusion_layer" in tileset_text:
        raise ValueError("Visual environment TileSet must not define collision or occlusion")
    if "assets/sprites/environment/facility_environment_atlas.png" not in tileset_text:
        raise ValueError("Visual environment TileSet must reference only the runtime atlas")
    if CATALOG_PATH.read_text(encoding="utf-8") != _runtime_catalog_text(spec):
        raise ValueError("Runtime environment catalog is stale")
    if manifest.get("source_concept", {}).get("sha256") != _sha256(ROOT / str(spec["concept_reference"])):
        raise ValueError("Environment source concept fingerprint changed")
    print(f"[environment-art] PASS: {len(expected_tiles)} tiles, 15 room families, {len(blueprint_ids)} semantic solids")


def fingerprint() -> None:
    paths: Iterable[Path] = (
        SPEC_PATH, PROCESSED_ATLAS, MANIFEST_PATH, PREVIEW_PATH,
        PALETTE_PREVIEW_PATH, RUNTIME_ATLAS, TILESET_PATH, CATALOG_PATH,
    )
    fingerprints: dict[str, dict[str, str]] = {}
    for path in paths:
        if not path.is_file():
            raise FileNotFoundError(path)
        if path.suffix == ".png":
            digest = _pixel_sha256(Image.open(path))
            kind = "decoded_rgba"
        elif path.suffix == ".json":
            canonical = json.dumps(
                _read_json(path), ensure_ascii=False, separators=(",", ":"), sort_keys=True,
            ).encode("utf-8")
            digest = hashlib.sha256(canonical).hexdigest()
            kind = "canonical_json"
        else:
            normalized_text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
            digest = hashlib.sha256(normalized_text.encode("utf-8")).hexdigest()
            kind = "normalized_text"
        fingerprints[path.relative_to(ROOT).as_posix()] = {"kind": kind, "sha256": digest}
    print(json.dumps(fingerprints, indent=2, ensure_ascii=False, sort_keys=True))


def inspect() -> None:
    spec = _read_json(SPEC_PATH)
    concept_path = ROOT / str(spec["concept_reference"])
    with Image.open(concept_path) as image:
        print(f"concept: {concept_path.relative_to(ROOT)} {image.size[0]}x{image.size[1]} {image.mode}")
    print(f"atlas contract: {ATLAS_GRID[0] * TILE_SIZE}x{ATLAS_GRID[1] * TILE_SIZE} RGBA, {len(_registered_tiles())} named tiles")
    print(f"room material families: {len(spec['room_families'])}; semantic solids: {len(spec['semantic_solids'])}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("inspect", "process-all", "validate", "fingerprint"))
    args = parser.parse_args()
    if args.command == "inspect":
        inspect()
    elif args.command == "process-all":
        process_all()
    elif args.command == "validate":
        validate()
    else:
        fingerprint()


if __name__ == "__main__":
    main()
