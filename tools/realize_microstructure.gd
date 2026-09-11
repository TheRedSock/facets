extends SceneTree
## Freeze an authored population program into an explicit specimen resource.
## --stone=res://... --recipe=res://... --output=res://generated/....res
func _initialize()->void:
	var args:={}
	for argument in OS.get_cmdline_user_args():
		var pair:=argument.trim_prefix("--").split("=",true,1)
		if pair.size()==2:args[pair[0]]=pair[1]
	var stone_path:String=args.get("stone","res://data/lapidary/stones/quartz.tres")
	var recipe_path:String=args.get("recipe","res://data/lapidary/microstructures/diagnostic_crystal_layer.tres")
	var output:String=args.get("output","res://generated/microstructure/quartz.res")
	if not ResourceLoader.exists(stone_path) or not ResourceLoader.exists(recipe_path) or output.get_extension()!="res":
		printerr("FAIL: source resources must exist and output must be binary .res");quit(1);return
	var source:=load(stone_path) as GemStone;var recipe:=load(recipe_path) as GemMicrostructureRecipe
	var result:=GemMicrostructureCompiler.realize(source,recipe)
	if not result.error.is_empty():printerr("FAIL: "+result.error);quit(1);return
	var job:=GemFrameJob.new();job.stone=result.stone
	job.rig=load("res://data/lapidary/rigs/gameplay_studio.tres");job.print_style=GemPrint.load_house()
	var error:=GemJobValidator.validate(job)
	if not error.is_empty():printerr("FAIL: "+error);quit(1);return
	if DirAccess.make_dir_recursive_absolute(output.get_base_dir())!=OK or GemResourceBundle.save(result.stone,output)!=OK:
		printerr("FAIL: cannot save realized specimen");quit(1);return
	var report:={"source":source.fingerprint(),"recipe":GemContentIdentity.digest(recipe),"specimen":result.stone.fingerprint(),"realization":result.report}
	if not GemArtifactStore.atomic_write(output.get_basename()+".json",JSON.stringify(report,"\t",true,true).to_utf8_buffer()):printerr("FAIL: cannot save realization provenance");quit(1);return
	print("Realized explicit specimen: "+output);quit()
