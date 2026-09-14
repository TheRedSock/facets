extends Node
## In-memory facade. RunController owns the accepted record; no second recorder.
func export_session(controller: RunController) -> Dictionary:
	return controller.export_replay()

func verify(record: Dictionary) -> Dictionary:
	return ReplayRecord.verify(record)
