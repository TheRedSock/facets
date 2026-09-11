extends SceneTree
## Compare two rounding_lookdev folders. Print-space errors include path noise;
## they are not a bias bound or an automatic physical-realism acceptance gate.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		printerr("Usage: -- BEFORE_DIR AFTER_DIR OUTPUT_JSON");quit(1);return
	var before: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0].path_join("report.json")))
	var after: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("report.json")))
	if not before is Array or not after is Array or before.size()!=after.size():
		printerr("Invalid comparison reports");quit(1);return
	var rows := []
	for i in before.size():
		if before[i].file!=after[i].file or before[i].radius_mm!=after[i].radius_mm:
			printerr("Frame/radius mismatch");quit(1);return
		var a := Image.load_from_file(args[0].path_join(before[i].file))
		var b := Image.load_from_file(args[1].path_join(after[i].file))
		if a==null or b==null or a.get_size()!=b.get_size():
			printerr("Image dimensions disagree");quit(1);return
		a.convert(Image.FORMAT_RGBA8);b.convert(Image.FORMAT_RGBA8)
		var x:=a.get_data();var y:=b.get_data()
		var alpha2:=0.0;var rgb2:=0.0;var opaque2:=0.0;var opaque_count:=0;var peak:=0
		for pixel in x.size()/4:
			var j:=pixel*4
			alpha2+=pow(float(x[j+3])-y[j+3],2)
			for channel in 3:
				var delta:=int(x[j+channel])-int(y[j+channel])
				rgb2+=pow(float(x[j+channel])*x[j+3]/255.0-float(y[j+channel])*y[j+3]/255.0,2)
				if x[j+3]==255 and y[j+3]==255:
					opaque2+=delta*delta;opaque_count+=1;peak=maxi(peak,absi(delta))
		var row:={"file":before[i].file,"radius_mm":before[i].radius_mm,
			"associated_rgb_rmse_lsb":sqrt(rgb2/(x.size()/4.0*3)),"alpha_rmse_lsb":sqrt(alpha2/(x.size()/4.0)),
			"opaque_rgb_rmse_lsb":sqrt(opaque2/maxi(1,opaque_count)),"opaque_peak_lsb":peak,
			"before_trace_ms":before[i].profile.trace_wall_ms,"after_trace_ms":after[i].profile.trace_wall_ms,
			"before_compile_ms":before[i].compile_ms,"after_compile_ms":after[i].compile_ms}
		rows.append(row);print(JSON.stringify(row,"",true,true))
	var result:={"before":args[0],"after":args[1],"sampling_noise_included":true,"frames":rows}
	var saved:=GemArtifactStore.atomic_write(args[2],JSON.stringify(result,"\t",true,true).to_utf8_buffer())
	if not saved:printerr("Cannot write comparison report");quit(1);return
	quit()
