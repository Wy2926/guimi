extends Node3D
## Standalone art review; never loads the arena or combat scripts.
## Space pauses. 1/2/3 select idle / charge / flight; A restores the loop.
## -- --capture saves GPU-rendered frames and a lightweight runtime report.
const SWORD = preload("res://assets/weapons/astral_edge/astral_edge.tscn")
const HIT = preload("res://assets/weapons/astral_edge/impact.tscn")
const UI_FONT = preload("res://assets/fonts/NotoSansSC.ttf")
var hero: Node3D
var swords: Array[Node3D] = []
var clock := 0.0
var paused := false
var forced := -1
var status: Label
var cycle_hit: Array[int] = [-1,-1,-1]
var capture_mode := false
var frame := 0
var captures: Array[String] = []
var fin_reference := Vector3.ZERO
var fin_moved := false
var max_trail_points := 0
var impact_count := 0
var max_draw_calls := 0
var max_nodes := 0
var record_frames := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_title("ASTRAL EDGE / 光剑设计样板")
	Engine.max_fps = 60
	capture_mode = "--capture" in OS.get_cmdline_user_args()
	record_frames = "--record-frames" in OS.get_cmdline_user_args()
	_setup_lighting()
	_setup_ui()
	hero = SWORD.instantiate()
	hero.process_mode = Node.PROCESS_MODE_PAUSABLE
	hero.position = Vector3(-3.0,0.28,0)
	hero.rotation.z = -0.17
	add_child(hero)
	fin_reference = hero.fins[0].position
	for i in 3:
		var sword := SWORD.instantiate()
		sword.process_mode = Node.PROCESS_MODE_PAUSABLE
		sword.scale = Vector3.ONE*0.36
		sword.phase = i*1.8
		add_child(sword)
		swords.append(sword)
	if capture_mode:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/astral-edge"))
	if record_frames:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/astral-edge/frames"))

func _setup_lighting() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("080e19")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("869ab6")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.52
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.35
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.4
	camera.position = Vector3(0,3.5,12)
	add_child(camera)
	camera.look_at(Vector3(0,2.0,0))
	for i in 2:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-35,-35 if i == 0 else 145,0)
		light.light_color = Color("ffe3b4") if i == 0 else Color("478fe3")
		light.light_energy = 1.4 if i == 0 else 0.8
		add_child(light)
	# A restrained ground ring keeps the hovering sword grounded in space.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.87
	torus.outer_radius = 0.881
	torus.rings = 64
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position = Vector3(-2.78,0.04,0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("214e71")
	ring.material_override = mat
	add_child(ring)

func _label(parent: Control, text_value: String, pos: Vector2, size_value: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = pos
	var font := FontVariation.new()
	font.base_font = UI_FONT
	font.variation_embolden = 0.6
	label.add_theme_font_override("font",font)
	label.add_theme_font_size_override("font_size",size_value)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var control := Control.new()
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(control)
	_label(control,"EMBER YARD   /   WEAPON ATELIER",Vector2(70,45),17,Color("68859c"))
	_label(control,"苍穹 · 裂星",Vector2(70,81),43,Color("e6eff8"))
	_label(control,"ASTRAL EDGE     01",Vector2(74,145),19,Color("bca776"))
	_label(control,"独立光剑样板  ·  原创剑型 / 悬空铭文 / 双生副刃",Vector2(72,192),17,Color("7892aa"))
	_label(control,"01  /  FORM & MATERIAL",Vector2(95,830),17,Color("6c94ab"))
	_label(control,"流动晶刃   ·   金属镂空   ·   呼吸悬浮",Vector2(95,864),22,Color("c0d8e7"))
	_label(control,"02  /  MOTION STUDY",Vector2(835,280),17,Color("6c94ab"))
	status = _label(control,"待机 · 灵刃蓄能",Vector2(835,325),26,Color("d9e7f0"))
	_label(control,"出阵 → 交错穿刺 → 碎光爆点 → 回旋归位",Vector2(835,775),19,Color("b5cddd"))
	_label(control,"SPACE 暂停    1 待机    2 蓄能    3 出击    A 自动",Vector2(72,925),17,Color("698399"))
	_label(control,"VISUAL PROTOTYPE  /  未修改战斗逻辑",Vector2(1070,925),15,Color("557085"))

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey:
		match event.physical_keycode:
			KEY_SPACE:
				paused = not paused
				get_tree().paused = paused
			KEY_1: forced = 0
			KEY_2: forced = 1
			KEY_3: forced = 2
			KEY_A: forced = -1
			KEY_ESCAPE: get_tree().quit()

func _process(delta: float) -> void:
	if paused:
		return
	clock += delta
	frame += 1
	var cycle := fmod(clock,7.0)
	var stage := forced if forced >= 0 else (0 if cycle<2.0 else (1 if cycle<2.55 else (2 if cycle<4.4 else 3)))
	status.text = ["待机 · 灵刃蓄能","蓄势 · 铭文唤醒","出击 · 交错穿刺","归位 · 剑光收束"][stage]
	hero.set_motion(stage)
	hero.rotation.y = sin(clock*0.35)*0.20
	for i in swords.size():
		var sword := swords[i]
		var home := Vector3(0.4+i*0.8,0.8+i*0.18,0)
		var local := fmod(maxf(0,cycle-2.55-i*0.18),1.4)
		if stage < 2:
			sword.position = home
			sword.rotation = Vector3(0,0,-0.15+i*0.13)
			sword.set_motion(stage)
		elif stage == 2:
			var ratio := local/1.4
			var angle := -PI/2.0 + sin(ratio*PI)*0.25
			sword.rotation = Vector3(0,0,angle)
			sword.position = Vector3(lerpf(0.0,4.0,ratio),1.0+i*0.25+sin(ratio*TAU+i*1.6)*0.35,i*0.13)
			sword.set_motion(2)
			var hit_key := int(floor((clock-2.55-i*0.18)/1.4))
			if ratio>0.68 and cycle_hit[i] != hit_key:
				cycle_hit[i] = hit_key
				var hit := HIT.instantiate()
				hit.process_mode = Node.PROCESS_MODE_PAUSABLE
				add_child(hit)
				hit.position = sword.to_global(Vector3(0,3.1,0))
				impact_count += 1
		else:
			sword.set_motion(3)
			sword.position = sword.position.lerp(home,1.0-exp(-delta*3.0))
			sword.rotation.z = lerp_angle(sword.rotation.z,-0.15+i*0.13,1.0-exp(-delta*4.0))
		max_trail_points = maxi(max_trail_points,sword.history.size())
	fin_moved = fin_moved or hero.fins[0].position.distance_to(fin_reference)>0.01
	max_draw_calls = maxi(max_draw_calls,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	max_nodes = maxi(max_nodes,int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	if capture_mode:
		if frame in [75,143,222,330]:
			_capture.call_deferred(["idle","charge","flight","return"][[75,143,222,330].find(frame)])
		if frame == 435:
			_finish_capture.call_deferred()
	if record_frames and frame%2 == 0 and frame <= 420:
		_capture.call_deferred("frames/%04d" % (frame >> 1))

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://artifacts/astral-edge/%s.png" % label
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error == OK and not label.begins_with("frames/"):
		captures.append(path)
	elif error != OK:
		push_error("Capture failed: " + path)

func _finish_capture() -> void:
	var report := {"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"captures":captures,"fin_animation_observed":fin_moved,"impact_count":impact_count,"max_trail_points":max_trail_points,"max_draw_calls":max_draw_calls,"max_nodes":max_nodes,"combat_scripts_loaded":false}
	var file := FileAccess.open("res://artifacts/astral-edge/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("ASTRAL_EDGE_REVIEW ",JSON.stringify(report))
	get_tree().quit(0 if fin_moved and impact_count>0 and max_trail_points>2 and captures.size()==4 else 1)
