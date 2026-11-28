extends RefCounted
## Tags the current frame with a build or gameplay step for the hitch log (Perf autoload) and
## the benchmark. Looked up at run time so it also works from scripts preloaded by headless
## test scripts, where autoload names are not known.

static func mark(from: Node, label: StringName) -> void:
	if from == null or not from.is_inside_tree():
		return
	var perf := from.get_node_or_null(^"/root/Perf")
	if perf != null:
		perf.mark(label)
