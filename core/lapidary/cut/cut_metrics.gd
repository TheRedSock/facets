class_name GemCutMetrics
extends RefCounted
## Engineering measurements on associated linear XYZ, before the house print.
## Relative dark area is not leakage. Facet modulation is not a calibrated
## scintillation grade; correspondence uses the first visible surface only.

static func frame(xyz:PackedFloat32Array, facet_ids:=PackedInt64Array(), dark_ratio:=.2)->Dictionary:
	if xyz.is_empty() or xyz.size()%4!=0 or (not facet_ids.is_empty() and facet_ids.size()!=xyz.size()/4):
		return {"error":"Invalid film or primary-facet buffer length"}
	if not is_finite(dark_ratio) or dark_ratio<=0 or dark_ratio>=1:
		return {"error":"Relative dark threshold must be between zero and one"}
	var energy:=0.0;var coverage:=0.0;var opaque_sum:=0.0
	var values:=PackedFloat64Array();var facets:={}
	for i in xyz.size()/4:
		var alpha:float=xyz[i*4+3]
		for k in 4:
			if not is_finite(xyz[i*4+k]) or xyz[i*4+k]<0:
				return {"error":"Film contains nonfinite or negative values"}
		if alpha>1.00001:return {"error":"Film coverage exceeds one"}
		if alpha==0 and (xyz[i*4]!=0 or xyz[i*4+1]!=0 or xyz[i*4+2]!=0):
			return {"error":"Unassociated energy outside specimen coverage"}
		coverage+=alpha;energy+=xyz[i*4+1]
		if alpha<.999:continue
		var y:float=xyz[i*4+1]/alpha
		values.append(y);opaque_sum+=y
		if not facet_ids.is_empty() and facet_ids[i]>=0:
			var id:=facet_ids[i]
			if not facets.has(id):facets[id]={"sum":0.0,"pixels":0}
			facets[id].sum+=y;facets[id].pixels+=1
	if coverage<=0 or values.size()<4:return {"error":"Insufficient opaque specimen coverage for appearance metrics"}
	var mean:=opaque_sum/values.size()
	var squared:=0.0;var dark:=0
	for y in values:
		squared+=(y-mean)*(y-mean)
		if mean==0 or y<dark_ratio*mean:dark+=1
	for id in facets:facets[id]["mean_Y"]=facets[id].sum/facets[id].pixels;facets[id].erase("sum")
	return {"error":"","mean_Y":energy/coverage,"opaque_mean_Y":mean,
		"contrast_cv":sqrt(squared/values.size())/mean if mean>0 else 0.0,
		"relative_dark_fraction":float(dark)/values.size(),"dark_ratio":dark_ratio,
		"coverage_pixels":coverage,"opaque_pixels":values.size(),"facets":facets}

static func pair(a:Dictionary,b:Dictionary, minimum_pixels:=4)->Dictionary:
	if not a.get("error","").is_empty() or not b.get("error","").is_empty() or minimum_pixels<1:
		return {"error":"Invalid frame pair"}
	var first:Dictionary=a.get("facets",{});var second:Dictionary=b.get("facets",{})
	var keys:=first.keys();keys.sort()
	var weighted:=0.0;var pixels:=0;var faces:=0
	for id in keys:
		if not second.has(id):continue
		var weight:=mini(first[id].pixels,second[id].pixels)
		if weight<minimum_pixels:continue
		var x:float=first[id].mean_Y;var y:float=second[id].mean_Y
		weighted+=weight*absf(x-y)/(x+y) if x+y>0 else 0.0
		pixels+=weight;faces+=1
	if pixels==0:return {"error":"No sufficiently sampled shared primary facets"}
	return {"error":"","modulation":weighted/pixels,"matched_facets":faces,"matched_pixels":pixels,
		"matched_fraction":float(pixels)/mini(a.opaque_pixels,b.opaque_pixels)}

static func public_frame(value:Dictionary)->Dictionary:
	var result:=value.duplicate(true);result.erase("facets");return result
