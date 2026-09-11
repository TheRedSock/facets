class_name GemCrystalHabit
extends Resource
## Convex crystal habit in its own Cartesian crystal frame. Plane distances
## are millimeters, normals are outward unit vectors. These are physical face
## supports, not Miller indices; lattice-to-Cartesian conversion is explicit.
## Changing supports changes growth extent while retaining declared face angles.
@export var faces: Array[Plane] = [Plane(Vector3.RIGHT,.1),Plane(Vector3.LEFT,.1),Plane(Vector3.UP,.1),Plane(Vector3.DOWN,.1),Plane(Vector3.BACK,.1),Plane(Vector3.FORWARD,.1)]
@export_multiline var source_note := "Authored habit; not a crystal-growth prediction."

func validate()->PackedStringArray:
	var errors:=PackedStringArray()
	if faces.size()<4 or faces.size()>64:errors.append("Habit needs 4..64 support planes")
	for face in faces:
		if not face.normal.is_finite() or absf(face.normal.length_squared()-1)>1e-5 or not is_finite(face.d) or face.d<1e-6 or face.d>10000:
			errors.append("Habit needs unit normals and positive finite millimeter supports")
	return errors

## Geometric template, without a species claim. Radius is prism apothem.
## A zero termination angle makes flat ends; otherwise inclined face normals
## retain this angle as the axial support changes.
static func prism(sides:int, radius_mm:float, half_length_mm:float, termination_deg:=0.0)->GemCrystalHabit:
	var habit:=GemCrystalHabit.new();habit.faces.clear()
	if sides<3 or sides>20 or not is_finite(termination_deg) or termination_deg<0 or termination_deg>=89:return habit
	for i in sides:
		var n:=Vector3(cos(TAU*i/sides),sin(TAU*i/sides),0)
		habit.faces.append(Plane(n,radius_mm))
		if termination_deg>0:
			var angle:=deg_to_rad(termination_deg)
			for sign_value in [-1.0,1.0]:habit.faces.append(Plane(n*sin(angle)+Vector3.BACK*(sign_value*cos(angle)),half_length_mm*cos(angle)))
	if termination_deg==0:
		habit.faces.append(Plane(Vector3.BACK,half_length_mm));habit.faces.append(Plane(Vector3.FORWARD,half_length_mm))
	return habit
