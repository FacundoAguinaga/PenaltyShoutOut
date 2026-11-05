import bpy
import os
import sys
import json
from PIL import Image

PROJECT_ROOT = "/home/facundoa/Documentos/projects/PenaltyShoutOut"
ASSETS_DIR = os.path.join(PROJECT_ROOT, "assets/models/people")
ANIM_DIR = os.path.join(ASSETS_DIR, "3d")

# Uso: blender --background --python prepare_crowd_asset.py -- [ratio] [sufijo]
# Ej: HIGH (default):  -- 0.045 ""
#     LOW  (tribunas lejanas): -- 0.01 _low
# Genera crowd_vat{suf}.exr + crowd_anim_meta{suf}.json + crowd_spectator_mesh{suf}.glb
_argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DECIMATE_RATIO = float(_argv[0]) if len(_argv) > 0 else 0.045
SUFFIX = _argv[1] if len(_argv) > 1 else ""
VAT_PATH = os.path.join(ASSETS_DIR, f"crowd_vat{SUFFIX}.exr")
META_PATH = os.path.join(ASSETS_DIR, f"crowd_anim_meta{SUFFIX}.json")
GLB_PATH = os.path.join(ASSETS_DIR, f"crowd_spectator_mesh{SUFFIX}.glb")

def run():
    print("=== STARTING CROWD ASSET PREPARATION ===")
    
    # 1. Reset scene and import Cheering.fbx
    bpy.ops.wm.read_homefile(use_empty=True)
    cheering_path = os.path.join(ANIM_DIR, "Cheering.fbx")
    print(f"Importing base model: {cheering_path}")
    bpy.ops.import_scene.fbx(filepath=cheering_path)
    
    # 2. Extract and create combined texture atlas
    temp_dir = "/tmp/crowd_prep"
    os.makedirs(temp_dir, exist_ok=True)
    
    body_img = None
    hair_img = None
    for img in bpy.data.images:
        if "Ch42_1001_Diffuse" in img.filepath or (img.name == "file2" and img.size[0] >= 2048):
            body_img = img
        elif "Ch42_1002_Diffuse" in img.filepath or (img.name in ["file7", "file7.001", "file7.002"] and img.size[0] >= 1024):
            hair_img = img
            
    diffuse_atlas_path = os.path.join(ASSETS_DIR, "crowd_diffuse.png")
    if body_img and hair_img:
        temp_body = os.path.join(temp_dir, "body.png")
        temp_hair = os.path.join(temp_dir, "hair.png")
        body_img.filepath_raw = temp_body
        body_img.file_format = 'PNG'
        body_img.save()
        hair_img.filepath_raw = temp_hair
        hair_img.file_format = 'PNG'
        hair_img.save()
        
        # Combine using PIL: 1024x1024 total, 512x1024 each
        im_body = Image.open(temp_body).convert("RGBA").resize((512, 1024), Image.Resampling.LANCZOS)
        im_hair = Image.open(temp_hair).convert("RGBA").resize((512, 1024), Image.Resampling.LANCZOS)
        atlas = Image.new("RGBA", (1024, 1024))
        atlas.paste(im_body, (0, 0))
        atlas.paste(im_hair, (512, 0))
        atlas.save(diffuse_atlas_path, "PNG")
        print(f"Created combined diffuse atlas: {diffuse_atlas_path} (1024x1024)")
    else:
        print("Warning: could not find embedded textures, looking for existing ones...")
        
    # 3. Clean and prepare mesh parts
    # Delete eyelashes
    if "Ch42__Eyelashes" in bpy.data.objects:
        bpy.data.objects.remove(bpy.data.objects["Ch42__Eyelashes"], do_unlink=True)
        print("Removed Ch42__Eyelashes")
        
    # Remap UVs for atlas
    # Body parts: U range [0, 1] -> [0, 0.5]
    # Hair: U range [0, 1] -> [0.5, 1.0]
    for obj in bpy.data.objects:
        if obj.type == 'MESH':
            uv_layer = obj.data.uv_layers.active
            if not uv_layer:
                continue
            is_hair = "Hair" in obj.name
            for loop in uv_layer.data:
                if is_hair:
                    loop.uv.x = 0.5 + loop.uv.x * 0.5
                else:
                    loop.uv.x = loop.uv.x * 0.5
            print(f"Remapped UVs for {obj.name} (is_hair={is_hair})")
            
    # Join meshes
    mesh_objects = [o for o in bpy.data.objects if o.type == 'MESH']
    for o in mesh_objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objects[0]
    bpy.ops.object.join()
    
    spectator = bpy.context.active_object
    spectator.name = "CrowdSpectator"
    print(f"Unified mesh: {len(spectator.data.vertices)} vertices, {len(spectator.data.polygons)} polygons")
    
    # 4. Decimate to optimize polygon count
    arm_obj = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    
    # Temporarily remove armature modifier to decimate cleanly
    arm_mods = [m for m in spectator.modifiers if m.type == 'ARMATURE']
    for m in arm_mods:
        spectator.modifiers.remove(m)
        
    dec = spectator.modifiers.new("Decimate", 'DECIMATE')
    dec.ratio = DECIMATE_RATIO
    bpy.ops.object.modifier_apply(modifier=dec.name)
    num_verts = len(spectator.data.vertices)
    num_polys = len(spectator.data.polygons)
    print(f"Decimated mesh: {num_verts} vertices, {num_polys} polygons")
    
    # Create second UV map (UVMap_VAT) storing normalized vertex ID in X
    vat_uv = spectator.data.uv_layers.new(name="UVMap_VAT")
    for poly in spectator.data.polygons:
        for loop_idx in poly.loop_indices:
            v_idx = spectator.data.loops[loop_idx].vertex_index
            vat_uv.data[loop_idx].uv = ((v_idx + 0.5) / float(num_verts), 0.5)
            
    # Setup single material for Godot
    spectator.data.materials.clear()
    mat = bpy.data.materials.new(name="CrowdMaterial")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    tex_node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex_node.image = bpy.data.images.load(diffuse_atlas_path)
    mat.node_tree.links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
    spectator.data.materials.append(mat)
    
    # Re-attach Armature modifier
    arm_mod = spectator.modifiers.new("Armature", 'ARMATURE')
    arm_mod.object = arm_obj
    
    # 5. Define animations to bake
    animations = [
        {"id": 0, "name": "idle", "file": "Breathing Idle.fbx", "start": 1, "end": 60},
        {"id": 1, "name": "cheer", "file": "Cheering.fbx", "start": 1, "end": 88},
        {"id": 2, "name": "victory", "file": "Victory.fbx", "start": 1, "end": 90},
        {"id": 3, "name": "angry", "file": "Angry.fbx", "start": 1, "end": 90},
        {"id": 4, "name": "clap", "file": "Clapping.fbx", "start": 1, "end": 36},
        {"id": 5, "name": "sitting", "file": "Sitting.fbx", "start": 1, "end": 60},
        {"id": 6, "name": "sitting_clap", "file": "Sitting Clap.fbx", "start": 1, "end": 50},
    ]
    
    # Cache actions.
    # NOTA: los FBX de Mixamo vienen en Y-up (altura en Y, no en Z como
    # espera Blender). No rotamos nada: horneamos en Y-up directo y
    # exportamos el GLB con export_yup=False para que Godot (Y-up)
    # lo reciba parado. Ver mapeo en el bake.
    # bpy.data.actions[-1] NO es fiable (Blender ordena alfabeticamente):
    # detectamos la accion nueva por diferencia de sets.
    actions_map = {}
    for anim in animations:
        fbx_p = os.path.join(ANIM_DIR, anim["file"])
        if anim["file"] == "Cheering.fbx":
            actions_map[anim["name"]] = arm_obj.animation_data.action
        else:
            print(f"Loading action for {anim['name']} from {anim['file']}...")
            acts_before = set(a.name_full for a in bpy.data.actions)
            bpy.ops.import_scene.fbx(filepath=fbx_p)
            acts_after = [a for a in bpy.data.actions if a.name_full not in acts_before]
            if not acts_after:
                # Fallback: buscar por nombre de armature importado
                print(f"  WARNING: no se detecto accion nueva para {anim['name']}, usando ultima por nombre")
                new_action = sorted(bpy.data.actions, key=lambda a: a.name_full)[-1]
            else:
                # El import crea exactamente 1 accion nueva; si hay varias
                # quedarse con la primera (Blender 5.x usa layers, no fcurves).
                if len(acts_after) > 1:
                    print(f"  WARNING: {len(acts_after)} acciones nuevas, candidatos: {[a.name_full for a in acts_after]}")
                new_action = acts_after[0]
            print(f"  -> accion detectada: {new_action.name_full}")
            actions_map[anim["name"]] = new_action
            # Remove any imported extraneous objects
            for obj in list(bpy.context.scene.objects):
                if obj != spectator and obj != arm_obj:
                    bpy.data.objects.remove(obj, do_unlink=True)
                    
    # Calculate total frames and build metadata
    current_row = 0
    metadata = {
        "num_vertices": num_verts,
        "fps": 30.0,
        "scale": 0.01,
        "animations": {}
    }
    
    for anim in animations:
        count = anim["end"] - anim["start"] + 1
        metadata["animations"][anim["name"]] = {
            "id": anim["id"],
            "start_frame": current_row,
            "frame_count": count,
            "fps": 30.0,
            "loop": True
        }
        current_row += count
        
    total_frames = current_row
    metadata["total_frames"] = total_frames
    print(f"Total animation frames to bake: {total_frames} across {len(animations)} animations")
    
    # 6. Bake vertex positions to float array
    # Array shape: total_frames rows, num_verts columns, 4 channels (RGBA)
    pixels = [0.0] * (num_verts * total_frames * 4)
    
    scene = bpy.context.scene

    anim_row = 0
    for anim in animations:
        act = actions_map[anim["name"]]
        arm_obj.animation_data.action = act
        # Depsgraph fresco por animacion: reutilizar el mismo dg entre
        # acciones distintas evaluaba poses mezcladas (raiz del VAT de 8m).
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        start_f = anim["start"]
        end_f = anim["end"]
        print(f"Baking {anim['name']} (frames {start_f} to {end_f})...")
        a_minx, a_maxx = 1e9, -1e9
        a_miny, a_maxy = 1e9, -1e9
        a_minz, a_maxz = 1e9, -1e9

        for f in range(start_f, end_f + 1):
            scene.frame_set(f)
            dg.update()
            eval_obj = spectator.evaluated_get(dg)
            eval_mesh = eval_obj.to_mesh()
            
            # Row index in image: anim_row
            row_offset = anim_row * num_verts * 4
            for v_idx in range(num_verts):
                co = eval_mesh.vertices[v_idx].co
                # Transform to Godot coordinates:
                # Los FBX Mixamo vienen Y-up (altura en Y), igual que Godot.
                # Solo cm -> m (* 0.01), SIN swap de ejes.
                # El swap clasico (X,Z,-Y) es para Blender Z-up y aca
                # acostaba al muñeco (altura en -Z) y generaba el VAT
                # de 24m que se veia como triangulos/particulas.
                gx = co.x * 0.01
                gy = co.y * 0.01
                gz = co.z * 0.01
                
                px_offset = row_offset + v_idx * 4
                pixels[px_offset + 0] = gx
                pixels[px_offset + 1] = gy
                pixels[px_offset + 2] = gz
                pixels[px_offset + 3] = 1.0
                if gx < a_minx: a_minx = gx
                if gx > a_maxx: a_maxx = gx
                if gy < a_miny: a_miny = gy
                if gy > a_maxy: a_maxy = gy
                if gz < a_minz: a_minz = gz
                if gz > a_maxz: a_maxz = gz

            eval_obj.to_mesh_clear()
            anim_row += 1
        print(f"  -> {anim['name']} bounds X[{a_minx:.2f},{a_maxx:.2f}] Y[{a_miny:.2f},{a_maxy:.2f}] Z[{a_minz:.2f},{a_maxz:.2f}]")
        if a_maxx - a_minx > 3.0 or a_maxy - a_miny > 3.0 or a_maxz - a_minz > 3.0:
            print(f"  WARNING: {anim['name']} excede 3m, revisar root-motion/pesos")
            
    # 7. Save VAT EXR Image
    # NOTA: bpy.data.images.new().save() CORROMPE los floats en Blender 5.2
    # (verificado: setear R=-0.5 guarda R=0.0/-1.29/etc). Se escribe el EXR
    # directo con OpenEXR, bypasseando el image editor.
    exr_path = VAT_PATH
    print(f"Saving VAT image: {num_verts}x{total_frames} to {exr_path} (ratio={DECIMATE_RATIO})")
    try:
        import numpy as _np
        import OpenEXR as _OEXR
        import Imath as _Imath
        _arr = _np.array(pixels, dtype=_np.float32)
        _R = _arr[0::4].tobytes()
        _G = _arr[1::4].tobytes()
        _B = _arr[2::4].tobytes()
        _hdr = _OEXR.Header(num_verts, total_frames)
        _hdr['compression'] = _Imath.Compression(_Imath.Compression.NO_COMPRESSION)
        _hdr['channels'] = {
            'R': _Imath.Channel(_Imath.PixelType(_Imath.PixelType.FLOAT)),
            'G': _Imath.Channel(_Imath.PixelType(_Imath.PixelType.FLOAT)),
            'B': _Imath.Channel(_Imath.PixelType(_Imath.PixelType.FLOAT)),
        }
        _out = _OEXR.OutputFile(exr_path, _hdr)
        _out.writePixels({'R': _R, 'G': _G, 'B': _B})
        _out.close()
        print("VAT EXR saved via OpenEXR (direct, sin image.save)!")
    except Exception as e:
        print(f"WARNING: fallo guardado directo OpenEXR ({e}), usando bpy image.save como fallback")
        vat_image = bpy.data.images.new("CrowdVAT", width=num_verts, height=total_frames, float_buffer=True)
        vat_image.pixels.foreach_set(pixels)
        vat_image.filepath_raw = exr_path
        vat_image.file_format = 'OPEN_EXR'
        vat_image.save()
        print("VAT EXR saved via bpy (fallback, puede estar corrupto)!")
    
    # 8. Save JSON metadata
    json_path = META_PATH
    with open(json_path, "w") as f:
        json.dump(metadata, f, indent=2)
    print(f"Saved animation metadata: {json_path}")
    
    # 9. Export base spectator mesh to glTF (.glb)
    bpy.ops.object.select_all(action='DESELECT')
    spectator.select_set(True)
    bpy.context.view_layer.objects.active = spectator
    
    # Remove armature modifier for clean static base mesh export
    spectator.modifiers.remove(arm_mod)
    
    # Put in rest scale (FBX was 100x / cm)
    spectator.scale = (0.01, 0.01, 0.01)
    spectator.rotation_euler = (0, 0, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    
    glb_path = GLB_PATH
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        use_selection=True,
        export_format='GLB',
        export_materials='EXPORT',
        export_animations=False,
        export_skins=False,
        # La malla ya esta en Y-up (Mixamo). Con export_yup=True (default)
        # el exporter aplica (X,Z,-Y) y la acuesta (altura en -Z).
        # Con False la deja parada, como la espera Godot Y-up.
        export_yup=False,
    )
    print(f"Base mesh exported to {glb_path}")
    print("=== CROWD ASSET PREPARATION COMPLETE ===")

if __name__ == "__main__":
    run()
