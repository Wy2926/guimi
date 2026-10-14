extends Control
## Presentation only: the run owns pause, upgrades, and restart transitions.

signal pause_requested
signal restart_requested
signal upgrade_selected(index: int)
signal frame_limit_requested(fps: int)
signal shake_changed(enabled: bool)

const INK := Color("eee7d7")
const MUTED := Color("9aabb0")
const GOLD := Color("e4b76d")
const TEAL := Color("80d6cf")
const RED := Color("df7772")
const FONT = preload("res://assets/fonts/interface.tres")
const DISPLAY = preload("res://assets/fonts/display.tres")
const MAX_POPUPS := 40
const POPUP_LIFETIME := 0.72

var arena: Node
var popups: Array[Dictionary] = []
var notice := ""
var notice_left := 0.0
var pause_panel: Control
var pause_button: Button
var frame_select: OptionButton
var choice_panel: Control
var result_panel: Control

var _base: MarginContainer
var _health: ProgressBar
var _health_text: Label
var _level: Label
var _experience: ProgressBar
var _experience_text: Label
var _time_label: Label
var _phase: Label
var _counts: Label
var _boss_panel: PanelContainer
var _boss_health: ProgressBar
var _boss_text: Label
var _skill_row: HBoxContainer
var _skill_widgets: Dictionary = {}
var _build_summary: Label
var _notice_label: Label
var _hint: Label
var _shake: CheckButton
var _mute: CheckButton
var _stat_text: Label
var _choice_box: PanelContainer
var _choice_title: Label
var _choice_subtitle: Label
var _choice_buttons: Array[Button] = []
var _choice_labels: Array[Dictionary] = []
var _choice_count := 0
var _choice_submitted := false
var _result_title: Label
var _result_description: Label
var _result_summary: Label
var _result_button: Button
var _refresh_left := 0.0
var _popup_sequence := 0


func setup(run: Node) -> void:
	arena = run
	if is_node_ready():
		sync_frame_limit(int(arena.frame_limit))
		_shake.set_pressed_no_signal(bool(arena.shake_enabled))
		_refresh()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	ui_theme.default_font = FONT
	ui_theme.default_font_size = 16
	ui_theme.set_color("font_color", "Label", INK)
	theme = ui_theme
	_build_gameplay()
	_build_pause()
	_build_choices()
	_build_result()
	resized.connect(_fit_layout)
	_fit_layout()
	if is_instance_valid(arena):
		setup(arena)


func _process(delta: float) -> void:
	if not is_instance_valid(arena):
		return
	if arena.state == "playing":
		for item in popups:
			item.age += delta
		popups = popups.filter(func(item: Dictionary) -> bool: return item.age < POPUP_LIFETIME)
		notice_left = maxf(0.0, notice_left - delta)
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.08
		_refresh()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(arena) or event.is_echo():
		return
	var state: String = arena.state
	if event.is_action_pressed("pause") and state in ["playing", "paused"]:
		get_viewport().set_input_as_handled()
		pause_requested.emit()
	elif event.is_action_pressed("restart") and state in ["paused", "won", "lost"]:
		get_viewport().set_input_as_handled()
		restart_requested.emit()
	elif state == "choosing" and event is InputEventKey and event.pressed:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key >= KEY_1 and key <= KEY_3:
			get_viewport().set_input_as_handled()
			_choose(key - KEY_1)


func _refresh() -> void:
	if not is_instance_valid(arena) or not is_instance_valid(arena.player) or not is_instance_valid(arena.progression):
		return
	var player = arena.player
	var progression = arena.progression
	var stats = player.stats
	_health.max_value = maxf(1.0, float(stats.max_health))
	_health.value = float(player.health)
	_health_text.text = "%d / %d" % [ceili(player.health), roundi(stats.max_health)]
	_level.text = "Lv.%02d" % int(progression.level)
	_experience.max_value = maxi(1, int(progression.xp_required()))
	_experience.value = float(progression.xp)
	_experience_text.text = "经验  %d / %d" % [int(progression.xp), int(_experience.max_value)]
	if is_instance_valid(arena.director):
		_time_label.text = ("%s · 试炼" % _clock(arena.director.elapsed)) if arena.director.combat_demo else "%s / %s" % [_clock(arena.director.elapsed), _clock(arena.director.duration)]
		_phase.text = str(arena.director.phase_name)
		_counts.text = "击杀 %d  ·  场上 %d" % [arena.defeat_count, arena.director.get_alive_count()]
	_update_divinity()
	_update_skill("swords", 0.0, false, 0.0)
	_update_skill("meteor", float(arena.storm.meteor_cooldown), false, 0.0)
	var orb_cooldown: float = float(arena.orbs.cooldown_left) if is_instance_valid(arena.orbs) else 0.0
	_update_skill("thunder_orb", orb_cooldown, false, 0.0)
	var aura_cooldown: float = float(arena.aura.cooldown_left) if is_instance_valid(arena.aura) else 0.0
	_update_skill("taiji_aura", aura_cooldown, false, 0.0)
	_update_skill("huntian_ling", float(arena.storm.ribbon_cooldown), not arena.storm.ribbon.is_empty(), 0.0)
	_build_summary.text = "天命：%s  ·  进化：%s" % [_owned_titles(progression.fate_definitions, progression.fates), _owned_titles(progression.evolution_definitions, progression.evolutions)]
	var boss = arena.boss
	_boss_panel.visible = is_instance_valid(boss) and not boss.dead
	if _boss_panel.visible:
		_boss_health.max_value = maxf(1.0, float(boss.stats.max_health))
		_boss_health.value = float(boss.health)
		_boss_text.text = "终局首领    %d / %d" % [ceili(boss.health), roundi(boss.stats.max_health)]
	_notice_label.text = notice if notice_left > 0.0 else ""
	if pause_panel.visible:
		_update_stats(stats)
	if choice_panel.visible:
		_update_choice_heading()


func _update_divinity() -> void:
	var definition: SkillDefinition = arena.progression.divinity
	var widgets: Dictionary = _skill_widgets["divinity"]
	if definition == null:
		widgets.title.text = "未选人物神通"
		widgets.status.text = ""
		widgets.bar.value = 0.0
		return
	widgets.title.text = definition.title.get_slice("·", 1)
	widgets.title.tooltip_text = definition.title + "\n" + definition.description
	widgets.binding.text = "常驻被动"
	widgets.status.text = "飞剑+1 · 绫链+1"
	widgets.status.tooltip_text = "仅强化已领悟的诛仙剑阵与混天绫，不解锁法宝或改变近战。"
	var active: bool = definition.id == "nezha"
	widgets.status.add_theme_color_override("font_color", GOLD if active else MUTED)
	widgets.bar.value = 1.0 if active else 0.0


func _owned_titles(definitions: Array[SkillDefinition], owned: Dictionary) -> String:
	var titles := PackedStringArray()
	for definition: SkillDefinition in definitions:
		if int(owned.get(definition.id, 0)) > 0:
			titles.append(definition.title)
	return "、".join(titles) if not titles.is_empty() else "未领悟"


func _update_skill(id: String, cooldown: float, active: bool, _remaining: float) -> void:
	var widgets: Dictionary = _skill_widgets[id]
	var level: int = arena.progression.skill_level(id)
	var definition = arena.progression.skill(id)
	var count: int = arena.progression.artifact_count(id)
	var title: Label = widgets.title
	var status: Label = widgets.status
	var bar: ProgressBar = widgets.bar
	var title_text: String = definition.title.get_slice("·", 1)
	title.text = "%s  Lv.%d" % [title_text, level]
	title.tooltip_text = definition.title + "\n" + definition.description
	widgets.binding.text = arena.progression.signature(definition)
	widgets.binding.tooltip_text = "法宝固有属性与异常，不继承人物附魔。"
	title.add_theme_color_override("font_color", INK if level > 0 else MUTED)
	if level <= 0:
		status.text = "升级时可领悟"
		status.add_theme_color_override("font_color", MUTED)
		bar.value = 0.0
	elif id == "swords":
		status.text = "%d 柄 · 束缚贯阵" % count if arena.progression.has_evolution("swords_pierce") else "%d 柄 · 绕行突刺" % count
		status.add_theme_color_override("font_color", TEAL)
		bar.value = 1.0
	elif id == "meteor":
		status.text = "祭印就绪" if cooldown <= 0.0 else "祭印 · %.1f秒" % cooldown
		status.add_theme_color_override("font_color", TEAL if cooldown <= 0.0 else MUTED)
		bar.value = clampf(1.0 - cooldown / maxf(0.1, float(definition.cooldown) * float(arena.player.stats.cooldown_multiplier)), 0.0, 1.0)
	elif id == "thunder_orb":
		status.text = "%d 颗 · 自动索敌" % count if cooldown <= 0.0 else "%d 颗 · %.1f 秒后投射" % [count, cooldown]
		status.add_theme_color_override("font_color", TEAL if cooldown <= 0.0 else MUTED)
		bar.value = clampf(1.0 - cooldown / maxf(0.1, float(definition.cooldown) * float(arena.player.stats.cooldown_multiplier)), 0.0, 1.0)
	elif id == "taiji_aura":
		status.text = "半径 %.1f米 · %.1f秒" % [float(arena.aura.radius), cooldown]
		status.add_theme_color_override("font_color", TEAL)
		bar.value = clampf(1.0 - cooldown / maxf(0.1, float(definition.cooldown) * float(arena.player.stats.cooldown_multiplier)), 0.0, 1.0)
	elif id == "huntian_ling":
		if active:
			var round_count: int = int(arena.storm.ribbon.remaining) + arena.storm.ribbon.visited.size()
			status.text = "本轮%d · 下轮%d" % [round_count, count] if round_count != count else "%d 连锁 · 穿梭中" % round_count
		else:
			status.text = "%d 连锁 · 就绪" % count if cooldown <= 0.0 else "%d 连锁 · %.1f 秒" % [count, cooldown]
		status.mouse_filter = Control.MOUSE_FILTER_PASS
		status.tooltip_text = "本轮连锁容量在施放时确定；升级后的数量从下一轮生效。" if active else ""
		status.add_theme_color_override("font_color", GOLD if active else TEAL)
		bar.value = clampf(1.0 - cooldown / maxf(0.1, float(definition.cooldown) * float(arena.player.stats.cooldown_multiplier)), 0.0, 1.0)


func _update_stats(stats: Resource) -> void:
	_stat_text.text = "物理攻击    %.0f\n魔法攻击    %.0f\n独立攻击    %.0f\n暴击率    %.0f%%    暴伤    %.0f%%\n闪避率    %.0f%%    吸血    %.1f%%\n移动速度    %.1f\n物理防御    %.0f    魔法防御    %.0f\n火 / 冰 / 光 / 暗抗性\n%.0f%% / %.0f%% / %.0f%% / %.0f%%\n攻击属性与异常由法宝自带。\n天命：%s\n进化：%s" % [
		stats.physical_attack, stats.magic_attack, stats.independent_attack,
		stats.crit_chance * 100.0, stats.crit_multiplier * 100.0,
		stats.dodge_chance * 100.0, stats.life_steal * 100.0, stats.move_speed,
		stats.physical_defense, stats.magic_defense,
		stats.resistances[0] * 100.0, stats.resistances[1] * 100.0,
		stats.resistances[2] * 100.0, stats.resistances[3] * 100.0,
		_owned_titles(arena.progression.fate_definitions, arena.progression.fates),
		_owned_titles(arena.progression.evolution_definitions, arena.progression.evolutions),
	]


func show_pause(value: bool) -> void:
	pause_panel.visible = value
	if value:
		choice_panel.hide()
		result_panel.hide()
		_shake.set_pressed_no_signal(bool(arena.shake_enabled))
		_mute.set_pressed_no_signal(AudioServer.is_bus_mute(0))
		_refresh()
		pause_button.grab_focus()
	else:
		_release_focus()


func show_choices(options: Array[Dictionary]) -> void:
	pause_panel.hide()
	result_panel.hide()
	choice_panel.show()
	_choice_count = mini(3, options.size())
	_choice_submitted = false
	_update_choice_heading()
	for i in _choice_buttons.size():
		var button := _choice_buttons[i]
		button.visible = i < _choice_count
		button.disabled = i >= _choice_count
		if i >= _choice_count:
			continue
		var option: Dictionary = options[i]
		var labels: Dictionary = _choice_labels[i]
		var category := str(option.get("category", "stat"))
		var category_title: String = {"skill": "法宝领悟", "fate": "天命词条", "evolution": "终极进化"}.get(category, "基础修行")
		labels.category.text = "%02d  /  %s" % [i + 1, category_title]
		labels.category.add_theme_color_override("font_color", TEAL if category == "skill" else GOLD)
		labels.title.text = str(option.get("title", "成长"))
		labels.description.text = str(option.get("description", ""))
		button.tooltip_text = "%s\n%s" % [labels.title.text, labels.description.text]
		button.focus_neighbor_left = button.get_path_to(_choice_buttons[(i + _choice_count - 1) % _choice_count])
		button.focus_neighbor_right = button.get_path_to(_choice_buttons[(i + 1) % _choice_count])
		button.focus_previous = button.focus_neighbor_left
		button.focus_next = button.focus_neighbor_right
	if _choice_count > 0:
		_choice_buttons[0].grab_focus()


func _update_choice_heading() -> void:
	_choice_title.text = "破境 · 三选一"
	_choice_subtitle.text = "Lv.%d  选择本局成长，组合你的神通与法宝" % int(arena.progression.level)
	if int(arena.progression.pending_levels) > 1:
		_choice_subtitle.text += "  ·  尚有 %d 次选择" % int(arena.progression.pending_levels)


func _choose(index: int) -> void:
	if not is_instance_valid(arena) or arena.state != "choosing" or _choice_submitted or index < 0 or index >= _choice_count:
		return
	_choice_submitted = true
	for button in _choice_buttons:
		button.disabled = true
	choice_panel.hide()
	_release_focus()
	upgrade_selected.emit(index)


func show_result(won: bool) -> void:
	pause_panel.hide()
	choice_panel.hide()
	result_panel.show()
	_result_title.text = "破阵而归" if won else "剑意未熄"
	_result_title.add_theme_color_override("font_color", GOLD if won else INK)
	_result_description.text = "首领已倒下，这一战属于你。" if won else "此番止步，下一局再问剑。"
	_result_summary.text = "存活时间  %s\n击败敌人  %d\n最终等级  Lv.%d" % [_clock(arena.director.elapsed), arena.defeat_count, arena.progression.level]
	_result_button.grab_focus()


func reset_hud() -> void:
	popups.clear()
	_popup_sequence = 0
	notice = ""
	notice_left = 0.0
	_choice_submitted = false
	pause_panel.hide()
	choice_panel.hide()
	result_panel.hide()
	_release_focus()
	_refresh_left = 0.0
	queue_redraw()


func sync_frame_limit(fps: int) -> void:
	if is_instance_valid(frame_select):
		frame_select.select(0 if fps == 60 else 1)


func hit(point: Vector3, lethal: bool, damage: int, heavy: bool, source: String = "") -> void:
	if popups.size() >= MAX_POPUPS:
		popups.pop_front()
	_popup_sequence += 1
	popups.append({"point": point + Vector3.UP * 1.7, "age": 0.0, "lethal": lethal, "damage": damage, "heavy": heavy, "source": source, "offset": float(_popup_sequence % 5 - 2) * 9.0})


func _draw() -> void:
	if not is_instance_valid(arena) or not is_instance_valid(arena.camera):
		return
	for item in popups:
		if arena.camera.is_position_behind(item.point):
			continue
		var point: Vector2 = arena.camera.unproject_position(item.point)
		point += Vector2(item.offset, -40.0 * item.age)
		if not Rect2(Vector2.ZERO, size).grow(30.0).has_point(point):
			continue
		var alpha := 1.0 - smoothstep(0.32, POPUP_LIFETIME, float(item.age))
		var color := GOLD if item.lethal else (TEAL if item.heavy else INK)
		if item.source in ["受伤", "敌人"]:
			color = RED
		color.a = alpha
		var font_size := 25 if item.lethal else (23 if item.heavy else 19)
		var value := str(item.damage)
		var font: Font = DISPLAY
		if item.source == "闪避":
			value = "闪避"
			font = FONT
			font_size = 16
		var position_2d := point - Vector2(font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5, 0)
		draw_string_outline(font, position_2d, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0.025, 0.04, 0.05, alpha * 0.9))
		draw_string(font, position_2d, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _build_gameplay() -> void:
	_base = MarginContainer.new()
	_base.name = "GameplayHUD"
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_base)
	_base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := _column(_base, 8)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 10)
	column.add_child(top)
	var vitals := _panel(top)
	vitals.custom_minimum_size.x = 252
	var vitals_column := _column(vitals, 4)
	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals_column.add_child(title_row)
	_label(title_row, "哪 吒", 21, GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level = _label(title_row, "Lv.01", 17, INK)
	_health = _bar(vitals_column, RED, 8)
	_health_text = _label(vitals_column, "100 / 100", 12, MUTED)
	_experience = _bar(vitals_column, TEAL, 4)
	_experience_text = _label(vitals_column, "经验  0 / 1", 11, MUTED)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var run_panel := _panel(top)
	run_panel.custom_minimum_size.x = 210
	run_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var run_column := _column(run_panel, 4)
	_time_label = _label(run_column, "00:00 / 10:00", 22, INK)
	_time_label.add_theme_font_override("font", DISPLAY)
	_phase = _label(run_column, "余烬初醒", 14, GOLD)
	_counts = _label(run_column, "击杀 0  ·  场上 0", 12, MUTED)
	var pause_control := _button(top, "暂停\nEsc", func() -> void: pause_requested.emit())
	pause_control.custom_minimum_size = Vector2(60, 54)
	pause_control.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pause_control.focus_mode = Control.FOCUS_NONE
	var boss_center := CenterContainer.new()
	boss_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(boss_center)
	_boss_panel = _panel(boss_center)
	_boss_panel.custom_minimum_size.x = 410
	var boss_column := _column(_boss_panel, 4)
	_boss_text = _label(boss_column, "终局首领", 13, RED, HORIZONTAL_ALIGNMENT_CENTER)
	_boss_health = _bar(boss_column, RED, 6)
	_boss_panel.hide()
	var space := Control.new()
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(space)
	_notice_label = _label(column, "", 15, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var skill_center := CenterContainer.new()
	skill_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(skill_center)
	_skill_row = HBoxContainer.new()
	_skill_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_row.add_theme_constant_override("separation", 8)
	skill_center.add_child(_skill_row)
	_make_skill("divinity", "三头八臂", "常驻被动")
	_make_skill("swords", "诛仙剑阵", "无属性 · 出血")
	_make_skill("huntian_ling", "混天绫", "无属性 · 束缚")
	_make_skill("meteor", "照天印", "火 · 灼烧")
	_make_skill("thunder_orb", "定海珠", "暗 · 诅咒")
	_make_skill("taiji_aura", "太极图", "光 · 感电")
	_build_summary = _label(column, "", 12, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_build_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint = _label(column, "WASD / 左摇杆移动  ·  自动攻击  ·  击杀拾取经验，升级选择成长", 12, MUTED, HORIZONTAL_ALIGNMENT_CENTER)


func _make_skill(id: String, title: String, key: String) -> void:
	var panel := _panel(_skill_row)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := _column(panel, 3)
	var key_label := _label(column, key, 11, MUTED)
	key_label.name = "Binding"
	var title_label := _label(column, title, 16, INK)
	title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	var status := _label(column, "升级时可领悟", 12, MUTED)
	for label in [key_label, title_label, status]:
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var bar := _bar(column, GOLD if id == "divinity" else TEAL, 3)
	_skill_widgets[id] = {"title": title_label, "status": status, "bar": bar, "binding": key_label}


func _build_pause() -> void:
	var modal := _modal("PauseMenu", 684)
	pause_panel = modal.overlay
	var column: VBoxContainer = modal.column
	_label(column, "片刻休整", 29, INK)
	_label(column, "哪吒 · 本局修行", 13, GOLD)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	column.add_child(row)
	var controls := _column(row, 10)
	controls.custom_minimum_size.x = 270
	pause_button = _button(controls, "继续战斗", func() -> void: pause_requested.emit())
	_button(controls, "重新开始", func() -> void: restart_requested.emit())
	var frame_row := HBoxContainer.new()
	controls.add_child(frame_row)
	_label(frame_row, "帧率上限", 15, MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_select = OptionButton.new()
	frame_select.add_item("60 FPS", 60)
	frame_select.add_item("120 FPS", 120)
	frame_select.select(1)
	frame_select.custom_minimum_size = Vector2(126, 38)
	frame_select.item_selected.connect(func(index: int) -> void: frame_limit_requested.emit(frame_select.get_item_id(index)))
	frame_row.add_child(frame_select)
	_shake = CheckButton.new()
	_shake.text = "镜头震动"
	_shake.button_pressed = true
	_shake.toggled.connect(func(enabled: bool) -> void: shake_changed.emit(enabled))
	controls.add_child(_shake)
	_mute = CheckButton.new()
	_mute.text = "静音"
	_mute.toggled.connect(func(enabled: bool) -> void: AudioServer.set_bus_mute(0, enabled))
	controls.add_child(_mute)
	_label(controls, "Esc / Start  继续\nR  重开    F11  全屏", 12, MUTED)
	var attributes := _column(row, 6)
	attributes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(attributes, "当前属性", 16, GOLD)
	_stat_text = _label(attributes, "", 14, INK)
	_stat_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stat_text.add_theme_constant_override("line_spacing", 5)
	pause_panel.hide()


func _build_choices() -> void:
	var modal := _modal("UpgradeSelection", 860)
	choice_panel = modal.overlay
	_choice_box = modal.panel
	var column: VBoxContainer = modal.column
	_choice_title = _label(column, "破境 · 三选一", 30, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_choice_subtitle = _label(column, "选择一项成长", 14, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	var cards := HBoxContainer.new()
	cards.name = "Cards"
	cards.add_theme_constant_override("separation", 12)
	column.add_child(cards)
	for i in 3:
		var button := _button(cards, "", _choose.bind(i))
		button.name = "Choice%d" % (i + 1)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 238)
		var margins := MarginContainer.new()
		margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(margins)
		margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "top", "right", "bottom"]:
			margins.add_theme_constant_override("margin_" + side, 17)
		var content := _column(margins, 14)
		var category := _label(content, "", 12, TEAL)
		var title := _label(content, "", 22, INK)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var description := _label(content, "", 15, MUTED)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_label(content, "选择此项  →", 13, GOLD)
		_choice_buttons.append(button)
		_choice_labels.append({"category": category, "title": title, "description": description})
	_label(column, "1 / 2 / 3 选择  ·  方向键 / 十字键切换  ·  Enter / A 确认", 12, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	choice_panel.hide()


func _build_result() -> void:
	var modal := _modal("RunResult", 480)
	result_panel = modal.overlay
	var column: VBoxContainer = modal.column
	_label(column, "烬 庭  /  哪 吒", 13, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_result_title = _label(column, "破阵而归", 38, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_result_description = _label(column, "", 15, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_result_summary = _label(column, "", 19, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_result_summary.add_theme_constant_override("line_spacing", 9)
	_result_button = _button(column, "再战一局", func() -> void: restart_requested.emit())
	_label(column, "R 重新开始", 12, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	result_panel.hide()


func _modal(title: String, width: float) -> Dictionary:
	var overlay := Control.new()
	overlay.name = title
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = Color(0.025, 0.04, 0.055, 0.88)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _style(Color("13242c"), Color("50616a"), 24))
	center.add_child(panel)
	var column := _column(panel, 15)
	return {"overlay": overlay, "panel": panel, "column": column}


func _fit_layout() -> void:
	if not is_instance_valid(_base):
		return
	var margin := 14 if size.x < 1100.0 else 22
	for side in ["left", "top", "right", "bottom"]:
		_base.add_theme_constant_override("margin_" + side, margin)
	_skill_row.custom_minimum_size.x = minf(1040.0, maxf(0.0, size.x - margin * 2.0))
	for widgets in _skill_widgets.values():
		widgets.title.add_theme_font_size_override("font_size", 15 if size.x < 1100.0 else 16)
		widgets.status.add_theme_font_size_override("font_size", 11 if size.x < 1100.0 else 12)
		widgets.binding.add_theme_font_size_override("font_size", 10 if size.x < 1100.0 else 11)
	_choice_box.custom_minimum_size.x = minf(1020.0, maxf(0.0, size.x - 56.0))
	for button in _choice_buttons:
		button.custom_minimum_size.y = 360.0 if size.y >= 680.0 else 330.0
	for labels in _choice_labels:
		labels.title.add_theme_font_size_override("font_size", 22 if size.y >= 680.0 else 20)
		labels.description.add_theme_font_size_override("font_size", 15 if size.y >= 680.0 else 14)


func _panel(parent: Node) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(Color(0.035, 0.065, 0.079, 0.85), Color(0.30, 0.39, 0.42, 0.55), 11))
	parent.add_child(panel)
	return panel


func _column(parent: Node, separation: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", separation)
	parent.add_child(column)
	return column


func _label(parent: Node, value: String, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = alignment
	parent.add_child(label)
	return label


func _bar(parent: Node, color: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	bar.custom_minimum_size.y = height
	bar.add_theme_stylebox_override("background", _style(Color("22343c"), Color.TRANSPARENT, 0))
	bar.add_theme_stylebox_override("fill", _style(color, Color.TRANSPARENT, 0))
	parent.add_child(bar)
	return bar


func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size.y = 42
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", GOLD)
	button.add_theme_stylebox_override("normal", _style(Color("1a303a"), Color("48606a"), 10))
	button.add_theme_stylebox_override("hover", _style(Color("29444d"), TEAL.darkened(0.25), 10))
	button.add_theme_stylebox_override("pressed", _style(Color("304b53"), GOLD, 10))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), GOLD, 10, 2))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _style(fill: Color, border: Color, padding: int, border_width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width if border.a > 0.0 else 0)
	style.set_corner_radius_all(5)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func _release_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused):
		focused.release_focus()


func _clock(seconds: float) -> String:
	var whole := maxi(0, floori(seconds))
	return "%02d:%02d" % [whole / 60, whole % 60]
