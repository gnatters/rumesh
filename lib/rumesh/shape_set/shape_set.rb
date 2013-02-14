require 'rumesh/shape_set/meshlabserver'
require 'rumesh/shape_set/mesh'
require 'rumesh/shape_set/volume'

Mesh.extend ShapeSet::Mesh


class ShapeSet
  # manages meshes within a workflow?
  # can reinitiate from any stage?
  
  @@border_index = []
  
  def initialize process_directory, path_to_meshlabserver, c3d_tool
    unless Dir.exist?(process_directory + "/volumes") and !Dir.new( process_directory + "/volumes").to_a.grep(/.nii$/).empty?
      raise ArgumentError, "invalid process directory, process directory must exist, and include a 'volumes' subdirectory which includes at least one '.nii' file."
    end
    raise ArgumentError, "invalid path to meshlabserver" unless File.exist? path_to_meshlabserver
    raise ArgumentError, "invalid path to c3d volume conversion tool" unless c3d_tool
    
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
  
  def convert_volumes
    
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

