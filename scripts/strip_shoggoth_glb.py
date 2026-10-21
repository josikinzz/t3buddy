#!/usr/bin/env python3
"""Writes the shoggoth pet model from the owner's Blender export.

    python3 -I scripts/strip_shoggoth_glb.py [SOURCE] [OUT]

SOURCE (default .scratch/shoggoth-source/shoggoth.glb) holds four scenes; only the one named
`shoggoth` is the pet. OUT (default Resources/Pet/shoggoth.glb) keeps that scene and what it
uses, drops the second UV set no material reads, and puts the creature on the origin: centred
in x and z, its underside at y = 0, as T3boii stands. The normal map is shrunk to 512 px with `sips`
(which also writes it at 8 bits a channel, from 16). Standard library only, so it reruns anywhere the source is.
"""

import json
import os
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENE = "shoggoth"
BODY_MESHES = ("Plane.016", "Plane.017")   # the creature's skin, eyes and eye-field, without the mask
NORMAL_MAP_PX = 512
COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        sys.exit(f"{path} is not a glTF 2 binary")
    offset, gltf, binary = 12, None, b""
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8: offset + 8 + length]
        if kind == 0x4E4F534A:
            gltf = json.loads(chunk)
        elif kind == 0x004E4942:
            binary = chunk
        offset += 8 + length
    return gltf, binary


def write_glb(path, gltf, binary):
    text = json.dumps(gltf, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    with open(path, "wb") as out:
        out.write(struct.pack("<III", 0x46546C67, 2, total))
        out.write(struct.pack("<II", len(text), 0x4E4F534A) + text)
        out.write(struct.pack("<II", len(binary), 0x004E4942) + binary)


def shrink_png(png):
    with tempfile.TemporaryDirectory() as work:
        source, small = os.path.join(work, "in.png"), os.path.join(work, "out.png")
        open(source, "wb").write(png)
        subprocess.run(["sips", "-Z", str(NORMAL_MAP_PX), source, "--out", small], check=True, stdout=subprocess.DEVNULL)
        return open(small, "rb").read()


def strip(gltf, binary):
    scene = next((s for s in gltf["scenes"] if s.get("name") == SCENE), None)
    if scene is None:
        sys.exit(f"no scene named {SCENE}")

    keep_nodes = []
    def walk(index):
        keep_nodes.append(index)
        for child in gltf["nodes"][index].get("children", []):
            walk(child)
    for root in scene["nodes"]:
        walk(root)

    remap = {"nodes": {}, "meshes": {}, "materials": {}, "textures": {}, "images": {}, "samplers": {}, "accessors": {}, "bufferViews": {}}
    out = {"asset": dict(gltf["asset"], extras={"source": "scripts/strip_shoggoth_glb.py"}), "scene": 0}

    def keep(kind, index):
        if index not in remap[kind]:
            remap[kind][index] = len(remap[kind])
        return remap[kind][index]

    for index in keep_nodes:
        keep("nodes", index)
        if "mesh" in gltf["nodes"][index]:
            keep("meshes", gltf["nodes"][index]["mesh"])
    for mesh_index in remap["meshes"]:
        for primitive in gltf["meshes"][mesh_index]["primitives"]:
            primitive["attributes"].pop("TEXCOORD_1", None)
            for accessor in list(primitive["attributes"].values()) + ([primitive["indices"]] if "indices" in primitive else []):
                keep("accessors", accessor)
            if "material" in primitive:
                keep("materials", primitive["material"])
    for material_index in remap["materials"]:
        material = gltf["materials"][material_index]
        refs = [material.get("normalTexture"), material.get("occlusionTexture"), material.get("emissiveTexture"),
                material.get("pbrMetallicRoughness", {}).get("baseColorTexture"),
                material.get("pbrMetallicRoughness", {}).get("metallicRoughnessTexture")]
        for ref in filter(None, refs):
            keep("textures", ref["index"])
    for texture_index in remap["textures"]:
        texture = gltf["textures"][texture_index]
        keep("images", texture["source"])
        if "sampler" in texture:
            keep("samplers", texture["sampler"])
    for accessor_index in remap["accessors"]:
        keep("bufferViews", gltf["accessors"][accessor_index]["bufferView"])
    for image_index in remap["images"]:
        keep("bufferViews", gltf["images"][image_index]["bufferView"])

    normal_images = {gltf["textures"][gltf["materials"][m]["normalTexture"]["index"]]["source"]
                     for m in remap["materials"] if "normalTexture" in gltf["materials"][m]}

    # Copy each kept view's bytes into a fresh buffer, 4-byte aligned.
    blob, views = bytearray(), []
    for old in sorted(remap["bufferViews"], key=remap["bufferViews"].get):
        view = dict(gltf["bufferViews"][old])
        chunk = binary[view.get("byteOffset", 0): view.get("byteOffset", 0) + view["byteLength"]]
        image = next((i for i in remap["images"] if gltf["images"][i]["bufferView"] == old), None)
        if image in normal_images:
            chunk = shrink_png(chunk)
        blob += b"\0" * (-len(blob) % 4)
        view.update(buffer=0, byteOffset=len(blob), byteLength=len(chunk))
        blob += chunk
        views.append(view)

    def ordered(kind):
        return [gltf[kind][old] for old in sorted(remap[kind], key=remap[kind].get)]

    out["scenes"] = [{"name": SCENE, "nodes": [remap["nodes"][n] for n in scene["nodes"]]}]
    out["nodes"] = []
    for node in ordered("nodes"):
        node = dict(node)
        if "mesh" in node:
            node["mesh"] = remap["meshes"][node["mesh"]]
        if "children" in node:
            node["children"] = [remap["nodes"][c] for c in node["children"]]
        out["nodes"].append(node)
    out["meshes"] = []
    for mesh in ordered("meshes"):
        mesh = json.loads(json.dumps(mesh))
        for primitive in mesh["primitives"]:
            primitive["attributes"] = {k: remap["accessors"][v] for k, v in primitive["attributes"].items()}
            if "indices" in primitive:
                primitive["indices"] = remap["accessors"][primitive["indices"]]
            if "material" in primitive:
                primitive["material"] = remap["materials"][primitive["material"]]
        out["meshes"].append(mesh)
    out["materials"] = []
    for material in ordered("materials"):
        material = json.loads(json.dumps(material))
        for ref in [material.get("normalTexture"), material.get("pbrMetallicRoughness", {}).get("baseColorTexture")]:
            if ref:
                ref["index"] = remap["textures"][ref["index"]]
        out["materials"].append(material)
    out["textures"] = [dict(t, source=remap["images"][t["source"]], **({"sampler": remap["samplers"][t["sampler"]]} if "sampler" in t else {}))
                       for t in ordered("textures")]
    out["images"] = [dict(i, bufferView=remap["bufferViews"][i["bufferView"]]) for i in ordered("images")]
    out["samplers"] = ordered("samplers")
    out["accessors"] = [dict(a, bufferView=remap["bufferViews"][a["bufferView"]]) for a in ordered("accessors")]
    out["bufferViews"] = views
    out["buffers"] = [{"byteLength": len(blob)}]
    used = {name for m in out["materials"] for name in m.get("extensions", {})}
    if used:
        out["extensionsUsed"] = sorted(used)

    # Stand it on the origin: the body meshes' bounds (they are untransformed under the root).
    lo, hi = [float("inf")] * 3, [float("-inf")] * 3
    for node in out["nodes"]:
        mesh = out["meshes"][node["mesh"]] if "mesh" in node else None
        if not mesh or mesh["name"] not in BODY_MESHES:
            continue
        for primitive in mesh["primitives"]:
            accessor = out["accessors"][primitive["attributes"]["POSITION"]]
            lo = [min(a, b) for a, b in zip(lo, accessor["min"])]
            hi = [max(a, b) for a, b in zip(hi, accessor["max"])]
    root = out["nodes"][out["scenes"][0]["nodes"][0]]
    root["translation"] = [-(lo[0] + hi[0]) / 2, -lo[1], -(lo[2] + hi[2]) / 2]
    return out, bytes(blob)


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".scratch/shoggoth-source/shoggoth.glb")
    target = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "Resources/Pet/shoggoth.glb")
    gltf, binary = read_glb(source)
    out, blob = strip(gltf, binary)
    write_glb(target, out, blob)
    print(f"{source}: {os.path.getsize(source)} bytes -> {target}: {os.path.getsize(target)} bytes")


if __name__ == "__main__":
    main()
