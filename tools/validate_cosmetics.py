#!/usr/bin/env python3
"""Validate the CSE cosmetic catalog without requiring the game runtime."""

from __future__ import annotations

import argparse
import shlex
import sys
from pathlib import Path


class CatalogError(ValueError):
    pass


def _tokens(path: Path) -> list[str]:
    lines = []
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        lines.append(line.split("//", 1)[0])

    lexer = shlex.shlex("\n".join(lines), posix=True, punctuation_chars="{}")
    lexer.whitespace_split = True
    lexer.commenters = ""
    return list(lexer)


def _object(tokens: list[str], position: int) -> tuple[dict[str, object], int]:
    if position >= len(tokens) or tokens[position] != "{":
        raise CatalogError("expected '{'")
    position += 1
    result: dict[str, object] = {}
    while position < len(tokens) and tokens[position] != "}":
        key = tokens[position]
        position += 1
        if key in result:
            raise CatalogError(f"duplicate key: {key}")
        if position >= len(tokens):
            raise CatalogError(f"missing value for {key}")
        if tokens[position] == "{":
            value, position = _object(tokens, position)
        else:
            value = tokens[position]
            position += 1
        result[key] = value
    if position >= len(tokens):
        raise CatalogError("unterminated object")
    return result, position + 1


def _int(value: object, field: str) -> int:
    try:
        return int(str(value))
    except (TypeError, ValueError) as exc:
        raise CatalogError(f"{field} must be an integer") from exc


def validate(path: Path) -> tuple[int, int]:
    tokens = _tokens(path)
    if len(tokens) < 3 or tokens[0] != "CseCosmetics":
        raise CatalogError("expected CseCosmetics root")
    root, position = _object(tokens, 1)
    if position != len(tokens):
        raise CatalogError("unexpected tokens after root")
    if _int(root.get("version"), "version") != 1:
        raise CatalogError("unsupported catalog version")

    weapons = root.get("weapons")
    if not isinstance(weapons, dict):
        raise CatalogError("weapons object is missing")
    catalog_size = _int(root.get("catalog_size"), "catalog_size")
    if len(weapons) != catalog_size or catalog_size != 30:
        raise CatalogError(f"expected 30 weapon entries, got {len(weapons)}")

    indexes: set[int] = set()
    engine_ids: set[int] = set()
    variant_ids: dict[str, set[int]] = {}
    variant_count = 0
    names: set[str] = set()
    allowed_categories = {
        "pistol", "shotgun", "smg", "rifle", "sniper", "machinegun",
        "grenade", "objective", "knife", "shield",
    }

    for slug, raw_weapon in weapons.items():
        if not isinstance(raw_weapon, dict):
            raise CatalogError(f"weapon {slug} must be an object")
        index = _int(raw_weapon.get("catalog_index"), f"{slug}.catalog_index")
        engine_id = _int(raw_weapon.get("engine_id"), f"{slug}.engine_id")
        if index in indexes:
            raise CatalogError(f"duplicate catalog index: {index}")
        if engine_id in engine_ids:
            raise CatalogError(f"duplicate engine id: {engine_id}")
        indexes.add(index)
        engine_ids.add(engine_id)
        if raw_weapon.get("category") not in allowed_categories:
            raise CatalogError(f"unknown category for {slug}")

        variants = raw_weapon.get("variants")
        if not isinstance(variants, dict) or not variants:
            raise CatalogError(f"{slug}.variants is empty")
        seen_ids: set[int] = set()
        variant_ids[slug] = seen_ids
        for variant_slug, raw_variant in variants.items():
            if not isinstance(raw_variant, dict):
                raise CatalogError(f"{slug}/{variant_slug} must be an object")
            variant_id = _int(raw_variant.get("variant_id"), f"{slug}/{variant_slug}.variant_id")
            level = _int(raw_variant.get("unlock_level"), f"{slug}/{variant_slug}.unlock_level")
            if variant_id <= 0 or variant_id > 4:
                raise CatalogError(f"{slug}/{variant_slug}: variant id must be 1..4")
            if variant_id in seen_ids:
                raise CatalogError(f"{slug}: duplicate variant id {variant_id}")
            if level < 1 or level > 100:
                raise CatalogError(f"{slug}/{variant_slug}: level must be 1..100")
            for field in ("name", "palette", "motif", "detail", "v", "p", "w"):
                if not raw_variant.get(field):
                    raise CatalogError(f"{slug}/{variant_slug}: missing {field}")
            if slug == "c4" and not raw_variant.get("w_planted"):
                raise CatalogError("c4 variant must define w_planted")
            name = str(raw_variant["name"])
            if name in names:
                raise CatalogError(f"duplicate localization token: {name}")
            names.add(name)
            seen_ids.add(variant_id)
            variant_count += 1

    if indexes != set(range(catalog_size)):
        raise CatalogError("catalog indexes must be exactly 0..29")
    if variant_count != 63:
        raise CatalogError(f"expected 63 variants, got {variant_count}")
    return len(weapons), variant_count


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "path",
        nargs="?",
        default="src/cse/cstrike/scripts/CseCosmetics.txt",
        type=Path,
    )
    args = parser.parse_args()
    try:
        weapons, variants = validate(args.path)
    except (OSError, CatalogError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(f"OK: {args.path} weapons={weapons}, variants={variants}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
