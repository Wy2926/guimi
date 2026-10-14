"""Author the Taiji aura using the existing Blender -> selected GLB workflow.

Run: blender --background --factory-startup --python tools/build_taiji_aura.py
Reuses Astral Edge's authored gold material; Godot reuses Feedback emitters and
astral_ring/energy shaders. New geometry is specific to this formation, not a
second effects framework. The preview is a Blender model render, not gameplay.
"""
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.geometry import tessellate_polygon

PROJECT = Path(__file__).resolve().parents[1]
OUT = PROJECT / "assets/effects/taiji_aura"
SOURCE = OUT / "source"
SOURCE.mkdir(parents=True, exist_ok=True)
scene = bpy.data.scenes.new("TaijiOrbit")
bpy.context.window.scene = scene
collection = bpy.data.collections.new("TaijiAura_Export")
scene.collection.children.link(collection)

# Append the existing metal rather than authoring another near-identical gold.
with bpy.data.libraries.load(str(PROJECT / "assets/weapons/astral_edge/source/astral_edge.blend"), link=False) as (available, selected):
    assert "AE_Gold" in available.materials
    selected.materials = ["AE_Gold"]
materials = {"Gold": selected.materials[0]}
for name, color, metal, rough, emission in [
    ("Jade", (.015, .105, .095), .35, .28, .05),
    ("Ivory", (.70, .67, .49), .22, .32, .06),
    ("Cyan", (.10, .65, .56), .20, .24, 2.4),
    ("Warm", (.84, .52, .16), .25, .26, 1.5),
]:
    mat = bpy.data.materials.new("TA_" + name)
    mat.use_nodes = True
    shader = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metal
    shader.inputs["Roughness"].default_value = rough
    shader.inputs["Emission Color"].default_value = (*color, 1)
    shader.inputs["Emission Strength"].default_value = emission
    mat.diffuse_color = (*color, 1)
    materials[name] = mat


def pivot(name, parent=None):
    obj = bpy.data.objects.new(name, None)
    collection.objects.link(obj)
    obj.parent = parent
    return obj


root = pivot("TaijiAura")
root["design"] = "Taishang Laojun / Taiji Diagram, original roguelite adaptation"
root["axis_contract"] = "Z-up -> Godot Y-up; origin at ground center; outer radius 1m"
root["concept"] = "../concept/taiji-aura.png"
center = pivot("LiangYi", root)
glyphs = pivot("Bagua", root)
outer = pivot("CloudOrbit", root)


def mesh(name, vertices, faces, mat, parent):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj.parent = parent
    data.materials.append(materials[mat])
    uv = data.uv_layers.new(name="UVMap")
    for poly in data.polygons:
        for index in poly.loop_indices:
            p = data.vertices[data.loops[index].vertex_index].co
            uv.data[index].uv = (p.x * .5 + .5, p.y * .5 + .5)
    return obj


def plate(name, points, z, depth, mat, parent, bevel=.003):
    n = len(points)
    vertices = [(x, y, z) for x, y in points] + [(x, y, z + depth) for x, y in points]
    boundary = [Vector((x, y, 0)) for x, y in points]
    lookup = {tuple(p): i for i, p in enumerate(boundary)}
    faces = []
    for triangle in tessellate_polygon([boundary]):
        ids = [p if isinstance(p, int) else lookup[tuple(p)] for p in triangle]
        faces.extend([tuple(reversed(ids)), tuple(i + n for i in ids)])
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    obj = mesh(name, vertices, faces, mat, parent)
    if bevel:
        mod = obj.modifiers.new("CraftedEdges", "BEVEL")
        mod.width, mod.segments = bevel, 2
    return obj


def line(name, points, width, mat, parent):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth, curve.bevel_resolution = width, 1
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for p, value in zip(spline.points, points):
        p.co = (*value, 1)
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    obj.parent = parent
    curve.materials.append(materials[mat])
    return obj


def ring(name, radius, width, z, mat, parent, origin=(0, 0), segments=160):
    return line(name, [(origin[0] + radius * math.cos(i * math.tau / segments), origin[1] + radius * math.sin(i * math.tau / segments), z) for i in range(segments + 1)], width, mat, parent)


def radial(points, angle, radius):
    return [(math.cos(angle) * (radius + y) - math.sin(angle) * x, math.sin(angle) * (radius + y) + math.cos(angle) * x) for x, y in points]


# Actual concave yin-yang halves: no image plane or font-dependent glyphs.
r = .355
fish = [(r * math.cos(-math.pi / 2 + i * math.pi / 64), r * math.sin(-math.pi / 2 + i * math.pi / 64)) for i in range(65)]
fish += [(-r / 2 * math.cos(math.pi / 2 - i * math.pi / 32), r / 2 + r / 2 * math.sin(math.pi / 2 - i * math.pi / 32)) for i in range(1, 33)]
fish += [(r / 2 * math.cos(math.pi / 2 - i * math.pi / 32), -r / 2 + r / 2 * math.sin(math.pi / 2 - i * math.pi / 32)) for i in range(1, 32)]
for sign, mat in [(1, "Ivory"), (-1, "Jade")]:
    points = [(sign * x, sign * y) for x, y in fish]
    plate("YinYangFish", points, .008, .027, mat, center, .002)
    eye = (0, sign * r / 2)
    ring("EyeSetting", .045, .006, .039, "Gold", center, eye, 48)
    # Domed eye with real faceted geometry and concentric bezels.
    vertices = [(eye[0], eye[1], .069)]
    vertices += [(eye[0] + .035 * math.cos(a * math.tau / 32), eye[1] + .035 * math.sin(a * math.tau / 32), .037) for a in range(32)]
    mesh("OppositeEye", vertices, [(0, i + 1, (i + 1) % 32 + 1) for i in range(32)], "Cyan" if sign == 1 else "Warm", center)
ring("FishBorder", .36, .008, .025, "Gold", center)
seam = [(-r / 2 * math.cos(math.pi / 2 - i * math.pi / 48), r / 2 + r / 2 * math.sin(math.pi / 2 - i * math.pi / 48), .039) for i in range(49)]
seam += [(r / 2 * math.cos(math.pi / 2 - i * math.pi / 48), -r / 2 + r / 2 * math.sin(math.pi / 2 - i * math.pi / 48), .039) for i in range(1, 49)]
line("GildedSSeam", seam, .0045, "Gold", center)

# Scalloped relief contained in each fish, with no random or illegible runes.
def inside(point):
    x, y = point
    result = False
    previous = fish[-1]
    for current in fish:
        if (current[1] > y) != (previous[1] > y) and x < (previous[0] - current[0]) * (y - current[1]) / (previous[1] - current[1]) + current[0]:
            result = not result
        previous = current
    return result


for sign, mat in [(1, "Ivory"), (-1, "Jade")]:
    for row in range(-6, 7):
        for col in range(-6, 7):
            x, y = col * .045 + (row % 2) * .0225, row * .045
            points = [(x + math.cos(i * math.pi / 8) * .021, y + math.sin(i * math.pi / 8) * .022) for i in range(9)]
            if all(inside(p) and math.hypot(p[0], p[1] - r / 2) > .064 for p in points):
                line("FishScaleRelief", [(sign * a, sign * b, .038) for a, b in points], .0017, mat, center)

# Separate hoops leave open floor between the solid center and eight plaques.
for radius, width, mat, z in [(.40, .007, "Cyan", .018), (.44, .010, "Gold", .015), (.52, .009, "Gold", .014), (.587, .008, "Gold", .018), (.817, .008, "Gold", .018), (.900, .012, "Jade", .016), (.926, .006, "Gold", .025), (.953, .0035, "Cyan", .020)]:
    ring("OpenworkHoop", radius, width, z, mat, outer if radius < .55 or radius > .88 else glyphs)

# Fuxi sequence around the circle. Each tuple is inner/bottom -> outer/top.
trigrams = [("Qian", (1, 1, 1)), ("Dui", (1, 1, 0)), ("Li", (1, 0, 1)), ("Zhen", (1, 0, 0)), ("Kun", (0, 0, 0)), ("Gen", (0, 0, 1)), ("Kan", (0, 1, 0)), ("Xun", (0, 1, 1))]
for index, (name, bits) in enumerate(trigrams):
    angle = math.pi / 2 - index * math.tau / 8
    origin = (.702 * math.cos(angle), .702 * math.sin(angle))
    disk = [(origin[0] + .111 * math.cos(i * math.tau / 48), origin[1] + .111 * math.sin(i * math.tau / 48)) for i in range(48)]
    plaque = plate(name + "_JadePlaque", disk, .012, .019, "Jade", glyphs)
    plaque["trigram_bottom_to_top"] = list(bits)
    ring(name + "_GildedRim", .115, .005, .031, "Gold", glyphs, origin, 64)
    for row, solid in enumerate(bits):
        y = (row - 1) * .047
        ranges = [(-.073, .073)] if solid else [(-.073, -.019), (.019, .073)]
        for left, right in ranges:
            shape = [(left, y - .009), (right, y - .009), (right, y + .009), (left, y + .009)]
            plate(name + "_Yao", radial(shape, angle, .702), .034, .012, "Warm", glyphs, .002)
    # Eight crown points, nested gem facets and scroll clasps.
    shape = [(0, .062), (-.032, -.013), (0, -.039), (.032, -.013)]
    plate("CompassFrame", radial(shape, angle, .934), .018, .018, "Gold", glyphs)
    shape = [(0, .034), (-.012, -.011), (0, -.026), (.012, -.011)]
    plate("CompassJade", radial(shape, angle, .934), .039, .009, "Jade", glyphs, .001)
    for radius in (.565, .840):
        shape = [(-.021, -.013), (.021, -.013), (.026, 0), (.021, .013), (-.021, .013), (-.026, 0)]
        plate("Clasp", radial(shape, angle, radius), .012, .016, "Gold", glyphs)
    # Opposed cloud curls: raised filigree, not texture-only decoration.
    for radius in (.478, .886):
        for side in (-1, 1):
            points = []
            for step in range(36):
                t = step / 35
                a = t * math.tau * 1.35
                size = .004 + t * .025
                x, y = side * (.036 + math.cos(a) * size), math.sin(a) * size
                px, py = radial([(x, y)], angle + math.pi / 8, radius)[0]
                points.append((px, py, .030))
            line("CloudScroll", points, .004 if radius < .6 else .005, "Gold" if radius < .6 else "Jade", outer)

# Fine perimeter and inner register ticks, batched on export.
for index in range(128):
    a = index * math.tau / 128
    height = .016 if index % 4 == 0 else .006
    shape = [(-.0015, -height / 2), (.0015, -height / 2), (.0015, height / 2), (-.0015, height / 2)]
    plate("PerimeterTick", radial(shape, a, .927), .032, .002, "Warm", outer, 0)

# Apply bevels, convert native curves, and merge by material/pivot for modest draw calls.
for obj in list(collection.objects):
    if obj.type not in {"MESH", "CURVE"}:
        continue
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
for parent in (center, glyphs, outer):
    for mat in materials.values():
        objects = [o for o in collection.objects if o.type == "MESH" and o.parent == parent and o.data.materials[0] == mat]
        if not objects:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        if len(objects) > 1:
            bpy.ops.object.join()
        bpy.context.object.name = parent.name + "_" + mat.name

scene.frame_start, scene.frame_end = 1, 721
scene.render.fps = 30
for obj, turns in ((center, 1), (glyphs, -1), (outer, 1)):
    for frame in range(1, 722, 180):
        obj.rotation_euler.z = turns * math.tau * (frame - 1) / 720
        obj.keyframe_insert(data_path="rotation_euler", frame=frame)
    obj.animation_data.action.name = "TaijiOrbit_" + obj.name
    for layer in obj.animation_data.action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = "LINEAR"
scene.frame_set(1)
bpy.ops.object.select_all(action="DESELECT")
for obj in collection.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = root
export_modes = [i.identifier for i in bpy.ops.export_scene.gltf.get_rna_type().properties["export_animation_mode"].enum_items]
assert "SCENE" in export_modes
bpy.ops.export_scene.gltf(filepath=str(OUT / "taiji_aura.glb"), export_format="GLB", use_selection=True, use_active_scene=True,
                          export_yup=True, export_animations=True, export_animation_mode="SCENE",
                          export_anim_scene_split_object=False, export_frame_range=True)

# Model-only studio preview; neither lights nor floor are exported to Godot.
def aim(obj, point=(0, 0, .01)):
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


data = bpy.data.cameras.new("WorkshopCamera")
camera = bpy.data.objects.new("WorkshopCamera", data)
scene.collection.objects.link(camera)
camera.location = (2.0, -3.1, 4.2)
aim(camera)
data.type, data.ortho_scale = "ORTHO", 2.65
scene.camera = camera
for name, position, color, power, size in [("WarmKey", (0, -1.5, 3), (1, .85, .62), 210, 3), ("JadeRim", (-2, 1, 2), (.20, .86, 1), 120, 2), ("SoftFill", (2, 1, 3), (1, .94, .85), 160, 2)]:
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.color, data.shape, data.size = power, color, "DISK", size
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = position
    aim(obj)
world = bpy.data.worlds.new("TaijiWorkshopWorld")
world.use_nodes = True
background = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
background.inputs[0].default_value = (.021, .033, .041, 1)
background.inputs[1].default_value = .35
scene.world = world
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.026))
floor = bpy.context.object
floor.name = "PreviewOnlyFloor"
floor_mat = bpy.data.materials.new("PreviewOnlyFloor")
floor_mat.use_nodes = True
node = next(n for n in floor_mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
node.inputs["Base Color"].default_value = (.018, .026, .031, 1)
node.inputs["Roughness"].default_value = .72
floor.data.materials.append(floor_mat)
# Use the engine already reported by this Blender build; no live-user scene is touched.
scene.render.engine = bpy.context.scene.render.engine
scene.render.resolution_x, scene.render.resolution_y = 1400, 1100
scene.render.resolution_percentage = 100
formats = [i.identifier for i in bpy.types.ImageFormatSettings.bl_rna.properties["file_format"].enum_items]
assert "PNG" in formats
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "concept/taiji-aura-model.png")
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "taiji_aura.blend"))
objects = [o for o in collection.objects if o.type == "MESH"]
triangles = sum(len(p.vertices) - 2 for o in objects for p in o.data.polygons)
report = {"mesh_batches": len(objects), "triangles": triangles, "trigrams_bottom_to_top": dict(trigrams),
          "materials_reused": ["AE_Gold"], "animation": "TaijiOrbit", "duration_seconds": 24,
          "preview": "Blender model only, not runtime GPU particles"}
(SOURCE / "asset_manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print("TAIJI_EXPORTED", json.dumps(report), flush=True)
bpy.ops.render.render(write_still=True)
