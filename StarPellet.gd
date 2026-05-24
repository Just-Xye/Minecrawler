@tool
extends MeshInstance3D

func _ready():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Define dimensions
	var outer_radius: float = 1.0
	var inner_radius: float = 0.3
	var thickness: float = 0.2
	
	# Define 3D points
	var top = Vector3(0, thickness, 0)
	var bottom = Vector3(0, -thickness, 0)
	
	var n_out = Vector3(0, 0, -outer_radius)
	var e_out = Vector3(outer_radius, 0, 0)
	var s_out = Vector3(0, 0, outer_radius)
	var w_out = Vector3(-outer_radius, 0, 0)
	
	var ne_in = Vector3(inner_radius, 0, -inner_radius)
	var se_in = Vector3(inner_radius, 0, inner_radius)
	var sw_in = Vector3(-inner_radius, 0, inner_radius)
	var nw_in = Vector3(-inner_radius, 0, -inner_radius)
	
	# Array of outer points and matching inner points
	var outer = [n_out, e_out, s_out, w_out]
	var inner = [ne_in, se_in, sw_in, nw_in]
	
	# Build the 8 top faces and 8 bottom faces
	for i in range(4):
		var next_i = (i + 1) % 4
		
		# Top Pyramids
		st.add_vertex(top)
		st.add_vertex(inner[i])
		st.add_vertex(outer[i])
		
		st.add_vertex(top)
		st.add_vertex(outer[i])
		st.add_vertex(inner[(i + 3) % 4])
		
		# Bottom Pyramids (Clockwise order flipped for normals)
		st.add_vertex(bottom)
		st.add_vertex(outer[i])
		st.add_vertex(inner[i])
		
		st.add_vertex(bottom)
		st.add_vertex(inner[(i + 3) % 4])
		st.add_vertex(outer[i])
	
	# Generate normals and assign mesh
	st.generate_normals()
	self.mesh = st.commit()
