"""Original Thunder Orb asset, authored after concept/thunder-orb-black-hole.png.

Run with Blender --background --factory-startup --python tools/build_thunder_orb.py.
Follows the existing Astral Edge authoring workflow: a separate workshop, UV meshes,
merged material/pivot batches, selected-only GLB export, retained .blend source.
No external models or paid generators. Godot owns collision, field expansion and damage.
"""
import math
import random
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path(__file__).resolve().parents[1]
OUT = PROJECT / "assets/effects/thunder_orb"
SOURCE = OUT / "source"
SOURCE.mkdir(parents=True, exist_ok=True)
PREVIEW = PROJECT / "artifacts/thunder-orb-model.png"
PREVIEW.parent.mkdir(parents=True, exist_ok=True)
rng = random.Random(41014)

scene = bpy.data.scenes.new("VortexOrbit")
bpy.context.window.scene = scene
collection = bpy.data.collections.new("ThunderOrb_Export")
scene.collection.children.link(collection)


def material(name, color, emission=0.0, metallic=0.0):
    mat = bpy.data.materials.new("TB_" + name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    node = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    node.inputs["Base Color"].default_value = (*color, 1.0)
    node.inputs["Metallic"].default_value = metallic
    node.inputs["Roughness"].default_value = 0.31
    node.inputs["Emission Color"].default_value = (*color, 1.0)
    node.inputs["Emission Strength"].default_value = emission
    return mat


materials = {
    "Core": material("Core", (0.0003, 0.0001, 0.0008)),
    "Accretion": material("Accretion", (0.16, 0.018, 0.36), 1.1, 0.45),
    "Filament": material("Filament", (0.41, 0.08, 0.83), 3.3),
    "Lightning": material("Lightning", (0.65, 0.32, 1.0), 6.5),
    "Debris": material("Debris", (0.035, 0.007, 0.065), 0.04, 0.3),
}
# View-dependent photon rim for the Blender preview. Replaced by the asset's
# singularity.gdshader in Godot, as glTF cannot preserve this node network.
nodes = materials["Core"].node_tree.nodes
links = materials["Core"].node_tree.links
bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
facing = nodes.new("ShaderNodeLayerWeight")
ramp = nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.80
ramp.color_ramp.elements[0].color = (0.00003, 0.00001, 0.00007, 1)
ramp.color_ramp.elements[1].position = 0.98
ramp.color_ramp.elements[1].color = (0.52, 0.19, 1.0, 1)
links.new(facing.outputs["Facing"], ramp.inputs["Fac"])
links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
bsdf.inputs["Emission Strength"].default_value = 4.0
bsdf.inputs["Specular IOR Level"].default_value = 0.0


def pivot(name, parent=None, tilt=0.0):
    obj = bpy.data.objects.new(name, None)
    collection.objects.link(obj)
    obj.parent = parent
    obj.rotation_euler.x = tilt
    return obj


root = pivot("ThunderOrb")
root["design"] = "Purple lightning / dark singularity; original modeled asset"
root["axis_contract"] = "Centered origin; Z-up authoring, Y-up Godot; max radius 1.18"
root["concept"] = "../concept/thunder-orb-black-hole.png"
inner = pivot("InnerOrbit", root, 0.30)
outer = pivot("OuterOrbit", root, -0.21)
bolts = [pivot("Lightning" + str(i), root, i * 0.31) for i in range(3)]


def mesh(name, vertices, faces, mat, parent, uv_coords=None):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj.parent = parent
    data.materials.append(materials[mat])
    uv = data.uv_layers.new(name="UVMap")
    for poly in data.polygons:
        poly.use_smooth = mat != "Debris"
        for idx in poly.loop_indices:
            vid = data.loops[idx].vertex_index
            point = data.vertices[vid].co
            uv.data[idx].uv = uv_coords[vid] if uv_coords else (point.x * 0.5 + 0.5, point.z * 0.5 + 0.5)
    return obj


def tube(name, points, radius, mat, parent, sides=5):
    vertices, faces, uv = [], [], []
    for i, co in enumerate(points):
        p = Vector(co)
        tangent = Vector(points[min(i + 1, len(points) - 1)]) - Vector(points[max(0, i - 1)])
        tangent.normalize()
        axis = Vector((0, 0, 1)) if abs(tangent.z) < 0.9 else Vector((0, 1, 0))
        right = tangent.cross(axis).normalized()
        up = tangent.cross(right).normalized()
        taper = 0.16 + 0.84 * math.sin(math.pi * i / (len(points) - 1)) ** 0.35
        for j in range(sides):
            a = math.tau * j / sides
            vertices.append(p + radius * taper * (right * math.cos(a) + up * math.sin(a)))
            uv.append((j / sides, i / (len(points) - 1)))
        if i:
            for j in range(sides):
                a = (i - 1) * sides + j
                b = (i - 1) * sides + (j + 1) % sides
                faces.append((a, b, b + sides, a + sides))
    return mesh(name, vertices, faces, mat, parent, uv)


bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=0.53)
core = bpy.context.object
core.name = "EventHorizon"
for coll in list(core.users_collection):
    coll.objects.unlink(core)
collection.objects.link(core)
core.parent = root
core.data.materials.append(materials["Core"])
for face in core.data.polygons:
    face.use_smooth = True

# Tapered spiral ribbons, not solid toruses: gaps leave the black center readable.
for group_index, parent in enumerate((inner, outer)):
    for ribbon in range(3):
        vertices, faces, uv, edge = [], [], [], []
        steps = 90
        for i in range(steps + 1):
            t = i / steps
            angle = ribbon * math.tau / 3 + t * math.tau * 0.77
            radius = 0.58 + group_index * 0.15 + t * 0.29
            width = (0.026 + 0.085 * math.sin(math.pi * t) ** 0.75) * (1.0 if group_index else 0.75)
            z = 0.035 * math.sin(angle * 3 + ribbon) + (t - 0.5) * 0.12
            for across in (0.0, 0.5, 1.0):
                r = radius + (across - 0.5) * width
                vertices.append((r * math.cos(angle), r * math.sin(angle), z + math.sin(across * math.pi) * 0.024))
                uv.append((across, t))
            edge.append(((radius + width * 0.5) * math.cos(angle), (radius + width * 0.5) * math.sin(angle), z))
            if i:
                start = (i - 1) * 3
                faces.extend(((start, start + 3, start + 4, start + 1), (start + 1, start + 4, start + 5, start + 2)))
        mesh("SpiralRibbon", vertices, faces, "Accretion", parent, uv)
        tube("PhotonFilament", edge, 0.006, "Filament", parent)

# Branching purple electricity, made as actual beveled mesh so it reads at any angle.
for group_index, parent in enumerate(bolts):
    for arc in range(2):
        points = []
        for i in range(26):
            t = i / 25
            angle = group_index * 2.1 + arc * math.pi + t * 2.25
            r = 0.58 + 0.15 * math.sin(t * math.pi) + rng.uniform(-0.035, 0.035)
            lat = (t - 0.5) * 1.35 + rng.uniform(-0.09, 0.09)
            points.append((r * math.cos(lat) * math.cos(angle), r * math.cos(lat) * math.sin(angle), r * math.sin(lat)))
        tube("ForkedBolt", points, 0.012, "Lightning", parent)
        for start in (8, 17):
            branch = [Vector(points[start])]
            for j in range(1, 6):
                p = branch[0] * (1 + j * 0.085) + Vector((rng.uniform(-0.025, 0.025), j * 0.012, -j * 0.018))
                branch.append(p)
            tube("BoltBranch", branch, 0.007, "Lightning", parent)

# Small obsidian fragments embedded in the vortex; material-batched, not new nodes per shard.
for i in range(18):
    a = i * math.tau / 18 + rng.uniform(-0.10, 0.10)
    r = rng.uniform(0.89, 1.12)
    center = Vector((r * math.cos(a), r * math.sin(a), rng.uniform(-0.16, 0.16)))
    size = rng.uniform(0.025, 0.057)
    vertices = [center + Vector(p) * size for p in [(0, 0, 1.6), (-1, -.6, 0), (1, -.5, 0), (.6, .8, 0), (-.5, .7, 0), (0, 0, -1)]]
    faces = [(0, 1, 2), (0, 2, 3), (0, 3, 4), (0, 4, 1), (5, 2, 1), (5, 3, 2), (5, 4, 3), (5, 1, 4)]
    mesh("ObsidianShard", vertices, faces, "Debris", outer)

for parent in (root, inner, outer, *bolts):
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

scene.frame_start, scene.frame_end = 1, 121
scene.render.fps = 30
for index, obj in enumerate((inner, outer, *bolts)):
    turns = 1 if index % 2 == 0 else -1
    for frame in range(1, 122, 30):
        obj.rotation_euler.z = turns * math.tau * (frame - 1) / 120
        obj.keyframe_insert(data_path="rotation_euler", frame=frame)
    action = obj.animation_data.action
    action.name = "VortexOrbit_" + obj.name
    for layer in action.layers:
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
bpy.ops.export_scene.gltf(filepath=str(OUT / "thunder_orb.glb"), export_format="GLB", use_selection=True,
                          use_active_scene=True, export_yup=True, export_animations=True,
                          export_animation_mode="SCENE", export_anim_scene_split_object=False,
                          export_frame_range=True)


def aim(obj, at=(0, 0, 0)):
    obj.rotation_euler = (Vector(at) - obj.location).to_track_quat("-Z", "Y").to_euler()


camera_data = bpy.data.cameras.new("WorkshopCamera")
camera = bpy.data.objects.new("WorkshopCamera", camera_data)
scene.collection.objects.link(camera)
camera.location = (2.2, -4.2, 2.5)
aim(camera)
camera_data.type = "ORTHO"
camera_data.ortho_scale = 3.2
scene.camera = camera
for name, position, color, power in (("VioletRim", (-2, 1, 3), (.30, .035, 1), 170), ("SoftKey", (2, -3, 4), (.7, .55, 1), 90)):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.color, data.size = power, color, 3
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = position
    aim(obj)
world = bpy.data.worlds.new("VoidWorkshop")
world.use_nodes = True
background = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
background.inputs[0].default_value = (.012, .007, .022, 1)
background.inputs[1].default_value = .3
scene.world = world
scene.render.engine = "CYCLES"
scene.cycles.samples = 32
scene.render.resolution_x, scene.render.resolution_y = 1000, 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(PREVIEW)
scene.view_settings.view_transform = "AgX"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "thunder_orb.blend"))
triangles = sum(len(poly.vertices) - 2 for obj in collection.objects if obj.type == "MESH" for poly in obj.data.polygons)
print("THUNDER_ORB_EXPORTED", "meshes", sum(o.type == "MESH" for o in collection.objects), "triangles", triangles, flush=True)
bpy.ops.render.render(write_still=True)
