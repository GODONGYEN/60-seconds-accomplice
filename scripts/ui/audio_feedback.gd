class_name AudioFeedback
extends Node

const MIX_RATE: float = 22050.0

@onready var player: AudioStreamPlayer = %AudioStreamPlayer

var _playback: AudioStreamGeneratorPlayback = null
var _phase: float = 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.35
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	player.stream = generator
	player.play()
	_playback = player.get_stream_playback() as AudioStreamGeneratorPlayback


func play_loop_start() -> void:
	_push_tone(520.0, 0.07, 0.10)
	_push_tone(760.0, 0.09, 0.10)


func play_door(is_open: bool) -> void:
	_push_tone(680.0 if is_open else 260.0, 0.08, 0.08)


func play_objective() -> void:
	_push_tone(880.0, 0.09, 0.12)
	_push_tone(1180.0, 0.12, 0.10)


func play_victory() -> void:
	_push_tone(660.0, 0.10, 0.12)
	_push_tone(880.0, 0.10, 0.12)
	_push_tone(1320.0, 0.16, 0.12)


func play_suspicion() -> void:
	_push_tone(410.0, 0.07, 0.08)


func play_alert() -> void:
	_push_tone(820.0, 0.08, 0.12)
	_push_tone(610.0, 0.12, 0.11)


func play_capture() -> void:
	_push_tone(240.0, 0.10, 0.13)
	_push_tone(150.0, 0.16, 0.13)


func _push_tone(frequency: float, duration: float, amplitude: float) -> void:
	if _playback == null:
		return
	var frame_count := int(MIX_RATE * duration)
	var phase_step := frequency / MIX_RATE
	for _frame: int in frame_count:
		var envelope := minf(1.0, float(_frame) / 90.0)
		envelope *= minf(1.0, float(frame_count - _frame) / 140.0)
		var sample := sin(_phase * TAU) * amplitude * envelope
		_playback.push_frame(Vector2(sample, sample))
		_phase = fmod(_phase + phase_step, 1.0)
