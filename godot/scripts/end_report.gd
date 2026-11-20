extends RefCounted
## UI-only journal. Never contains, restores, or modifies an engine save.
const PATH := "user://last_run.json"
const VERSION := 1

static func read_report(path := PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	var value = parser.data
	if not value is Dictionary or value.get("version") != VERSION:
		return {}
	if not value.get("pages") is Array or not value.get("cause") is String:
		return {}
	for page in value.pages:
		if not page is Dictionary or not page.get("text") is String or not page.get("title") is String:
			return {}
	return value

static func write_report(value: Dictionary, path := PATH) -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	return DirAccess.rename_absolute(path + ".tmp", path) == OK
