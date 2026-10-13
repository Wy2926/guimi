extends Control

const INK := Color("eee6d6")
const MUTED := Color("91a3a7")
const GOLD := Color("d8ad71")
const TEAL := Color("7fc4c8")
const FONT = preload("res://assets/fonts/interface.tres")
const DISPLAY = preload("res://assets/fonts/display.tres")

@onready var arena: Node3D = get_parent().get_parent()
var displayed_hp := 1.0
var chip_hp := 1.0
var hit_glow := 0.0
var notice := "按住 J / 左键 连段  ·  G 切换厉鬼  ·  K 裂环斩"
var notice_left := 7.0
var popups: Array[Dictionary] = []
var pause_panel: Control
var pause_button: Button
var frame_select: OptionButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var vignette := ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vignette_material := ShaderMaterial.new()
	vignette_material.shader = preload("res://shaders/vignette.gdshader")
	vignette.material = vignette_material
	vignette.show_behind_parent = true
	add_child(vignette)
	move_child(vignette, 0)
	# Draw ornaments on top of the vignette, while native buttons handle pause input.
	_build_pause()

func _process(delta: float) -> void:
	if not get_tree().paused:
		displayed_hp = move_toward(displayed_hp, float(arena.enemy.health) / 100, delta * 4.0)
		chip_hp = move_toward(chip_hp, displayed_hp, delta * 0.55)
		hit_glow = maxf(0, hit_glow - delta * 3.0)
		notice_left = maxf(0, notice_left - delta)
		for item in popups:
			item.age += delta
		popups = popups.filter(func(item: Dictionary) -> bool: return item.age < 0.85)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not arena.ready_to_play:
		return
	if event.is_action_pressed("pause") and not event.is_echo():
		toggle_pause()
		get_viewport().set_input_as_handled()

func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	pause_panel.visible = get_tree().paused
	if get_tree().paused:
		pause_button.grab_focus()

func reset_hud() -> void:
	pause_panel.hide()
	popups.clear()
	displayed_hp = 1.0
	chip_hp = 1.0
	hit_glow = 0.0
	notice = "按住 J / 左键 连段  ·  G 切换厉鬼  ·  K 裂环斩"
	notice_left = 4.0

func hit(point: Vector3, lethal: bool, damage: int, heavy: bool, source: String = "") -> void:
	hit_glow = 1.0
	popups.append({"point": point + Vector3.UP * 2.2, "age": 0.0, "lethal": lethal, "damage": damage, "heavy": heavy, "source": source, "offset": float(popups.size() % 3 - 1) * 21.0 if source == "厉鬼" else 0.0})
	notice = "击破 · 守卫即将归位" if lethal else ""
	notice_left = 2.8 if lethal else 0.0

func _draw() -> void:
	if not is_instance_valid(arena) or not is_instance_valid(arena.player):
		return
	var w := size.x
	var h := size.y
	var m := 52.0
	# Header: editorial typography and a quiet copper rule.
	draw_line(Vector2(m, 46), Vector2(m + 24, 46), GOLD, 2)
	_text("近  战  习  作", Vector2(m + 35, 52), 13, MUTED)
	_text("烬 庭", Vector2(m - 2, 111), 47, INK)
	_text("E M B E R   Y A R D", Vector2(m, 141), 13, GOLD, DISPLAY)
	_right("试炼场  /  01", Vector2(w - m, 62), 19, INK)
	_right("一击之间，自有分量。", Vector2(w - m, 92), 14, MUTED)
	_right("COMBAT STUDY  ·  %d FPS" % arena.frame_limit, Vector2(w - m, 119), 11, GOLD, DISPLAY)
	var center := w / 2.0
	var guard_count: int = arena.guards.size()
	var living_guards := 0
	_center("骸 骨 守 卫 × %d" % guard_count, Vector2(center, 65), 18, INK)
	# One segment per guard makes the group state distinct from a single boss bar.
	var segment_width := (280.0 - maxf(guard_count - 1, 0) * 5.0) / maxf(guard_count, 1)
	for i in range(guard_count):
		var guard: DuelFighter = arena.guards[i]
		if guard.health > 0:
			living_guards += 1
		var hp := clampf(float(guard.health) / 100.0, 0.0, 1.0)
		var segment := Rect2(center - 140 + i * (segment_width + 5), 82, segment_width, 5)
		draw_rect(segment, Color(0.04, 0.075, 0.085, 0.9))
		draw_rect(Rect2(segment.position, Vector2(segment_width * hp, 5)), Color("d68965"))
		if guard.health <= 0 or guard.health >= 100:
			continue
		var marker: Vector3 = guard.global_position + Vector3.UP * 2.65
		if arena.camera.is_position_behind(marker):
			continue
		var marker_pos: Vector2 = arena.camera.unproject_position(marker) + Vector2(-26, -12)
		draw_rect(Rect2(marker_pos - Vector2(1, 1), Vector2(54, 5)), Color(0.025, 0.045, 0.058, 0.9))
		draw_rect(Rect2(marker_pos, Vector2(52 * hp, 3)), Color("d8ad71"))
	_center("存活 %02d / %02d" % [living_guards, guard_count], Vector2(center, 108), 12, MUTED)
	# Two compact stance rows share the original corner; no extra equipment bar.
	var ghost: bool = arena.player.ghost_active
	var ghost_pending: bool = arena.player.ghost_requested != ghost
	var combat_tint := Color("ff8cab") if ghost else GOLD
	var storm := arena.get("storm") as Node3D
	var storm_active := is_instance_valid(storm) and bool(storm.get("active"))
	var storm_tint := Color("a4edf3") if storm_active else MUTED
	var stance_card := Rect2(m, h - 285, 330, 134)
	draw_style_box(_panel_style(Color(0.115, 0.042, 0.078, 0.85) if ghost else Color(0.045, 0.09, 0.115, 0.82)), stance_card)
	_text("厉 鬼 解 放" if ghost else "常 态 连 斩", Vector2(m + 16, h - 260), 20, combat_tint)
	var ghost_control := "G / B 切换"
	if ghost_pending:
		ghost_control = "收势后解放" if arena.player.ghost_requested else "收势后复原"
	_right(ghost_control, Vector2(m + 310, h - 262), 12, combat_tint if ghost_pending else MUTED)
	var ghost_stats := "5 式 8 击 · 伤害 +%d%% · 攻速 +%d%%" % [roundi((arena.player.damage_multiplier - 1.0) * 100.0), roundi((arena.player.attack_speed - 1.0) * 100.0)]
	_text(ghost_stats if ghost else "3 式 3 击 · 按住普攻连续衔接", Vector2(m + 16, h - 239), 12, combat_tint if ghost else MUTED)
	draw_line(Vector2(m + 16, h - 225), Vector2(m + 314, h - 225), Color(0.60, 0.65, 0.63, 0.2), 1)
	var storm_icon := Vector2(m + 23, h - 205)
	for i in range(3):
		var offset := Vector2((i - 1) * 7, absf(i - 1) * 4)
		draw_line(storm_icon + offset + Vector2(0, -7), storm_icon + offset + Vector2(0, 9), storm_tint, 1.5, true)
		draw_line(storm_icon + offset + Vector2(-3, 4), storm_icon + offset + Vector2(3, 4), storm_tint, 1.2, true)
	_text("万 剑 归 宗", Vector2(m + 44, h - 200), 18, storm_tint)
	_right("已启" if storm_active else "收阵", Vector2(m + 310, h - 201), 13, storm_tint)
	_text("L / Y 收放  ·  攻击时群体追击", Vector2(m + 16, h - 181), 12, MUTED)
	_text("28% 引落流星", Vector2(m + 16, h - 163), 12, GOLD)
	if is_instance_valid(storm):
		_right("飞剑 %02d / 8" % int(storm.get("active_swords")), Vector2(m + 310, h - 163), 12, storm_tint)
	draw_line(Vector2(m, h - 137), Vector2(w - m, h - 137), Color(0.60, 0.65, 0.63, 0.2), 1)
	_key("W A S D", Vector2(m, h - 103), 91)
	_text("移动", Vector2(m + 106, h - 82), 16, INK)
	_text("方向键 / 左摇杆同样可用", Vector2(m, h - 47), 12, MUTED)
	var state := "就绪"
	var progress := 1.0
	var combo_playing: bool = arena.player.attacking and not arena.player.using_skill
	var combo_title := "厉鬼五连" if ghost else "普通三连"
	var combo_detail := "5 式 / 8 击" if ghost else "3 式 / 3 击"
	if combo_playing:
		state = arena.player.get_attack_phase()
		combo_title = arena.player.combo_label
		combo_detail = "%d / %d 式 · %d 段" % [arena.player.combo_index + 1, arena.player.combo_total, arena.player.strike_total]
		progress = clampf(arena.player.animation.current_animation_position / arena.player.move_duration, 0, 1)
		for strike in range(arena.player.strike_total):
			var segment_color := combat_tint if strike <= arena.player.strike_index else combat_tint.darkened(0.70)
			draw_rect(Rect2(center - 30 - (arena.player.strike_total - strike) * 11, h - 119, 7, 4), segment_color)
	_text(combo_detail, Vector2(center - 224, h - 111), 11, combat_tint)
	var icon := Vector2(center - 270, h - 82)
	var diamond := PackedVector2Array([icon + Vector2(0, -29), icon + Vector2(29, 0), icon + Vector2(0, 29), icon + Vector2(-29, 0), icon + Vector2(0, -29)])
	draw_polyline(diamond, combat_tint.lerp(INK, hit_glow), 1.3, true)
	draw_line(icon + Vector2(-9, 11), icon + Vector2(11, -12), INK, 3, true)
	draw_line(icon + Vector2(-10, 1), icon + Vector2(1, 11), combat_tint, 2, true)
	draw_line(icon + Vector2(9, -12), icon + Vector2(13, -15), INK, 2, true)
	_text(combo_title, Vector2(center - 224, h - 88), 24, INK)
	_text("按住 J / 左键 / X 连段", Vector2(center - 224, h - 62), 13, MUTED)
	_right(state, Vector2(center - 30, h - 88), 13, TEAL if state == "就绪" else combat_tint)
	draw_rect(Rect2(center - 224, h - 45, 194, 2), Color("23343a"))
	draw_rect(Rect2(center - 224, h - 45, progress * 194, 2), combat_tint if combo_playing else TEAL.darkened(0.3))
	var cooldown: float = arena.player.skill_cooldown
	var skill_tint := Color("9becf0") if cooldown <= 0 else TEAL.darkened(0.25)
	var skill_state := "就绪" if cooldown <= 0 else "%.1f s" % cooldown
	if arena.player.using_skill:
		var t: float = arena.player.animation.current_animation_position
		skill_state = "聚势" if t < DuelFighter.SKILL_SWING else ("裂环" if t < 0.66 else "收势")
		skill_tint = Color("bafcff")
	var skill_icon := Vector2(center + 65, h - 82)
	draw_arc(skill_icon, 26, -0.7, 2.4, 32, skill_tint, 2.0, true)
	draw_arc(skill_icon, 21, 2.5, 5.5, 32, skill_tint, 1.4, true)
	draw_line(skill_icon + Vector2(-13, 13), skill_icon + Vector2(12, -15), INK, 2.5, true)
	draw_line(skill_icon + Vector2(-6, 6), skill_icon + Vector2(10, 9), skill_tint, 1.5, true)
	_text("裂 环 斩", Vector2(center + 110, h - 88), 24, INK)
	_text("K / 右键 / 手柄 RB", Vector2(center + 110, h - 62), 13, MUTED)
	_right(skill_state, Vector2(center + 330, h - 88), 13, skill_tint)
	draw_rect(Rect2(center + 110, h - 45, 220, 2), Color("23343a"))
	draw_rect(Rect2(center + 110, h - 45, 220 * (1.0 - cooldown / DuelFighter.SKILL_COOLDOWN), 2), skill_tint)
	_right("%02d" % arena.hit_count, Vector2(w - m, h - 85), 30, INK, DISPLAY)
	_right("确认命中", Vector2(w - m - 56, h - 91), 13, MUTED)
	_right("R  重置     Esc  暂停", Vector2(w - m, h - 48), 14, MUTED)
	if notice_left > 0.0:
		_center(notice, Vector2(center, h - 163), 15, Color(0.87, 0.83, 0.72, minf(notice_left, 0.9)))
	for item in popups:
		var p: Vector2 = arena.camera.unproject_position(item.point)
		p.x += item.offset
		p.y -= 20 + 54 * item.age
		var alpha := 1.0 - smoothstep(0.45, 0.85, item.age)
		var flying_sword: bool = item.source == "飞剑"
		var meteor: bool = item.source == "流星"
		var ghost_hit: bool = item.source == "厉鬼"
		var tint := Color(0.65, 0.97, 1.0, alpha) if item.heavy else Color(1.0, 0.84, 0.54, alpha)
		if meteor:
			tint = Color(1.0, 0.75, 0.35, alpha)
		elif ghost_hit:
			tint = Color(1.0, 0.49, 0.66, alpha)
		var damage_size := 20 if flying_sword else (34 if meteor else (38 if item.heavy else (33 if item.lethal else 29)))
		_center(str(item.damage), p, damage_size, tint, DISPLAY)
		if item.lethal or meteor or (item.heavy and not flying_sword):
			var label := "击破" if item.lethal else ("流星" if meteor else ("厉鬼裂环" if ghost_hit else "裂环斩"))
			_center(label, p + Vector2(0, 19 if flying_sword else 26), 13 if flying_sword else 15, tint)

func _text(value: String, pos: Vector2, font_size: int, color: Color, font: Font = FONT) -> void:
	draw_string(font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _right(value: String, pos: Vector2, font_size: int, color: Color, font: Font = FONT) -> void:
	_text(value, pos - Vector2(font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, 0), font_size, color, font)

func _center(value: String, pos: Vector2, font_size: int, color: Color, font: Font = FONT) -> void:
	_text(value, pos - Vector2(font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5, 0), font_size, color, font)

func _key(value: String, pos: Vector2, width: float) -> void:
	draw_style_box(_panel_style(Color(0.075, 0.115, 0.135, 0.85)), Rect2(pos, Vector2(width, 29)))
	_center(value, pos + Vector2(width * 0.5, 20), 12, INK)

func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("536165")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.content_margin_left = 24
	style.content_margin_right = 24
	return style

func _build_pause() -> void:
	pause_panel = Control.new()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pause_panel)
	var background := ColorRect.new()
	background.color = Color(0.025, 0.045, 0.058, 0.94)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(370, 0)
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)
	var pause_theme := Theme.new()
	pause_theme.default_font = FONT
	pause_theme.default_font_size = 17
	column.theme = pause_theme
	var title := Label.new()
	title.text = "片刻休整"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "EMBER YARD  /  近战试炼"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = MUTED
	column.add_child(subtitle)
	pause_button = _button(column, "继续试炼", toggle_pause)
	_button(column, "重置场景", func() -> void: arena.restart())
	var frame_row := HBoxContainer.new()
	column.add_child(frame_row)
	var frame_label := Label.new()
	frame_label.text = "帧率上限"
	frame_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_row.add_child(frame_label)
	frame_select = OptionButton.new()
	frame_select.add_item("60 FPS", 60)
	frame_select.add_item("120 FPS", 120)
	frame_select.select(1)
	frame_select.custom_minimum_size.x = 150
	frame_select.item_selected.connect(func(index: int) -> void: arena.set_frame_limit(frame_select.get_item_id(index), true))
	frame_row.add_child(frame_select)
	var shake := CheckButton.new()
	shake.text = "镜头震动与冲击推近"
	shake.button_pressed = true
	shake.toggled.connect(func(enabled: bool) -> void: arena.shake_enabled = enabled)
	column.add_child(shake)
	var mute := CheckButton.new()
	mute.text = "静音"
	mute.toggled.connect(func(enabled: bool) -> void: AudioServer.set_bus_mute(0, enabled))
	column.add_child(mute)
	var help := Label.new()
	help.text = "WASD / 左摇杆  移动\n按住 J / 左键 / X  连段    K / 右键 / RB  裂环斩\nG / 手柄 B  厉鬼：五式八击 · 伤害与攻速提升\nL / 手柄 Y  收放万剑归宗 · 攻击时群体追击\n攻击有 28% 概率引落流星\nR  重置    F11  全屏"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 13)
	help.modulate = MUTED
	column.add_child(help)
	pause_panel.hide()

func sync_frame_limit(fps: int) -> void:
	if is_instance_valid(frame_select):
		frame_select.select(0 if fps == 60 else 1)

func _button(parent: Control, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.add_theme_stylebox_override("normal", _panel_style(Color("172a32")))
	button.add_theme_stylebox_override("hover", _panel_style(Color("29404a")))
	button.add_theme_stylebox_override("focus", _panel_style(Color("304951")))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("304951")))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
