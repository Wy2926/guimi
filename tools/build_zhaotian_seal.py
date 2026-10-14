"""Author Luo Xuan's Zhaotian Seal projection and its actual fracture animation.

blender --background --factory-startup --python tools/build_zhaotian_seal.py
Uses the existing selected-GLB workflow and Astral Edge gold. No live scene is
edited. The ONLY body is already partitioned: the same pieces fall and break.
The seal form, fire knob and breakable projection are game adaptations of
Fengshen Yanyi chapter 64, not claims about the original artifact's appearance.
"""
import json
import math
import random
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.geometry import tessellate_polygon

PROJECT = Path(__file__).resolve().parents[1]
OUT = PROJECT / "assets/effects/zhaotian_seal"
SOURCE = OUT / "source"
PREVIEW = PROJECT / "artifacts"
SOURCE.mkdir(parents=True, exist_ok=True)
PREVIEW.mkdir(parents=True, exist_ok=True)
rng = random.Random(641014)
scene = bpy.data.scenes.new("SealShatter")
bpy.context.window.scene = scene
collection = bpy.data.collections.new("ZhaotianSeal_Export")
scene.collection.children.link(collection)

with bpy.data.libraries.load(str(PROJECT / "assets/weapons/astral_edge/source/astral_edge.blend"), link=False) as (available, selected):
    assert "AE_Gold" in available.materials
    selected.materials = ["AE_Gold"]
materials = {"Gold": selected.materials[0]}
for name, color, metal, rough, emission in [
    ("Cinnabar", (.26, .026, .012), .28, .30, .06),
    ("CutStone", (.07, .009, .004), .12, .47, .0),
    ("FireVein", (1.0, .23, .035), .30, .26, 2.0),
]:
    mat = bpy.data.materials.new("ZS_" + name)
    mat.use_nodes = True
    shader = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metal
    shader.inputs["Roughness"].default_value = rough
    shader.inputs["Emission Color"].default_value = (*color, 1)
    shader.inputs["Emission Strength"].default_value = emission
    mat.diffuse_color = (*color, 1)
    materials[name] = mat

# Bake the cinnabar's cloudy stone grain using Blender's own shader baker.
# Pack it into the .blend and GLB; no extra untracked texture dependency.
mat = materials["Cinnabar"]
nodes, links = mat.node_tree.nodes, mat.node_tree.links
shader = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
output = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")
coords = nodes.new("ShaderNodeTexCoord")
noise = nodes.new("ShaderNodeTexNoise")
noise.inputs["Scale"].default_value = 6.5
noise.inputs["Detail"].default_value = 5.0
noise.inputs["Roughness"].default_value = .72
links.new(coords.outputs["UV"], noise.inputs["Vector"])
colors = nodes.new("ShaderNodeValToRGB")
colors.color_ramp.elements[0].position = .22
colors.color_ramp.elements[0].color = (.035, .003, .002, 1)
colors.color_ramp.elements[1].position = .77
colors.color_ramp.elements[1].color = (.32, .038, .016, 1)
colors.color_ramp.elements.new(.56).color = (.14, .014, .008, 1)
links.new(noise.outputs["Fac"], colors.inputs["Fac"])
emission = nodes.new("ShaderNodeEmission")
links.new(colors.outputs["Color"], emission.inputs["Color"])
links.new(emission.outputs[0], output.inputs["Surface"])
texture = bpy.data.images.new("ZS_CinnabarGrain", width=512, height=512)
image_node = nodes.new("ShaderNodeTexImage")
image_node.image = texture
nodes.active = image_node
bpy.ops.mesh.primitive_plane_add(size=2)
bake_plane = bpy.context.object
bake_plane.data.materials.append(mat)
original_engine = scene.render.engine
try:
    scene.render.engine = "CYCLES"
except TypeError as error:
    raise RuntimeError("Native material bake requires a supported Cycles engine") from error
scene.cycles.samples = 1
bpy.ops.object.bake(type="EMIT")
texture.pack()
bpy.data.objects.remove(bake_plane, do_unlink=True)
links.new(shader.outputs[0], output.inputs["Surface"])
links.new(image_node.outputs["Color"], shader.inputs["Base Color"])
scene.render.engine = original_engine


def empty(name, parent=None):
    obj = bpy.data.objects.new(name, None)
    collection.objects.link(obj)
    obj.parent = parent
    return obj


def own(obj, parent, mat):
    for existing in list(obj.users_collection):
        existing.objects.unlink(obj)
    collection.objects.link(obj)
    obj.parent = parent
    obj.data.materials.append(materials[mat])
    return obj


def curve(name, points, width, mat, parent):
    # Native beveled curves, converted and batched below; no new geometry library.
    data = bpy.data.curves.new(name, "CURVE")
    data.dimensions = "3D"
    data.bevel_depth, data.bevel_resolution = width, 1
    spline = data.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (*co, 1)
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj.parent = parent
    obj.data.materials.append(materials[mat])
    return obj


root = empty("ZhaotianSeal")
root["source"] = "Fengshen Yanyi ch64: Luo Xuan casts Zhaotian Seal at Longji"
root["adaptation"] = "Cinnabar seal with open flame knob; the projection shatters, not the original treasure"
root["axis_contract"] = "Z-up to Godot Y-up; origin is the bottom contact plane"
root["reference"] = "../concept/zhaotian-seal.png"
body = empty("SealBody", root)
shards = []

# Twelve contiguous irregular cells partition one square stamp. Half-plane
# clipping is local to this asset; there is no runtime fracture/physics system.
seeds = [Vector((-.66 + x * .44 + rng.uniform(-.10, .10), -.56 + y * .56 + rng.uniform(-.10, .10)))
         for y in range(3) for x in range(4)]


def cell(index):
    polygon = [Vector((-.86, -.86)), Vector((.86, -.86)), Vector((.86, .86)), Vector((-.86, .86))]
    for other, seed in enumerate(seeds):
        if other == index:
            continue
        normal = seed - seeds[index]
        midpoint = (seed + seeds[index]) * .5
        clipped = []
        for a, b in zip(polygon, polygon[1:] + polygon[:1]):
            da, db = (a - midpoint).dot(normal), (b - midpoint).dot(normal)
            if da <= 0:
                clipped.append(a)
            if (da <= 0) != (db <= 0):
                clipped.append(a.lerp(b, da / (da - db)))
        polygon = clipped
    return polygon


for index in range(len(seeds)):
    polygon = cell(index)
    center = sum(polygon, Vector((0, 0))) / len(polygon)
    polygon = [center + (point - center) * .974 for point in polygon]
    shard = empty("Shard_%02d" % index, body)
    shard.location = (center.x, center.y, .38)
    shards.append(shard)
    levels = [(0, 1.08), (.10, 1.08), (.14, .96), (.34, .96), (.365, 1.00), (.40, 1.00),
              (.42, .955), (.61, .955), (.635, 1.00), (.67, 1.00), (.73, .94), (.77, .94)]
    vertices = [(p.x * scale - center.x, p.y * scale - center.y, z - .38) for z, scale in levels for p in polygon]
    n = len(polygon)
    faces = [tuple(reversed(range(n))), tuple(range((len(levels) - 1) * n, len(levels) * n))]
    mat_indices = [1, 0]
    for layer in range(len(levels) - 1):
        for edge in range(n):
            faces.append((layer * n + edge, layer * n + (edge + 1) % n, (layer + 1) * n + (edge + 1) % n, (layer + 1) * n + edge))
            a, b = polygon[edge], polygon[(edge + 1) % n]
            exterior = abs(a.x) > .83 and abs(b.x) > .83 or abs(a.y) > .83 and abs(b.y) > .83
            mat_indices.append(2 if layer in (4, 8) else (0 if exterior else 1))
    data = bpy.data.meshes.new(shard.name + "Stone")
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(shard.name + "Stone", data)
    collection.objects.link(obj)
    obj.parent = shard
    for mat in ("Cinnabar", "CutStone", "Gold"):
        data.materials.append(materials[mat])
    for face, mat_index in zip(data.polygons, mat_indices):
        face.material_index = mat_index
    bevel = obj.modifiers.new("StoneEdges", "BEVEL")
    bevel.width, bevel.segments = .012, 2
    # Fine incandescent fissure tops remain attached to their actual stone pieces.
    curve("Fissure", [(p.x * .94 - center.x, p.y * .94 - center.y, .397) for p in polygon + [polygon[0]]], .004, "FireVein", shard)

# Raised cloud curls and the fire-associated Li trigram on the four side faces.
# They are decoration on the stamp, not an invented pseudo-script or doctrine.
for side in range(4):
    angle = side * math.pi / 2
    def side_point(u, z):
        return Vector((u * math.cos(angle) + .830 * math.sin(angle), u * math.sin(angle) - .830 * math.cos(angle), z))
    for sign in (-1, 1):
        points = [side_point(sign * (.48 + (.16 - t * .0038) * math.cos(t * math.tau / 28)), .47 + (.13 - t * .0028) * math.sin(t * math.tau / 28)) for t in range(36)]
        owner = min(shards, key=lambda p: (Vector((p.location.x, p.location.y, 0)) - Vector((points[0].x, points[0].y, 0))).length)
        curve("CloudRelief", [p - owner.location for p in points], .022, "Gold", owner)
    for row, segments in enumerate([[(-.18, .18)], [(-.18, -.045), (.045, .18)], [(-.18, .18)]]):
        for left, right in segments:
            points = [side_point(left, .255 + row * .10), side_point(right, .255 + row * .10)]
            owner = min(shards, key=lambda p: (p.location - points[0]).length)
            curve("LiRelief", [p - owner.location for p in points], .016, "Gold", owner)

# Gilded corner braces follow the stepped stone silhouette, not a floating cage.
for sx, sy in [(-1, -1), (-1, 1), (1, -1), (1, 1)]:
    owner = min(shards, key=lambda p: (p.location - Vector((sx * .8, sy * .8, .38))).length)
    for z, half, height in [(.15, .85, .17), (.45, .815, .19), (.69, .80, .12)]:
        for axis in (0, 1):
            location = Vector((sx * half, sy * half, z))
            location[axis] -= (sx if axis == 0 else sy) * .105
            bpy.ops.mesh.primitive_cube_add(size=1, location=location - owner.location)
            obj = own(bpy.context.object, owner, "Gold")
            obj.name = "SteppedCornerBrace"
            obj.scale = (.28, .055, height) if axis == 0 else (.055, .28, height)
            bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
            bevel = obj.modifiers.new("GildedBevel", "BEVEL")
            bevel.width, bevel.segments = .025, 3

# Broad sculpted flame ribbons match the image's openwork gold knob. Their
# taper, S curvature and inner hot edge leave the central flame clearly visible.
for index in range(3):
    shard = empty("Shard_%02d" % len(shards), body)
    shard.location = (0, 0, .79)
    shards.append(shard)
    angle = index * math.tau / 3 + .2
    height = [1.34, .94, 1.10][index]
    # A chased S-flame silhouette, broad at the curled foot, needle-fine at the
    # leaning tip. Cubic outline sections avoid a straight, cut-off petal top.
    sections = [((-.10, 0), (-.35, .06), (-.38, .25), (-.24, .42)),
                ((-.24, .42), (-.10, .61), (.18, .74), (.065, 1.0)),
                ((.065, 1.0), (.30, .82), (.31, .69), (.13, .52)),
                ((.13, .52), (-.04, .36), (.23, .30), (.15, .11)),
                ((.15, .11), (.11, .015), (.01, -.015), (-.10, 0))]
    outline = []
    for a, b, c, d in sections:
        for step in range(16):
            t = step / 16
            p = Vector(a) * (1 - t) ** 3 + Vector(b) * (3 * t * (1 - t) ** 2) + Vector(c) * (3 * t * t * (1 - t)) + Vector(d) * t ** 3
            radius = .20 + .065 * math.sin(p.y * math.pi)
            outline.append(Vector((radius * math.cos(angle) - p.x * math.sin(angle), radius * math.sin(angle) + p.x * math.cos(angle), .055 + height * p.y)))
    normal = Vector((math.cos(angle), math.sin(angle), 0))
    vertices = [p + normal * depth for depth in (-.030, .030) for p in outline]
    n = len(outline)
    # Project to the plane tangent to the lobe for robust concave tessellation.
    projected = [Vector((-p.x * math.sin(angle) + p.y * math.cos(angle), p.z, 0)) for p in outline]
    tris = tessellate_polygon([projected])
    indices = {tuple(p): i for i, p in enumerate(projected)}
    triangle_indices = [tuple(p if isinstance(p, int) else indices[tuple(p)] for p in tri) for tri in tris]
    faces = [tuple(reversed(tri)) for tri in triangle_indices]
    faces += [tuple(n + p for p in tri) for tri in triangle_indices]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    data = bpy.data.meshes.new("SculptedFlame")
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new("SculptedFlame", data)
    collection.objects.link(obj)
    obj.parent = shard
    data.materials.append(materials["Gold"])
    bevel = obj.modifiers.new("FlameEdge", "BEVEL")
    bevel.width, bevel.segments = .012, 2
    curve("FlameInnerVein", [p - normal * .034 for p in outline[32:64]], .006, "FireVein", shard)
    curve("FineGoldRim", [p + normal * .034 for p in outline + [outline[0]]], .008, "Gold", shard)
    # Small grounded mounting plate and a chased curl at the lobe's root.
    bpy.ops.mesh.primitive_cube_add(size=1, location=(normal.x * .22, normal.y * .22, .035))
    plate = own(bpy.context.object, shard, "Gold")
    plate.scale = (.48, .48, .06)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel = plate.modifiers.new("MountBevel", "BEVEL")
    bevel.width, bevel.segments = .018, 3
    curl = []
    for step in range(37):
        a, r = step * math.tau / 28, .11 - step * .0025
        u, z = r * math.cos(a), .16 + r * math.sin(a)
        curl.append((.28 * normal.x - u * normal.y, .28 * normal.y + u * normal.x, z))
    curve("KnobCloudChase", curl, .009, "Cinnabar", shard)

# A slim, twisted ember core between the open metal lobes. Its surface is reused
# by the runtime energy material, with crossed wisps adding only a thin halo.
for strand in range(2):
    vertices, faces = [], []
    for ring in range(25):
        t = ring / 24
        radius = .005 + .095 * math.sin(math.pi * t) ** .85
        for side in range(12):
            angle = side * math.tau / 12 + t * 1.8
            vertices.append((.11 * math.sin(t * math.pi * 1.5 + strand) + radius * math.cos(angle),
                             (strand - .5) * .09 + radius * .48 * math.sin(angle), .10 + (.84 - strand * .19) * t))
        if ring:
            for side in range(12):
                a, b = (ring - 1) * 12 + side, (ring - 1) * 12 + (side + 1) % 12
                faces.append((a, b, b + 12, a + 12))
    data = bpy.data.meshes.new("InnerSpiritFlame")
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new("InnerSpiritFlame", data)
    collection.objects.link(obj)
    obj.parent = shards[12 + strand]
    data.materials.append(materials["FireVein"])

# Convert/apply and merge per shard, retaining material slots, UV and one
# transform per chunk. Godot reuses these meshes through the imported clip.
for shard in shards:
    objects = list(shard.children)
    for obj in objects:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target="MESH")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in shard.children:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = shard.children[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = shard.name + "_Mesh"
    # Keep hard stone faces while smoothing the hand-curved knob metal.
    if shard in shards[12:]:
        for face in obj.data.polygons:
            face.use_smooth = True
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=.02)
    bpy.ops.object.mode_set(mode="OBJECT")

# Authored contact -> compression -> fracture -> ballistic tumble -> bounce ->
# ember shrink. No duplicate intact body, rigid bodies or per-frame CPU debris.
scene.frame_start, scene.frame_end = 1, 37
scene.render.fps = 30
for frame, scale in [(1, (1, 1, 1)), (3, (1.08, 1.08, .85)), (5, (1, 1, 1)), (37, (1, 1, 1))]:
    body.scale = scale
    body.keyframe_insert(data_path="scale", frame=frame)
for index, shard in enumerate(shards):
    origin = shard.location.copy()
    heading = Vector((origin.x, origin.y, 0))
    if heading.length < .1:
        heading = Vector((math.cos(index * 2.4), math.sin(index * 2.4), 0))
    heading.normalize()
    reach = rng.uniform(1.15, 2.35) if index < 12 else 1.0
    spin = Vector((rng.uniform(-1.6, 1.6), rng.uniform(-1.6, 1.6), rng.uniform(-2, 2)))
    for frame, spread, lift, turn, scale in [(1, 0, 0, 0, 1), (3, 0, 0, 0, 1), (5, .10, .08, .04, 1),
                                           (10, .48, 1.05, .48, 1), (17, .85, .60, .95, .88),
                                           (23, 1, -.18 if index < 12 else -.60, 1.2, .68),
                                           (27, 1.06, .04 if index < 12 else -.48, 1.35, .47),
                                           (32, 1.11, -.15 if index < 12 else -.66, 1.45, .23),
                                           (37, 1.14, -.30 if index < 12 else -.72, 1.48, .001)]:
        shard.location = origin + heading * reach * spread + Vector((0, 0, lift))
        shard.rotation_euler = spin * turn
        shard.scale = (scale, scale, scale)
        if frame >= 23:
            mesh = shard.children[0]
            bottom = min((shard.rotation_euler.to_matrix() @ (mesh.matrix_local @ Vector(corner)) * scale).z for corner in mesh.bound_box)
            shard.location.z = max(shard.location.z, -bottom + .025 + (.13 if frame == 27 else 0))
        for data_path in ("location", "rotation_euler", "scale"):
            shard.keyframe_insert(data_path=data_path, frame=frame)
for obj in [body] + shards:
    obj.animation_data.action.name = "SealShatter_" + obj.name
    for layer in obj.animation_data.action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fcurve in bag.fcurves:
                    for key in fcurve.keyframe_points:
                        key.interpolation = "LINEAR"
scene.frame_set(1)
bpy.ops.object.select_all(action="DESELECT")
for obj in collection.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = root
export_modes = [i.identifier for i in bpy.ops.export_scene.gltf.get_rna_type().properties["export_animation_mode"].enum_items]
assert "SCENE" in export_modes
bpy.ops.export_scene.gltf(filepath=str(OUT / "zhaotian_seal.glb"), export_format="GLB", use_selection=True, use_active_scene=True,
                          export_yup=True, export_animations=True, export_animation_mode="SCENE",
                          export_anim_scene_split_object=False, export_frame_range=True)

# Studio evidence only: no runtime GPU particles or game screenshots implied.
def aim(obj, point=(0, 0, .45)):
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


data = bpy.data.cameras.new("WorkshopCamera")
camera = bpy.data.objects.new("WorkshopCamera", data)
scene.collection.objects.link(camera)
camera.location = (3.8, -5.8, 6.8)
aim(camera)
data.type, data.ortho_scale = "ORTHO", 4.8
scene.camera = camera
for name, position, color, power, size in [("WarmKey", (1, -3, 5), (1, .81, .57), 340, 4), ("CoolRim", (-3, 2, 4), (.42, .73, 1), 380, 3), ("SoftFill", (3, 2, 3), (1, .47, .22), 220, 3)]:
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.color, data.size = power, color, size
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = position
    aim(obj)
world = bpy.data.worlds.new("SealWorkshopWorld")
world.use_nodes = True
background = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
background.inputs[0].default_value = (.035, .051, .062, 1)
background.inputs[1].default_value = .22
scene.world = world
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.055))
floor = bpy.context.object
floor.name = "PreviewOnlyFloor"
mat = bpy.data.materials.new("PreviewOnlyFloor")
mat.use_nodes = True
node = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
node.inputs["Base Color"].default_value = (.021, .030, .035, 1)
node.inputs["Roughness"].default_value = .78
floor.data.materials.append(mat)
scene.render.engine = bpy.context.scene.render.engine
scene.render.resolution_x, scene.render.resolution_y = 1100, 900
scene.render.resolution_percentage = 100
formats = [i.identifier for i in bpy.types.ImageFormatSettings.bl_rna.properties["file_format"].enum_items]
assert "PNG" in formats
scene.render.image_settings.file_format = "PNG"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "zhaotian_seal.blend"))
meshes = [o for o in collection.objects if o.type == "MESH"]
report = {"mesh_instances": len(meshes), "fracture_chunks": len(shards),
          "material_surfaces": sum(len({o.data.materials[p.material_index].name for p in o.data.polygons}) for o in meshes),
          "triangles": sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons),
          "materials_reused": ["AE_Gold"], "animation": "SealShatter", "duration_seconds": 1.2,
          "preview": "Blender model only, not runtime GPU particles"}
(SOURCE / "asset_manifest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print("SEAL_EXPORTED", json.dumps(report), flush=True)
for frame, suffix, scale in [(1, "model", 4.8), (12, "fracture", 6.8), (1, "game-angle", 4.4)]:
    scene.frame_set(frame)
    if suffix == "game-angle":
        camera.location = (3.8, -5.8, 12.45)
        aim(camera)
    camera.data.ortho_scale = scale
    scene.render.filepath = str(PREVIEW / ("zhaotian-seal-" + suffix + ".png"))
    bpy.ops.render.render(write_still=True)
