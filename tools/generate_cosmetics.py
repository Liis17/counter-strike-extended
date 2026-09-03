#!/usr/bin/env python3
"""Build the CSE cosmetic catalog from the stock GoldSrc studio models.

The generated files are runtime artifacts.  The repository keeps the catalog
and this deterministic recipe, while the stock models remain the installed
game assets.  Each output keeps the original skeleton and animations, remaps
the weapon texture palettes, adds a small materialized detail mesh, and is
then compiled back to a GoldSrc .mdl.
"""

from __future__ import annotations

import argparse
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

from validate_cosmetics import CatalogError, _int, _object, _tokens


MODEL_SUFFIXES = ("v", "p", "w")
SHIELD_COMBOS = (
    "deagle",
    "fiveseven",
    "flashbang",
    "glock18",
    "hegrenade",
    "knife",
    "p228",
    "smokegrenade",
    "usp",
)
HAND_TEXTURE_WORDS = ("finger", "glove", "hand", "skin", "sleeve")
IDST = int.from_bytes(b"IDST", "little")


@dataclass(frozen=True)
class CosmeticVariant:
    weapon: str
    slug: str
    variant_id: int
    palette: tuple[tuple[int, int, int], ...]
    motif: str
    detail: str
    paths: dict[str, str]


@dataclass(frozen=True)
class CosmeticWeapon:
    slug: str
    catalog_index: int
    category: str
    variants: tuple[CosmeticVariant, ...]


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig", errors="replace")


def _catalog_variant_paths(raw_variant: dict[str, object], slug: str, variant_slug: str) -> dict[str, str]:
    paths: dict[str, str] = {}
    for field in ("v", "p", "w"):
        value = raw_variant.get(field)
        if not isinstance(value, str) or not value:
            raise CatalogError(f"{slug}/{variant_slug}: missing {field}")
        paths[field] = value
    planted = raw_variant.get("w_planted")
    if planted:
        if not isinstance(planted, str):
            raise CatalogError(f"{slug}/{variant_slug}.w_planted must be a path")
        paths["w_planted"] = planted
    return paths


def _parse_palette(value: object, field: str) -> tuple[tuple[int, int, int], ...]:
    if not isinstance(value, str):
        raise CatalogError(f"{field} must be a palette")
    values = value.split("/")
    if len(values) != 3:
        raise CatalogError(f"{field} must contain three colors")
    colors: list[tuple[int, int, int]] = []
    for color in values:
        if not re.fullmatch(r"#[0-9A-Fa-f]{6}", color):
            raise CatalogError(f"{field} has invalid color {color}")
        colors.append(tuple(int(color[offset : offset + 2], 16) for offset in (1, 3, 5)))
    return tuple(colors)


def parse_catalog(path: Path) -> tuple[CosmeticWeapon, ...]:
    tokens = _tokens(path)
    if len(tokens) < 3 or tokens[0] != "CseCosmetics":
        raise CatalogError("expected CseCosmetics root")
    root, position = _object(tokens, 1)
    if position != len(tokens):
        raise CatalogError("unexpected tokens after root")

    weapons = root.get("weapons")
    if not isinstance(weapons, dict):
        raise CatalogError("weapons object is missing")

    parsed: list[CosmeticWeapon] = []
    for slug, raw_weapon in weapons.items():
        if not isinstance(raw_weapon, dict):
            raise CatalogError(f"weapon {slug} must be an object")
        raw_variants = raw_weapon.get("variants")
        if not isinstance(raw_variants, dict):
            raise CatalogError(f"{slug}.variants is missing")

        variants: list[CosmeticVariant] = []
        for variant_slug, raw_variant in raw_variants.items():
            if not isinstance(raw_variant, dict):
                raise CatalogError(f"{slug}/{variant_slug} must be an object")
            motif = raw_variant.get("motif")
            detail = raw_variant.get("detail")
            if not isinstance(motif, str) or not motif:
                raise CatalogError(f"{slug}/{variant_slug}: missing motif")
            if not isinstance(detail, str) or not detail:
                raise CatalogError(f"{slug}/{variant_slug}: missing detail")
            variants.append(
                CosmeticVariant(
                    weapon=slug,
                    slug=variant_slug,
                    variant_id=_int(raw_variant.get("variant_id"), f"{slug}/{variant_slug}.variant_id"),
                    palette=_parse_palette(raw_variant.get("palette"), f"{slug}/{variant_slug}.palette"),
                    motif=motif,
                    detail=detail,
                    paths=_catalog_variant_paths(raw_variant, slug, variant_slug),
                )
            )

        parsed.append(
            CosmeticWeapon(
                slug=slug,
                catalog_index=_int(raw_weapon.get("catalog_index"), f"{slug}.catalog_index"),
                category=str(raw_weapon.get("category", "")),
                variants=tuple(sorted(variants, key=lambda item: item.variant_id)),
            )
        )

    return tuple(sorted(parsed, key=lambda item: item.catalog_index))


def _fnv1a(value: str) -> int:
    result = 2166136261
    for byte in value.encode("utf-8"):
        result ^= byte
        result = (result * 16777619) & 0xFFFFFFFF
    return result


def _mix(first: tuple[int, int, int], second: tuple[int, int, int], amount: float) -> tuple[int, int, int]:
    return tuple(round(first[index] + (second[index] - first[index]) * amount) for index in range(3))


def _palette_color(colors: tuple[tuple[int, int, int], ...], index: int) -> tuple[int, int, int]:
    if index == 0:
        return colors[0]
    if index == 1:
        return colors[1]
    if index == 2:
        return colors[2]
    return _mix(colors[1], (235, 235, 226), 0.45)


def _is_hand_texture(path: Path) -> bool:
    name = path.stem.lower()
    return any(word in name for word in HAND_TEXTURE_WORDS)


def _remap_bmp_palette(path: Path, colors: tuple[tuple[int, int, int], ...]) -> None:
    data = bytearray(path.read_bytes())
    if len(data) < 1078 or data[0:2] != b"BM":
        raise ValueError(f"{path}: expected an 8-bit BMP")
    bits_per_pixel = struct.unpack_from("<H", data, 28)[0]
    compression = struct.unpack_from("<I", data, 30)[0]
    if bits_per_pixel != 8 or compression != 0:
        raise ValueError(f"{path}: only uncompressed 8-bit BMP files are supported")

    colors_used = struct.unpack_from("<I", data, 46)[0] or 256
    palette_start = 54
    for palette_index in range(min(colors_used, 256)):
        if palette_index == 255:
            continue
        offset = palette_start + palette_index * 4
        blue, green, red = data[offset : offset + 3]
        luminance = (red * 299 + green * 587 + blue * 114) / 1000.0 / 255.0
        if luminance < 0.5:
            mapped = _mix(colors[0], colors[1], luminance / 0.5)
        else:
            mapped = _mix(colors[1], colors[2], (luminance - 0.5) / 0.5)
        data[offset : offset + 3] = bytes((mapped[2], mapped[1], mapped[0]))
    path.write_bytes(data)


def _write_detail_bmp(
    path: Path,
    colors: tuple[tuple[int, int, int], ...],
    motif: str,
    seed: int,
) -> None:
    width, height = 128, 64
    stride = (width + 3) & ~3
    pixels = bytearray(stride * height)
    motif = motif.lower()

    for y in range(height):
        for x in range(width):
            value = 1
            if "hazard" in motif:
                value = 2 if ((x + y + seed) // 10) % 2 == 0 else 0
            elif "contour" in motif or "topographic" in motif:
                value = 2 if (x * 3 + y * 7 + seed) % 29 < 2 else 1
            elif "hex" in motif or "panel" in motif:
                value = 2 if (x % 16 in (0, 1) or y % 12 in (0, 1)) else 0
            elif "branch" in motif or "camo" in motif:
                value = 2 if ((x * 5 + y * 3 + seed) % 23) < 8 else 0
            elif "frost" in motif or "crystal" in motif:
                value = 3 if (x + y + seed) % 17 == 0 else (2 if (x - y + seed) % 13 == 0 else 1)
            elif "grid" in motif or "coordinate" in motif or "route" in motif:
                value = 2 if (x % 24 in (0, 1) or y % 16 in (0, 1)) else 1
            elif "chevron" in motif or "arrow" in motif:
                value = 2 if ((x // 8 + y // 8 + seed) % 2 == 0 and (x + y) % 8 < 2) else 0
            elif "star" in motif:
                value = 3 if ((x * 7 + y * 11 + seed) % 41) == 0 else 1
            elif "digital" in motif or "interference" in motif:
                value = 2 if ((x // 4 + y // 3 + seed) % 5) == 0 else 0
            elif "warning" in motif or "signal" in motif:
                value = 2 if (x + seed) % 18 < 3 else 0
            elif "stencil" in motif or "number" in motif or "marks" in motif:
                value = 2 if (x % 20 in (0, 1, 2) or y % 20 in (0, 1, 2)) else 1
            elif "minimal" in motif or "etch" in motif:
                value = 2 if (x * 5 + y * 2 + seed) % 37 == 0 else 0
            elif "scale" in motif:
                value = 2 if ((x // 6 + y // 6) % 2) == 0 else 0
            else:
                value = 2 if (x + y + seed) % 19 < 2 else 0
            pixels[(height - 1 - y) * stride + x] = value

    palette = bytearray()
    for palette_index in range(256):
        red, green, blue = _palette_color(colors, palette_index if palette_index < 4 else 0)
        palette.extend((blue, green, red, 0))

    pixel_offset = 14 + 40 + len(palette)
    file_size = pixel_offset + len(pixels)
    header = struct.pack("<2sIHHI", b"BM", file_size, 0, 0, pixel_offset)
    info = struct.pack(
        "<IiiHHIIiiII",
        40,
        width,
        height,
        1,
        8,
        0,
        len(pixels),
        2835,
        2835,
        256,
        0,
    )
    path.write_bytes(header + info + palette + pixels)


def _float(value: str) -> float:
    return float(value.replace(",", "."))


def _reference_geometry(path: Path) -> tuple[list[str], int, tuple[float, float, float], tuple[float, float, float]]:
    lines = _read_text(path).splitlines()
    try:
        triangles = next(index for index, line in enumerate(lines) if line.strip() == "triangles")
    except StopIteration as exc:
        raise ValueError(f"{path}: triangles section is missing") from exc

    vertices: list[tuple[float, float, float]] = []
    bone = 0
    for line in lines[triangles + 1 :]:
        if line.strip() == "end":
            break
        fields = line.split()
        if len(fields) < 8:
            continue
        try:
            candidate_bone = int(fields[0])
            point = (_float(fields[1]), _float(fields[2]), _float(fields[3]))
        except ValueError:
            continue
        if not vertices:
            bone = candidate_bone
        vertices.append(point)
    if not vertices:
        raise ValueError(f"{path}: triangles section has no vertices")

    minimum = tuple(min(point[index] for point in vertices) for index in range(3))
    maximum = tuple(max(point[index] for point in vertices) for index in range(3))
    return lines, bone, minimum, maximum


def _vertex_line(
    bone: int,
    point: tuple[float, float, float],
    normal: tuple[float, float, float],
    uv: tuple[float, float],
) -> str:
    return (
        f" {bone} {point[0]:.6f} {point[1]:.6f} {point[2]:.6f}"
        f" {normal[0]:.6f} {normal[1]:.6f} {normal[2]:.6f}"
        f" {uv[0]:.6f} {uv[1]:.6f}"
    )


def _box_triangles(
    minimum: tuple[float, float, float],
    maximum: tuple[float, float, float],
    bone: int,
) -> list[str]:
    x0, y0, z0 = minimum
    x1, y1, z1 = maximum
    points = (
        (x0, y0, z0),
        (x1, y0, z0),
        (x1, y1, z0),
        (x0, y1, z0),
        (x0, y0, z1),
        (x1, y0, z1),
        (x1, y1, z1),
        (x0, y1, z1),
    )
    faces = (
        ((0, 2, 1), (0.0, 0.0, -1.0), ((0.0, 0.0), (1.0, 1.0), (1.0, 0.0))),
        ((0, 3, 2), (0.0, 0.0, -1.0), ((0.0, 0.0), (0.0, 1.0), (1.0, 1.0))),
        ((4, 5, 6), (0.0, 0.0, 1.0), ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0))),
        ((4, 6, 7), (0.0, 0.0, 1.0), ((0.0, 0.0), (1.0, 1.0), (0.0, 1.0))),
        ((0, 4, 7), (-1.0, 0.0, 0.0), ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0))),
        ((0, 7, 3), (-1.0, 0.0, 0.0), ((0.0, 0.0), (1.0, 1.0), (0.0, 1.0))),
        ((1, 2, 6), (1.0, 0.0, 0.0), ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0))),
        ((1, 6, 5), (1.0, 0.0, 0.0), ((0.0, 0.0), (1.0, 1.0), (0.0, 1.0))),
        ((0, 1, 5), (0.0, -1.0, 0.0), ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0))),
        ((0, 5, 4), (0.0, -1.0, 0.0), ((0.0, 0.0), (1.0, 1.0), (0.0, 1.0))),
        ((3, 7, 6), (0.0, 1.0, 0.0), ((0.0, 0.0), (0.0, 1.0), (1.0, 1.0))),
        ((3, 6, 2), (0.0, 1.0, 0.0), ((0.0, 0.0), (1.0, 1.0), (1.0, 0.0))),
    )
    result: list[str] = []
    for indices, normal, uvs in faces:
        result.append("cse_detail.bmp")
        for index, uv in zip(indices, uvs):
            result.append(_vertex_line(bone, points[index], normal, uv))
    return result


def _detail_kind(detail: str, category: str) -> str:
    value = detail.lower()
    if category == "shield" or "perimeter" in value or "viewport" in value:
        return "shield"
    if any(word in value for word in ("rail", "rib", "vent", "scope", "sight", "handguard", "foregrip")):
        return "rail"
    if any(word in value for word in ("collar", "sleeve", "cap", "cage", "hood", "pommel", "cable")):
        return "collar"
    if any(word in value for word in ("guard", "plate", "panel", "housing", "pad", "block")):
        return "panel"
    return "badge"


def _detail_boxes(
    minimum: tuple[float, float, float],
    maximum: tuple[float, float, float],
    bone: int,
    detail: str,
    category: str,
    seed: int,
) -> list[str]:
    dimensions = tuple(maximum[index] - minimum[index] for index in range(3))
    axes = sorted(range(3), key=lambda index: dimensions[index], reverse=True)
    long_axis, middle_axis, short_axis = axes
    long_size, middle_size, short_size = (dimensions[index] for index in axes)
    if min(dimensions) <= 0.0:
        raise ValueError("reference mesh has a zero-sized bounding axis")

    long_position = 0.34 + ((seed >> 8) & 0xFF) / 255.0 * 0.32
    middle_position = 0.42 + ((seed >> 16) & 0xFF) / 255.0 * 0.16
    surface_offset = max(short_size * 0.02, 0.01)
    kind = _detail_kind(detail, category)

    def make_box(
        long_center: float,
        middle_center: float,
        length: float,
        width: float,
        depth: float,
    ) -> list[str]:
        low = list(minimum)
        high = list(maximum)
        low[long_axis] = minimum[long_axis] + long_center - length / 2.0
        high[long_axis] = low[long_axis] + length
        low[middle_axis] = minimum[middle_axis] + middle_center - width / 2.0
        high[middle_axis] = low[middle_axis] + width
        low[short_axis] = maximum[short_axis] + surface_offset
        high[short_axis] = low[short_axis] + depth
        return _box_triangles(tuple(low), tuple(high), bone)

    if kind == "rail":
        return make_box(
            long_size * long_position,
            middle_size * middle_position,
            max(long_size * 0.50, 0.05),
            max(middle_size * 0.15, 0.04),
            max(short_size * 0.08, 0.025),
        )
    if kind == "collar":
        return make_box(
            long_size * (0.23 + (seed & 0xFF) / 255.0 * 0.54),
            middle_size * 0.5,
            max(long_size * 0.14, 0.05),
            max(middle_size * 0.52, 0.04),
            max(short_size * 0.18, 0.03),
        )
    if kind == "shield":
        return make_box(
            long_size * 0.5,
            middle_size * 0.5,
            max(long_size * 0.62, 0.1),
            max(middle_size * 0.72, 0.1),
            max(short_size * 0.05, 0.04),
        )
    if kind == "panel":
        first = make_box(
            long_size * long_position,
            middle_size * middle_position,
            max(long_size * 0.40, 0.05),
            max(middle_size * 0.38, 0.04),
            max(short_size * 0.10, 0.03),
        )
        second = make_box(
            long_size * (1.0 - long_position),
            middle_size * (1.0 - middle_position),
            max(long_size * 0.12, 0.04),
            max(middle_size * 0.20, 0.03),
            max(short_size * 0.12, 0.03),
        )
        return first + second

    return make_box(
        long_size * long_position,
        middle_size * middle_position,
        max(long_size * 0.18, 0.04),
        max(middle_size * 0.25, 0.04),
        max(short_size * 0.14, 0.03),
    )


def _append_detail_geometry(
    path: Path,
    detail: str,
    category: str,
    motif: str,
    seed: int,
) -> None:
    lines, bone, minimum, maximum = _reference_geometry(path)
    try:
        end = next(index for index in range(len(lines) - 1, -1, -1) if lines[index].strip() == "end")
    except StopIteration as exc:
        raise ValueError(f"{path}: SMD end marker is missing") from exc

    detail_lines = _detail_boxes(minimum, maximum, bone, detail, category, seed)
    lines[end:end] = detail_lines
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _model_source(game_root: Path, weapon: str, surface: str, combo: str | None) -> Path:
    if weapon == "shield":
        if surface in ("v", "p"):
            if combo is None:
                combo = "deagle"
            return game_root / "models" / "shield" / f"{surface}_shield_{combo}.mdl"
        return game_root / "models" / "w_shield.mdl"
    if weapon == "knife" and surface == "v":
        return game_root / "models" / "v_knife.mdl"
    if weapon == "c4" and surface == "w_planted":
        return game_root / "models" / "w_backpack.mdl"
    return game_root / "models" / f"{surface}_{weapon}.mdl"


def _output_path(game_root: Path, variant: CosmeticVariant, surface: str, combo: str | None) -> Path:
    relative = Path(variant.paths[surface])
    if variant.weapon == "shield" and surface in ("v", "p") and combo is not None:
        relative = relative.with_name(f"{relative.stem}_{combo}{relative.suffix}")
    return game_root / relative


def _body_sources(qc_path: Path) -> list[Path]:
    body_pattern = re.compile(r'^\s*\$body\s+"[^"]+"\s+"([^"]+)"', re.IGNORECASE)
    sources: list[Path] = []
    for line in _read_text(qc_path).splitlines():
        match = body_pattern.match(line)
        if match:
            source = (qc_path.parent / match.group(1)).with_suffix(".smd")
            if source.is_file():
                sources.append(source)
    if not sources:
        raise ValueError(f"{qc_path}: no body SMD files found")
    return sources


def _weapon_body(qc_path: Path) -> Path:
    sources = _body_sources(qc_path)
    for source in sources:
        if not any(word in source.stem.lower() for word in ("hand", "rhand", "lhand")):
            return source
    return sources[-1]


def _run(command: Sequence[str], cwd: Path, label: str) -> None:
    completed = subprocess.run(
        list(command),
        cwd=cwd,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=os.environ.copy(),
    )
    if completed.returncode != 0:
        output = completed.stdout.strip()
        raise RuntimeError(f"{label} failed with exit code {completed.returncode}\n{output}")


def _decompile(mdldec: Path, source: Path, target: Path, activities: Path | None) -> Path:
    target.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    if activities is not None:
        environment["MDLDEC_ACT_PATH"] = str(activities if activities.is_dir() else activities.parent)
    completed = subprocess.run(
        [str(mdldec), "-m", "-t", str(source), str(target)],
        cwd=target,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=environment,
    )
    if completed.returncode != 0:
        output = completed.stdout.strip()
        raise RuntimeError(f"mdldec failed for {source} with exit code {completed.returncode}\n{output}")
    qc_files = tuple(target.rglob("*.qc"))
    if len(qc_files) != 1:
        raise ValueError(f"{source}: expected one generated QC, found {len(qc_files)}")
    return qc_files[0]


def _compile(studiomdl: Path, qc_path: Path, output_stem: str) -> Path:
    text = _read_text(qc_path)
    text, replacements = re.subn(
        r'(?mi)^\s*\$modelname\s+"[^"]+"',
        f'$modelname "{output_stem}.mdl"',
        text,
        count=1,
    )
    if replacements != 1:
        raise ValueError(f"{qc_path}: $modelname is missing")
    qc_path.write_text(text, encoding="utf-8")
    _run((str(studiomdl), qc_path.name), qc_path.parent, f"studiomdl {qc_path.name}")
    output = qc_path.parent / f"{output_stem}.mdl"
    if not output.is_file():
        raise ValueError(f"studiomdl did not create {output}")
    data = output.read_bytes()
    if len(data) < 4 or struct.unpack_from("<i", data, 0)[0] != IDST:
        raise ValueError(f"{output}: invalid GoldSrc studio model")
    return output


def _prepare_textures(
    directory: Path,
    colors: tuple[tuple[int, int, int], ...],
    motif: str,
    detail: str,
    seed: int,
) -> None:
    textures = tuple(directory.rglob("*.bmp"))
    if not textures:
        raise ValueError(f"{directory}: decompiler produced no BMP textures")
    for texture in textures:
        if not _is_hand_texture(texture):
            _remap_bmp_palette(texture, colors)
    detail_texture = directory / "textures" / "cse_detail.bmp"
    detail_texture.parent.mkdir(parents=True, exist_ok=True)
    _write_detail_bmp(detail_texture, colors, motif + "_" + detail, seed)


def _build_one(
    mdldec: Path,
    studiomdl: Path,
    activities: Path | None,
    game_root: Path,
    variant: CosmeticVariant,
    surface: str,
    combo: str | None,
    output_root: Path,
) -> Path:
    source = _model_source(game_root, variant.weapon, surface, combo)
    if not source.is_file():
        raise FileNotFoundError(f"stock model not found: {source}")
    destination = _output_path(game_root, variant, surface, combo)
    output_root.mkdir(parents=True, exist_ok=True)
    output_stem = destination.stem
    seed = _fnv1a(f"{variant.weapon}/{variant.slug}/{surface}/{combo or ''}")
    with tempfile.TemporaryDirectory(prefix="cse-cosmetic-") as temporary:
        work = Path(temporary)
        qc_path = _decompile(mdldec, source, work / "source", activities)
        _prepare_textures(qc_path.parent, variant.palette, variant.motif, variant.detail, seed)
        _append_detail_geometry(_weapon_body(qc_path), variant.detail, "shield" if variant.weapon == "shield" else "weapon", variant.motif, seed)
        compiled = _compile(studiomdl, qc_path, output_stem)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(compiled, destination)
    return destination


def _iter_jobs(weapons: Iterable[CosmeticWeapon]) -> Iterable[tuple[CosmeticVariant, str, str | None]]:
    for weapon in weapons:
        for variant in weapon.variants:
            for surface in MODEL_SUFFIXES:
                if weapon.slug == "shield" and surface in ("v", "p"):
                    yield variant, surface, None
                    for combo in SHIELD_COMBOS:
                        yield variant, surface, combo
                else:
                    yield variant, surface, None
            if "w_planted" in variant.paths:
                yield variant, "w_planted", None


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=Path("src/cse/cstrike/scripts/CseCosmetics.txt"))
    parser.add_argument("--root", type=Path, default=Path("runtime/cstrike"), help="installed cstrike root")
    parser.add_argument("--mdldec", type=Path, help="Xash mdldec executable")
    parser.add_argument("--studiomdl", type=Path, help="GoldSrc studiomdl executable")
    parser.add_argument("--activities", type=Path, help="directory containing mdldec activities.txt")
    parser.add_argument("--dry-run", action="store_true")
    return parser


def main() -> int:
    args = _parser().parse_args()
    try:
        weapons = parse_catalog(args.catalog)
        jobs = tuple(_iter_jobs(weapons))
        if args.dry_run:
            for variant, surface, combo in jobs:
                destination = _output_path(args.root, variant, surface, combo)
                print(f"DRY: {variant.weapon}/{variant.slug} {surface}{'/' + combo if combo else ''} -> {destination}")
            print(f"DRY: jobs={len(jobs)}")
            return 0
        if args.mdldec is None or args.studiomdl is None:
            raise ValueError("--mdldec and --studiomdl are required unless --dry-run is used")

        for number, (variant, surface, combo) in enumerate(jobs, start=1):
            destination = _build_one(
                args.mdldec.resolve(),
                args.studiomdl.resolve(),
                args.activities.resolve() if args.activities else None,
                args.root.resolve(),
                variant,
                surface,
                combo,
                args.root.resolve() / "models" / "cse",
            )
            print(f"[{number}/{len(jobs)}] {destination.relative_to(args.root.resolve())}")
        print(f"OK: generated={len(jobs)}")
        return 0
    except (CatalogError, OSError, ValueError, RuntimeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
