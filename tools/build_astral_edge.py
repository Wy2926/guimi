"""Original Astral Edge model. Run through Blender MCP or Blender --python.

Creates a NEW workshop scene, not an edit to the currently open scene.
Z-up authoring exports as Y-up; origin is pommel, blade tip is +Y in Godot.
Only the authored model collection is exported. No paid/cloud assets.
"""
import bpy
import math
from mathutils import Vector
from pathlib import Path

PROJECT = Path("D:/Project/Github/guimi")
OUT = PROJECT / "assets/weapons/astral_edge"
SOURCE = OUT / "source"
SOURCE.mkdir(parents=True, exist_ok=True)

scene = bpy.data.scenes.new("Astral Edge - Design Workshop")
bpy.context.window.scene = scene
collection = bpy.data.collections.new("AstralEdge_Export")
scene.collection.children.link(collection)

def material(name, color, metallic=0.0, rough=0.3, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Emission Color"].default_value = (*color, 1)
    bsdf.inputs["Emission Strength"].default_value = emission
    return mat

MATS = {
    "Obsidian": material("AE_Obsidian", (0.018, 0.047, 0.09), 0.85, 0.28),
    "Gold": material("AE_Gold", (0.66, 0.48, 0.22), 0.78, 0.25),
    "Silver": material("AE_Silver", (0.65, 0.79, 0.83), 0.8, 0.22),
    "Crystal": material("AE_Crystal", (0.012, 0.31, 0.59), 0.35, 0.19, 0.55),
    "Runes": material("AE_Runes", (0.12, 0.75, 1.0), 0.25, 0.24, 2.4),
    "Edge": material("AE_Edge", (0.48, 0.87, 1.0), 0.35, 0.2, 1.5),
    "Leather": material("AE_Leather", (0.012, 0.018, 0.035), 0.1, 0.65),
}

def empty(name, parent=None):
    obj = bpy.data.objects.new(name, None)
    collection.objects.link(obj)
    obj.parent = parent
    return obj

root = empty("AstralEdge")
root["design"] = "Astral Edge 01 / original cyan-gold split-spine sword"
root["axis_contract"] = "Godot +Y tip; +Z front; origin at pommel"
root["source"] = "Original modeled geometry. Concept generated with built-in imagegen."

def mesh(name, verts, faces, mat, parent=root):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj.parent = parent
    obj.data.materials.append(MATS[mat])
    # Planar front/back UVs for the runtime travelling energy shader.
    uv = data.uv_layers.new(name="UVMap")
    for polygon in data.polygons:
        for loop_index in polygon.loop_indices:
            co = data.vertices[data.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv = ((co.x + 0.7) / 1.4, co.z / 3.6)
    return obj

def plate(name, points, depth, mat, parent=root, y=0.0, bevel=0.006):
    n = len(points)
    verts = [(x, y - depth / 2, z) for x, z in points]
    verts += [(x, y + depth / 2, z) for x, z in points]
    faces = [tuple(reversed(range(n))), tuple(range(n, 2*n))]
    faces += [(i, (i+1) % n, (i+1) % n + n, i+n) for i in range(n)]
    obj = mesh(name, verts, faces, mat, parent)
    if bevel:
        modifier = obj.modifiers.new("Crafted bevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
    return obj

def line(name, points, width, mat, parent=root):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = width
    curve.bevel_resolution = 1
    spline = curve.splines.new("POLY")
    spline.points.add(len(points)-1)
    for p, co in zip(spline.points, points):
        p.co = (*co, 1)
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    obj.parent = parent
    obj.data.materials.append(MATS[mat])
    return obj

def jewel(name, x, z, radius, mat="Crystal", parent=root, y=-0.11):
    # Hexagonal double pyramid: actual beveled-looking crystal facets.
    verts = [(x, y-radius*0.7, z), (x, y+radius*0.55, z)]
    verts += [(x+math.sin(a*math.tau/6)*radius, y, z+math.cos(a*math.tau/6)*radius*1.2) for a in range(6)]
    faces = []
    for i in range(6):
        faces += [(0, 2+i, 2+(i+1)%6), (1, 2+(i+1)%6, 2+i)]
    return mesh(name, verts, faces, mat, parent)

def ring(name, x, z, radius, width, mat, parent=root, y=-0.12, squash=1.0):
    points = [(x+math.sin(i*math.tau/48)*radius, y, z+math.cos(i*math.tau/48)*radius*squash) for i in range(49)]
    return line(name, points, width, mat, parent)

# Wrapped dark grip, diamond pommel and raised gold collars.
plate("Grip", [(-.065,.11),(-.058,.53),(.058,.53),(.065,.11)], .11, "Leather")
for side in (-1, 1):
    for i in range(7):
        z = .13 + i*.053
        line("Grip braid", [(-.063,side*.059,z),(.063,side*.059,z+.047)], .009, "Obsidian")
for z in (.11, .51):
    plate("Grip ferrule", [(-.079,z-.024),(-.074,z+.026),(.074,z+.026),(.079,z-.024)], .14, "Gold")
plate("Pommel frame", [(0,-.05),(-.115,.08),(0,.205),(.115,.08)], .09, "Gold")
jewel("Pommel gem", 0, .082, .067, y=-.067)

# Sculpted wing guard: layered custom swept shapes, negative-space gaps.
for sign in (-1, 1):
    def mirror(points):
        return [(sign*x,z) for x,z in points]
    plate("Guard shadow", mirror([(.055,.5),(.18,.59),(.32,.74),(.46,.97),(.40,.70),(.24,.54),(.11,.48)]), .115, "Obsidian")
    plate("Guard gilded wing", mirror([(.05,.57),(.18,.70),(.40,.81),(.51,1.02),(.43,.72),(.22,.59),(.1,.54)]), .10, "Gold", y=-.055)
    plate("Guard silver feather", mirror([(.12,.70),(.25,.89),(.37,1.05),(.32,.79),(.20,.66)]), .08, "Silver", y=-.08)
    plate("Guard lower talon", mirror([(.07,.54),(.25,.47),(.34,.38),(.24,.56),(.10,.63)]), .09, "Gold")
    line("Guard engraving", [(sign*.14,-.12,.64),(sign*.23,-.12,.71),(sign*.35,-.12,.76),(sign*.42,-.09,.87)], .009, "Obsidian")
    line("Guard live inlay", [(sign*.17,-.125,.66),(sign*.24,-.125,.72),(sign*.34,-.125,.77)], .0045, "Runes")
ring("Guard medallion", 0,.66,.141,.025,"Gold",y=-.155)
jewel("Guard sapphire", 0,.66,.115,y=-.173)
for sign in (-1,1):
    plate("Gem prong", [(sign*.055,.57),(sign*.14,.71),(sign*.12,.76),(sign*.08,.65)], .06, "Silver",y=-.19)

# Split-spine blade, deliberately pierced with a long central void.
for sign in (-1, 1):
    pts = [(.047,.85),(.095,.91),(.16,1.06),(.18,1.48),(.15,2.15),(.105,2.83),(0,3.50),(.025,2.70),(.034,1.75)]
    plate("Crystal blade", [(sign*x,z) for x,z in pts], .065,"Crystal",bevel=.009)
    outline = [(.16,1.04),(.205,1.22),(.194,1.51),(.16,2.19),(.115,2.84),(0,3.50)]
    line("Hot cutting edge", [(sign*x,-.012,z) for x,z in outline], .011,"Edge")
    spine = [(.047,.86),(.057,1.32),(.05,2.10),(.035,2.72),(0,3.50)]
    line("Gilded spine", [(sign*x,-.071,z) for x,z in spine], .018,"Gold")
    # Pointed armored ribs articulate the blade without filling its silhouette.
    for z,w in ((1.0,.28),(1.41,.245),(1.83,.205)):
        plate("Blade crown", [(sign*.055,z+.10),(sign*w,z-.04),(sign*(w-.08),z+.17),(sign*.062,z+.27)], .055,"Gold",y=-.047,bevel=.004)
        line("Blade crown etching", [(sign*.065,-.083,z+.16),(sign*(w-.085),-.083,z+.09),(sign*(w-.052),-.075,z+.02)],.004,"Obsidian")
    # Flow channels/faceted etching run along the broad blade flats.
    for back in (-1, 1):
        line("Crystal channel", [(sign*.10,back*.044,1.32),(sign*.145,back*.044,1.65),(sign*.088,back*.044,2.0),(sign*.092,back*.044,2.46),(sign*.043,back*.044,2.94)], .006,"Runes")
        line("Crystal facet seam", [(sign*.18,back*.042,1.48),(sign*.115,back*.042,1.86),(sign*.145,back*.042,2.15)], .006,"Silver")

# Individual hollow glyphs, not a flat painted stripe.
for i in range(8):
    z = 1.02 + i*.235
    w = .037 if i < 5 else .027
    for back in (-1,1):
        y = back*.02
        line("Suspended rune", [(0,y,z+.060),(-w,y,z),(0,y,z-.060),(w,y,z),(0,y,z+.060)], .006,"Runes")
        line("Rune notch", [(0,y,z+.033),(w*.65,y,z),(0,y,z-.014)], .004,"Edge")

# Two floating satellite blades, kept as separate named animation pivots.
fins = []
for sign,label in ((-1,"L"),(1,"R")):
    pivot = empty("Fin_"+label,root)
    pivot.location = (sign*.50, 0, 1.23)
    pivot.rotation_euler.y = sign*-.17
    fins.append(pivot)
    plate("Fin shell", [(0,-.40),(-.12,-.08),(-.055,.16),(0,.55),(.085,.15),(.11,-.14)], .075,"Gold",pivot)
    plate("Fin crystal", [(0,-.32),(-.071,-.07),(-.025,.14),(0,.43),(.046,.13),(.061,-.1)], .06,"Crystal",pivot,y=-.065)
    line("Fin edge", [(0,-.107,-.32),(-.072,-.107,-.07),(-.025,-.107,.14),(0,-.105,.43)],.006,"Edge",pivot)
    ring("Fin boss",0,.025,.072,.014,"Silver",pivot,y=-.11)
    jewel("Fin jewel",0,.025,.042,"Runes",pivot,y=-.125)
    line("Fin filigree",[(0,-.12,.1),(.026,-.108,.18),(0,-.105,.32)],.005,"Gold",pivot)

# Join per material and animation pivot: geometry is detailed, draw count bounded.
for parent in [root]+fins:
    for mat in MATS.values():
        objects = [o for o in list(collection.objects) if o.parent == parent and o.type in {"MESH","CURVE"} and o.data.materials and o.data.materials[0] == mat]
        if not objects:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        bpy.ops.object.convert(target="MESH")
        if len(bpy.context.selected_objects) > 1:
            bpy.ops.object.join()
        joined = bpy.context.object
        joined.name = parent.name + "_" + mat.name

# Authoring animation is preserved in .blend; Godot owns the runtime state blend.
scene.frame_start,scene.frame_end = 1,120
scene.render.fps = 30
for i,fin in enumerate(fins):
    home = fin.location.copy()
    for frame,phase in ((1,0),(31,math.pi/2),(61,math.pi),(91,3*math.pi/2),(121,math.tau)):
        fin.location = home + Vector((math.sin(phase)*(.025 if i else -.025),0,math.sin(phase+i*math.pi)*.055))
        fin.keyframe_insert(data_path="location",frame=frame)
    if fin.animation_data:
        fin.animation_data.action.name = "AstralEdge_Idle_"+str(i)
scene.frame_set(1)

# Only export model objects, never the workshop camera or lights.
bpy.ops.object.select_all(action="DESELECT")
for obj in collection.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(filepath=str(OUT/"astral_edge.glb"),export_format="GLB",use_selection=True,use_active_scene=True,export_animations=False,export_apply=True,export_yup=True)

# A reusable high-quality workshop camera, for checking surfaces and silhouette.
def aim(obj, point):
    obj.rotation_euler = (Vector(point)-obj.location).to_track_quat("-Z","Y").to_euler()
camera_data = bpy.data.cameras.new("WorkshopCamera")
camera = bpy.data.objects.new("WorkshopCamera",camera_data)
scene.collection.objects.link(camera)
camera.location = (2.0,-9.0,2.35)
aim(camera,(0,0,1.65))
camera_data.type = "ORTHO"
camera_data.ortho_scale = 4.3
scene.camera = camera
for name,loc,color,power,size in (("Key",(1,-4,5),(1,.85,.66),600,4),("Rim",(-3,1,3),(.22,.60,1),800,3),("Fill",(3,-1,0),(.32,.62,1),300,3)):
    data=bpy.data.lights.new(name,"AREA")
    data.energy=power
    data.color=color
    data.shape="DISK"
    data.size=size
    obj=bpy.data.objects.new(name,data)
    scene.collection.objects.link(obj)
    obj.location=loc
    aim(obj,(0,0,1.6))
world=bpy.data.worlds.new("Midnight workshop")
world.use_nodes=True
world.node_tree.nodes["Background"].inputs[0].default_value=(.014,.022,.038,1)
world.node_tree.nodes["Background"].inputs[1].default_value=.35
scene.world=world
scene.render.engine="CYCLES"
scene.cycles.samples=24
scene.render.resolution_x=900
scene.render.resolution_y=1100
scene.render.resolution_percentage=100
scene.view_settings.view_transform="AgX"
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/"astral_edge.blend"))
triangles=sum(len(p.vertices)-2 for o in collection.objects if o.type=="MESH" for p in o.data.polygons)
print("ASTRAL_EDGE_EXPORTED",str(OUT/"astral_edge.glb"),"mesh_objects",sum(o.type=="MESH" for o in collection.objects),"triangles",triangles)
