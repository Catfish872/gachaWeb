extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var app=load("res://main.tscn").instantiate()
	root.add_child(app)
	for frame in 10:await process_frame
	assert(app.is_inside_tree() and app.main_body.get_child_count()>0)
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("SCENE LIFECYCLE: normal startup and shutdown passed")
	quit()
