"""Render a 3D icon (GLB/GLTF/FBX/OBJ/BLEND) to a transparent square PNG.

Called by prepare_symbols.py:
  blender -b --factory-startup -P tool/assets/blender_render.py -- <input> <output.png> <size>

Front orthographic camera framed on the model's bounds, soft three-point
lighting, transparent film. Materials and colours come from the source file.
Uses Cycles on the CPU so it works headless.
"""

import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
source, output, size = args[0], args[1], int(args[2])

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
ext = source.lower().rsplit(".", 1)[-1]
if ext in ("glb", "gltf"):
    bpy.ops.import_scene.gltf(filepath=source)
elif ext == "fbx":
    bpy.ops.import_scene.fbx(filepath=source)
elif ext == "obj":
    bpy.ops.wm.obj_import(filepath=source)
elif ext == "blend":
    with bpy.data.libraries.load(source, link=False) as (data_from, data_to):
        data_to.objects = data_from.objects
    for obj in data_to.objects:
        if obj is not None and obj.type not in ("CAMERA", "LIGHT"):
            scene.collection.objects.link(obj)
else:
    raise SystemExit(f"unsupported 3D format: {ext}")

meshes = [o for o in scene.objects if o.type == "MESH"]
if not meshes:
    raise SystemExit("no mesh found in source")
corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
low = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
high = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
center = (low + high) / 2
extent = high - low

# Front view: camera on -Y looking at +Y, Z up.
camera_data = bpy.data.cameras.new("IconCamera")
camera_data.type = "ORTHO"
camera_data.ortho_scale = max(extent.x, extent.z) * 1.15
camera = bpy.data.objects.new("IconCamera", camera_data)
camera.location = center + Vector((0, -max(extent.length, 1) * 3, 0))
camera.rotation_euler = (1.5707963, 0, 0)
scene.collection.objects.link(camera)
scene.camera = camera
camera_data.clip_end = max(extent.length, 1) * 10


def add_light(name, kind, energy, rotation, location=(0, 0, 0)):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    light = bpy.data.objects.new(name, data)
    light.rotation_euler = rotation
    light.location = center + Vector(location)
    scene.collection.objects.link(light)


add_light("Key", "SUN", 2.4, (0.9, 0.0, -0.6))
add_light("Fill", "SUN", 0.8, (1.2, 0.0, 0.8))
add_light("Rim", "SUN", 1.0, (-0.6, 0.0, 3.1))

world = bpy.data.worlds.new("IconWorld")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[1].default_value = 0.35
scene.world = world

# Standard view transform keeps the source colours (AgX/Filmic desaturate).
scene.view_settings.view_transform = "Standard"
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 64
scene.render.film_transparent = True
scene.render.resolution_x = size
scene.render.resolution_y = size
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.filepath = output
bpy.ops.render.render(write_still=True)
