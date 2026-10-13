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
var notice := "J 试刀  ·  K 释放裂环斩"
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
	notice = "J 试刀  ·  K 释放裂环斩"
	notice_left = 4.0

func hit(point: Vector3, lethal: bool, damage: int, heavy: bool) -> void:
	hit_glow = 1.0
	popups.append({"point": point + Vector3.UP * 2.2, "age": 0.0, "lethal": lethal, "damage": damage, "heavy": heavy})
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
	_center("骸 骨 守 卫", Vector2(center, 65), 18, INK)
	var bar := Rect2(center - 140, 82, 280, 5)
	draw_rect(bar, Color(0.04, 0.075, 0.085, 0.9))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * chip_hp, 5)), GOLD.darkened(0.25))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * displayed_hp, 5)), Color("d68965").lerp(INK, hit_glow * 0.4))
	for i in range(1, 4):
		draw_line(bar.position + Vector2(i * 70, 0), bar.position + Vector2(i * 70, 5), Color("17272e"), 2)
	_center("%03d  /  100" % arena.enemy.health, Vector2(center, 108), 12, MUTED)
	# Only the two implemented moves; no empty slots or unrelated systems.
	draw_line(Vector2(m, h - 137), Vector2(w - m, h - 137), Color(0.60, 0.65, 0.63, 0.2), 1)
	_key("W A S D", Vector2(m, h - 103), 91)
	_text("移动", Vector2(m + 106, h - 82), 16, INK)
	_text("方向键 / 左摇杆同样可用", Vector2(m, h - 47), 12, MUTED)
	var state := "就绪"
	var progress := 1.0
	if arena.player.attacking and not arena.player.using_skill:
		var t: float = arena.player.animation.current_animation_position
		state = "蓄势" if t < DuelFighter.SWING_START else ("挥斩" if t < DuelFighter.ACTIVE_END else "收势")
		progress = clampf(t / 0.60, 0, 1)
	var icon := Vector2(center - 270, h - 82)
	var diamond := PackedVector2Array([icon + Vector2(0, -29), icon + Vector2(29, 0), icon + Vector2(0, 29), icon + Vector2(-29, 0), icon + Vector2(0, -29)])
	draw_polyline(diamond, GOLD.lerp(INK, hit_glow), 1.3, true)
	draw_line(icon + Vector2(-9, 11), icon + Vector2(11, -12), INK, 3, true)
	draw_line(icon + Vector2(-10, 1), icon + Vector2(1, 11), GOLD, 2, true)
	draw_line(icon + Vector2(9, -12), icon + Vector2(13, -15), INK, 2, true)
	_text("横 斩", Vector2(center - 224, h - 88), 24, INK)
	_text("J / 左键 / 手柄 X", Vector2(center - 224, h - 62), 13, MUTED)
	_text(state, Vector2(center - 65, h - 88), 13, TEAL if state == "就绪" else GOLD)
	draw_rect(Rect2(center - 224, h - 45, 194, 2), Color("23343a"))
	draw_rect(Rect2(center - 224, h - 45, progress * 194, 2), GOLD if arena.player.attacking and not arena.player.using_skill else TEAL.darkened(0.3))
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
		p.y -= 20 + 54 * item.age
		var alpha := 1.0 - smoothstep(0.45, 0.85, item.age)
		var tint := Color(0.65, 0.97, 1.0, alpha) if item.heavy else Color(1.0, 0.84, 0.54, alpha)
		_center(str(item.damage), p, 38 if item.heavy else (33 if item.lethal else 29), tint, DISPLAY)
		if item.lethal or item.heavy:
			_center("击破" if item.lethal else "裂环斩", p + Vector2(0, 26), 15, tint)

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
	help.text = "WASD / 左摇杆  移动\nJ / 左键 / X  横斩    K / 右键 / RB  裂环斩\nR / 手柄 Y  重置    F11  全屏"
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
