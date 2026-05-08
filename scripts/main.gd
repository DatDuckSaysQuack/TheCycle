extends Node2D

# Extinction Cycle Prototype 0 architecture:
# - Simulation state lives in this script for clarity (single-scene prototype).
# - World entities are lightweight dictionary records rendered through child nodes.
# - A simple state machine controls pre-extinction, flood, limbo, and failure outcomes.

const MAP_RECT := Rect2(40, 120, 1200, 540)
const SETTLEMENT_CENTER := Vector2(920, 390)

const HUMAN_COLOR := Color("d6c29a")
const XENO_COLOR := Color("2e103e")
const POLLY_COLOR := Color.WHITE
const BALL_COLOR := Color.YELLOW
const ROCK_COLOR := Color("c9c9c9")
const FLOOD_COLOR := Color("4ba8ff")

const POLLY_SPEED := 85.0
const VILLAGER_SPEED := 45.0
const FLEE_SPEED := 80.0

const FLOOD_BASE_SPEED := 48.0
const FLOOD_BARRIER_SLOW := 0.42
const BARRIER_RADIUS := 85.0
const BARRIER_MAX_HEALTH := 100.0
const BARRIER_DAMAGE_PER_SEC := 18.0

const RECONCILIATION_AMOUNT := 18.0
const CONFLICT_RISE_PER_SEC := 2.4

var houses_built := 0
var conflict_level := 10.0
var objectives_complete := false
var extinction_vulnerable := false
var polly_on_rock_hold_time := 0.0

var extinction_triggered := false
var flood_x := MAP_RECT.position.x - 40.0
var flood_survival_time := 0.0
var limbo_state := false
var failure_state := false

var villagers: Array[Dictionary] = []
var houses: Array[Vector2] = []
var barriers: Array[Dictionary] = []

var polly_holding_ball := false
var polly_target := Vector2.ZERO
var polly_retarget_time := 0.0

@onready var map_rect: ColorRect = $Map
@onready var settlement_marker: ColorRect = $SettlementCenter
@onready var flood_wall: ColorRect = $FloodWall
@onready var ball: ColorRect = $Ball
@onready var rock: ColorRect = $MarbleRock
@onready var polly_label: Label = $Polly/Label
@onready var ui_status: Label = $UIRoot/StatusLabel
@onready var ui_objectives: Label = $UIRoot/ObjectivesLabel
@onready var ui_conflict: Label = $UIRoot/ConflictLabel
@onready var ui_vulnerable: Label = $UIRoot/VulnerabilityLabel
@onready var ui_trigger_hint: Label = $UIRoot/TriggerHintLabel
@onready var ui_trigger_progress: Label = $UIRoot/TriggerProgressLabel
@onready var ui_flood_timer: Label = $UIRoot/FloodTimerLabel
@onready var build_house_button: Button = $UIRoot/Buttons/BuildHouseButton
@onready var reconcile_button: Button = $UIRoot/Buttons/ReconcileButton

func _ready() -> void:
	randomize()
	_setup_initial_entities()
	build_house_button.pressed.connect(_on_build_house_pressed)
	reconcile_button.pressed.connect(_on_reconcile_pressed)
	_refresh_ui()

func _setup_initial_entities() -> void:
	# Populate starting civilization: 6 humans, 4 xenomorph-like villagers, and Polly.
	for _i in range(6):
		_spawn_villager("human", _random_map_position(), HUMAN_COLOR)
	for _i in range(4):
		_spawn_villager("xeno", _random_map_position(), XENO_COLOR)
	_spawn_polly()
	ball.position = _random_map_position() - ball.size * 0.5
	rock.position = SETTLEMENT_CENTER + Vector2(-170, -110)

func _spawn_villager(kind: String, world_pos: Vector2, color: Color) -> void:
	var body := ColorRect.new()
	body.size = Vector2(16, 16)
	body.color = color
	body.position = world_pos - body.size * 0.5
	add_child(body)
	villagers.append({
		"kind": kind,
		"node": body,
		"velocity": Vector2.from_angle(randf() * TAU) * VILLAGER_SPEED,
		"alive": true,
	})

func _spawn_polly() -> void:
	$Polly.color = POLLY_COLOR
	$Polly.size = Vector2(18, 18)
	$Polly.position = _random_map_position() - $Polly.size * 0.5
	polly_label.text = "Polly"
	polly_label.position = Vector2(-6, -20)
	polly_target = _random_map_position()

func _process(delta: float) -> void:
	if limbo_state or failure_state:
		_refresh_ui()
		return

	if houses_built > 0 and not extinction_triggered:
		conflict_level = min(100.0, conflict_level + CONFLICT_RISE_PER_SEC * delta)

	_update_polly(delta)
	_update_ball_attachment()
	_update_villagers(delta)
	_check_objectives()
	_check_extinction_condition(delta)
	_update_flood(delta)
	_refresh_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = event.position
		if MAP_RECT.has_point(pos) and extinction_triggered and not limbo_state and not failure_state:
			_place_barrier(pos)

func _update_polly(delta: float) -> void:
	var polly: ColorRect = $Polly
	polly_retarget_time -= delta
	if polly_retarget_time <= 0.0 or polly.global_position.distance_to(polly_target) < 10.0:
		polly_target = _random_map_position()
		polly_retarget_time = randf_range(1.2, 3.4)

	var current := polly.position + polly.size * 0.5
	var dir := (polly_target - current).normalized()
	var next := current + dir * POLLY_SPEED * delta
	next = _clamp_to_map(next)
	polly.position = next - polly.size * 0.5

	# Pick up yellow playball when close enough.
	if not polly_holding_ball:
		var ball_center := ball.position + ball.size * 0.5
		if current.distance_to(ball_center) < 26.0:
			polly_holding_ball = true

func _update_ball_attachment() -> void:
	if polly_holding_ball:
		var polly: ColorRect = $Polly
		var anchor := polly.position + polly.size * 0.5 + Vector2(13, -8)
		ball.position = anchor - ball.size * 0.5

func _update_villagers(delta: float) -> void:
	for v in villagers:
		if not v["alive"]:
			continue
		var node: ColorRect = v["node"]
		var center := node.position + node.size * 0.5
		var vel: Vector2 = v["velocity"]
		if extinction_triggered:
			# Villagers flee rightward, away from left-to-right flood wall.
			var away := Vector2.RIGHT
			vel = away * FLEE_SPEED
		else:
			if randf() < 0.02:
				vel = Vector2.from_angle(randf() * TAU) * VILLAGER_SPEED
		var next := center + vel * delta
		if not MAP_RECT.has_point(next):
			if next.x < MAP_RECT.position.x or next.x > MAP_RECT.end.x:
				vel.x *= -1.0
			if next.y < MAP_RECT.position.y or next.y > MAP_RECT.end.y:
				vel.y *= -1.0
			next = _clamp_to_map(next)
		node.position = next - node.size * 0.5
		v["velocity"] = vel

func _check_objectives() -> void:
	var live_count := _living_villager_count()
	objectives_complete = houses_built >= 3 and live_count >= 10 and conflict_level < 50.0
	if objectives_complete:
		extinction_vulnerable = true

func _check_extinction_condition(delta: float) -> void:
	if not extinction_vulnerable or extinction_triggered:
		polly_on_rock_hold_time = 0.0
		return
	var polly_center := $Polly.position + $Polly.size * 0.5
	var rock_rect := Rect2(rock.position, rock.size)
	if polly_holding_ball and rock_rect.grow(8).has_point(polly_center):
		polly_on_rock_hold_time += delta
		if polly_on_rock_hold_time >= 5.0:
			_trigger_extinction()
	else:
		polly_on_rock_hold_time = 0.0

func _trigger_extinction() -> void:
	extinction_triggered = true
	flood_x = MAP_RECT.position.x
	ui_status.text = "EXTINCTION INVOKED"

func _update_flood(delta: float) -> void:
	if not extinction_triggered or limbo_state or failure_state:
		return
	var speed_mod := 1.0
	for b in barriers:
		if absf(b["pos"].x - flood_x) <= BARRIER_RADIUS:
			# As barrier health drops, its slowdown contribution weakens.
			var health_ratio: float = b["health"] / BARRIER_MAX_HEALTH
			speed_mod *= lerp(1.0, FLOOD_BARRIER_SLOW, health_ratio)
			b["health"] = max(0.0, b["health"] - BARRIER_DAMAGE_PER_SEC * delta)
			var node: ColorRect = b["node"]
			var intensity := b["health"] / BARRIER_MAX_HEALTH
			node.color = Color(0.64, 1.0, 0.92, 0.25 + intensity * 0.75)
	_prune_broken_barriers()
	var speed := max(5.0, FLOOD_BASE_SPEED * speed_mod)
	flood_x += speed * delta
	flood_wall.position.x = flood_x - flood_wall.size.x
	flood_survival_time += delta

	if flood_survival_time >= 30.0 and flood_x < SETTLEMENT_CENTER.x:
		limbo_state = true
		ui_status.text = "The flood hangs in limbo. This world survives."
		return

	if flood_x >= SETTLEMENT_CENTER.x:
		failure_state = true
		ui_status.text = "The civilization was washed away. A new cycle may begin."

func _on_build_house_pressed() -> void:
	var p := _random_map_position()
	houses_built += 1
	houses.append(p)
	var house := ColorRect.new()
	house.size = Vector2(26, 26)
	house.color = Color("8b5e3c")
	house.position = p - house.size * 0.5
	add_child(house)

func _on_reconcile_pressed() -> void:
	conflict_level = max(0.0, conflict_level - RECONCILIATION_AMOUNT)

func _place_barrier(pos: Vector2) -> void:
	var barrier := ColorRect.new()
	barrier.size = Vector2(22, 22)
	barrier.color = Color("a4ffea")
	barrier.position = pos - barrier.size * 0.5
	add_child(barrier)
	barriers.append({
		"pos": pos,
		"node": barrier,
		"health": BARRIER_MAX_HEALTH,
	})

func _prune_broken_barriers() -> void:
	for i in range(barriers.size() - 1, -1, -1):
		if barriers[i]["health"] <= 0.0:
			var dead_node: ColorRect = barriers[i]["node"]
			dead_node.queue_free()
			barriers.remove_at(i)

func _refresh_ui() -> void:
	var live_count := _living_villager_count()
	var polly_center := $Polly.position + $Polly.size * 0.5
	var rock_rect := Rect2(rock.position, rock.size)
	var polly_near_rock := rock_rect.grow(38).has_point(polly_center)

	ui_objectives.text = "Objectives:\n- Build 3 houses: %d/3\n- Keep >=10 villagers alive: %d/10\n- Conflict below 50: %.1f" % [houses_built, live_count, conflict_level]
	ui_conflict.text = "Conflict: %.1f" % conflict_level
	if extinction_vulnerable and not extinction_triggered:
		ui_vulnerable.text = "The world is extinction-vulnerable\nDo not let the white dog carry the sun to the pale stone."
	elif extinction_triggered and not limbo_state and not failure_state:
		ui_vulnerable.text = "Place magical barriers (click map) to hold flood for 30s."
	elif not extinction_vulnerable:
		ui_vulnerable.text = ""
	flood_wall.visible = extinction_triggered

	# Visual hint: Polly label reflects whether she is holding the yellow ball.
	polly_label.text = "Polly (holding sun)" if polly_holding_ball else "Polly"
	# Visual hint: marble rock gets brighter when Polly is nearby.
	rock.color = Color("ffffff") if polly_near_rock else ROCK_COLOR

	# Trigger-readability hints for the magical final condition.
	if not extinction_vulnerable or extinction_triggered:
		ui_trigger_hint.text = ""
		ui_trigger_progress.text = ""
	elif polly_holding_ball and polly_near_rock:
		ui_trigger_hint.text = "Polly nears the pale stone while carrying the sun."
		ui_trigger_progress.text = "Invocation countdown: %.1f / 5.0 s" % polly_on_rock_hold_time
	else:
		var ball_state := "holding the sun" if polly_holding_ball else "not holding the sun"
		var rock_state := "near the pale stone" if polly_near_rock else "away from the pale stone"
		ui_trigger_hint.text = "Trigger setup: Polly is %s and is %s." % [ball_state, rock_state]
		ui_trigger_progress.text = "Invocation countdown: %.1f / 5.0 s" % polly_on_rock_hold_time

	# Clearer flood win/loss timer messaging.
	if extinction_triggered and not limbo_state and not failure_state:
		var survive_remaining := max(0.0, 30.0 - flood_survival_time)
		var dist_to_center := max(0.0, SETTLEMENT_CENTER.x - flood_x)
		ui_flood_timer.text = "Containment timer: %.1fs remaining | Flood distance to settlement: %.0f px | Barriers active: %d" % [survive_remaining, dist_to_center, barriers.size()]
	elif limbo_state:
		ui_flood_timer.text = "Containment complete. Flood suspended in limbo."
	elif failure_state:
		ui_flood_timer.text = "Containment failed. Flood reached settlement center."
	else:
		ui_flood_timer.text = ""

func _living_villager_count() -> int:
	var c := 0
	for v in villagers:
		if v["alive"]:
			c += 1
	return c

func _random_map_position() -> Vector2:
	return Vector2(
		randf_range(MAP_RECT.position.x + 20, MAP_RECT.end.x - 20),
		randf_range(MAP_RECT.position.y + 20, MAP_RECT.end.y - 20)
	)

func _clamp_to_map(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, MAP_RECT.position.x + 6, MAP_RECT.end.x - 6),
		clampf(pos.y, MAP_RECT.position.y + 6, MAP_RECT.end.y - 6)
	)
