extends Node
## Записывает состояние дня и читает сохранение без применения к игре.

const SAVE_PATH: String = "user://save.cfg"
const FORMAT_VERSION: int = 1
const SAVE_SECTIONS: Array[String] = [
	"stats", "time", "quests", "achievements", "statistics", "events", "location",
]


func save_game() -> bool:
	if SceneManager.is_transitioning():
		push_warning("SaveManager: дождитесь окончания перехода между локациями.")
		return false
	var data: Dictionary = {
		"stats": GameStateManager.get_stats(),
		"time": TimeManager.get_save_data(),
		"quests": QuestManager.get_save_data(),
		"achievements": AchievementManager.get_save_data(),
		"statistics": StatisticsManager.get_save_data(),
		"events": RandomEventManager.get_save_data(),
		"location": {"location_id": SceneManager.get_current_location_id()},
	}
	var config: ConfigFile = ConfigFile.new()
	config.set_value("meta", "version", FORMAT_VERSION)
	for section: String in SAVE_SECTIONS:
		config.set_value(section, "data", data[section])
	var error: Error = config.save(SAVE_PATH)
	if error != OK:
		push_warning("SaveManager: не удалось записать сохранение: %s" % error_string(error))
		return false
	return true


func read_save_data() -> Dictionary:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(SAVE_PATH)
	if error == ERR_FILE_NOT_FOUND:
		return {}
	if error != OK:
		push_warning("SaveManager: не удалось прочитать сохранение: %s" % error_string(error))
		return {}
	if config.get_value("meta", "version", 0) != FORMAT_VERSION:
		push_warning("SaveManager: неподдерживаемая версия сохранения.")
		return {}
	var data: Dictionary = {}
	for section: String in SAVE_SECTIONS:
		var section_data: Variant = null
		if config.has_section_key(section, "data"):
			section_data = config.get_value(section, "data")
		if not section_data is Dictionary:
			push_warning("SaveManager: отсутствует или повреждён раздел: %s" % section)
			return {}
		data[section] = section_data
	return data
