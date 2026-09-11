extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)

func film(values:Array,alphas:Array=[])->PackedFloat32Array:
	var result:=PackedFloat32Array()
	for i in values.size():
		var alpha:float=alphas[i] if not alphas.is_empty() else 1.0
		result.append_array(PackedFloat32Array([values[i]*alpha,values[i]*alpha,values[i]*alpha,alpha]))
	return result

func _initialize()->void:
	var ids:=PackedInt64Array([0,0,0,0,1,1,1,1])
	var raw:=film([1,1,1,1,3,3,3,3])
	var a:=GemCutMetrics.frame(raw,ids)
	check(a.error.is_empty() and a.mean_Y==2 and a.contrast_cv==.5,"known mean and coefficient of variation")
	check(a.relative_dark_fraction==0 and a.coverage_pixels==8,"known relative dark fraction and coverage")
	var dark:=GemCutMetrics.frame(film([0,0,0,0,2,2,2,2]),ids)
	check(dark.contrast_cv==1 and dark.relative_dark_fraction==.5,"half-dark pattern")
	var black:=GemCutMetrics.frame(film([0,0,0,0,0,0,0,0]),ids)
	check(black.mean_Y==0 and black.contrast_cv==0 and black.relative_dark_fraction==1,"black image is fully dark, without division by zero")
	var partial:=GemCutMetrics.frame(film([1,1,1,1,3,3,3,3],[1,1,1,1,.5,.5,.5,.5]),ids)
	check(absf(partial.mean_Y-5.0/3)<1e-12 and partial.opaque_mean_Y==1,"associated alpha-weighted mean versus opaque appearance")
	check(partial.opaque_pixels==4 and partial.contrast_cv==0,"coverage edges excluded from contrast")
	var bright:=GemCutMetrics.frame(film([10,10,10,10,30,30,30,30]),ids)
	check(bright.contrast_cv==a.contrast_cv and bright.relative_dark_fraction==a.relative_dark_fraction,"relative pattern metrics are exposure invariant")
	var stationary:=GemCutMetrics.pair(a,a)
	check(stationary.modulation==0 and stationary.matched_facets==2 and stationary.matched_fraction==1,"identical views have zero modulation")
	var b:=GemCutMetrics.frame(film([2,2,2,2,6,6,6,6]),ids)
	check(absf(GemCutMetrics.pair(a,b).modulation-1.0/3)<1e-12,"known relative facet modulation")
	var changed_ids:=PackedInt64Array([9,9,9,9,1,1,1,1])
	var changed:=GemCutMetrics.frame(raw,changed_ids)
	var matched:=GemCutMetrics.pair(a,changed)
	check(matched.matched_facets==1 and matched.matched_fraction==.5,"newly visible facets do not masquerade as registered motion")
	check(GemCutMetrics.pair(a,changed,5).has("error") and not GemCutMetrics.pair(a,changed,5).error.is_empty(),"undersampled facet pairs rejected")
	check(not GemCutMetrics.public_frame(a).has("facets") and a.has("facets"),"public metrics detach detailed correspondence")
	for bad in [PackedFloat32Array(),PackedFloat32Array([1,1,1]),film([1,1,1])]:
		check(not GemCutMetrics.frame(bad).error.is_empty(),"invalid or insufficient film rejected")
	var invalid:=raw.duplicate();invalid[0]=NAN
	check(not GemCutMetrics.frame(invalid).error.is_empty(),"nonfinite film rejected")
	invalid=raw.duplicate();invalid[1]=-1
	check(not GemCutMetrics.frame(invalid).error.is_empty(),"negative radiance rejected")
	invalid=raw.duplicate();invalid[3]=0
	check(not GemCutMetrics.frame(invalid).error.is_empty(),"energy outside coverage rejected")
	invalid=raw.duplicate();invalid[3]=2
	check(not GemCutMetrics.frame(invalid).error.is_empty(),"excess coverage rejected")
	check(not GemCutMetrics.frame(raw,PackedInt64Array([1])).error.is_empty(),"mismatched correspondence rejected")
	check(not GemCutMetrics.frame(raw,ids,0).error.is_empty(),"invalid dark threshold rejected")
	var preference:=GemCutPreference.new()
	var baseline:={"error":"","mean_Y":1.0,"worst_Y":.5,"worst_dark_fraction":.2,"mean_contrast_cv":.7,"excess_modulation":.1}
	var score:=GemCutSearch.preference_score(baseline,baseline,preference)
	check(score.error.is_empty() and score.eligible and absf(score.utility-.78)<1e-12,"explicit preference utility")
	var worse:=baseline.duplicate();worse.mean_Y=.79
	check(not GemCutSearch.preference_score(worse,baseline,preference).eligible,"return floor enforced")
	worse=baseline.duplicate();worse.worst_dark_fraction=.81
	check(not GemCutSearch.preference_score(worse,baseline,preference).eligible,"relative dark-area limit enforced")
	check(not GemCutSearch.preference_score({"error":"failed transport"},baseline,preference).error.is_empty(),"failed candidates cannot be scored")
	worse=baseline.duplicate();worse.mean_Y=INF
	check(not GemCutSearch.preference_score(worse,baseline,preference).error.is_empty(),"nonfinite metrics cannot be scored")
	worse=baseline.duplicate();worse.mean_Y=0
	check(not GemCutSearch.preference_score(baseline,worse,preference).error.is_empty(),"dark normalization baseline rejected")
	var scores:Array[Dictionary]=[
		{"eligible":true,"axes":[1,1,1,1,.1]},
		{"eligible":true,"axes":[2,2,1,1,.1]},
		{"eligible":true,"axes":[1,1,1,1,.2]},
		{"eligible":false,"axes":[9,9,9,9,9]}]
	check(GemCutSearch.frontier(scores,preference)==PackedInt32Array([1,2]),"Pareto alternatives preserve real tradeoffs and exclude infeasible designs")
	preference.worst_return_weight=0;preference.dark_area_weight=0;preference.contrast_weight=0;preference.modulation_weight=0
	check(GemCutSearch.frontier(scores,preference)==PackedInt32Array([1]),"disabled preference axes cannot affect dominance")
	preference.mean_return_weight=1e300
	check(is_finite(GemCutSearch.preference_score(baseline,baseline,preference).utility),"large finite weights normalize without intermediate overflow")
	preference.mean_return_weight=-1
	check(not preference.validate().is_empty(),"negative weights rejected")
	check(not GemCutSearch.evaluate(null,null,[],{},8).error.is_empty(),"missing study inputs rejected before GPU access")
	print("Cut metrics: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
