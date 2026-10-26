extends Node3D
## Связывает постоянного игрока и контейнер локаций с SceneManager.

@export var initial_location_id: StringName = &"test_room"


func _ready() -> void:
	if not SceneManager.setup($Locations, $VRPlayer, $Locations/TestRoom, initial_location_id):
		push_error("Main: не удалось подключить игрока и начальную локацию к SceneManager.")
		return
	$MainMenuPanel.setup($VRPlayer)
	$VRPlayer/XROrigin3D/RightHand/Phone.setup($VRPlayer, $MainMenuPanel)
