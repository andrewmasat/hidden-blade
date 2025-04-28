# DashIcon.gd
extends Control

class_name DashIcon

# Signal emitted when this specific charge finishes recharging
signal recharge_finished

enum State { READY, RECHARGING }

@onready var ready_icon = $ReadyIcon
@onready var recharge_progress = $RechargeProgress
@onready var recharge_timer = $RechargeTimer

var current_state: State = State.READY : set = set_current_state

func _ready():
	recharge_timer.timeout.connect(_on_recharge_timer_timeout)
	set_visual_state(true)

func _process(_delta):
	# Conditions needed: Timer must be running AND progress bar must be visible
	var is_timer_running = not recharge_timer.is_stopped()
	var is_progress_visible = recharge_progress.visible

	if is_timer_running and is_progress_visible:
		# We expect this block to execute during recharge

		if recharge_timer.wait_time > 0:
			# Calculate the value
			var time_left = max(0.0, recharge_timer.time_left)
			var percent_complete = (1.0 - (time_left / recharge_timer.wait_time)) * 100.0

			# *** THE CRITICAL LINE ***
			recharge_progress.value = percent_complete
			# ************************

		else: # Should not happen if start_recharge works
			print(name, " Process WARNING: Wait time is zero.")

	# else: # Debugging if conditions fail
		# if is_progress_visible:
		#	print(name, " Process DEBUG: Progress Visible but Timer Stopped. TimeLeft:", recharge_timer.time_left)

# Call this externally to make the icon appear ready
func show_ready():
	current_state = State.READY
	ready_icon.visible = true
	recharge_progress.visible = false
	recharge_progress.value = 0 # Reset progress

func set_current_state(new_state: State):
	if current_state != new_state:
		# print(name, " internal state changing to ", State.keys()[new_state]) # Optional debug
		current_state = new_state

# Call this externally to start the recharge visual and timer
func start_recharge(duration: float):
	if duration <= 0:
		# If duration is invalid, ensure timer is stopped and signal finished.
		# Visual state will be handled by HUD based on count.
		if not recharge_timer.is_stopped():
			recharge_timer.stop()
		emit_signal("recharge_finished") # Treat as immediately finished
		print(name, " start_recharge: Invalid duration, stopping timer and emitting finished.")
		return

	recharge_progress.value = 0 # Reset visual progress when timer starts
	recharge_timer.wait_time = duration
	recharge_timer.start()
	print(name, " start_recharge: Started timer for ", duration, " seconds.")
	# HUD controls visibility via set_visual_state


func _on_recharge_timer_timeout():
	# Timer finished naturally.
	print(name, " _on_recharge_timer_timeout: Timer finished. Emitting recharge_finished.")
	# We don't need to change internal state here anymore.
	# We MUST ensure the progress value is finalized in case _process didn't catch the last frame
	recharge_progress.value = 100
	emit_signal("recharge_finished")

# --- Visual State Management (Called by HUD) ---

# Forces the icon to LOOK ready or recharging, does NOT affect timer/internal state
func set_visual_state(is_ready: bool):
	# print(name, " Setting visual state to ready: ", is_ready) # Debug print
	ready_icon.visible = is_ready
	recharge_progress.visible = not is_ready

	# If forcing visuals to recharging, ensure bar starts empty if timer isn't running
	if not is_ready and recharge_timer.is_stopped():
		recharge_progress.value = 0
	# If forcing visuals to ready, ensure progress value is visually reset
	elif is_ready:
		recharge_progress.value = 0
		# We could potentially stop the timer here if HUD forces visuals to ready,
		# but that might conflict with player logic if HUD is ahead. Let Player manage gain_charge.
		# if not recharge_timer.is_stopped():
		#     print(name, " set_visual_state(true): Stopping timer because visuals forced ready.")
		#     recharge_timer.stop()e


# Call this externally to make the icon appear ready AND ensure internal state is ready
# Use this when a charge is gained instantly or reset
func show_ready_and_reset_state():
	if not recharge_timer.is_stopped():
		recharge_timer.stop()
		print(name, " show_ready_and_reset_timer: Stopping active timer.")
	set_visual_state(true) # Set visuals
