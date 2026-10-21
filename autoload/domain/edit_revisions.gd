extends RefCounted

# Which version of the rig is live, and which one was last written to an avatar
# file. Every history entry remembers the revision it captured, so undoing back
# to the saved state reads as clean again and a discarded no-op edit leaves no
# trace. UndoManager keeps these lists in step with its own stacks.

const NEVER_SAVED := -1

var current := 0
var saved := 0

var _next := 0
var _undo: Array[int] = []
var _redo: Array[int] = []


# A snapshot was pushed: it holds the current state, and the edit that follows
# is a new revision.
func pushed(max_history: int) -> void:
	_undo.push_back(current)
	_redo.clear()
	if _undo.size() > max_history:
		_undo.pop_front()
	_next += 1
	current = _next


# The snapshot just pushed was thrown away, so the edit never happened.
func discarded() -> void:
	if not _undo.is_empty():
		current = _undo.pop_back()


func undone() -> void:
	if _undo.is_empty():
		return
	_redo.push_back(current)
	current = _undo.pop_back()


func redone() -> void:
	if _redo.is_empty():
		return
	_undo.push_back(current)
	current = _redo.pop_back()


func mark_saved(revision: int) -> void:
	saved = revision


# The live rig matches no file, e.g. a recovered session.
func mark_unsaved() -> void:
	saved = NEVER_SAVED


func has_unsaved_changes() -> bool:
	return current != saved
