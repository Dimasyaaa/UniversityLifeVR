extends RigidBody3D

## Будильник, который можно взять в руку (Модуль 1).
## Можно поднять с стола, носить. Если уронить/упасть на землю — будильник
## выключается (игрок просыпается).

@export var wake_energy_bonus: float = 25.0

var is_awake: bool = false
var _was_in_air: bool = false
var _is_picked_up: bool = false  # Track if alarm is being held

func _ready() -> void:
	# Режим rigid: можно взять в руку через FunctionPickup
	mode = RigidBody3D.MODE_RIGID
	collision_layer = 2  # Interactable — видно указателю
	collision_mask = 1   # World

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Если будильник в движении — его взяли/бросили
	if state.linear_velocity.length() > 0.1:
		_was_in_air = true
	# Если упал на пол после перемещения — выключаем будильник
	if _was_in_air and global_position.y < 0.25 and not is_awake and state.linear_velocity.length() < 0.5:
		_wake_up()

func _wake_up() -> void:
	if is_awake:
		return
	is_awake = true

	GameStateManager.set_awake(true)
	GameStateManager.change_stat("energy", wake_energy_bonus)

	if GameStateManager.game_minutes < 7 * 60:
		QuestManager.unlock_achievement("early_bird")

	HintSystem.show_hint(
		"Подъём! %s  +%d к Энергии\nГлавный квест: сдать экзамен в 16:00" % [
			GameStateManager.get_time_string(),
			int(wake_energy_bonus),
		],
		6.0)
