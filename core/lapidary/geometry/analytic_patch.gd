class_name GemAnalyticPatch
extends RefCounted
## Continuous quadric patch clipped by outward half-spaces. CPU binary64
## reference for the procedural backend; not yet a GPU wire representation.
const V := preload("res://core/lapidary/geometry/geometry64.gd")
enum Kind { PLANE, CYLINDER, SPHERE }
var kind := Kind.PLANE
var center := PackedFloat64Array([0,0,0])
var axis := PackedFloat64Array([0,0,1])
var end := PackedFloat64Array([0,0,0])
var radius := 0.0
var offset := 0.0
var facet := 0
var clips: Array[PackedFloat64Array] = []
var lower := PackedFloat64Array([0,0,0])
var upper := PackedFloat64Array([0,0,0])

func intersect(origin: PackedFloat64Array, direction: PackedFloat64Array, min_t: float, max_t: float, tolerance: float) -> Dictionary:
	if not _box_hit(origin,direction,min_t,max_t,tolerance): return {}
	var roots: Array[float] = []
	if kind==Kind.PLANE:
		var denominator:=V.dot(axis,direction)
		if absf(denominator)<1e-30: return {}
		roots.append((offset-V.dot(axis,origin))/denominator)
	else:
		var o:=V.subtract(origin,center)
		var d:=direction
		if kind==Kind.CYLINDER:
			o=V.subtract(o,V.scale(axis,V.dot(o,axis)))
			d=V.subtract(d,V.scale(axis,V.dot(d,axis)))
		var a:=V.dot(d,d)
		if a<1e-30: return {}
		# Closest approach retains tiny radii when |o|^2-r^2 would round to |o|^2.
		var middle:=-V.dot(o,d)/a
		var nearest:=V.add(o,V.scale(d,middle))
		var squared:=radius*radius-V.dot(nearest,nearest)
		if squared<0: return {}
		var delta:=sqrt(squared/a)
		roots.append(middle-delta); roots.append(middle+delta)
	for t in roots:
		if t<=min_t or t>=max_t: continue
		var p:=V.add(origin,V.scale(direction,t))
		var inside:=true
		for halfspace in clips:
			if V.plane_distance(halfspace,p)>tolerance: inside=false;break
		if not inside: continue
		var normal:=axis
		if kind!=Kind.PLANE:
			normal=V.subtract(p,center)
			if kind==Kind.CYLINDER: normal=V.subtract(normal,V.scale(axis,V.dot(normal,axis)))
			normal=V.unit(normal)
		return {"t":t,"position":p,"normal":normal.duplicate(),"facet":facet,"kind":kind}
	return {}

func _box_hit(origin: PackedFloat64Array, direction: PackedFloat64Array, min_t: float, max_t: float, tolerance: float) -> bool:
	var lo:=min_t;var hi:=max_t
	for coordinate in 3:
		if absf(direction[coordinate])<1e-30:
			if origin[coordinate]<lower[coordinate]-tolerance or origin[coordinate]>upper[coordinate]+tolerance: return false
		else:
			var a:=(lower[coordinate]-tolerance-origin[coordinate])/direction[coordinate]
			var b:=(upper[coordinate]+tolerance-origin[coordinate])/direction[coordinate]
			lo=maxf(lo,minf(a,b));hi=minf(hi,maxf(a,b))
			if lo>hi: return false
	return true
