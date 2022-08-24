extends KinematicBody

## Player Attribute Metrics
var metric_focus = 4
var metric_instincts = 4
var metric_reflexes = 4
var metric_muscle = 4

## Camera Perspective Variables
var m_input_sensitivity = 0.15
var j_input_sensitivity = 2
const J_DEADZONE = 0.15
var rotate_control = true
var sign_offset = 1

## Headbob and Strafe/Leaning Variables
var sqr_distance = 0
var bob_intensity = 0.25
var bob_dir = 0.0
var lean_dir = 0.0

## Player Character Height (Metric-Dependent)
var standing_height = 1.6 + (0.2 * metric_muscle)
var crouching_height = 0.6

## Player Posture, States, Speed (Metric-Dependent)
var crouched = false
var leap_yield = false
var velocity = 6 + metric_reflexes
var velocity_crouch = 3 + (0.5 * metric_reflexes)

## Base Acceleration (Metric-Dependent)
var A_BASE_RATE = 4.5 + (0.5 * metric_reflexes)
var A_AIR_FACTOR = 0.5 + (0.25 * metric_reflexes)
onready var acceleration = A_BASE_RATE

## Leap, Gravity, Movesets (Metric-Dependent)
var leap_height = 4 + metric_muscle
var g_force = ProjectSettings.get_setting("physics/3d/default_gravity")
var can_flip = false
var can_dive = false

## Initializing Movement/Motion Vectors
var foot_directional = Vector3.ZERO
var foot_motion = Vector3.ZERO
var vert_motion = Vector3.ZERO
var total_motion = Vector3.ZERO
var snap

## Initializing Node Members
onready var head = $Head
onready var camera = $Head/Camera
onready var body = $Body_CollisionShape
onready var ray_crown = $Body_CollisionShape/Crown_RayCast


## Ready: Initialize height, moveset capabilities from given metrics. Center mouse.
## Called when the node enters the scene tree for the first time.
func _ready():
	body.shape.height = standing_height
	if metric_reflexes > 2:
		can_flip = true
	if metric_muscle > 2:
		can_dive = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Camera, Lean: Strafe drift and lean perspecitve.
## Requires strafe calculation, delta for time interpolation.
func _camera_lean(strafe, delta):
	# Lean into strafe momentum when not crouched, can be mid-air or grounded.
	if !crouched:
		camera.rotate_z(deg2rad(strafe / -3))
	
	# When on floor, allow leaning (head x offset, camera z rotation) according to reflexes.
	# Otherwise, interpolate over time back to origin position and rotation.
	if is_on_floor():
		lean_dir = lerp(lean_dir, Input.get_action_strength("lean_left") - Input.get_action_strength("lean_right"), 0.1)
		if abs(lean_dir) > 0:
			if strafe == 0:
				camera.rotate_z(deg2rad(lean_dir * 2))
				head.transform.origin.x = lerp(head.transform.origin.x, -0.75 * lean_dir, PI * delta)
		elif head.transform.origin.x != self.transform.origin.x:
			head.transform.origin.x = lerp(head.transform.origin.x, 0, 3 * delta)
		camera.rotation.z = lerp_angle(camera.rotation.z, deg2rad(0), PI * delta)
	else:
		if strafe == 0 and camera.rotation.z != deg2rad(0):
			camera.rotation.z = lerp_angle(camera.rotation.z, deg2rad(0), PI * delta)
		if head.transform.origin.x != self.transform.origin.x:
			head.transform.origin.x = lerp(head.transform.origin.x, 0, PI * delta)
	
	# Clamp camera rotation degree according to velocity limit.
	camera.rotation.z = clamp(camera.rotation.z, deg2rad(-velocity / 1.5), deg2rad(velocity / 1.5))


## Bob, Helper: Calculates magnitude for headbob calculation.
## Requires delta for time-distance interval.
func _bob_helper(delta):
	return (PI * (1 / (bob_intensity * 2))) * ((bob_intensity * camera.transform.origin.y) + (sqr_distance * delta))


## Camera, Bob: Displaces camera's local origin along y-axis according to given magnitude.
## Requires magnitude that is time-scaled (delta), intensity must be initialized.
func _camera_bob(magnitude):
	camera.transform.origin.y = lerp(camera.transform.origin.y, bob_intensity * sin(magnitude), 0.5)


## Camera, Rest: Interpolate-reset camera to resting position along y-axis for local origin.
## Requires delta for interpolation.
func _camera_rest(delta):
	camera.transform.origin.y = lerp(camera.transform.origin.y, 0, 6 * delta)


## Camera, Input: Calculate x, y rotations (body - horizontal, head+camera - vertical) for given player input.
## Requires x and y from input actions, offset must be initialized to maintain control with inverted perspective.
## Clamp rotation to ~88 degrees if grounded, or allow mid-air flips for high reflex characters.
func _camera_input(x, y):
	# When controllable, set horizontal rotation with inverse x offset for self, vertical for head.
	if rotate_control:
		self.rotate_y(deg2rad(x * (sign_offset)))
		head.rotate_x(deg2rad(y))
	
	# Clamp head's x-rotation if character cannot flip, or if control is allowed but character is grounded.
	if !can_flip:
		head.rotation.x = clamp(head.rotation.x, deg2rad(-87.99), deg2rad(87.99))
	else:
		if rotate_control and vert_motion == Vector3.ZERO:
			head.rotation.x = clamp(head.rotation.x, deg2rad(-87.99), deg2rad(87.99))


## Foot, Input: Receive, manage locomotive control (horizontal, vertical, physics constraints).
## Requires estimate of head rotation degrees, and delta for interpolation-related concerns.
## Calls _camera_lean (strafing / lean input), _camera_rest (perspective reset),
## _bob_helper (headbob factor), _camera_bob (headbob movement).
func _foot_input(head_deg, delta):
	var orientation = global_transform.basis.get_euler().y
	
	# Control for camera perspective inversion based on up/down approximation. Maintain expected control.
	if head_deg >= -88 and head_deg <= 88:
		sign_offset = 1
	else:
		sign_offset = -1
	
	# Receive horizontal movement inputs.
	var k_input_move = (Input.get_action_strength("foot_backward") - Input.get_action_strength("foot_forward")) * sign_offset
	var k_input_strafe = Input.get_action_strength("foot_right") - Input.get_action_strength("foot_left")
	
	# Set direction vector based upon movement, set for correct orientation and normalize.
	foot_directional = Vector3(k_input_strafe, 0, k_input_move).rotated(Vector3.UP, orientation).normalized()
	
	# Call for strafe / lean input as clean, initial inputs received.
	_camera_lean(k_input_strafe * ((metric_reflexes + 5) / 5), delta)
	
	# Yield a leap if input released and vertical motion still rising for leap height. Go to 0, then fall with gravity.
	if Input.is_action_just_released("foot_leap") and vert_motion.y > 0:
		leap_yield = true
	if leap_yield and vert_motion.y > 0:
		vert_motion.y = lerp(vert_motion.y, 0, PI * delta)
	else:
		leap_yield = false
	
	# Call for gradual reset to origin when camera out of local y-position.
	if camera.transform.origin.y != 0:
		_camera_rest(delta)
	
	# Rules for locomotion when grounded, otherwise assume mid-air.
	if is_on_floor():
		# Check top raycast to avoiding intersections and level behavior underneath collisions.
		var hit_head = ray_crown.is_colliding()
		
		# On floor, get angle vector of the surface's normal for calculating motion resistance/reception.
		# Cancel vertical property of vector.
		var traction_level = get_floor_normal()
		traction_level.y = 0
		
		# Headbobbing conditions - only when moving, no top/wall collision. Set displacement and calculate, or reset.
		if !hit_head and (abs(k_input_move) + abs(k_input_strafe) > 0):
			if !is_on_wall():
				sqr_distance += foot_directional.length_squared()
				bob_dir = _bob_helper(delta)
				_camera_bob(bob_dir)
			else:
				sqr_distance = 0
				_camera_rest(delta)
		else:
			sqr_distance = 0
		
		# Set resistance/reception for motion according to floor's slope angle - traction.
		if foot_directional.length_squared() > 0:
			var traction = traction_level.length_squared()
			
			#Regulate traction if not crouched, climb/slide if crouching against slope (diminishing, metric-based).
			if !crouched:
				foot_directional += (traction_level * (PI / 2))
			elif traction > 0.01 and traction < 0.2:
				foot_directional += traction_level
				foot_directional *= 0.75 * ((PI * ((metric_muscle + 5) / 4)) - (PI * sqrt(traction / 4)))
		
		# Resetting rotation with flip, cancel movement whilst interpolating back to 0.
		if !rotate_control:
			k_input_move = 0
			k_input_strafe = 0
			head.rotation.x = lerp_angle(head.rotation.x, deg2rad(0), PI * delta)
			
			# Return rotation control when orientation is returned near center.
			if abs(head_deg) < 15:
				_camera_rest(delta)
				rotate_control = true
		
		# Set acceleration for grounded motion, snap against normal.
		acceleration = A_BASE_RATE
		vert_motion = Vector3.ZERO
		
		snap = -get_floor_normal()
		
		# Receive leap input, only if raycast detects no collision immediately above current position.
		if Input.is_action_just_pressed("foot_leap") and !hit_head:
			body.shape.height = crouching_height
			rotate_control = true
			vert_motion = Vector3.UP * leap_height
			snap = Vector3.ZERO
		
		# Receive crouch input, shrink down body relative to time and set crouched state.
		if Input.is_action_pressed("foot_crouch"):
			crouched = true
			body.shape.height -= (1.5 * velocity_crouch) * delta
		elif !hit_head:
			crouched = false
			body.shape.height += (1.5 * velocity_crouch) * delta
		else:
			crouched = true
		# Limit height according to constraints.
		body.shape.height = clamp(body.shape.height, crouching_height, standing_height)	
	else:
		# With a character than can dive, allow crouch mid-air to control a powerful descent.
		if can_dive and Input.is_action_pressed("foot_crouch"):
			vert_motion += Vector3.DOWN * (velocity * 2 * PI) * delta
		
		# Set acceleration for mid-air motion, gravity for vertical, and snap.
		acceleration = A_BASE_RATE * A_AIR_FACTOR
		vert_motion += Vector3.DOWN * g_force * delta
		snap = Vector3.DOWN


## Foot, Motion: Set character into motion after input has been validated and cleaned for environmental constraints.
## Requires estimate for head rotation degrees, delta for time, and external input as prerequisite.
func _foot_motion(head_deg, delta):
	# Select appropriate speed type from an input-initialized posture.
	var posture_speed
	if crouched:
		posture_speed = velocity_crouch
	else:
		posture_speed = velocity
	
	# Clamp for terminal velocity.
	vert_motion.y = clamp(vert_motion.y, -32, 32)
	
	# Set motion vector with input direction, speed, floor velocity - according to acceleration and time.
	foot_motion = foot_motion.linear_interpolate((foot_directional * posture_speed) + get_floor_velocity(), acceleration * delta)
	
	# Store and move with total motion with horizontal and pre-calculated vertical.
	total_motion = move_and_slide_with_snap(foot_motion + vert_motion, snap, Vector3.UP)
	
	# If can flip and rotation out-of-bounds, prevent rotation control if vertical motion indicates grounded.
	if vert_motion == Vector3.ZERO:
		if can_flip and (abs(head_deg) > 88):
			rotate_control = false
	else:
		rotate_control = true


## Input: Runs on event detection.
## Handles mouse-based camera control.
func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_camera_input(-event.relative.x * m_input_sensitivity, -event.relative.y * m_input_sensitivity)


## Physics, Process: Fixed rate processing for physics, motion, etc.
## Handles input, motion calculations for character controller.
func _physics_process(delta):
	var head_deg = int(round(rad2deg(head.rotation.x)))
	
	# Handle joystick-based camera control.
	if Input.get_connected_joypads().size() > 0:
		var look_vector = Vector2.ZERO
		look_vector = Vector2(-Input.get_joy_axis(0, 2), -Input.get_joy_axis(0, 3))
		
		if look_vector.length() < J_DEADZONE:
			look_vector = Vector2.ZERO
		else:
			look_vector = look_vector.normalized() * ((look_vector.length() - J_DEADZONE) / (1 - J_DEADZONE))
			_camera_input(look_vector.x * j_input_sensitivity, look_vector.y * j_input_sensitivity)
	
	# Call for input, then motion.
	_foot_input(head_deg, delta)
	_foot_motion(head_deg, delta)
	
#func _process(delta):
