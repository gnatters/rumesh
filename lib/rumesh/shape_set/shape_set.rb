require 'fileutils'
require 'json'


class ShapeSet
  # manages meshes within a workflow?
  # can reinitiate from any stage?
  
  @@border_index = []
  
  attr_accessor :shapes
  attr_accessor :meshes
  attr_accessor :volume
  attr_accessor :paths
  
  def initialize process_directory, path_to_c3d_tool, path_to_meshlabserver, mls_exec_dir=nil
    unless Dir.exist?(process_directory+"/volumes") and !(files_in(process_directory+"/volumes").keys&(["nii"]+Convert3D.input_formats.map{|e|e[1..-1]})).empty?
      !Dir.new( process_directory + "/volumes").to_a.grep(/.nii$/).empty?
      raise ArgumentError, "invalid process directory, process directory must exist, and include a 'volumes' subdirectory which includes at least one '.nii' file."
    end
    raise ArgumentError, "invalid path to meshlabserver" unless File.exist? path_to_meshlabserver
    raise ArgumentError, "invalid path to c3d volume conversion tool" unless File.exist? path_to_c3d_tool
    
    @proc_dir = ( process_directory.end_with?("/") ? process_directory : process_directory + "/" )
    @c3d = Convert3D.setup path_to_c3d_tool
    @mls = MeshLabServer.setup path_to_meshlabserver, mls_exec_dir
    
    # setup directory structure for process directory
    @paths = Hash.new {|h,k| h[k] = @proc_dir }
    @paths[:volumes_dir]            += "volumes"
    @paths[:converted_volumes_dir]  += "volumes/converted"
    @paths[:stl_dir]                += "stl_files"
    @paths[:obj_dir]                += "obj_files"
    @paths[:obj_raw_dir]            += "obj_files/raw"
    @paths[:obj_manifold_dir]       += "obj_files/manifold"
    #@paths[:obj_non_manifold_dir]   += "obj_files/smoothed"
    @paths[:obj_smoothed_dir]       += "obj_files/smoothed"
    @paths[:obj_decimated_dir]      += "obj_files/decimated"
    @paths[:obj_final_dir]          += "obj_files/final"
    @paths[:json_dir]               += "json_meshes"
    @paths[:logs_dir]               += "logs"
    @paths[:mls_logs_dir]           += "logs/mls"
    @paths[:scripts_dir]            += "scripts"
    
    @paths.each do |dir, path|
      if dir.to_s.end_with? "_dir" and not File.directory? path
        Dir.mkdir path 
      elsif not File.exist? path
        File.write(path, "")
      end
    end
    
    @shapes = Hash.new {|h,k| h[k]={}} # shape_id => { :name, :neighbors }
    @meshes = Hash.new {|h,k| h[k]={}} # mesh_id => { :mesh, :boundary_indices, :boundary_vertices, :matches, :borders }
    @scripts = [] # maybe @mls or @meshes should handle this?
    @volume = nil
  end
  
  
  
  def repair_non_manifold_edges
        
    # load all mesh buffers into a single vbuffer and fbuffer
    # create a map for each vertex in the global vbuffer mapping it onto a specific vertex(es)  in individual mesh(es)
    # thus when it comes to updating squares etc, the changes can be mapped onto the individual meshes
    
    find_shared_boundary_vertices unless @meshes.first.last[:matches]
    
    # maybe mesh merging isn't event the solution?
    # maybe just need some kind of cross referencing
    # before diagnosing the type of a nm-vertex, check whether it's on the boundary
    # => if it is then fetch any missing square from their respective meshes by searching the boundaries 
    # thus a global index of squares is still required
    
    # determine whether to flip the normal based on shape indices
    
    squares = Hash.new {|h,k| h[k]=[]} # {mesh_id: [{{ faces:[f1,f2], half_normal:[x,y,z], vertices:[vertex_indices] }, ...}]}
    actions = Hash.new {|h,k| h[k]=Hash.new {|i,l| i[l]=[]}} # {mesh_id: {nudge_vertices:, add_vertices:, add_triangles:, remove_triangles:, update_triangles:}, ... }
    
    @meshes.each do |mesh_id, meta|
      
      natural_shape = mesh_id.split("-").last
      next_vertex_i = @meshes[mesh_id][:mesh].vbuffer.size-1
      
      # identify non-manifold edges
      nm_edges = []
      meta[:mesh].fbuffer.build_index
      
      meta[:mesh].vbuffer.each_index do |i|
        # boundary vertices have identifiable as they have two or more neighboring vertices which are 
        #  only included in one face which includes this vertex.
        (meta[:mesh].fbuffer.faces_with(i).flatten - [i]).inject(Hash.new(0)) { |hsh,id| hsh[id] += 1; hsh }.
          each { |n,count| nm_edges << (i<n ? [i,n] : [n,i]) if count == 4 }
      end
      nm_edges.uniq!
      nm_edges.flatten!
      nm_edges_kept = nm_edges.dup
      
      # group non-manifold vertices into seams
      seams = []
      
      until nm_edges.empty?
        new_seam = [nm_edges.shift, nm_edges.shift]
        new_vertices = new_seam.dup
        
        until new_vertices.empty?
          new_seam.concat new_vertices = (new_vertices.map do |v|
            items = []
            while (newvi = nm_edges.index(v))
              items << nm_edges.slice!((newvi/2)*2, 2)
            end
            items
          end.flatten.compact.uniq - new_seam)
        end
        seams << { :vertices => new_seam }
      end
      
      nm_edges = nm_edges_kept
      
      seams.map do |seam|
        seam[:squares] = [] # references items in squares
        seam[:gsquares] = []
        seam[:fsquares] = []
        seam[:groups] = [] # like squares but groups items in sub-arrays
        
        seam[:vertices].each do |v|
          
          # find native squares
          square_refs, squares[mesh_id] = native_squares_of_vertex v, squares[mesh_id]
          
          seam[:squares] << square_refs
          seam[:gsquares] << [] # guest squares
          seam[:fsquares] << [] # foreign squares
          
          # if this is a boundary vertex then find squares from other meshes using this mesh's matches
          if boundary_vertices(false).include? v
            
            # needs to influence all connected squares... 
            # => but only count ones required to complete the shape which this mesh is natural to
            # so as well as native squares, there are guest squares (also counted) and forign squares which are modified but not counted
            
            external_square_refs = Hash[ meta[:matches].map do |other_mesh_id, matches|
              next unless matches.has_key?(v)
              new_square_refs, squares[other_mesh_id] = @meshes[other_mesh_id][:mesh].native_squares_of_vertex matches[v], squares[other_mesh_id]
              [other_mesh_id, new_square_refs]
            end ]
            
            if other_mesh_id.split("-").include? natural_shape
              # this is guest square
              seam[:gsquares].last << external_square_refs
            else # this is a foreign square
              seam[:fsquares].last << external_square_refs
            end
          end
          
          # fill out the squares representation: normal, vertices etc
          seam[:squares].last.each do |sqri|
            next if squares[mesh_id][sqri][:half_normal] # skip if this square isn't actually new
            squares[mesh_id][sqri][:half_normal] = @meshes[mesh_id][:mesh].fbuffer.calculate_normal_of(squares[mesh_id][sqri][:faces].first, @meshes[mesh_id][:mesh].vbuffer).map {|x| x/2}
            squares[mesh_id][sqri][:vertices] = @meshes[mesh_id][:mesh].fbuffer.get(squares[mesh_id][sqri][:faces]).flatten.uniq
            # calculate the point which the center of the square plus half the normal
            squares[mesh_id][sqri][:half_normal_point] = @meshes[mesh_id][:mesh].vbuffer.average_of(squares[mesh_id][sqri][:vertices]).each_with_index.map { |n,i| n + squares[mesh_id][sqri][:half_normal][i] }
          end
          
          # and same for guest and foreign squares
          (seam[:gsquares]+seam[:fsquares]).each do |other_mesh_id, square_refs|
            square_refs.each do |sqri|
              next if squares[other_mesh_id][sqri][:half_normal] # skip if this square isn't actually new
              squares[other_mesh_id][sqri][:half_normal] = @meshes[other_mesh_id][:mesh].fbuffer.calculate_normal_of(squares[other_mesh_id][sqri][:faces].first, @meshes[other_mesh_id][:mesh].vbuffer).map {|x| x/2}
              squares[other_mesh_id][sqri][:vertices] = @meshes[other_mesh_id][:mesh].fbuffer.get(squares[other_mesh_id][sqri][:faces]).flatten.uniq
              # calculate the point which the center of the square plus half the normal
              squares[other_mesh_id][sqri][:half_normal_point] = @meshes[other_mesh_id][:mesh].vbuffer.average_of(squares[other_mesh_id][sqri][:vertices]).each_with_index.map { |n,i| n + squares[other_mesh_id][sqri][:half_normal][i] }
            end
          end
          
          # apply grouping rules to squares
          seam[:groups] << seam[:squares].last+seam[:gsquares].last.to_a.
                            inject( Hash.new {|h,k| h[k]=[]} ) do |hsh,sqri|
                              if sqri.kind_of? Numeric
                                hsh[squares[mesh_id][sqri][:half_normal_point]] << sqri
                              elsif sqri.kind_of? Hash
                                # reverse the half_normal_point for this grouping if this is a guest square but is not natural to natural_shape
                                gof_mesh_id, gof_square_id = sqri.to_a.first
                                hnp = squares[guest_mesh_id][guest_square_id][:half_normal_point]
                                if gof_mesh_id.split("-").last != natural_shape
                                  hnp = hnp.each_with_index.map { |n,i| n-squares[gof_mesh_id][gof_square_id][:half_normal][i]*2 }
                                end
                                hsh[hnp] << sqri
                              end
                              hsh
                            end.values.sort_by { |s| s.length }
          
          # diagnose the type of vertex v and process it accordingly 
          new_vs = []
          groups = []
          squares_to_retriangulate = []

          # foreign squares need to be paired with the vertex which after nudging is closest to their center point
          # this means that the foreign mesh just needs to have the boundary vertices in question nudged to maintain the match
          # => and its matches reference updated
          
          new_vs = [v,next_vertex_i+=1]
          actions[mesh_id][:add_vertices] << @meshes[mesh_id][:mesh].vbuffer[v]
          
          case [ nm_edges.count(v), seam[:squares].last.count, seam[:groups].last.count]
          when [1,6,4] # top
            squares_to_retriangulate = seam[:groups].last[0..1].flatten
            groups = seam[:groups].last[2..3]
          when [1,6,2] # bottom
            groups = seam[:groups].last
          when [1,7,3] # half_bottom
            groups = [seam[:groups].last[0..1].flatten, seam[:groups].last[2]]
          when [1,7,5] # half-top
            groups = seam[:groups].last[3..4]
            seam[:groups].last[0..2].flatten.each do |sqri|
              sqr_hn = if sqri.kind_of? Numeric then squares[mesh_id][sqri][:half_normal]
              elsif sqri.kind_of? Hash
                gof_mesh_id, gof_square_id = sqri.to_a.first
                squares[gof_mesh_id][gof_square_id][:half_normal]
              end
              if groups.first.any? { |sqrj| 
                  sqr_hn2 = if sqri.kind_of? Numeric then squares[mesh_id][sqri][:half_normal]
                  elsif sqri.kind_of? Hash
                    gof_mesh_id, gof_square_id = sqri.to_a.first
                    squares[gof_mesh_id][gof_square_id][:half_normal]
                  end
                  sqr_hn2 == sqr_hn
                }
                groups.first << sqri 
              elsif groups.last.any? { |sqrj| 
                sqr_hn2 = if sqri.kind_of? Numeric then squares[mesh_id][sqri][:half_normal]
                elsif sqri.kind_of? Hash
                  gof_mesh_id, gof_square_id = sqri.to_a.first
                  squares[gof_mesh_id][gof_square_id][:half_normal]
                end
                sqr_hn2 == sqr_hn
                }
                groups.last << sqri
              else
                squares_to_retriangulate = [sqri]
              end
            end
            # also add a triangle to fill split edge, 
            split_neighbor = (squares[groups.first.last][:vertices].flatten & squares[groups.last.last][:vertices].flatten - [v]).first
            actions[mesh_id][:new_triangles] << [new_vs[0],new_vs[1],split_neighbor]
          when [2,8,4] # middle or corner
            case seam[:groups].last.map(&:length)
            when [2,2,2,2] # middle
              groups = [seam[:groups].last[0],[]]
              seam[:groups].last[1..-1].each do |g|
                sqr_hnp1 = if sqri.kind_of? Numeric then squares[mesh_id][g.first][:half_normal_point]
                elsif sqri.kind_of? Hash
                  gof_mesh_id, gof_square_id = g.first.to_a.first
                  squares[gof_mesh_id][gof_square_id][:half_normal_point]
                end
                sqr_hnp2 = if sqri.kind_of? Numeric then squares[mesh_id][groups.first.first][:half_normal_point]
                elsif sqri.kind_of? Hash
                  gof_mesh_id, gof_square_id = groups.first.first.to_a.first
                  squares[gof_mesh_id][gof_square_id][:half_normal_point]
                end
                # test if first item in this group (representative of whole group) has h_n_p 1 unit away from h_n_p of first item of first group 
                if sqr_hnp1.zip(sqr_hnp2).map { |a,b| (a-b).abs }.count(1) == 1
                  groups.first.concat g
                else
                  groups.last.concat g
                end
              end
            when [1,2,2,3] # corner
              groups = [seam[:groups].last[0..2].flatten, seam[:groups].last[3]]
            end
          when [3,9,3] # closedY
            # add a third copy of the vertex
            new_vs = [v,next_vertex_i+=1]
            actions[mesh_id][:add_vertices] << @meshes[mesh_id][:mesh].vbuffer[v]
            groups = seam[:groups].last
          when [3,9,4] # openY
            groups = [seam[:groups].last[0..2].flatten, seam[:groups].last[3]]
          when [6,12,4] # star
            # add a third and fourth copy of the vertex
            new_vs = [v,next_vertex_i+=1,next_vertex_i+=1]
            actions[mesh_id][:add_vertices] << @meshes[mesh_id][:mesh].vbuffer[v]
            actions[mesh_id][:add_vertices] << @meshes[mesh_id][:mesh].vbuffer[v]
            groups = seam[:groups].last
          else
            throw "un-classifiable vertex! #{v} :: #{[ nm_edges.count(v), seam[:squares].last.count, seam[:groups].last.count]}"
          end
          
          squares_to_retriangulate.each do |sqri|
            # split vertex v within this square
            if sqri.kind_of? Numeric
              squares[mesh_id][sqri][:vertices].map! { |sv| ( sv==v ? new_vs : sv ) }
            elsif sqri.kind_of? Hash
              # guest or foreign squares are more complicated to reference...
              gof_mesh_id, gof_square_id = sqri.to_a.first
              squares[gof_mesh_id][gof_square_id][:vertices].map! { |sv| ( sv==v ? new_vs : sv ) }
            end
            squares[mesh_id][sqri][:vertices].map! { |sv| ( sv==v ? new_vs : sv ) }
          end
          
          throw "Square group - split vertices mismatch" unless new_vs.length == groups.length
          
          # update references to v and nudge new_vs apart
          groups.each_with_index do |group, i|
            nudge_vector = group.map { |gs| squares[mesh_id][gs][:half_normal] }.transpose.map { |ns| ns.inject(:+) }
            l = Math.sqrt(nudge_vector[0]**2 + nudge_vector[1]**2 + nudge_vector[2]**2)*1000
            
            # need to nudge this vertex in this mesh, and in any guest or foreign meshes which are aligned to this post-split vertex
            actions[mesh_id][:nudge_vertices][new_vs[i]] = nudge_vector.map! { |n| n/l } # nudge a distance of about 0.001
            
            (seam[:gsquares]+seam[:fsquares]).map{|hsh| hsh.to_a.first}.each do |other_mesh_id, sqri|
              
              
              squares[other_mesh_id][sqri]
              # which vertex in this square is v???
              
              
              actions[other_mesh_id][]
            end
            
            group.each { |sqri| squares[sqri][:vertices].map! { |sv| ( sv==v ? new_vs[i] : sv ) } }
            
            
          end
          
          seam
        end
        
      end
      
      
      # if two foreign squares from different meshes share an edge
      
      
      # if the the shape on the other side of the mesh from a square that is being remeshed has...
      
      
      # when identifying the squares of a given vertex
      # need to be able to bring in "guest squares from other meshes"
      # so squares should be loaded globally but referneced by mesh, and vertices should be able to references squares from other meshes
      
      # if a border vertex is split in one mesh, it must also be split in bordering meshes...
      # => sharing the squares index between all meshes and only should handle this
      
      
      # there's is a problem of the creation of simple triangle holes potentially.
      # => this can be solved later by the scanning for missing triangles that are not filled by any other mesh
      # => and filling them then... or something cleverer if i can be bothered later
      
    end
    
    
  end
  
  
  
  
  
  
  
  def convert_volumes verbose=true
    convertable_files = files_in(:volumes_dir).select { |t,fs| @c3d.input_formats.include? ".#{t}" }.values.
                          flatten.map { |f| "#{@paths[:volumes_dir]}/#{f}" }
    convertable_files.each do |file_path|
      file_name, file_ext = file_path.split("/").last.split(".",2)
      
      # make sure there are no spaces in the file name
      if file_name[/\s/]
        new_name = file_name.gsub(/\s/,"_")
        new_path = "#{@paths[:volumes_dir]}/#{new_name}.#{file_ext}"
        File.rename file_path, new_path
        puts "#{file_name} renamed as #{new_name}" if verbose
        file_name = new_name
        file_path = new_path
      end
      
      print "Converting #{file_name}.#{file_ext}:" if verbose
      @c3d.convert file_path.gsub(" ","\ "), "#{paths[:volumes_dir]}/#{file_name}.nii"
      puts "done" if verbose
      FileUtils.move file_path, "#{paths[:converted_volumes_dir]}/#{file_name}.#{file_ext}"
    end
  end
  
  def load_volumes prefer_bin=true, verbose=true
    bin_files = files_in(:volumes_dir)["bin"].map { |f| "#{@paths[:volumes_dir]}/#{f}" }
    input_files = if prefer_bin and !bin_files.empty?
      bin_files
    else
      nifti_files = files_in(:volumes_dir)["nii"].map { |f| "#{@paths[:volumes_dir]}/#{f}" }
    end
    
    print "Loading volumes:" if verbose
    @volume = Volume.new input_files.shift
    print "." if verbose
    @volume.merge!(Volume.new(input_files.shift)) and (print "." if verbose) until input_files.empty?
    puts "done" if verbose
    
    @volume.labels.each { |value,labels| @shapes[value][:name] = labels.join("+") }
    @volume
  end
  
  def generate_surfaces verbose=true
    print "Generating surfaces:" if verbose
    @volume.build_label_surfaces @paths[:stl_dir]
    print "done" if verbose
  end
    
  def load_meshes dir, verbose=true
    initial = @meshes.empty?
    mesh_files = files_in(dir).select { |t,fs| ["obj","stl"].include? t }.values.flatten.map { |f| "#{dir}/#{f}" }
    print "Loading meshes:" if verbose
    mesh_files.each do |file_path|
      file_name = file_path.split("/").last.split(".").first
      next unless initial or @meshes.has_key?(file_name)
      
      @meshes[file_name][:mesh] = ::Mesh.new file_path
      print "." if verbose
    end
    print "done" if verbose
    @meshes
  end
  
# this isn't really needed ???
#  def find_boundary_vertices verbose=true
#    @meshes.each { |mesh_id, meta| meta[:boundary_indices] = meta[:mesh].boundary_vertices }
#  end
    
  def find_shared_boundary_vertices verbose=true
    @meshes.each { |mesh_id, meta| meta[:bb] = meta[:mesh].bounding_box }
    @meshes.keys.each { |mesh_id| @meshes[mesh_id][:matches] = {} }
    @meshes.keys.product(@meshes.keys).map(&:sort).uniq.each do |m1, m2|
      next if m1 == m2 or !@meshes[m1][:bb].intersects?(@meshes[m2][:bb])
      
      matches = @meshes[m1][:mesh].shared_boundary_vertices(@meshes[m2][:mesh])
      next if matches.empty?
      @meshes[m1][:matches][m2] = matches
      @meshes[m2][:matches][m1] = matches.invert
      print"."
    end
  end
  
  def smooth_meshes verbose=true
    print "Smoothing meshes:" if verbose
    # write and run smoothing scripts
    write_mls_script "smoothing", :taubin_laplacian_smoothing
    @meshes.each do |mesh_id, meta|
      file_name = "#{mesh_id}.obj"
      input_file = "#{@paths[:obj_manifold_dir]}/#{file_name}"
      output_file = "#{@paths[:obj_smoothed_dir]}/#{file_name}"
      run_mls_script "smoothing", input_file, output_file
      print "." if verbose
    end
    puts "done" if verbose
    
    print "Updating vertices:" if verbose
    # reload vertex positions
    @meshes.each do |mesh_id, meta|
      file_path = "#{@paths[:obj_smoothed_dir]}/#{mesh_id}.obj"
      meta[:mesh].update_vertices_from_obj file_path
      # boundary indices should not have changed although boundary vertices have been moved
      meta[:boundary_vertices] = meta[:mesh].vbuffer.get(meta[:boundary_indices])
      print "." if verbose
    end
    puts "done" if verbose
  end
  
  def decimate_meshes factor, verbose=true
    print "Decimating meshes:" if verbose
    # write and run decimation scripts
    @meshes.each do |mesh_id, meta|
      # factor is applied to the number of non-boundary faces, since boundary edges mustn't be altered
      target_face_number = ((meta[:mesh].fbuffer.size - meta[:mesh].boundary_faces.size)*factor).to_i
      
      file_name = "#{mesh_id}.obj"
      script_name = "decimate_#{mesh_id}"
      input_file = "#{@paths[:obj_smoothed_dir]}/#{file_name}"
      output_file = "#{@paths[:obj_decimated_dir]}/#{file_name}"
      write_mls_script script_name, :qec_decimation, :TargetFaceNum => target_face_number
      run_mls_script script_name, input_file, output_file
      print "." if verbose
    end
    puts "done" if verbose
    
    # reload meshes
    load_meshes @paths[:obj_decimated_dir]
    
    analyze_meshes2
    
    print "Reindexing meshes:" if verbose
    @meshes.keys.each { |mesh_id| @meshes[mesh_id][:new_boundary_indices] = {} }
    
    @meshes.each do |mesh_id, meta|
      boundary_index_map = Hash.new
      # update the boundary indices from the boundary positions
      meta[:mesh].vbuffer.build_index unless meta[:mesh].vbuffer.indexed?
      meta[:boundary_vertices].each_with_index do |vertex,i|
        matches = vertex.map { |value| meta[:mesh].vbuffer.locate(value) }.inject(:&)
        warn("WARNING: multiple matches for boundary vertex #{i} !") if matches.size > 1
        warn("WARNING: lost boundary vertex #{i} !") if matches.size < 1
        meta[:new_boundary_indices][i] = matches.first
        boundary_index_map[meta[:boundary_indices][i]] = meta[:new_boundary_indices][i]
      end
      
      # update borders and remove matches
      #meta[:neighbors] = meta[:matches].keys
      #meta[:matches] = nil
      
      meta[:borders].keys.each do |border_id|
        
        meta[:borders][border_id].map! { |i| boundary_index_map[i] }
        
        throw "missing border index! :: #{meta[:borders][border_id]}" unless meta[:borders][border_id].all?
        
      end
      
      print "." if verbose
    end
    puts "done" if verbose
  end
  
  def realign_boundaries
    
    mesh_ids = @meshes.keys
    
    until mesh_ids.empty?
      meta = @meshes[(mesh_id = mesh_ids.shift)]
      
      # create a hash like { border_id => ids_of_other_meshes_which_share_this_border_excluding_meshes_already_processed, ... }
      shared_borders = ( meta[:neighbors] & mesh_ids ).inject( Hash.new {|h,k| h[k]=[]} ) do |hsh, mid|
        ( @meshes[mid][:borders].keys & meta[:borders].keys ).each { |border_id| hsh[border_id] << mid }
        hsh
      end
      
      shared_borders.each do |border_id, other_meshes|
        
        meta[:borders][border_id].each_with_index do |vid, i|
          
          # create hash like { mesh_id => corresponding_vertex_index } for all meshes including this boundary vertex
          vertex_indices = other_meshes.inject({mesh_id => vid}) { |hsh, mid| hsh[mid] = @meshes[mid][:borders][border_id][i]; hsh }
          
          # run a little check
          throw "problem!" unless vertex_indices.map do |meshi, verti|
            @meshes[meshi][:mesh].vbuffer.get[verti].to_a
          end.transpose.map {|d| d.uniq.length == 1}.all?
          
          # could also attempt an extra order of normal smoothing of neighbors of boundary vertices...
          
          average_vertex = vertex_indices.map { |meshi, verti| @meshes[meshi][:mesh].vbuffer.get[verti].to_a  }.transpose.map {|d| d.inject(:+)/d }
          average_normal = vertex_indices.map { |meshi, verti| @meshes[meshi][:mesh].vnbuffer.get[verti].to_a }.transpose.map {|d| d.inject(:+)/d }
          
          vertex_indices.each do |meshi, verti|
            @meshes[meshi][:mesh].vbuffer.update verti => average_vertex
            @meshes[meshi][:mesh].vnbuffer.update verti => average_normal
          end
        end
      end
    end
  end
  
  def scale_and_center scale_factor, offset=[0,0,0] 
    global_bounding_box = Cuboid.global_bounding_box @meshes.map { |mesh_id, meta| meta[:bb] }
    global_bounding_box.center.m
  end
  
  def write_final_meshes
    @meshes.each { |mesh_id, meta| meta[:mesh].write_obj_file "#{@paths[:obj_final_dir]}/#{mesh_id}.obj" }
  end
  
  def write_json_file path
    header = "{\n\"type\": \"ShapeSet\",\n\"name\": \"#{@proc_dir.split("/").last}\",\n\"timestamp\": \"#{Time.now}\",\n"
    shapes = "\"shapes\": #{JSON.dump( @shapes.inject({}){ |hsh,pair| hsh[pair.first] = pair.last[:name] } )},"
    File.open(path,'w') do |f|
      f.write header
      f.write shapes
      f.write "\"meshes\": ["
      @meshes.each do |mesh_id,meta|
        f.write "\"name\": \"#{mesh_id}\","
        f.write "\"vertex_positions\": ["
        f.write meta[:mesh].vbuffer.as_string(5)
        f.write "],\n"
        f.write "\"vertex_normals\": ["
        f.write meta[:mesh].vnbuffer.as_string(5)
        f.write "],\n"
        f.write "\"triangles\": ["
        f.write meta[:mesh].fbuffer.as_string(5)
        f.write "],\n"
        f.write "\"borders\": ["
        f.write JSON.dump(meta[:borders])
        f.write "],\n"
        
        meta[:mesh]
      end
      f.write "]\n}"
    end
  end
  
  def files_in dir
    dir = (( @paths.has_key?(dir) ? @paths[dir] : dir ) rescue dir)
    types = Hash.new { |h,k| h[k]=[] }
    Dir.foreach(dir) do |f|
      next unless f[0] != "." and File.exists? "#{dir}/#{f}"
      types[f.split(".")[1..-1].join(".")] << f
    end
    types
  end
  
  def write_mls_script name, type, params={}
    @mls.write_new_script name, @paths[:scripts_dir], type, params
  end
  
  def run_mls_script script_name, input_file, output_file
    script_location = "#{@paths[:scripts_dir]}/#{script_name}.mlx"
    stdout, stderr, status = @mls.run script_location, input_file, output_file
    File.open("#{@paths[:logs_dir]}/#{Time.now.to_i}-#{script_name}.log", 'w') { |f| f.puts stdout }
    status
  end
  
  def build_borders_index
    border_ids = []
    meshes = @meshes.to_a
    
    until meshes.empty?
      mesh_id, meta = meshes.shift
      
      matches = meta[:matches].keys.sort
      until matches.empty?
        match1 = matches.shift
        
        meta[:matches][match1].keys.each do |v|
          # build array of items like [mesh_id,vertex_id] for all meshes with this boundary vertex
          mesh_vertex = matches.select { |match2| meta[:matches][match2].values.include?(v) }.
                          map { |match2| [match2, meta[:matches][match2].key(v)] }.unshift([match1,v])

          border_description = mesh_vertex.map(&:first).join("_")
          border_id = border_ids.index(border_description) or (border_ids<<border_description).size-1
          
          mesh_vertex.each do |mesh_id, vertex_id|
            @meshes[mesh_id][:borders] ||= Hash.new {|h,k| h[k]=[]}
            @meshes[mesh_id][:borders][border_id] << vertex_id
          end
        end
      end
    end
    
  end
  
  def save_progress
    
  end
  
end

