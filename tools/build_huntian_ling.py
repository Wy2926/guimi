"""Author Nezha's continuous silk sash, UVs and native segmented skin.

blender --background --factory-startup --python tools/build_huntian_ling.py
Follows the existing selected-GLB/source/manifest workflow; reuses AE_Gold.
No live Blender scene is changed. Studio renders are NOT game screenshots.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector, Matrix

PROJECT = Path(__file__).resolve().parents[1]
OUT = PROJECT / "assets/effects/huntian_ling"
SOURCE = OUT / "source"
PREVIEW = PROJECT / "artifacts"
SOURCE.mkdir(parents=True, exist_ok=True)
PREVIEW.mkdir(parents=True, exist_ok=True)
if "--pose-preview" in sys.argv:
    # Read exact native Godot bone matrices, not a second motion simulation.
    # This previews geometry/materials offline; it is not a game screenshot.
    snapshots = json.loads(Path(sys.argv[sys.argv.index("--pose-preview")+1]).read_text(encoding="utf-8"))
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE / "huntian_ling.blend"))
    scene = bpy.data.scenes["HuntianLingWorkshop"]
    bpy.context.window.scene = scene
    rig = bpy.data.objects["SilkRig"]
    conversion = Matrix(((1,0,0,0), (0,0,-1,0), (0,1,0,0), (0,0,0,1)))
    for target in snapshots[0]["targets"]:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(PROJECT / "assets/characters/Skeleton_Warrior.glb"))
        imported = set(bpy.data.objects)-before
        holder = bpy.data.objects.new("PreviewEnemy", None)
        scene.collection.objects.link(holder)
        for item in imported:
            if item.parent not in imported:
                item.parent = holder
            if item.animation_data:
                item.animation_data_clear()
        holder.location = conversion @ Vector(target)
        holder.scale = (.8, .8, .8)
    for snapshot in snapshots:
        positions = []
        for name, values in snapshot["bones"].items():
            matrix = conversion @ Matrix([values[i:i+4] for i in range(0,16,4)])
            rig.pose.bones[name].matrix = matrix
            positions.append(matrix.translation)
        bpy.context.view_layer.update()
        focus = Vector((0,2.5,.8))
        scene.camera.location = focus + Vector((7,-10,21))
        scene.camera.rotation_euler = (focus-scene.camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.camera.data.ortho_scale = 12.0
        for name, offset in [("SoftGoldKey", (1,-4,8)), ("CoolEdge", (-5,2,6)), ("SilkFill", (5,3,5))]:
            light = bpy.data.objects[name]
            light.location = focus+Vector(offset)
            light.rotation_euler = (focus-light.location).to_track_quat("-Z", "Y").to_euler()
            light.data.energy *= 1.8 if snapshot == snapshots[0] else 1.0
        scene.render.filepath = str(PREVIEW / f"huntian-follow-{snapshot['hits']}.png")
        bpy.ops.render.render(write_still=True)
    raise SystemExit(0)
scene = bpy.data.scenes.new("HuntianLingWorkshop")
bpy.context.window.scene = scene
collection = bpy.data.collections.new("HuntianLing_Export")
scene.collection.children.link(collection)
scene.render.fps = 30
scene.frame_start, scene.frame_end = 0, 60
BODY_LENGTH, BONE_COUNT = 12.0, 65

with bpy.data.libraries.load(str(PROJECT / "assets/weapons/astral_edge/source/astral_edge.blend"), link=False) as (available, selected):
    assert "AE_Gold" in available.materials
    selected.materials = ["AE_Gold"]
gold = selected.materials[0]
silk = bpy.data.materials.new("HT_CinnabarSilk")
silk.use_nodes = True
shader = next(n for n in silk.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
shader.inputs["Base Color"].default_value = (.43, .012, .023, 1)
shader.inputs["Roughness"].default_value = .44
shader.inputs["Metallic"].default_value = .025
shader.inputs["Sheen Weight"].default_value = .24
shader.inputs["Sheen Roughness"].default_value = .38
silk.diffuse_color = (.43, .012, .023, 1)
spirit = gold.copy()
spirit.name = "HT_SpiritSeam"
shader = next(n for n in spirit.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
shader.inputs["Emission Color"].default_value = (1, .30, .055, 1)
shader.inputs["Emission Strength"].default_value = .65

# Native shader baking, as used by the seal asset. UV warp/weft become an
# embedded color texture; actual pleats, thickness and embroidery are geometry.
nodes, links = silk.node_tree.nodes, silk.node_tree.links
shader = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
output = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")
coords = nodes.new("ShaderNodeTexCoord")
waves = []
for axis, scale in [("X", 220), ("Y", 74)]:
    wave = nodes.new("ShaderNodeTexWave")
    wave.bands_direction = axis
    wave.inputs["Scale"].default_value = scale
    wave.inputs["Distortion"].default_value = .4
    links.new(coords.outputs["UV"], wave.inputs["Vector"])
    waves.append(wave)
mix = nodes.new("ShaderNodeMath")
mix.operation = "MULTIPLY"
for index, wave in enumerate(waves):
    links.new(wave.outputs["Fac"], mix.inputs[index])
colors = nodes.new("ShaderNodeValToRGB")
colors.color_ramp.elements[0].color = (.22, .006, .010, 1)
colors.color_ramp.elements[1].color = (.37, .016, .023, 1)
links.new(mix.outputs[0], colors.inputs["Fac"])
emission = nodes.new("ShaderNodeEmission")
links.new(colors.outputs[0], emission.inputs["Color"])
links.new(emission.outputs[0], output.inputs["Surface"])
texture = bpy.data.images.new("HT_SilkWeave", width=512, height=512)
image_node = nodes.new("ShaderNodeTexImage")
image_node.image = texture
nodes.active = image_node
bpy.ops.mesh.primitive_plane_add(size=2)
plane = bpy.context.object
plane.data.materials.append(silk)
original_engine = scene.render.engine
scene.render.engine = "CYCLES"
scene.cycles.samples = 1
bpy.ops.object.bake(type="EMIT")
texture.pack()
bpy.data.objects.remove(plane, do_unlink=True)
links.new(shader.outputs[0], output.inputs["Surface"])
links.new(image_node.outputs["Color"], shader.inputs["Base Color"])
scene.render.engine = original_engine


def center(t):
    # Straight bind pose only. The runtime bends the real cloth along the
    # head's travelled path; it never rotates a rigid pre-curved sash.
    return Vector((0, -BODY_LENGTH * (1-t), 0))


def surface(t, u, depth):
    # A concave hem produces two swallowtail tips without detached ribbons.
    t += .032 * (1 - abs(u)) ** 2 * (max(0, 1 - t / .08) - max(0, (t - .92) / .08))
    side, normal = Vector((1, 0, 0)), Vector((0, 0, 1))
    bank = .18 * math.sin(t * math.tau * 2)
    across = side * math.cos(bank) + normal * math.sin(bank)
    up = normal * math.cos(bank) - side * math.sin(bank)
    width = .045 + .255 * max(0, math.sin(math.pi * t)) ** .32
    pleat = .027 * math.sin(u * math.pi * 3 + t * 13) * (1 - u * u)
    return center(t) + across * width * u + up * (depth + pleat)


parameters, faces, material_ids, uvs = [], [], [], []


def vertex(t, u, depth):
    parameters.append((t, u, depth))
    uvs.append((t, (u + 1) * .5))
    return len(parameters) - 1


def face(indices, material):
    faces.append(indices)
    material_ids.append(material)


LENGTH, WIDTH = 144, 12
for layer in range(2):
    for i in range(LENGTH + 1):
        for j in range(WIDTH + 1):
            vertex(i / LENGTH, -1 + 2 * j / WIDTH, .009 if layer == 0 else -.009)
stride = WIDTH + 1
bottom = (LENGTH + 1) * stride
for i in range(LENGTH):
    for j in range(WIDTH):
        a = i * stride + j
        face((a, a + stride, a + stride + 1, a + 1), 0)
        face((a + bottom + 1, a + bottom + stride + 1, a + bottom + stride, a + bottom), 0)
    for j in (0, WIDTH):
        a = i * stride + j
        edge = (a, a + bottom, a + bottom + stride, a + stride)
        face(edge if j == 0 else tuple(reversed(edge)), 0)
for i in (0, LENGTH):
    for j in range(WIDTH):
        a = i * stride + j
        edge = (a, a + 1, a + 1 + bottom, a + bottom)
        face(edge if i == 0 else tuple(reversed(edge)), 0)


def embroidery(points, radius, material=1):
    start, sides = len(parameters), 5
    for t, u in points:
        width = .045 + .255 * max(0, math.sin(math.pi * t)) ** .32
        for k in range(sides):
            angle = k * math.tau / sides
            vertex(t, u + radius * math.cos(angle) / width, .012 + radius * math.sin(angle))
    for i in range(len(points) - 1):
        for k in range(sides):
            a, b = start + i * sides + k, start + i * sides + (k + 1) % sides
            face((a, b, b + sides, a + sides), material)


# Two continuous hems and one sparse animated spirit thread, all in the SAME
# deforming mesh so embroidery cannot slide off the cloth during a whip.
for side in (-1, 1):
    for u, radius, material in [(side * .96, .007, 1), (side * .83, .003, 2)]:
        embroidery([(i / LENGTH, u) for i in range(LENGTH + 1)], radius, material)
for index, t0 in enumerate((.15, .29, .43, .57, .71, .85)):
    sign = 1 if index % 2 else -1
    for dt, v, scale in [(0, 0, 1), (.017, -.23, .65), (-.017, .23, .65)]:
        points = []
        for step in range(37):
            r = (.29 - step * .0069) * scale
            angle = step * math.tau / 27
            points.append((t0 + dt + r * .06 * math.cos(angle), sign * (v + r * math.sin(angle))))
        embroidery(points, .005)
    embroidery([(t0 - .025 + i * .0017, sign * (.44 + .06 * math.sin(i * .2))) for i in range(30)], .004)

mesh = bpy.data.meshes.new("ContinuousSilkWithWovenClouds")
mesh.from_pydata([surface(*p) for p in parameters], [], faces)
mesh.update()
obj = bpy.data.objects.new("HuntianSilk", mesh)
collection.objects.link(obj)
for material in (silk, gold, spirit):
    mesh.materials.append(material)
for poly, material in zip(mesh.polygons, material_ids):
    poly.material_index = material
    poly.use_smooth = True
uv = mesh.uv_layers.new(name="SilkUV")
for poly in mesh.polygons:
    for loop in poly.loop_indices:
        uv.data[loop].uv = uvs[mesh.loops[loop].vertex_index]
obj["source"] = "Fengshen Yanyi chapter 12: red silk, stirring water and wrapping the opponent"
obj["adaptation"] = "Gold clouds, chain targeting and whip damage are game design, not religious doctrine"
obj["reference"] = "../concept/huntian-ling.png"
obj["axis_contract"] = "Flight head at origin, Blender +Y / Godot -Z forward; cloth trails behind"
# One native skin for cloth, piping and embroidery. All longitudinal bones
# share a stationary root: rotating the head cannot drag a parented tail.
armature = bpy.data.armatures.new("SilkSpine")
rig = bpy.data.objects.new("SilkRig", armature)
collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
root_bone = armature.edit_bones.new("SilkRoot")
root_bone.head, root_bone.tail = (0, 0, 0), (0, .2, 0)
for index in range(BONE_COUNT):
    bone = armature.edit_bones.new(f"Silk{index:02d}")
    bone.head = center(index/(BONE_COUNT-1))
    bone.tail = bone.head + Vector((0, BODY_LENGTH/(BONE_COUNT-1), 0))
    bone.parent = root_bone
    bone.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")
groups = [obj.vertex_groups.new(name=f"Silk{i:02d}") for i in range(BONE_COUNT)]
for vertex_index, vertex_data in enumerate(mesh.vertices):
    # Include the swallowtail cut in longitudinal weighting too.
    coordinate = max(0, min(BONE_COUNT-1, (vertex_data.co.y/BODY_LENGTH+1)*(BONE_COUNT-1)))
    lower = min(BONE_COUNT-2, int(coordinate))
    fraction = coordinate-lower
    if fraction < 1:
        groups[lower].add([vertex_index], 1-fraction, "REPLACE")
    if fraction > 0:
        groups[lower+1].add([vertex_index], fraction, "REPLACE")
modifier = obj.modifiers.new("ContinuousSilkSkin", "ARMATURE")
modifier.object = rig
obj.parent = rig
bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUT / "huntian_ling.glb"), export_format="GLB", use_selection=True,
                          use_active_scene=True, export_yup=True, export_animations=False,
                          export_skins=True, export_morph=False)


def aim(item, target=(0, -1.5, 0)):
    item.rotation_euler = (Vector(target) - item.location).to_track_quat("-Z", "Y").to_euler()


camera_data = bpy.data.cameras.new("WorkshopCamera")
camera = bpy.data.objects.new("WorkshopCamera", camera_data)
scene.collection.objects.link(camera)
camera.location = (3.0, -5.5, 9.0)
aim(camera)
camera_data.type, camera_data.ortho_scale = "ORTHO", 5.2
scene.camera = camera
for name, position, color, power, size in [("SoftGoldKey", (1, -4, 6), (1, .82, .65), 520, 5),
                                         ("CoolEdge", (-3, 0, 4), (.45, .73, 1), 390, 4),
                                         ("SilkFill", (3, 1, 3), (1, .40, .27), 220, 3)]:
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.color, data.size = power, color, size
    item = bpy.data.objects.new(name, data)
    scene.collection.objects.link(item)
    item.location = position
    aim(item)
world = bpy.data.worlds.new("SilkWorkshopWorld")
world.use_nodes = True
background = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
background.inputs[0].default_value = (.026, .046, .058, 1)
background.inputs[1].default_value = .38
scene.world = world
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.85))
floor = bpy.context.object
floor.name = "PreviewOnlyFloor"
mat = bpy.data.materials.new("PreviewOnlyFloor")
mat.use_nodes = True
shader = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
shader.inputs["Base Color"].default_value = (.018, .036, .044, 1)
shader.inputs["Roughness"].default_value = .82
floor.data.materials.append(mat)
scene.render.resolution_x, scene.render.resolution_y = 1200, 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "huntian_ling.blend"))
report = {"mesh_instances": 1, "material_surfaces": 3, "vertices": len(parameters),
          "triangles": sum(len(f) - 2 for f in faces), "materials_reused": ["AE_Gold"],
          "bones": BONE_COUNT+1, "deforming_bones": BONE_COUNT, "body_length": BODY_LENGTH,
          "skin_influences": 2, "animations": {}, "morph_targets": [],
          "flow": "independent native skin bones follow arc-length samples of the head history",
          "texture": "512x512 packed silk weave",
          "reference": "../concept/huntian-ling.png", "preview": "Blender only, not runtime GPU particles"}
(SOURCE / "asset_manifest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print("HUNTIAN_EXPORTED", json.dumps(report), flush=True)
# A curved skin study (not gameplay footage) makes the actual binding visible.
for index in range(BONE_COUNT):
    t = index/(BONE_COUNT-1)
    angle = -1.0 + t*math.tau*1.15
    point = Vector((1.5*math.cos(angle), -2.0+2.6*math.sin(angle), .18*math.sin(t*math.tau*2)))
    tangent = Vector((-1.5*math.sin(angle), 2.6*math.cos(angle), .05)).normalized()
    rotation = Vector((0, 1, 0)).rotation_difference(tangent).to_matrix().to_4x4()
    rig.pose.bones[f"Silk{index:02d}"].matrix = Matrix.Translation(point) @ rotation
camera.location = (3.0, -5.5, 9.0)
aim(camera, (0, -2.0, 0))
camera_data.ortho_scale = 7.0
scene.render.filepath = str(PREVIEW / "huntian-ling-model.png")
bpy.ops.render.render(write_still=True)
