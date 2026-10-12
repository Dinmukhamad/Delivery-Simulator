extends RefCounted



static var _cache: Dictionary = {}


static func box(size: Vector3, radius: float = 0.1, segments: int = 3) -> ArrayMesh:
	var dimensions: = Vector3(maxf(size.x, 0.001), maxf(size.y, 0.001), maxf(size.z, 0.001))
	var half: = dimensions * 0.5
	var bevel: = clampf(radius, 0.0001, minf(half.x, minf(half.y, half.z)) * 0.98)
	var steps: = clampi(segments, 1, 6)
	var key: = "%s:%s:%d" % [dimensions, bevel, steps]
	if _cache.has(key):
		return _cache[key] as ArrayMesh
	var core: = half - Vector3.ONE * bevel
	var surface: = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	var faces: = [
		[Vector3.RIGHT, Vector3.FORWARD, Vector3.UP, half.x, half.z, half.y], 
		[Vector3.LEFT, Vector3.BACK, Vector3.UP, half.x, half.z, half.y], 
		[Vector3.UP, Vector3.RIGHT, Vector3.FORWARD, half.y, half.x, half.z], 
		[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK, half.y, half.x, half.z], 
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP, half.z, half.x, half.y], 
		[Vector3.FORWARD, Vector3.LEFT, Vector3.UP, half.z, half.x, half.y]
	]
	for face: Array in faces:
		var normal_axis: Vector3 = face[0]
		var u_axis: Vector3 = face[1]
		var v_axis: Vector3 = face[2]
		var us: = _coordinates(float(face[4]), bevel, steps)
		var vs: = _coordinates(float(face[5]), bevel, steps)
		var origin: Vector3 = normal_axis * float(face[3])
		for u_index in range(us.size() - 1):
			for v_index in range(vs.size() - 1):
				var a: Vector3 = origin + u_axis * us[u_index] + v_axis * vs[v_index]
				var b: Vector3 = origin + u_axis * us[u_index + 1] + v_axis * vs[v_index]
				var c: Vector3 = origin + u_axis * us[u_index + 1] + v_axis * vs[v_index + 1]
				var d: Vector3 = origin + u_axis * us[u_index] + v_axis * vs[v_index + 1]
				for point: Vector3 in [a, d, c, a, c, b]:
					var closest: = Vector3(clampf(point.x, - core.x, core.x), 
						clampf(point.y, - core.y, core.y), clampf(point.z, - core.z, core.z))
					var outward: = (point - closest).normalized()
					surface.set_normal(outward)
					surface.add_vertex(closest + outward * bevel)
	surface.index()
	var mesh: ArrayMesh = surface.commit()
	_cache[key] = mesh
	return mesh


static func _coordinates(half_extent: float, bevel: float, steps: int) -> Array[float]:
	var values: Array[float] = []
	for index in range(steps + 1):
		values.append( - half_extent + bevel * float(index) / float(steps))
	for index in range(steps + 1):
		values.append(half_extent - bevel + bevel * float(index) / float(steps))
	return values
