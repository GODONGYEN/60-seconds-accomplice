class_name GameMode
extends RefCounted

enum Mode {
	MAIN_MENU,
	OPERATION_BLACK_MINUTE,
	PROTOTYPE_LOOP,
	FACILITY_REGRESSION,
}

const PROTOTYPE_ARGUMENT: String = "--prototype"
const FACILITY_ARGUMENT: String = "--facility-regression"


static func requested_from_command_line() -> Mode:
	var arguments: PackedStringArray = OS.get_cmdline_args()
	for user_argument: String in OS.get_cmdline_user_args():
		if not arguments.has(user_argument):
			arguments.append(user_argument)
	if arguments.has(PROTOTYPE_ARGUMENT):
		return Mode.PROTOTYPE_LOOP
	if arguments.has(FACILITY_ARGUMENT):
		return Mode.FACILITY_REGRESSION
	return Mode.MAIN_MENU


static func get_display_name(mode: Mode) -> String:
	match mode:
		Mode.OPERATION_BLACK_MINUTE:
			return "OPERATION: BLACK MINUTE"
		Mode.PROTOTYPE_LOOP:
			return "PROTOTYPE LOOP"
		Mode.FACILITY_REGRESSION:
			return "FACILITY 01 REGRESSION"
		_:
			return "MAIN MENU"
