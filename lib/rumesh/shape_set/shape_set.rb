require 'rumesh/shape_set/volume'
require 'rumesh/shape_set/meshlabserver'

class ShapeSet
  # manages meshes within a workflow?
  # can reinitiate from any stage?
  
  @@border_index = []
  
  def initialize process_directory, path_to_meshlabserver, c3d_tool
    unless Dir.exist?(process_directory + "/volumes") and !Dir.new( process_directory + "/volumes").to_a.grep(/.nii$/).empty?
      raise ArgumentError, "invalid process directory, process directory must exist, and include a 'volumes' subdirectory which includes at least one '.nii' file."
    end
    raise ArgumentError, "invalid path to meshlabserver" unless File.exist? path_to_meshlabserver
    raise ArgumentError, "invalid path to meshlabserver" unless c3d_tool
    
    @proc_dir = ( process_directory.end_with? "/" ? process_directory : process_directory + "/" )
    @mls = path_to_meshlabserver
    
    @paths = Hash.new {|h,k| h[k] = @proc_dir }
    @paths[:volumes_dir]           += "volumes"
    @paths[:converted_volumes_dir] += "volumes/converted"
    @paths[:stl_dir]               += "stl_files"
    @paths[:obj_dir]               += "obj_files"
    @paths[:obj_raw_dir]           += "obj_files/raw"
    @paths[:obj_non_manifold_dir]  += "obj_files/smoothed"
    @paths[:obj_smoothed_dir]      += "obj_files/smoothed"
    @paths[:obj_decimated_dir]     += "obj_files/decimated"
    @paths[:obj_final_dir]         += "obj_files/final"
    @paths[:json_dir]              += "json_meshes"
    @paths[:logs_dir]              += "logs"
    #@paths[:mls_log]               += "logs/mls.txt"
    @paths[:scripts_dir]           += "scripts"
    
    
    @shapes = {} # shape_id => { :name, :neighbors }
    @meshes = {} # mesh_id => { :mesh, :border_indices, :border_locations, :matches, :borders }
    @scripts = []
    @volume = nil
    
  end
  
  
  def consolidate_volumes
    
    @shapes
  end
  
  def write_mls_script type, params, 
    
  end
  
  def run_mls_script script_name, input_file, output_file
    script_location = "#{@paths[:scripts_dir]}/#{script_name}.mls"
    stdout, stderr, status = MeshLabServer.run script_location, input_file, output_file
    File.open("#{@paths[:logs_dir]}/#{script_name}-#{Time.now.to_i}.log", 'w') { |f| f.puts stdout }
    status
  end
  
  def build_borders_index
    #
    
    #  create a border for each set of vertices shared between a set of meshes
    
    
  end
  
  def write_json_file path
    
  end
  
  def save_progress
    
  end
  
end


class Mesh
  
  attr_reader :boundaries
  
  # Build an index of boundary vertices, unconnected boundaries are indexed seperately.
  # Boundary vertices are detected as they are edges which are only represented in a single face
  def find_boundaries
    @fbuffer.ensure_uniqueness
    
    @boundaries = []
    boundary_edges = []
    
    @vbuffer.each_index do |i|
      # boundary vertices have identifiable as they have two or more neighboring vertices which are 
      #  only included in one face which includes this vertex.
      n_counts = (@fbuffer.faces_with(i).flatten - [i]).inject({}) { |hsh,id| hsh[id] = hsh[id] ? hsh[id] + 1 : 1 ; hsh }
      n_counts.each { |n,count| boundary_edges << (i<n ? [i,n] : [n,i]) if count == 1 }
    end
    boundary_edges.uniq!.flatten!
    
    partial_boundary = []
    
    # keep starting new boundaries until there are no boundary edges left to start with
    until boundary_edges.empty? do
      partial_boundary = [boundary_edges.shift, boundary_edges.shift]
      
      # until current partial boundary forms a closed loop
      until partial_boundary.first == partial_boundary.last
        # pick the first potential next edge and add it to the current partial boundary... should it choose an edge more systematically???
        next_e = boundary_edges.slice!( (boundary_edges.index(partial_boundary.last)/2)*2, 2 ) # this will error out (due to index returning nil) to avoid looping infinitely in case of funny data
        partial_boundary << ( partial_boundary.last == next_e.first ? next_e.last : next_e.first )
      end
      
      @boundaries << partial_boundary[0...-1]
      partial_boundary = []
    end
    @boundaries
  end
  
  # @return (Boolean) indicates whether or not the boundaries representation has been calculated or not.
  def has_boundaries?
    @boundaries ? true : false
  end
  
  def clear_boundaries!
    @boundaries = nil
  end
  
  
  def shared_boundary_vertices other
    # assumes boundary representations are up to date if they exist
    find_boundaries unless has_boundaries?
    other.find_boundaries unless other.has_boundaries?
    
    own_boundaries = boundaries
    other_boundaries = other.boundaries
    
    own_boundary_bbs = own_boundaries.map { |b| subset_bounding_box b }
    other_boundary_bbs = other_boundaries.map { |b| other.subset_bounding_box b }
    
    matches = Hash.new
    
    own_boundaries.each_with_index do |ownb, i|
      other_boundaries.each_with_index do |otherb, j|
        next unless own_boundary_bbs[i].intersects? other_boundary_bbs[j]
        
        i = j = -1
        verts = ( nget(ownb).to_a.map         { |t| t.concat [0, i += 1] } + 
                  other.nget(otherb).to_a.map { |t| t.concat [1, j += 1] } ).sort!
                
        prev = nil
        until verts.empty?
          v = verts.shift
          if (v[3] > prev[3] && v[2] == prev[2] && v[1] == prev[1] && v[0] == prev[0] rescue false)
            # this will only be true when prev is from ownb and v is from otherb
            matches[prev[4]] = v[4]
            prev = nil
          else
            prev = v
          end
        end
        
      end
    end
    matches
  end
  
  
  def update_vertices_from_obj input
    input = File.open(input, 'r') unless input =~ /\n/
    
    vertices = Array.new
    vertex_normals = Array.new
    
    types = [
      [:vertices,        /^\s*v\s+(\-?\d*\.\d+)\s+(\-?\d*\.\d+)\s+(\-?\d*\.\d+)/],
      [:vertex_normals,  /^\s*vn\s+(\-?\d*\.\d+)\s+(\-?\d*\.\d+)\s+(\-?\d*\.\d+)/]
    ]

    input.each_line do |line|
      type = match = nil
      types.each do |t, re|
        next unless match = line.scan(re).first
        type = t
        break 
      end
      case type
      when :vertices then       vertices.push       match[0].to_f, match[1].to_f, match[2].to_f
      when :vertex_normals then vertex_normals.push match[0].to_f, match[1].to_f, match[2].to_f
      end      
    end
    
    @vbuffer  = VertexBuffer.new  :array => vertices
    @vnbuffer = VectorBuffer.new  :array => vertex_normals
  end
  
end
