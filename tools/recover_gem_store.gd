extends SceneTree
## First inspect --store=...; then stop all workers/publishers and apply the
## exact reported --snapshot=... --workers-stopped=true. No timeout stealing.
func _initialize()->void:
	var args:={}
	for argument in OS.get_cmdline_user_args():
		var pair:=argument.trim_prefix("--").split("=",true,1)
		if pair.size()==2:args[pair[0]]=pair[1]
	if not args.has("store"):printerr("--store is required");quit(1);return
	var recovery:=GemStoreRecovery.new()
	var result:=recovery.recover(args.store,args.snapshot,args.get("workers-stopped","")=="true") if args.has("snapshot") else recovery.inspect(args.store)
	if result.is_empty():printerr(recovery.last_error);quit(1);return
	print(JSON.stringify(result,"\t"));quit()
