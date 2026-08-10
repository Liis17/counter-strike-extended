#!/usr/bin/env python3
"""Recolor GoldSrc studio-model palettes without changing model geometry."""

from __future__ import annotations

import argparse
import colorsys
import math
import shlex
import struct
import sys
from dataclasses import dataclass
from pathlib import Path


MODEL_NUM_TEXTURES_OFFSET = 180
MODEL_TEXTURE_INDEX_OFFSET = 184
MODEL_TEXTURE_FIELDS_END = 192
TEXTURE_RECORD_SIZE = 80
TEXTURE_PALETTE_SIZE = 768
TRANSPARENT_PALETTE_INDEX = 255
IDST = int.from_bytes(b"IDST", "little")


@dataclass(frozen=True)
class Transform:
    hue_shift: float = 0.0
    tint: tuple[float, float, float] = (1.0, 1.0, 1.0)

    @property
    def is_identity(self) -> bool:
        return (self.hue_shift % 360.0) == 0.0 and self.tint == (1.0, 1.0, 1.0)


@dataclass(frozen=True)
class Recipe:
    source: str
    transform: Transform
    output: str


def _validate_transform(transform: Transform) -> None:
    if not math.isfinite(transform.hue_shift):
        raise ValueError("сдвиг тона должен быть конечным числом")
    if len(transform.tint) != 3 or any(
        not math.isfinite(channel) or channel < 0.0 for channel in transform.tint
    ):
        raise ValueError("тонировка должна содержать три неотрицательных конечных числа")


def _parse_transform(value: str) -> Transform:
    hue_shift = 0.0
    tint = (1.0, 1.0, 1.0)

    for clause in value.split(";"):
        clause = clause.strip()
        if not clause:
            continue
        if "=" not in clause:
            raise ValueError(f"неизвестное преобразование: {clause}")
        key, raw_value = (part.strip().lower() for part in clause.split("=", 1))
        if key in {"hue", "hue_shift"}:
            hue_shift = float(raw_value)
        elif key == "tint":
            channels = tuple(float(part) for part in raw_value.replace(",", " ").split())
            if len(channels) != 3:
                raise ValueError("tint должен содержать три канала: tint=R,G,B")
            tint = channels
        else:
            raise ValueError(f"неизвестный параметр преобразования: {key}")

    transform = Transform(hue_shift=hue_shift, tint=tint)
    _validate_transform(transform)
    return transform


def _model_header(data: bytes, path: Path) -> tuple[int, int]:
    if len(data) < MODEL_TEXTURE_FIELDS_END:
        raise ValueError(f"{path}: файл короче заголовка studio-модели")
    if struct.unpack_from("<i", data, 0)[0] != IDST:
        raise ValueError(f"{path}: ожидался GoldSrc studio-модельный заголовок IDST")

    numtextures = struct.unpack_from("<i", data, MODEL_NUM_TEXTURES_OFFSET)[0]
    textureindex = struct.unpack_from("<i", data, MODEL_TEXTURE_INDEX_OFFSET)[0]
    if numtextures < 0:
        raise ValueError(f"{path}: отрицательное число текстур")
    if numtextures == 0:
        return numtextures, textureindex
    if textureindex < MODEL_TEXTURE_FIELDS_END:
        raise ValueError(f"{path}: некорректный textureindex={textureindex}")

    table_end = textureindex + numtextures * TEXTURE_RECORD_SIZE
    if table_end > len(data):
        raise ValueError(f"{path}: таблица текстур выходит за пределы файла")
    return numtextures, textureindex


def _recolor_inline_model(
    data: bytes, path: Path, transform: Transform
) -> tuple[bytes, int]:
    numtextures, textureindex = _model_header(data, path)
    if numtextures == 0:
        raise ValueError(f"{path}: в модели нет встроенных текстур")

    output = bytearray(data)
    for texture_number in range(numtextures):
        record_offset = textureindex + texture_number * TEXTURE_RECORD_SIZE
        flags, width, height, image_index = struct.unpack_from(
            "<4i", data, record_offset + 64
        )
        del flags
        if width <= 0 or height <= 0:
            raise ValueError(
                f"{path}: текстура {texture_number} имеет размер {width}x{height}"
            )
        if image_index < 0:
            raise ValueError(f"{path}: текстура {texture_number} имеет отрицательный index")

        palette_start = image_index + width * height
        palette_end = palette_start + TEXTURE_PALETTE_SIZE
        if palette_end > len(data):
            raise ValueError(
                f"{path}: палитра текстуры {texture_number} выходит за пределы файла"
            )
        _recolor_palette(output, palette_start, transform)

    return bytes(output), numtextures


def _recolor_palette(data: bytearray, palette_start: int, transform: Transform) -> None:
    if transform.is_identity:
        return

    hue_shift = (transform.hue_shift % 360.0) / 360.0
    tint_r, tint_g, tint_b = transform.tint
    for palette_index in range(256):
        if palette_index == TRANSPARENT_PALETTE_INDEX:
            continue

        offset = palette_start + palette_index * 3
        red, green, blue = (channel / 255.0 for channel in data[offset : offset + 3])
        hue, saturation, value = colorsys.rgb_to_hsv(red, green, blue)
        hue = (hue + hue_shift) % 1.0
        red, green, blue = colorsys.hsv_to_rgb(hue, saturation, value)

        data[offset] = _to_byte(red * tint_r)
        data[offset + 1] = _to_byte(green * tint_g)
        data[offset + 2] = _to_byte(blue * tint_b)


def _to_byte(value: float) -> int:
    return max(0, min(255, int(round(value * 255.0))))


def recolor_model(source: Path, output: Path, transform: Transform) -> list[Path]:
    _validate_transform(transform)
    source = source.resolve()
    output = output.resolve()
    if source == output:
        raise ValueError(f"источник и выход совпадают: {source}")
    if not source.is_file():
        raise FileNotFoundError(f"исходная модель не найдена: {source}")

    source_data = source.read_bytes()
    numtextures, _ = _model_header(source_data, source)
    output.parent.mkdir(parents=True, exist_ok=True)

    if numtextures > 0:
        recolored, texture_count = _recolor_inline_model(source_data, source, transform)
        output.write_bytes(recolored)
        print(f"OK: {source} -> {output} ({texture_count} textures)")
        return [output]

    external_source = source.with_name(f"{source.stem}T.mdl")
    if not external_source.is_file():
        raise FileNotFoundError(
            f"{source}: numtextures=0, но внешний файл текстур не найден: {external_source}"
        )
    external_output = output.with_name(f"{output.stem}T.mdl")
    if external_source.resolve() == external_output:
        raise ValueError(f"внешний источник и выход совпадают: {external_source}")

    recolored_external, texture_count = _recolor_inline_model(
        external_source.read_bytes(), external_source, transform
    )
    output.write_bytes(source_data)
    external_output.write_bytes(recolored_external)
    print(
        f"OK: {source} + {external_source} -> {output} + {external_output} "
        f"({texture_count} textures)"
    )
    return [output, external_output]


def _recipe_tokens(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8-sig")
    lines = []
    for line in text.splitlines():
        line = line.split("//", 1)[0]
        line = line.split("#", 1)[0]
        lines.append(line)

    lexer = shlex.shlex("\n".join(lines), posix=True, punctuation_chars="{}")
    lexer.whitespace_split = True
    lexer.commenters = ""
    return list(lexer)


def parse_recipes(path: Path) -> list[Recipe]:
    tokens = _recipe_tokens(path)
    if len(tokens) < 3 or tokens[0] != "CseSkinRecipes" or tokens[1] != "{" or tokens[-1] != "}":
        raise ValueError(f"{path}: ожидался блок CseSkinRecipes {{ ... }}")

    body = tokens[2:-1]
    if len(body) % 3 != 0:
        raise ValueError(
            f"{path}: каждая запись должна содержать source, transform и output"
        )

    recipes = []
    for index in range(0, len(body), 3):
        source, transform, output = body[index : index + 3]
        recipes.append(
            Recipe(source=source, transform=_parse_transform(transform), output=output)
        )
    return recipes


def _resolve_game_path(root: Path, value: str) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    return root / path


def process_recipes(recipe_path: Path, root: Path, dry_run: bool) -> int:
    recipes = parse_recipes(recipe_path)
    if not recipes:
        raise ValueError(f"{recipe_path}: список рецептов пуст")

    generated_files = 0
    for recipe in recipes:
        source = _resolve_game_path(root, recipe.source)
        output = _resolve_game_path(root, recipe.output)
        if dry_run:
            print(f"DRY: {source} -> {output} ({recipe.transform})")
            continue
        generated_files += len(recolor_model(source, output, recipe.transform))

    if dry_run:
        print(f"DRY: recipes={len(recipes)}")
    else:
        print(f"OK: recipes={len(recipes)}, files={generated_files}")
    return 0


def _argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Перекрасить палитры GoldSrc studio-модели без изменения геометрии."
    )
    parser.add_argument("source", nargs="?", type=Path, help="исходный .mdl")
    parser.add_argument("output", nargs="?", type=Path, help="выходной .mdl")
    parser.add_argument(
        "--hue-shift", type=float, default=0.0, help="сдвиг тона в градусах"
    )
    parser.add_argument(
        "--tint",
        nargs=3,
        type=float,
        metavar=("R", "G", "B"),
        default=(1.0, 1.0, 1.0),
        help="множители каналов после сдвига тона",
    )
    parser.add_argument(
        "--recipes", type=Path, help="файл CseSkinRecipes.txt вместо одной модели"
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path.cwd(),
        help="корень cstrike для относительных путей рецептов",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="показать рецепты без записи файлов"
    )
    return parser


def main() -> int:
    parser = _argument_parser()
    args = parser.parse_args()

    if args.recipes:
        if args.source or args.output:
            parser.error("--recipes нельзя совмещать с source/output")
        try:
            return process_recipes(args.recipes, args.root, args.dry_run)
        except (OSError, ValueError) as error:
            print(f"ERROR: {error}", file=sys.stderr)
            return 1

    if not args.source or not args.output:
        parser.error("укажите source и output либо используйте --recipes")
    if args.dry_run:
        parser.error("--dry-run доступен только в режиме --recipes")

    try:
        transform = Transform(hue_shift=args.hue_shift, tint=tuple(args.tint))
        recolor_model(args.source, args.output, transform)
        return 0
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
