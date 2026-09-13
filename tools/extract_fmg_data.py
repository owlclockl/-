#!/usr/bin/env python3
"""Extract the data tables the Godot port needs from a Fantasy Map Generator checkout.

Fantasy Map Generator (https://github.com/Azgaar/Fantasy-Map-Generator, MIT) keeps its
world-building data in TypeScript sources. Instead of retyping them, this script converts the
tables into JSON files the Godot project loads at runtime:

    python3 tools/extract_fmg_data.py /path/to/Fantasy-Map-Generator

Writes:
    data/heightmap_templates.json   all generation templates ("Hill 1 90-100 44-56 40-60" scripts)
    data/name_bases.json            the name bases used by the Markov name generator
    data/biomes.json                biome names, colours, habitability and movement costs

Run it again after updating the upstream checkout to refresh the data.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def extract_heightmap_templates(text: str) -> dict:
    """Templates are template literals assigned to constants, then listed in a Record."""
    literals = dict(re.findall(r"const\s+(\w+)\s*=\s*`([^`]*)`", text, re.S))
    entries = re.findall(
        r"(\w+):\s*\{\s*id:\s*(\d+),\s*name:\s*\"([^\"]+)\",\s*template:\s*(\w+),\s*probability:\s*(\d+)",
        text,
    )
    templates = {}
    for _key, entry_id, name, template_var, probability in entries:
        templates[template_var] = {
            "id": int(entry_id),
            "name": name,
            "probability": int(probability),
            "template": literals.get(template_var, "").strip(),
        }
    return templates


def extract_name_bases(text: str) -> list:
    blocks = re.findall(r"\{\s*name:\s*\"[^\"]*\".*?\n\s*\}", text, re.S)
    bases = []
    for block in blocks:
        entry = {
            "name": re.search(r"name:\s*\"([^\"]*)\"", block).group(1),
            "i": int(re.search(r"i:\s*(\d+)", block).group(1)),
            "min": int(re.search(r"min:\s*(\d+)", block).group(1)),
            "max": int(re.search(r"max:\s*(\d+)", block).group(1)),
            "d": re.search(r"\bd:\s*\"([^\"]*)\"", block).group(1),
            "b": re.search(r"\bb:\s*\"([^\"]*)\"", block).group(1),
        }
        bases.append(entry)
    bases.sort(key=lambda item: item["i"])
    return bases


def extract_biomes(text: str) -> list:
    def list_of(name: str) -> list:
        match = re.search(r"const\s+%s\s*=\s*\[(.*?)\];" % name, text, re.S)
        return re.findall(r"\"([^\"]*)\"|(-?[\d.]+)", match.group(1))

    def parse_values(name: str, kind: str) -> list:
        match = re.search(r"const\s+%s\s*=\s*\[(.*?)\];" % name, text, re.S)
        raw = match.group(1)
        if kind == "string":
            return re.findall(r"\"([^\"]*)\"", raw)
        return [float(v) for v in re.findall(r"-?[\d.]+", raw)]

    names = parse_values("name", "string")
    colors = parse_values("color", "string")
    habitability = parse_values("habitability", "number")
    icons_density = parse_values("iconsDensity", "number")
    cost = parse_values("cost", "number")
    biomes = []
    for i, biome_name in enumerate(names):
        biomes.append({
            "i": i,
            "name": biome_name,
            "color": colors[i],
            "habitability": habitability[i],
            "iconsDensity": icons_density[i],
            "cost": cost[i],
        })
    return biomes


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    src = Path(sys.argv[1]) / "src"
    if not src.exists():
        print(f"not a Fantasy Map Generator checkout: {src}")
        return 2

    DATA.mkdir(exist_ok=True)
    written = []

    templates = extract_heightmap_templates(read(src / "data" / "heightmap-templates.ts"))
    (DATA / "heightmap_templates.json").write_text(json.dumps(templates, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    written.append(("heightmap_templates.json", len(templates)))

    bases = extract_name_bases(read(src / "data" / "name-bases.ts"))
    (DATA / "name_bases.json").write_text(json.dumps(bases, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    written.append(("name_bases.json", len(bases)))

    biomes = extract_biomes(read(src / "generators" / "biomes-generator.ts"))
    (DATA / "biomes.json").write_text(json.dumps(biomes, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    written.append(("biomes.json", len(biomes)))

    for name, count in written:
        print(f"wrote data/{name}: {count} entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
