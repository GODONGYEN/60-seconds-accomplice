#!/usr/bin/env python3
"""Deterministic derivative-asset pipeline for the generated concept sheets.

The source PNGs are immutable inputs. Runtime scenes only consume the atlases in
assets/sprites and the Godot resources generated from the JSON manifests.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
import sys
from collections import Counter, deque
from pathlib import Path
from typing import Any, Iterable

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "assets" / "source" / "generated"
PROCESSED_DIR = ROOT / "assets" / "processed"
RUNTIME_SPRITE_DIR = ROOT / "assets" / "sprites"
RESOURCE_DIR = ROOT / "resources"

PIPELINE_VERSION = "1.0.0"
FRAME_SIZE = (48, 64)
PIVOT = (24, 62)
ATLAS_COLUMNS = 8
TILE_SIZE = 32

SOURCE_FILES = {
    "player": SOURCE_DIR / "player_animation_source.png",
    "guard": SOURCE_DIR / "guard_animation_source.png",
    "facility": SOURCE_DIR / "facility_map_tileset_source.png",
}

# These hashes make accidental edits to the supplied AI sources fail loudly.
EXPECTED_SOURCE_SHA256 = {
    "player": "1f77a8deeae04022a2bff8c91af9829ebb64dfd824d950fcfd56975756ffa7e1",
    "guard": "a66592ebbd84c19901ea150875ad319a8aa0212e68faae4af3f1d3797bf33f78",
    "facility": "c2bb4c0279e5b5de2bbfecd2d199b7ca0ed747189b3df50609e2963c956d0546",
}

PLAYER_ANIMATIONS = (
    "idle_down",
    "idle_left",
    "idle_right",
    "idle_up",
    "walk_down",
    "walk_left",
    "walk_right",
    "walk_up",
    "interact_down",
    "interact_left",
    "interact_right",
    "interact_up",
)

GUARD_ANIMATIONS = (
    "idle_down",
    "idle_left",
    "idle_right",
    "idle_up",
    "walk_down",
    "walk_left",
    "walk_right",
    "walk_up",
    "alert_down",
    "alert_left",
    "alert_right",
    "alert_up",
)

FLOOR_X_RANGES = (
    (866, 944),
    (948, 1026),
    (1029, 1106),
    (1110, 1188),
    (1190, 1269),
    (1271, 1350),
    (1352, 1431),
    (1434, 1513),
)


def _log(message: str) -> None:
    print(f"[asset-pipeline] {message}")


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _pixel_sha256(image: Image.Image) -> str:
    rgba = image.convert("RGBA")
    digest = hashlib.sha256()
    digest.update(f"{rgba.width}x{rgba.height}:RGBA".encode("ascii"))
    digest.update(rgba.tobytes())
    return digest.hexdigest()


def _relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def _godot_path(path: Path) -> str:
    return f"res://{_relative(path)}"


def _ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def _save_png(image: Image.Image, path: Path) -> None:
    _ensure_parent(path)
    image.convert("RGBA").save(path, format="PNG", optimize=False, compress_level=9)


def _save_json(data: dict[str, Any], path: Path) -> None:
    _ensure_parent(path)
    path.write_text(
        json.dumps(data, indent=2, ensure_ascii=False, sort_keys=False) + "\n",
        encoding="utf-8",
    )


def _require_sources() -> None:
    for key, path in SOURCE_FILES.items():
        if not path.is_file():
            raise FileNotFoundError(f"Missing required {key} source: {_relative(path)}")
        actual_sha = _sha256_file(path)
        expected_sha = EXPECTED_SOURCE_SHA256[key]
        if actual_sha != expected_sha:
            raise ValueError(
                f"Source '{key}' changed unexpectedly: expected {expected_sha}, got {actual_sha}"
            )


def _neighbors4(x: int, y: int, width: int, height: int) -> Iterable[tuple[int, int]]:
    if x > 0:
        yield x - 1, y
    if x + 1 < width:
        yield x + 1, y
    if y > 0:
        yield x, y - 1
    if y + 1 < height:
        yield x, y + 1


def _connected_components(
    mask: np.ndarray, min_area: int = 1, keep_pixels: bool = False
) -> list[dict[str, Any]]:
    if mask.ndim != 2:
        raise ValueError("Connected-component mask must be two-dimensional")
    height, width = mask.shape
    visited = np.zeros(mask.shape, dtype=np.bool_)
    components: list[dict[str, Any]] = []
    candidates = np.argwhere(mask)
    for y_value, x_value in candidates:
        y = int(y_value)
        x = int(x_value)
        if visited[y, x]:
            continue
        queue: deque[tuple[int, int]] = deque([(x, y)])
        visited[y, x] = True
        pixels: list[tuple[int, int]] = []
        min_x = max_x = x
        min_y = max_y = y
        while queue:
            current_x, current_y = queue.popleft()
            pixels.append((current_x, current_y))
            min_x = min(min_x, current_x)
            max_x = max(max_x, current_x)
            min_y = min(min_y, current_y)
            max_y = max(max_y, current_y)
            for next_x, next_y in _neighbors4(current_x, current_y, width, height):
                if visited[next_y, next_x] or not mask[next_y, next_x]:
                    continue
                visited[next_y, next_x] = True
                queue.append((next_x, next_y))
        if len(pixels) < min_area:
            continue
        component: dict[str, Any] = {
            "area": len(pixels),
            "bbox": (min_x, min_y, max_x + 1, max_y + 1),
        }
        if keep_pixels:
            component["pixels"] = pixels
        components.append(component)
    components.sort(key=lambda item: int(item["area"]), reverse=True)
    return components


def _flood_from_border(candidate: np.ndarray) -> np.ndarray:
    height, width = candidate.shape
    flooded = np.zeros(candidate.shape, dtype=np.bool_)
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        if candidate[0, x]:
            queue.append((x, 0))
            flooded[0, x] = True
        if candidate[height - 1, x] and not flooded[height - 1, x]:
            queue.append((x, height - 1))
            flooded[height - 1, x] = True
    for y in range(height):
        if candidate[y, 0] and not flooded[y, 0]:
            queue.append((0, y))
            flooded[y, 0] = True
        if candidate[y, width - 1] and not flooded[y, width - 1]:
            queue.append((width - 1, y))
            flooded[y, width - 1] = True
    while queue:
        x, y = queue.popleft()
        for next_x, next_y in _neighbors4(x, y, width, height):
            if flooded[next_y, next_x] or not candidate[next_y, next_x]:
                continue
            flooded[next_y, next_x] = True
            queue.append((next_x, next_y))
    return flooded


def _adjacent_to(mask: np.ndarray) -> np.ndarray:
    result = np.zeros(mask.shape, dtype=np.bool_)
    result[1:, :] |= mask[:-1, :]
    result[:-1, :] |= mask[1:, :]
    result[:, 1:] |= mask[:, :-1]
    result[:, :-1] |= mask[:, 1:]
    return result


def _keep_largest_component(array: np.ndarray, threshold: int = 1) -> np.ndarray:
    mask = array[:, :, 3] >= threshold
    components = _connected_components(mask, min_area=8, keep_pixels=True)
    if not components:
        raise ValueError("No foreground component was detected")
    keep = np.zeros(mask.shape, dtype=np.bool_)
    for x, y in components[0]["pixels"]:
        keep[y, x] = True
    output = array.copy()
    output[~keep, 3] = 0
    output[output[:, :, 3] == 0, :3] = 0
    return output


def _remove_player_checker(image: Image.Image) -> Image.Image:
    array = np.asarray(image.convert("RGBA")).copy()
    rgb = array[:, :, :3].astype(np.int16)
    minimum = rgb.min(axis=2)
    maximum = rgb.max(axis=2)
    chroma = maximum - minimum
    alpha = array[:, :, 3]
    checker_candidate = ((minimum >= 225) & (chroma <= 8)) | (alpha < 8)
    flooded = _flood_from_border(checker_candidate)
    array[flooded, 3] = 0

    # Peel two exposed neutral antialias passes. Enclosed visor/equipment highlights stay intact.
    relaxed_candidate = (minimum >= 185) & (chroma <= 14)
    for _pass in range(2):
        exposed = relaxed_candidate & _adjacent_to(array[:, :, 3] == 0)
        array[exposed, 3] = 0
    array = _keep_largest_component(array, threshold=1)
    return Image.fromarray(array)


def _remove_guard_hidden_background(image: Image.Image) -> Image.Image:
    array = np.asarray(image.convert("RGBA")).copy()
    array[array[:, :, 3] < 16, 3] = 0
    array = _keep_largest_component(array, threshold=16)
    array[array[:, :, 3] == 0, :3] = 0
    return Image.fromarray(array)


def _remove_dark_matte(image: Image.Image) -> Image.Image:
    array = np.asarray(image.convert("RGBA")).copy()
    rgb = array[:, :, :3].astype(np.int16)
    maximum = rgb.max(axis=2)
    minimum = rgb.min(axis=2)
    dark_candidate = (maximum <= 18) & ((maximum - minimum) <= 10)
    flooded = _flood_from_border(dark_candidate)
    array[flooded, 3] = 0
    # Only clear very dark exposed pixels. A single pass protects the 1px object outline.
    exposed = (maximum <= 9) & _adjacent_to(array[:, :, 3] == 0)
    array[exposed, 3] = 0
    array = _keep_largest_component(array, threshold=1)
    return Image.fromarray(array)


def _alpha_bbox(image: Image.Image, threshold: int = 1) -> tuple[int, int, int, int]:
    alpha = np.asarray(image.convert("RGBA"))[:, :, 3]
    ys, xs = np.nonzero(alpha >= threshold)
    if xs.size == 0:
        raise ValueError("Frame has no foreground pixels")
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def _fixed_actor_scale(images: Iterable[Image.Image], maximum_size: tuple[int, int]) -> float:
    max_width = 0
    max_height = 0
    for image in images:
        x0, y0, x1, y1 = _alpha_bbox(image, 1)
        max_width = max(max_width, x1 - x0)
        max_height = max(max_height, y1 - y0)
    if max_width <= 0 or max_height <= 0:
        raise ValueError("Cannot calculate scale for empty frames")
    return min(maximum_size[0] / max_width, maximum_size[1] / max_height)


def _normalize_character_frame(image: Image.Image, scale: float) -> Image.Image:
    x0, y0, x1, y1 = _alpha_bbox(image, 1)
    cropped = image.crop((x0, y0, x1, y1)).convert("RGBA")
    new_size = (
        max(1, int(round(cropped.width * scale))),
        max(1, int(round(cropped.height * scale))),
    )
    resized = cropped.resize(new_size, Image.Resampling.NEAREST)
    alpha = np.asarray(resized)[:, :, 3]
    foot_start = max(0, resized.height - max(2, resized.height // 5))
    foot_y, foot_x = np.nonzero(alpha[foot_start:, :] > 0)
    if foot_x.size:
        foot_center = float(foot_x.min() + foot_x.max() + 1) * 0.5
    else:
        foot_center = resized.width * 0.5
    paste_x = int(round(PIVOT[0] - foot_center))
    paste_y = PIVOT[1] - resized.height
    paste_x = max(1, min(FRAME_SIZE[0] - resized.width - 1, paste_x))
    paste_y = max(1, min(FRAME_SIZE[1] - resized.height - 1, paste_y))
    canvas = Image.new("RGBA", FRAME_SIZE, (0, 0, 0, 0))
    canvas.alpha_composite(resized, (paste_x, paste_y))
    return canvas


def _normalize_prop(image: Image.Image) -> Image.Image:
    x0, y0, x1, y1 = _alpha_bbox(image, 1)
    cropped = image.crop((x0, y0, x1, y1)).convert("RGBA")
    scale = min(30.0 / cropped.width, 30.0 / cropped.height)
    size = (
        max(1, int(round(cropped.width * scale))),
        max(1, int(round(cropped.height * scale))),
    )
    resized = cropped.resize(size, Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", (TILE_SIZE, TILE_SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(resized, ((TILE_SIZE - size[0]) // 2, TILE_SIZE - 1 - size[1]))
    return canvas


def _player_candidates(source: Image.Image) -> tuple[dict[str, Image.Image], dict[str, list[int]]]:
    candidates: dict[str, Image.Image] = {}
    boxes: dict[str, list[int]] = {}
    for row in range(4):
        y0 = round(row * source.height / 4.0)
        y1 = round((row + 1) * source.height / 4.0)
        for column in range(8):
            x0 = round(column * source.width / 8.0)
            x1 = round((column + 1) * source.width / 8.0)
            key = f"r{row}c{column}"
            cleaned = _remove_player_checker(source.crop((x0, y0, x1, y1)))
            local_bbox = _alpha_bbox(cleaned, 1)
            candidates[key] = cleaned
            boxes[key] = [
                x0 + local_bbox[0],
                y0 + local_bbox[1],
                x0 + local_bbox[2],
                y0 + local_bbox[3],
            ]
    return candidates, boxes


def _guard_candidates(source: Image.Image) -> tuple[dict[str, Image.Image], dict[str, list[int]]]:
    alpha = np.asarray(source.convert("RGBA"))[:, :, 3]
    components = _connected_components(alpha >= 16, min_area=1200)
    if len(components) != 20:
        raise ValueError(f"Expected 20 guard components at alpha>=16, found {len(components)}")
    ordered = sorted(components, key=lambda item: (item["bbox"][1], item["bbox"][0]))
    rows: list[list[dict[str, Any]]] = []
    for index in range(0, 20, 5):
        row = sorted(ordered[index : index + 5], key=lambda item: item["bbox"][0])
        rows.append(row)
    candidates: dict[str, Image.Image] = {}
    boxes: dict[str, list[int]] = {}
    for row_index, row in enumerate(rows):
        for column_index, component in enumerate(row):
            x0, y0, x1, y1 = component["bbox"]
            padding = 2
            crop_box = (
                max(0, x0 - padding),
                max(0, y0 - padding),
                min(source.width, x1 + padding),
                min(source.height, y1 + padding),
            )
            key = f"r{row_index}c{column_index}"
            cleaned = _remove_guard_hidden_background(source.crop(crop_box))
            candidates[key] = cleaned
            boxes[key] = [x0, y0, x1, y1]
    return candidates, boxes


def _pack_atlas(
    frame_keys: list[str], frames: dict[str, Image.Image]
) -> tuple[Image.Image, dict[str, int], list[dict[str, Any]]]:
    rows = int(math.ceil(len(frame_keys) / ATLAS_COLUMNS))
    atlas = Image.new(
        "RGBA",
        (ATLAS_COLUMNS * FRAME_SIZE[0], rows * FRAME_SIZE[1]),
        (0, 0, 0, 0),
    )
    key_to_index: dict[str, int] = {}
    metadata: list[dict[str, Any]] = []
    for index, key in enumerate(frame_keys):
        x = (index % ATLAS_COLUMNS) * FRAME_SIZE[0]
        y = (index // ATLAS_COLUMNS) * FRAME_SIZE[1]
        atlas.alpha_composite(frames[key], (x, y))
        key_to_index[key] = index
        metadata.append(
            {
                "index": index,
                "source_key": key,
                "rect": [x, y, FRAME_SIZE[0], FRAME_SIZE[1]],
                "content_bbox": list(_alpha_bbox(frames[key], 1)),
                "horizontal_flip": False,
            }
        )
    return atlas, key_to_index, metadata


def _animation_entry(
    keys: list[str], key_to_index: dict[str, int], fps: float, loop: bool
) -> dict[str, Any]:
    return {
        "fps": fps,
        "loop": loop,
        "frames": [
            {
                "index": key_to_index[key],
            }
            for key in keys
        ],
    }


def _make_character_preview(
    atlas: Image.Image,
    manifest: dict[str, Any],
    animation_order: tuple[str, ...],
    candidate_frames: dict[str, Image.Image],
) -> Image.Image:
    columns = 4
    rows = 3
    panel_width = 150
    panel_height = 164
    animation_preview = Image.new(
        "RGBA", (columns * panel_width, rows * panel_height), (7, 13, 24, 255)
    )
    draw = ImageDraw.Draw(animation_preview)
    for animation_index, animation_name in enumerate(animation_order):
        panel_x = (animation_index % columns) * panel_width
        panel_y = (animation_index // columns) * panel_height
        draw.rectangle(
            (panel_x + 2, panel_y + 2, panel_x + panel_width - 3, panel_y + panel_height - 3),
            fill=(14, 24, 38, 255),
            outline=(55, 81, 104, 255),
        )
        frame_index = manifest["animations"][animation_name]["frames"][0]["index"]
        frame = manifest["frames"][frame_index]
        x, y, width, height = frame["rect"]
        sprite = atlas.crop((x, y, x + width, y + height)).resize(
            (width * 2, height * 2), Image.Resampling.NEAREST
        )
        animation_preview.alpha_composite(sprite, (panel_x + 27, panel_y + 20))
        draw.text((panel_x + 8, panel_y + 140), animation_name, fill=(210, 231, 244, 255))

    candidate_columns = 8
    candidate_panel_width = 80
    candidate_panel_height = 92
    candidate_keys = sorted(candidate_frames.keys())
    candidate_rows = int(math.ceil(len(candidate_keys) / candidate_columns))
    candidate_width = candidate_columns * candidate_panel_width
    candidate_height = 26 + candidate_rows * candidate_panel_height
    combined = Image.new(
        "RGBA",
        (max(animation_preview.width, candidate_width), animation_preview.height + candidate_height),
        (7, 13, 24, 255),
    )
    combined.alpha_composite(
        animation_preview,
        ((combined.width - animation_preview.width) // 2, 0),
    )
    combined_draw = ImageDraw.Draw(combined)
    candidate_top = animation_preview.height
    combined_draw.text(
        (8, candidate_top + 7),
        "ALL DETECTED SOURCE CANDIDATES (cyan=selected, orange=review only)",
        fill=(210, 231, 244, 255),
    )
    selected_keys = {str(frame["source_key"]) for frame in manifest["frames"]}
    for candidate_index, key in enumerate(candidate_keys):
        panel_x = (candidate_index % candidate_columns) * candidate_panel_width
        panel_y = candidate_top + 26 + (candidate_index // candidate_columns) * candidate_panel_height
        border = (51, 224, 216, 255) if key in selected_keys else (242, 158, 67, 255)
        combined_draw.rectangle(
            (panel_x + 2, panel_y + 2, panel_x + candidate_panel_width - 3, panel_y + candidate_panel_height - 3),
            fill=(14, 24, 38, 255),
            outline=border,
        )
        combined.alpha_composite(candidate_frames[key], (panel_x + 16, panel_y + 7))
        combined_draw.text((panel_x + 6, panel_y + 75), key, fill=border)
    return combined


def _render_sprite_frames_resource(
    manifest: dict[str, Any], animation_order: tuple[str, ...]
) -> str:
    atlas_path = ROOT / manifest["runtime_atlas"]
    lines = [
        f'[gd_resource type="SpriteFrames" load_steps={len(manifest["frames"]) + 2} format=3]',
        "",
        f'[ext_resource type="Texture2D" path="{_godot_path(atlas_path)}" id="1_atlas"]',
        "",
    ]
    for frame in manifest["frames"]:
        index = int(frame["index"])
        x, y, width, height = frame["rect"]
        lines.extend(
            [
                f'[sub_resource type="AtlasTexture" id="AtlasTexture_{index}"]',
                'atlas = ExtResource("1_atlas")',
                f"region = Rect2({x}, {y}, {width}, {height})",
                "filter_clip = true",
                "",
            ]
        )
    lines.append("[resource]")
    lines.append("animations = [{")
    for animation_index, animation_name in enumerate(animation_order):
        animation = manifest["animations"][animation_name]
        if animation_index > 0:
            lines.append("{")
        lines.append('"frames": [')
        for frame_position, frame in enumerate(animation["frames"]):
            comma = "," if frame_position + 1 < len(animation["frames"]) else ""
            lines.extend(
                [
                    "{",
                    '"duration": 1.0,',
                    f'"texture": SubResource("AtlasTexture_{frame["index"]}")',
                    f"}}{comma}",
                ]
            )
        lines.extend(
            [
                "],",
                f'"loop": {1 if animation["loop"] else 0},',
                f'"name": &"{animation_name}",',
                f'"speed": {float(animation["fps"]):.1f}',
                "}" + ("," if animation_index + 1 < len(animation_order) else ""),
            ]
        )
    lines.append("]")
    return "\n".join(lines) + "\n"


def _write_sprite_frames_resource(
    manifest: dict[str, Any], animation_order: tuple[str, ...], output_path: Path
) -> None:
    _ensure_parent(output_path)
    output_path.write_text(
        _render_sprite_frames_resource(manifest, animation_order),
        encoding="utf-8",
    )


def _character_manifest_base(
    character: str,
    source: Image.Image,
    atlas: Image.Image,
    frames: list[dict[str, Any]],
    source_boxes: dict[str, list[int]],
    scale: float,
) -> dict[str, Any]:
    processed_atlas = PROCESSED_DIR / "characters" / character / f"{character}_atlas.png"
    runtime_atlas = RUNTIME_SPRITE_DIR / "characters" / f"{character}_atlas.png"
    return {
        "schema_version": 1,
        "pipeline_version": PIPELINE_VERSION,
        "character": character,
        "source": _relative(SOURCE_FILES[character]),
        "source_sha256": _sha256_file(SOURCE_FILES[character]),
        "source_size": [source.width, source.height],
        "source_mode": source.mode,
        "processed_atlas": _relative(processed_atlas),
        "runtime_atlas": _relative(runtime_atlas),
        "atlas_size": [atlas.width, atlas.height],
        "atlas_pixel_sha256": _pixel_sha256(atlas),
        "frame_size": list(FRAME_SIZE),
        "pivot": list(PIVOT),
        "normalization": {
            "resize_filter": "nearest",
            "actor_fixed_scale": round(scale, 8),
            "alignment": "bottom_center",
            "maximum_content_size": [46, 60],
        },
        "detected_candidate_count": len(source_boxes),
        "selected_frame_count": len(frames),
        "source_candidates": source_boxes,
        "frames": frames,
        "animations": {},
        "fallbacks": {},
        "horizontal_flip_animations": [],
    }


def process_player() -> None:
    _require_sources()
    source = Image.open(SOURCE_FILES["player"])
    candidates, boxes = _player_candidates(source)
    selected_keys = ["r0c0", "r0c1"]
    for row in (1, 2, 3):
        selected_keys.extend(f"r{row}c{column}" for column in range(8))
    scale = _fixed_actor_scale((candidates[key] for key in selected_keys), (46, 60))
    normalized_candidates = {
        key: _normalize_character_frame(candidate, scale) for key, candidate in candidates.items()
    }
    normalized = {key: normalized_candidates[key] for key in selected_keys}
    atlas, key_to_index, frames = _pack_atlas(selected_keys, normalized)
    manifest = _character_manifest_base(
        "player", source, atlas, frames, boxes, scale
    )
    manifest["background_removal"] = {
        "method": "border_flood_fill_then_largest_component",
        "checker_threshold": "min_rgb>=225 and chroma<=8",
        "fringe_cleanup": "two exposed passes at min_rgb>=185 and chroma<=14",
        "white_key_used": False,
        "source_has_baked_checkerboard": True,
    }
    animations = manifest["animations"]
    animations["idle_down"] = _animation_entry(["r0c0", "r0c1"], key_to_index, 3.0, True)
    animations["idle_left"] = _animation_entry(["r1c0", "r1c1"], key_to_index, 3.0, True)
    animations["idle_right"] = _animation_entry(["r2c0", "r2c1"], key_to_index, 3.0, True)
    animations["idle_up"] = _animation_entry(["r3c0", "r3c1"], key_to_index, 3.0, True)
    animations["walk_down"] = _animation_entry(["r0c0", "r0c1"], key_to_index, 4.0, True)
    animations["walk_left"] = _animation_entry(
        [f"r1c{column}" for column in range(2, 8)], key_to_index, 8.0, True
    )
    animations["walk_right"] = _animation_entry(
        [f"r2c{column}" for column in range(2, 8)], key_to_index, 8.0, True
    )
    animations["walk_up"] = _animation_entry(
        [f"r3c{column}" for column in range(2, 8)], key_to_index, 8.0, True
    )
    animations["interact_down"] = _animation_entry(["r0c0"], key_to_index, 6.0, False)
    animations["interact_left"] = _animation_entry(["r1c6", "r1c7"], key_to_index, 6.0, False)
    animations["interact_right"] = _animation_entry(["r2c6", "r2c7"], key_to_index, 6.0, False)
    animations["interact_up"] = _animation_entry(["r3c0"], key_to_index, 6.0, False)
    manifest["fallbacks"] = {
        "walk_down": {
            "kind": "idle_pose_reuse",
            "target": "idle_down",
            "reason": "Only two stable front-facing poses exist; the remaining first-row poses drift left.",
        },
        "interact_down": {
            "kind": "static_pose_placeholder",
            "target": "idle_down",
            "reason": "No authored down interaction pose exists.",
        },
        "interact_left": {
            "kind": "source_pose_placeholder",
            "target": "idle_left",
            "reason": "Late left-facing source poses are reused; they were not authored as interaction frames.",
        },
        "interact_right": {
            "kind": "source_pose_placeholder",
            "target": "idle_right",
            "reason": "Late right-facing source poses are reused; they were not authored as interaction frames.",
        },
        "interact_up": {
            "kind": "static_pose_placeholder",
            "target": "idle_up",
            "reason": "No authored up interaction pose exists.",
        },
    }
    manifest["quality_limits"] = [
        "The front walk uses two near-idle poses and is intentionally limited to 4 FPS.",
        "Interaction poses are documented fallbacks, not newly authored animation.",
        "Original frame proportions vary slightly; actor-wide fixed scaling prevents size popping.",
    ]

    processed_dir = PROCESSED_DIR / "characters" / "player"
    processed_atlas = processed_dir / "player_atlas.png"
    runtime_atlas = RUNTIME_SPRITE_DIR / "characters" / "player_atlas.png"
    manifest_path = processed_dir / "player_frames.json"
    preview_path = processed_dir / "player_preview.png"
    _save_png(atlas, processed_atlas)
    _save_png(atlas, runtime_atlas)
    _save_json(manifest, manifest_path)
    _save_png(
        _make_character_preview(atlas, manifest, PLAYER_ANIMATIONS, normalized_candidates),
        preview_path,
    )
    _write_sprite_frames_resource(
        manifest,
        PLAYER_ANIMATIONS,
        RESOURCE_DIR / "characters" / "player_sprite_frames.tres",
    )
    _log(f"Player: 32 candidates, {len(frames)} selected frames, atlas {atlas.size}")


def process_guard() -> None:
    _require_sources()
    source = Image.open(SOURCE_FILES["guard"])
    candidates, boxes = _guard_candidates(source)
    direction_columns = {"down": 0, "left": 1, "right": 4, "up": 2}
    selected_keys: list[str] = []
    for row in range(4):
        for column in direction_columns.values():
            key = f"r{row}c{column}"
            if key not in selected_keys:
                selected_keys.append(key)
    scale = _fixed_actor_scale((candidates[key] for key in selected_keys), (46, 60))
    normalized_candidates = {
        key: _normalize_character_frame(candidate, scale) for key, candidate in candidates.items()
    }
    normalized = {key: normalized_candidates[key] for key in selected_keys}
    atlas, key_to_index, frames = _pack_atlas(selected_keys, normalized)
    manifest = _character_manifest_base(
        "guard", source, atlas, frames, boxes, scale
    )
    manifest["background_removal"] = {
        "method": "source_alpha_threshold_then_largest_component",
        "alpha_threshold": 16,
        "source_alpha_is_authoritative": True,
        "transparent_rgb_zeroed": True,
    }
    animations = manifest["animations"]
    for direction, column in direction_columns.items():
        animations[f"idle_{direction}"] = _animation_entry(
            [f"r0c{column}"], key_to_index, 3.0, True
        )
    for direction, column in direction_columns.items():
        animations[f"walk_{direction}"] = _animation_entry(
            [f"r0c{column}", f"r1c{column}"], key_to_index, 6.0, True
        )
    for direction, column in direction_columns.items():
        animations[f"alert_{direction}"] = _animation_entry(
            [f"r2c{column}", f"r3c{column}"], key_to_index, 6.0, False
        )
    manifest["fallbacks"] = {
        f"walk_{direction}": {
            "kind": "two_pose_walk_placeholder",
            "target": f"idle_{direction}",
            "reason": "Rows 1 and 2 are subtle alternate poses, not a complete authored walk cycle.",
        }
        for direction in direction_columns
    }
    for direction in direction_columns:
        manifest["fallbacks"][f"alert_{direction}"] = {
            "kind": "equipment_pose_placeholder",
            "target": f"idle_{direction}",
            "reason": "Rows 3 and 4 show equipment poses and are used as the clearest available alert cue.",
        }
    manifest["quality_limits"] = [
        "Left and right views are three-quarter poses rather than strict profiles.",
        "The source does not contain a complete patrol cycle or authored alert sequence.",
        "Equipment direction is presentation-only and is not used as authoritative vision data.",
    ]

    processed_dir = PROCESSED_DIR / "characters" / "guard"
    processed_atlas = processed_dir / "guard_atlas.png"
    runtime_atlas = RUNTIME_SPRITE_DIR / "characters" / "guard_atlas.png"
    manifest_path = processed_dir / "guard_frames.json"
    preview_path = processed_dir / "guard_preview.png"
    _save_png(atlas, processed_atlas)
    _save_png(atlas, runtime_atlas)
    _save_json(manifest, manifest_path)
    _save_png(
        _make_character_preview(atlas, manifest, GUARD_ANIMATIONS, normalized_candidates),
        preview_path,
    )
    _write_sprite_frames_resource(
        manifest,
        GUARD_ANIMATIONS,
        RESOURCE_DIR / "characters" / "guard_sprite_frames.tres",
    )
    _log(f"Guard: 20 candidates, {len(frames)} selected frames, atlas {atlas.size}")


def _procedural_wall_tile(corner: bool = False) -> Image.Image:
    tile = Image.new("RGBA", (TILE_SIZE, TILE_SIZE), (18, 28, 42, 255))
    draw = ImageDraw.Draw(tile)
    draw.rectangle((0, 0, 31, 5), fill=(68, 81, 98, 255))
    draw.line((0, 6, 31, 6), fill=(106, 119, 132, 255), width=1)
    draw.rectangle((2, 9, 29, 29), fill=(29, 41, 57, 255), outline=(47, 62, 79, 255))
    draw.line((16, 9, 16, 29), fill=(22, 33, 47, 255), width=1)
    draw.rectangle((4, 12, 6, 14), fill=(55, 180, 191, 255))
    if corner:
        draw.rectangle((0, 0, 6, 31), fill=(64, 78, 96, 255))
        draw.line((7, 0, 7, 31), fill=(108, 119, 132, 255), width=1)
    return tile


def _procedural_floor_tile() -> Image.Image:
    tile = Image.new("RGBA", (TILE_SIZE, TILE_SIZE), (13, 23, 36, 255))
    draw = ImageDraw.Draw(tile)
    draw.rectangle((0, 0, 31, 31), outline=(25, 40, 56, 255))
    draw.line((2, 2, 29, 2), fill=(31, 47, 63, 255), width=1)
    draw.line((2, 29, 29, 29), fill=(8, 16, 27, 255), width=1)
    draw.point((6, 6), fill=(47, 69, 84, 255))
    draw.point((25, 25), fill=(6, 14, 24, 255))
    return tile


def _tile_entry(
    identifier: str,
    coord: tuple[int, int],
    category: str,
    origin: str,
    usage: str,
    collision: bool = False,
    source_bbox: tuple[int, int, int, int] | None = None,
    quality_note: str = "",
) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "id": identifier,
        "atlas_coords": list(coord),
        "category": category,
        "origin": origin,
        "usage": usage,
        "collision": collision,
    }
    if source_bbox is not None:
        entry["source_bbox"] = list(source_bbox)
    if quality_note:
        entry["quality_note"] = quality_note
    return entry


def _extract_prop(source: Image.Image, bbox: tuple[int, int, int, int]) -> Image.Image:
    return _normalize_prop(_remove_dark_matte(source.crop(bbox)))


def _render_tileset_resource(manifest: dict[str, Any]) -> str:
    runtime_atlas = ROOT / manifest["runtime_atlas"]
    lines = [
        '[gd_resource type="TileSet" load_steps=4 format=3]',
        "",
        f'[ext_resource type="Texture2D" path="{_godot_path(runtime_atlas)}" id="1_tiles"]',
        "",
        '[sub_resource type="OccluderPolygon2D" id="OccluderPolygon2D_full_cell"]',
        'polygon = PackedVector2Array(-16, -16, 16, -16, 16, 16, -16, 16)',
        "",
        '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_facility"]',
        'texture = ExtResource("1_tiles")',
        f"texture_region_size = Vector2i({TILE_SIZE}, {TILE_SIZE})",
    ]
    collision_points = "PackedVector2Array(-16, -16, 16, -16, 16, 16, -16, 16)"
    for entry in manifest["tiles"]:
        x, y = entry["atlas_coords"]
        lines.append(f"{x}:{y}/0 = 0")
        if entry["collision"]:
            lines.append(
                f"{x}:{y}/0/physics_layer_0/polygon_0/points = {collision_points}"
            )
            lines.append(
                f'{x}:{y}/0/occlusion_layer_0/polygon_0/polygon = '
                'SubResource("OccluderPolygon2D_full_cell")'
            )
    lines.extend(
        [
            "",
            "[resource]",
            f"tile_size = Vector2i({TILE_SIZE}, {TILE_SIZE})",
            "physics_layer_0/collision_layer = 65",
            "physics_layer_0/collision_mask = 0",
            "occlusion_layer_0/light_mask = 1",
            "occlusion_layer_0/sdf_collision = false",
            'sources/0 = SubResource("TileSetAtlasSource_facility")',
        ]
    )
    return "\n".join(lines) + "\n"


def _write_tileset_resource(manifest: dict[str, Any], output_path: Path) -> None:
    _ensure_parent(output_path)
    output_path.write_text(_render_tileset_resource(manifest), encoding="utf-8")


def _make_tileset_preview(atlas: Image.Image, entries: list[dict[str, Any]]) -> Image.Image:
    scale = 3
    panel_width = 144
    panel_height = 128
    columns = 4
    rows = int(math.ceil(len(entries) / columns))
    preview = Image.new(
        "RGBA", (columns * panel_width, rows * panel_height), (6, 10, 17, 255)
    )
    draw = ImageDraw.Draw(preview)
    for index, entry in enumerate(entries):
        panel_x = (index % columns) * panel_width
        panel_y = (index // columns) * panel_height
        x, y = entry["atlas_coords"]
        tile = atlas.crop(
            (x * TILE_SIZE, y * TILE_SIZE, (x + 1) * TILE_SIZE, (y + 1) * TILE_SIZE)
        ).resize((TILE_SIZE * scale, TILE_SIZE * scale), Image.Resampling.NEAREST)
        draw.rectangle(
            (panel_x + 2, panel_y + 2, panel_x + panel_width - 3, panel_y + panel_height - 3),
            fill=(15, 24, 36, 255),
            outline=(55, 74, 91, 255),
        )
        preview.alpha_composite(tile, (panel_x + 24, panel_y + 8))
        draw.text((panel_x + 6, panel_y + 106), entry["id"], fill=(205, 222, 234, 255))
    return preview


def process_tileset() -> None:
    _require_sources()
    source = Image.open(SOURCE_FILES["facility"]).convert("RGB")
    atlas = Image.new("RGBA", (8 * TILE_SIZE, 4 * TILE_SIZE), (0, 0, 0, 0))
    entries: list[dict[str, Any]] = []

    for row, (y0, y1) in enumerate(((287, 365), (369, 449))):
        for column, (x0, x1) in enumerate(FLOOR_X_RANGES):
            crop = source.crop((x0, y0, x1, y1)).convert("RGBA")
            tile = crop.resize((TILE_SIZE, TILE_SIZE), Image.Resampling.NEAREST)
            atlas.alpha_composite(tile, (column * TILE_SIZE, row * TILE_SIZE))
            identifiers = (
                (
                    "floor_panel_a",
                    "floor_panel_b",
                    "floor_lit_reference",
                    "floor_vent_reference",
                    "floor_dark_panel",
                    "floor_cracked_a",
                    "floor_cracked_b",
                    "floor_cracked_c",
                )
                if row == 0
                else (
                    "floor_hazard_a",
                    "floor_hazard_b",
                    "floor_pit_reference",
                    "floor_moss_reference",
                    "floor_wood_reference",
                    "floor_stone_a",
                    "floor_stone_b",
                    "floor_stone_c",
                )
            )
            identifier = identifiers[column]
            usage = "runtime_limited" if identifier in {
                "floor_panel_a",
                "floor_panel_b",
                "floor_dark_panel",
            } else "reference_only"
            category = "floor" if "floor" in identifier else "unused_reference"
            entries.append(
                _tile_entry(
                    identifier,
                    (column, row),
                    category,
                    "source_crop_nearest",
                    usage,
                    source_bbox=(x0, y0, x1, y1),
                    quality_note=(
                        "Panel edges are not seamless; use as a sparse panel grid, not a terrain fill."
                    ),
                )
            )

    row_two: list[tuple[dict[str, Any], Image.Image]] = [
        (
            _tile_entry(
                "wall_authored_placeholder",
                (0, 2),
                "wall",
                "procedural_placeholder_source_palette",
                "runtime",
                collision=True,
                quality_note="AI wall pieces were rejected for inconsistent perspective and dimensions.",
            ),
            _procedural_wall_tile(False),
        ),
        (
            _tile_entry(
                "wall_corner_authored_placeholder",
                (1, 2),
                "wall_corner",
                "procedural_placeholder_source_palette",
                "runtime",
                collision=True,
            ),
            _procedural_wall_tile(True),
        ),
        (
            _tile_entry(
                "door_reference",
                (2, 2),
                "door",
                "source_crop_manual_mask",
                "reference_only",
                source_bbox=(1110, 149, 1188, 251),
                quality_note="Stateful doors remain separate scenes.",
            ),
            _extract_prop(source, (1110, 149, 1188, 251)),
        ),
        (
            _tile_entry(
                "obstacle_metal_crate",
                (3, 2),
                "obstacle",
                "source_crop_manual_mask",
                "runtime_optional",
                collision=True,
                source_bbox=(1072, 484, 1121, 543),
            ),
            _extract_prop(source, (1072, 484, 1121, 543)),
        ),
        (
            _tile_entry(
                "terminal_console",
                (4, 2),
                "terminal",
                "source_crop_manual_mask",
                "runtime_optional",
                source_bbox=(871, 564, 933, 626),
            ),
            _extract_prop(source, (871, 564, 933, 626)),
        ),
        (
            _tile_entry(
                "server_rack",
                (5, 2),
                "server",
                "source_crop_manual_mask",
                "runtime_optional",
                collision=True,
                source_bbox=(1009, 564, 1056, 626),
            ),
            _extract_prop(source, (1009, 564, 1056, 626)),
        ),
        (
            _tile_entry(
                "crate_wood",
                (6, 2),
                "crate",
                "source_crop_manual_mask",
                "runtime_optional",
                collision=True,
                source_bbox=(962, 483, 1000, 543),
            ),
            _extract_prop(source, (962, 483, 1000, 543)),
        ),
        (
            _tile_entry(
                "decoration_plant",
                (7, 2),
                "decoration",
                "source_crop_manual_mask",
                "runtime_optional",
                source_bbox=(1451, 475, 1495, 542),
            ),
            _extract_prop(source, (1451, 475, 1495, 542)),
        ),
    ]

    row_three_specs = [
        (
            "pressure_plate_reference",
            "pressure_plate",
            (1071, 653, 1112, 690),
            "No authored pressure plate exists; this panel is reference-only.",
        ),
        (
            "objective_light_reference",
            "objective",
            (1110, 873, 1188, 988),
            "Colored light demo only; objective remains a separate procedural scene.",
        ),
        (
            "exit_light_reference",
            "exit",
            (1029, 873, 1106, 988),
            "Colored light demo only; exit remains a separate trigger scene.",
        ),
        (
            "laser_reference",
            "laser",
            (927, 653, 1050, 698),
            "Stateful laser visual is not used by the MVP puzzle.",
        ),
        (
            "light_reference",
            "light",
            (866, 873, 944, 988),
            "Baked lighting demonstration; not suitable for seamless terrain.",
        ),
        (
            "unused_wall_reference",
            "unused_reference",
            (868, 33, 965, 136),
            "Rejected wall perspective reference.",
        ),
        (
            "unused_camera_reference",
            "unused_reference",
            (1293, 652, 1338, 695),
            "Reference prop not used in tutorial gameplay.",
        ),
    ]
    row_three: list[tuple[dict[str, Any], Image.Image]] = []
    for column, (identifier, category, bbox, note) in enumerate(row_three_specs):
        row_three.append(
            (
                _tile_entry(
                    identifier,
                    (column, 3),
                    category,
                    "source_crop_manual_mask",
                    "reference_only",
                    source_bbox=bbox,
                    quality_note=note,
                ),
                _extract_prop(source, bbox),
            )
        )
    row_three.append(
        (
            _tile_entry(
                "floor_authored_placeholder",
                (7, 3),
                "floor",
                "procedural_placeholder_source_palette",
                "runtime",
                quality_note=(
                    "Stable seamless base retained because the AI floor candidates have mismatched edges."
                ),
            ),
            _procedural_floor_tile(),
        )
    )

    for entry, tile in row_two + row_three:
        x, y = entry["atlas_coords"]
        atlas.alpha_composite(tile, (x * TILE_SIZE, y * TILE_SIZE))
        entries.append(entry)

    processed_dir = PROCESSED_DIR / "environment"
    processed_atlas = processed_dir / "facility_tileset.png"
    runtime_atlas = RUNTIME_SPRITE_DIR / "environment" / "facility_tileset.png"
    manifest = {
        "schema_version": 1,
        "pipeline_version": PIPELINE_VERSION,
        "source": _relative(SOURCE_FILES["facility"]),
        "source_sha256": _sha256_file(SOURCE_FILES["facility"]),
        "source_size": [source.width, source.height],
        "source_mode": "RGB",
        "processed_atlas": _relative(processed_atlas),
        "runtime_atlas": _relative(runtime_atlas),
        "atlas_size": [atlas.width, atlas.height],
        "atlas_pixel_sha256": _pixel_sha256(atlas),
        "tile_size": [TILE_SIZE, TILE_SIZE],
        "tiles": entries,
        "runtime_floor_ids": [
            "floor_authored_placeholder",
            "floor_panel_a",
            "floor_panel_b",
            "floor_dark_panel",
        ],
        "runtime_wall_ids": [
            "wall_authored_placeholder",
            "wall_corner_authored_placeholder",
        ],
        "stateful_scene_categories": ["door", "pressure_plate", "objective", "exit"],
        "quality_limits": [
            "No AI-generated floor candidate is seamless; runtime panels are used sparsely.",
            "All AI wall pieces were rejected as collision terrain due to perspective and size mismatch.",
            "The runtime wall tile is a deterministic procedural placeholder using the source palette.",
            "The left-side map preview is reference-only and is never loaded by gameplay.",
        ],
    }
    _save_png(atlas, processed_atlas)
    _save_png(atlas, runtime_atlas)
    _save_json(manifest, processed_dir / "facility_tileset_manifest.json")
    _save_png(_make_tileset_preview(atlas, entries), processed_dir / "facility_tileset_preview.png")
    map_reference = source.crop((13, 25, 837, 832)).convert("RGBA")
    _save_png(map_reference, processed_dir / "facility_map_reference.png")
    _write_tileset_resource(
        manifest, RESOURCE_DIR / "tilesets" / "facility_tileset.tres"
    )
    _log(f"Facility: {len(entries)} classified tiles, atlas {atlas.size}; map preview kept reference-only")


def _inspect_image(key: str, path: Path) -> dict[str, Any]:
    image = Image.open(path)
    rgba = np.asarray(image.convert("RGBA"))
    alpha = rgba[:, :, 3]
    colors = Counter(map(tuple, rgba[:, :, :3].reshape(-1, 3))).most_common(8)
    report: dict[str, Any] = {
        "path": _relative(path),
        "size": [image.width, image.height],
        "mode": image.mode,
        "sha256": _sha256_file(path),
        "has_alpha_channel": "A" in image.getbands(),
        "alpha": {
            "transparent_pixels": int(np.count_nonzero(alpha == 0)),
            "partial_pixels": int(np.count_nonzero((alpha > 0) & (alpha < 255))),
            "opaque_pixels": int(np.count_nonzero(alpha == 255)),
        },
        "dominant_rgb": [
            {"color": [int(channel) for channel in color], "count": int(count)}
            for color, count in colors
        ],
    }
    if key == "player":
        _candidates, boxes = _player_candidates(image)
        report["baked_checkerboard_detected"] = True
        report["candidate_layout"] = [4, 8]
        report["candidate_boxes"] = boxes
    elif key == "guard":
        _candidates, boxes = _guard_candidates(image)
        report["baked_checkerboard_detected"] = False
        report["candidate_layout"] = [4, 5]
        report["candidate_boxes"] = boxes
    else:
        report["baked_checkerboard_detected"] = False
        report["classification"] = "concept_sheet_with_map_preview_tiles_props_and_guides"
        report["map_reference_bbox"] = [13, 25, 837, 832]
        report["floor_candidate_boxes"] = [
            [x0, y0, x1, y1]
            for y0, y1 in ((287, 365), (369, 449))
            for x0, x1 in FLOOR_X_RANGES
        ]
    return report


def inspect_sources() -> None:
    _require_sources()
    report = {
        "pipeline_version": PIPELINE_VERSION,
        "sources": {
            key: _inspect_image(key, path) for key, path in SOURCE_FILES.items()
        },
    }
    print(json.dumps(report, indent=2, ensure_ascii=False))


def _generated_output_paths() -> list[Path]:
    return [
        PROCESSED_DIR / "characters" / "player" / "player_atlas.png",
        PROCESSED_DIR / "characters" / "player" / "player_frames.json",
        PROCESSED_DIR / "characters" / "player" / "player_preview.png",
        PROCESSED_DIR / "characters" / "guard" / "guard_atlas.png",
        PROCESSED_DIR / "characters" / "guard" / "guard_frames.json",
        PROCESSED_DIR / "characters" / "guard" / "guard_preview.png",
        PROCESSED_DIR / "environment" / "facility_tileset.png",
        PROCESSED_DIR / "environment" / "facility_tileset_manifest.json",
        PROCESSED_DIR / "environment" / "facility_tileset_preview.png",
        PROCESSED_DIR / "environment" / "facility_map_reference.png",
        RUNTIME_SPRITE_DIR / "characters" / "player_atlas.png",
        RUNTIME_SPRITE_DIR / "characters" / "guard_atlas.png",
        RUNTIME_SPRITE_DIR / "environment" / "facility_tileset.png",
        RESOURCE_DIR / "characters" / "player_sprite_frames.tres",
        RESOURCE_DIR / "characters" / "guard_sprite_frames.tres",
        RESOURCE_DIR / "tilesets" / "facility_tileset.tres",
    ]


def fingerprint_outputs() -> None:
    """Print a platform-neutral semantic fingerprint for reproducibility checks."""
    _require_sources()
    fingerprints: dict[str, dict[str, str]] = {}
    for path in _generated_output_paths():
        if not path.is_file():
            raise FileNotFoundError(f"Missing generated output: {_relative(path)}")
        if path.suffix == ".png":
            digest = _pixel_sha256(Image.open(path))
            kind = "decoded_rgba"
        elif path.suffix == ".json":
            canonical = json.dumps(
                _load_json(path),
                ensure_ascii=False,
                separators=(",", ":"),
                sort_keys=True,
            ).encode("utf-8")
            digest = hashlib.sha256(canonical).hexdigest()
            kind = "canonical_json"
        else:
            normalized_text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
            digest = hashlib.sha256(normalized_text.encode("utf-8")).hexdigest()
            kind = "normalized_text"
        fingerprints[_relative(path)] = {"kind": kind, "sha256": digest}
    print(json.dumps(fingerprints, indent=2, ensure_ascii=False, sort_keys=True))


def _load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ValueError(f"Invalid JSON in {_relative(path)}: {error}") from error
    if not isinstance(data, dict):
        raise ValueError(f"Expected an object at the root of {_relative(path)}")
    return data


def _validate_character(character: str, expected_names: tuple[str, ...]) -> list[str]:
    errors: list[str] = []
    processed_dir = PROCESSED_DIR / "characters" / character
    manifest_path = processed_dir / f"{character}_frames.json"
    processed_atlas_path = processed_dir / f"{character}_atlas.png"
    runtime_atlas_path = RUNTIME_SPRITE_DIR / "characters" / f"{character}_atlas.png"
    resource_path = RESOURCE_DIR / "characters" / f"{character}_sprite_frames.tres"
    required = [
        manifest_path,
        processed_atlas_path,
        runtime_atlas_path,
        processed_dir / f"{character}_preview.png",
        resource_path,
    ]
    for path in required:
        if not path.is_file():
            errors.append(f"Missing {_relative(path)}")
    if errors:
        return errors
    manifest = _load_json(manifest_path)
    if manifest.get("pipeline_version") != PIPELINE_VERSION:
        errors.append(f"{character} manifest pipeline version is stale")
    if manifest.get("source_sha256") != EXPECTED_SOURCE_SHA256[character]:
        errors.append(f"{character} manifest source SHA is stale")
    if manifest.get("frame_size") != list(FRAME_SIZE):
        errors.append(f"{character} frame size is not {FRAME_SIZE}")
    if manifest.get("pivot") != list(PIVOT):
        errors.append(f"{character} pivot is not {PIVOT}")
    animation_names = tuple(manifest.get("animations", {}).keys())
    if animation_names != expected_names:
        errors.append(
            f"{character} animations differ: expected {expected_names}, got {animation_names}"
        )
    atlas = Image.open(processed_atlas_path)
    runtime_atlas = Image.open(runtime_atlas_path)
    if atlas.mode != "RGBA" or runtime_atlas.mode != "RGBA":
        errors.append(f"{character} atlases must be RGBA")
    if atlas.width % FRAME_SIZE[0] != 0 or atlas.height % FRAME_SIZE[1] != 0:
        errors.append(f"{character} atlas is not a multiple of the frame grid")
    if _pixel_sha256(atlas) != _pixel_sha256(runtime_atlas):
        errors.append(f"{character} processed/runtime atlas pixels differ")
    if manifest.get("atlas_pixel_sha256") != _pixel_sha256(atlas):
        errors.append(f"{character} manifest atlas pixel hash is stale")

    frame_count = len(manifest.get("frames", []))
    if int(manifest.get("selected_frame_count", -1)) != frame_count:
        errors.append(f"{character} selected-frame count is stale")
    if int(manifest.get("detected_candidate_count", -1)) != len(
        manifest.get("source_candidates", {})
    ):
        errors.append(f"{character} detected-candidate count is stale")
    for frame in manifest.get("frames", []):
        index = int(frame.get("index", -1))
        rect = frame.get("rect", [])
        if len(rect) != 4:
            errors.append(f"{character} frame {index} has an invalid rect")
            continue
        x, y, width, height = map(int, rect)
        if width != FRAME_SIZE[0] or height != FRAME_SIZE[1]:
            errors.append(f"{character} frame {index} has inconsistent dimensions")
        if x < 0 or y < 0 or x + width > atlas.width or y + height > atlas.height:
            errors.append(f"{character} frame {index} exceeds the atlas")
            continue
        frame_image = atlas.crop((x, y, x + width, y + height)).convert("RGBA")
        frame_array = np.asarray(frame_image)
        alpha = frame_array[:, :, 3]
        if not np.any(alpha > 0):
            errors.append(f"{character} frame {index} is empty")
        if not np.any(alpha == 0):
            errors.append(f"{character} frame {index} has no transparent padding")
        if np.any(alpha[0, :] > 0) or np.any(alpha[-1, :] > 0):
            errors.append(f"{character} frame {index} touches a vertical canvas edge")
        if np.any(alpha[:, 0] > 0) or np.any(alpha[:, -1] > 0):
            errors.append(f"{character} frame {index} touches a horizontal canvas edge")
        components = _connected_components(alpha > 0, min_area=1)
        significant = [component for component in components if component["area"] >= 8]
        if len(significant) != 1:
            errors.append(
                f"{character} frame {index} has {len(significant)} significant foreground components"
            )
        rgb = frame_array[:, :, :3].astype(np.int16)
        neutral_checker = (
            (rgb.min(axis=2) >= 225)
            & ((rgb.max(axis=2) - rgb.min(axis=2)) <= 8)
            & (alpha > 0)
        )
        if np.count_nonzero(neutral_checker) > max(180, int(np.count_nonzero(alpha) * 0.08)):
            errors.append(f"{character} frame {index} likely retains checkerboard pixels")

    for name, animation in manifest.get("animations", {}).items():
        if float(animation.get("fps", 0.0)) <= 0.0:
            errors.append(f"{character} animation {name} has non-positive FPS")
        animation_frames = animation.get("frames", [])
        if not animation_frames:
            errors.append(f"{character} animation {name} has no frames")
        for frame in animation_frames:
            index = int(frame.get("index", -1))
            if index < 0 or index >= frame_count:
                errors.append(f"{character} animation {name} references frame {index}")
    for name, fallback in manifest.get("fallbacks", {}).items():
        if name not in manifest.get("animations", {}):
            errors.append(f"{character} fallback key {name} has no animation")
        target = fallback.get("target", "")
        if target not in manifest.get("animations", {}):
            errors.append(f"{character} fallback {name} targets missing animation {target}")

    resource_text = resource_path.read_text(encoding="utf-8")
    expected_resource_text = _render_sprite_frames_resource(manifest, expected_names)
    if resource_text != expected_resource_text:
        errors.append(
            f"{character} SpriteFrames resource does not exactly match its manifest"
        )
    resource_names = tuple(re.findall(r'"name": &"([^"]+)"', resource_text))
    if resource_names != expected_names:
        errors.append(f"{character} SpriteFrames names differ from the manifest")
    if _godot_path(runtime_atlas_path) not in resource_text:
        errors.append(f"{character} SpriteFrames does not reference the runtime atlas")
    regions = re.findall(r"region = Rect2\((\d+), (\d+), (\d+), (\d+)\)", resource_text)
    if len(regions) != frame_count:
        errors.append(f"{character} SpriteFrames region count differs from the manifest")
    return errors


def _validate_tileset() -> list[str]:
    errors: list[str] = []
    processed_dir = PROCESSED_DIR / "environment"
    manifest_path = processed_dir / "facility_tileset_manifest.json"
    processed_atlas_path = processed_dir / "facility_tileset.png"
    runtime_atlas_path = RUNTIME_SPRITE_DIR / "environment" / "facility_tileset.png"
    resource_path = RESOURCE_DIR / "tilesets" / "facility_tileset.tres"
    required = [
        manifest_path,
        processed_atlas_path,
        runtime_atlas_path,
        processed_dir / "facility_tileset_preview.png",
        processed_dir / "facility_map_reference.png",
        resource_path,
    ]
    for path in required:
        if not path.is_file():
            errors.append(f"Missing {_relative(path)}")
    if errors:
        return errors
    manifest = _load_json(manifest_path)
    if manifest.get("pipeline_version") != PIPELINE_VERSION:
        errors.append("Facility manifest pipeline version is stale")
    if manifest.get("source_sha256") != EXPECTED_SOURCE_SHA256["facility"]:
        errors.append("Facility manifest source SHA is stale")
    atlas = Image.open(processed_atlas_path)
    runtime_atlas = Image.open(runtime_atlas_path)
    if atlas.mode != "RGBA" or runtime_atlas.mode != "RGBA":
        errors.append("Facility atlases must be RGBA")
    if atlas.width % TILE_SIZE != 0 or atlas.height % TILE_SIZE != 0:
        errors.append("Facility atlas size is not a multiple of 32")
    if _pixel_sha256(atlas) != _pixel_sha256(runtime_atlas):
        errors.append("Facility processed/runtime atlas pixels differ")
    if manifest.get("atlas_pixel_sha256") != _pixel_sha256(atlas):
        errors.append("Facility manifest atlas pixel hash is stale")
    required_categories = {
        "floor",
        "wall",
        "wall_corner",
        "door",
        "obstacle",
        "terminal",
        "server",
        "crate",
        "decoration",
        "pressure_plate",
        "objective",
        "exit",
        "laser",
        "light",
        "unused_reference",
    }
    categories = {entry.get("category") for entry in manifest.get("tiles", [])}
    missing_categories = required_categories - categories
    if missing_categories:
        errors.append(f"Facility manifest misses categories: {sorted(missing_categories)}")
    identifiers: set[str] = set()
    for entry in manifest.get("tiles", []):
        identifier = str(entry.get("id", ""))
        if not identifier or identifier in identifiers:
            errors.append(f"Duplicate or empty tile ID: {identifier!r}")
        identifiers.add(identifier)
        x, y = map(int, entry.get("atlas_coords", [-1, -1]))
        if x < 0 or y < 0 or (x + 1) * TILE_SIZE > atlas.width or (y + 1) * TILE_SIZE > atlas.height:
            errors.append(f"Tile {identifier} is outside the atlas")
            continue
        tile = np.asarray(
            atlas.crop(
                (x * TILE_SIZE, y * TILE_SIZE, (x + 1) * TILE_SIZE, (y + 1) * TILE_SIZE)
            ).convert("RGBA")
        )
        if not np.any(tile[:, :, 3] > 0):
            errors.append(f"Tile {identifier} is empty")
        if entry.get("category") == "floor" and entry.get("collision"):
            errors.append(f"Floor tile {identifier} unexpectedly has collision")
        if entry.get("category") in {"wall", "wall_corner"} and not entry.get("collision"):
            errors.append(f"Wall tile {identifier} lacks collision")
    resource_text = resource_path.read_text(encoding="utf-8")
    if resource_text != _render_tileset_resource(manifest):
        errors.append("TileSet resource does not exactly match its manifest")
    if _godot_path(runtime_atlas_path) not in resource_text:
        errors.append("TileSet does not reference the runtime atlas")
    if "physics_layer_0/collision_layer = 65" not in resource_text:
        errors.append("TileSet lacks the World and PlayerVisionBlocker layers")
    if "occlusion_layer_0/light_mask = 1" not in resource_text:
        errors.append("TileSet lacks the player-light occlusion layer")
    for entry in manifest.get("tiles", []):
        if not entry.get("collision"):
            continue
        x, y = map(int, entry["atlas_coords"])
        occlusion_property = f"{x}:{y}/0/occlusion_layer_0/polygon_0/polygon"
        if occlusion_property not in resource_text:
            errors.append(f"Solid tile {entry.get('id', '')} lacks light occlusion")
    return errors


def _validate_runtime_references() -> list[str]:
    errors: list[str] = []
    suffixes = {".gd", ".tscn", ".tres", ".godot"}
    roots = [ROOT / "scenes", ROOT / "scripts", ROOT / "resources", ROOT / "project.godot"]
    paths: list[Path] = []
    for root in roots:
        if root.is_file():
            paths.append(root)
        elif root.is_dir():
            paths.extend(path for path in root.rglob("*") if path.is_file() and path.suffix in suffixes)
    for path in paths:
        text = path.read_text(encoding="utf-8", errors="replace")
        forbidden_roots = (
            "res://assets/source/",
            "res://assets/processed/",
            "res://assets/concept/",
        )
        if any(forbidden_root in text for forbidden_root in forbidden_roots):
            errors.append(f"Gameplay resource references a non-runtime asset: {_relative(path)}")
    return errors


def validate() -> None:
    _require_sources()
    errors: list[str] = []
    errors.extend(_validate_character("player", PLAYER_ANIMATIONS))
    errors.extend(_validate_character("guard", GUARD_ANIMATIONS))
    errors.extend(_validate_tileset())
    errors.extend(_validate_runtime_references())
    if errors:
        for error in errors:
            print(f"[asset-pipeline] ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
    _log("PASS: source hashes, transparency, atlases, metadata, resources, and runtime references")


def process_all() -> None:
    process_player()
    process_guard()
    process_tileset()
    validate()


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("inspect", help="Inspect source modes, alpha, colors, and candidate boxes")
    subparsers.add_parser("process-player", help="Generate the player atlas, manifest, preview, and resource")
    subparsers.add_parser("process-guard", help="Generate the guard atlas, manifest, preview, and resource")
    subparsers.add_parser("process-tileset", help="Generate the classified facility derivative atlas")
    subparsers.add_parser("process-all", help="Generate all derivatives and validate them")
    subparsers.add_parser("validate", help="Validate committed derivatives without rewriting them")
    subparsers.add_parser(
        "fingerprint",
        help="Print semantic output hashes for cross-platform reproducibility comparison",
    )
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    commands = {
        "inspect": inspect_sources,
        "process-player": process_player,
        "process-guard": process_guard,
        "process-tileset": process_tileset,
        "process-all": process_all,
        "validate": validate,
        "fingerprint": fingerprint_outputs,
    }
    try:
        commands[args.command]()
    except (FileNotFoundError, ValueError) as error:
        print(f"[asset-pipeline] ERROR: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
