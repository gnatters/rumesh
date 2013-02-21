
module ShapeSet::Mesh
  
  attr_reader :boundaries
  
  
  # Build an index of boundary vertices, unconnected boundaries are indexed seperately.
  # Boundary vertices are detected as they are edges which are only represented in a single face
  def find_boundaries
    @fbuffer.ensure_uniqueness
    
    @boundaries = []
    boundary_edges = []
    @fbuffer.build_index
    
    @vbuffer.each_index do |i|
      # boundary vertices have identifiable as they have two or more neighboring vertices which are 
      #  only included in one face which includes this vertex.
      (@fbuffer.faces_with(i).flatten - [i]).inject(Hash.new(0)) { |hsh,id| hsh[id] += 1; hsh }.
        each { |n,count| boundary_edges << (i<n ? [i,n] : [n,i]) if count == 1 }
    end
    boundary_edges.uniq!
    boundary_edges.flatten!
    
#    partial_boundary = []
    
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
  
  def boundary_vertices
    @fbuffer.ensure_uniqueness
    boundary_edges = []
    
    @fbuffer.build_index unless @fbuffer.indexed?
    @vbuffer.each_index do |i|
      # boundary vertices have identifiable as they have two or more neighboring vertices which are 
      #  only included in one face which includes this vertex.
      n_counts = (@fbuffer.faces_with(i).flatten - [i]).inject(Hash.new(0)) { |hsh,id| hsh[id] += 1; hsh }
      n_counts.each { |n,count| boundary_edges << (i<n ? [i,n] : [n,i]) if count == 1 }
    end
    @boundary_vertices = boundary_edges.flatten!.uniq!
  end
  
  # @return (Boolean) indicates whether or not the boundaries representation has been calculated or not.
  def has_boundaries?
    (@boundaries and not @boundaries.empty?)
  end
  
  def clear_boundaries!
    @boundaries = nil
  end
  
  def boundary_faces
    # boundary faces are identifiable as they contain one or more edges which are not also present in another face
    faces_with_a_boundary_edge = []
    @vbuffer.each_index do |i|
      n_counts = (@fbuffer.faces_with(i).flatten - [i]).inject({}) { |hsh,id| hsh[id] = hsh[id] ? hsh[id] + 1 : 1 ; hsh }
      @fbuffer.faces_with2(i).each do |i,face|
        faces_with_a_boundary_edge << i if face.map { |v| n_counts[v] }.include?(1)
      end
    end
    faces_with_a_boundary_edge.uniq!
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

        k = l = -1
        verts = ( @vbuffer.nget(ownb).to_a.map         { |t| t.concat [0, k += 1] } + 
                  other.vbuffer.nget(otherb).to_a.map { |t| t.concat [1, l += 1] } ).sort!
                
        prev = nil
        until verts.empty?
          v = verts.shift
          if (v[3] > prev[3] && v[2] == prev[2] && v[1] == prev[1] && v[0] == prev[0] rescue false)
            # this will only be true when prev is from ownb and v is from otherb
            matches[ownb[prev[4]]] = otherb[v[4]]
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
    @vbuffer.build_index if @vbuffer.indexed?
    @vnbuffer = VectorBuffer.new  :array => vertex_normals
    @vnbuffer.build_index if @vnbuffer.indexed?
  end
  
  def repair_non_manifold_edges
    
    # identify non-manifold edges
    nm_edges = []
    @fbuffer.build_index
    
    @vbuffer.each_index do |i|
      # boundary vertices have identifiable as they have two or more neighboring vertices which are 
      #  only included in one face which includes this vertex.
      (@fbuffer.faces_with(i).flatten - [i]).inject(Hash.new(0)) { |hsh,id| hsh[id] += 1; hsh }.
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
    
    # squares := [{ faces:[f1,f2], half_normal:[x,y,z], vertices:[vertex_indices], slant:Boolean(abd,bcd vs abd,adb), seams:[] }, ...]
    # when a vertex is split, add the required number of vertices to @vbuffer, and vertices:[a,b,c,d] becomes vertices:[[a1,a2],b,c,d]
    squares = []    
    nudges = {}
    nm_edges = nm_edges_kept
    
    seams.map do |seam|
      seam[:squares] = [] # references items in squares
      seam[:groups] = [] # like squares but groups items in sub-arrays
      seam[:types] = []
      
      seam[:vertices].each do |v|
        
        # need to create/reference all squares for each vertex
        # squares can be identified as pairs of faces sharing a hypotonuse edge ( i.e. an edge of length about √2 )
        faces = @fbuffer.faces_with2(v)
        seam[:squares] << []
        
        # find squares where the hypotenuse edge converges on vertex v
        face_ids = faces.keys
        loop do
          break unless (fid1 = face_ids.shift)
          next unless (face = faces[fid1])
          face_ids.each do |fid2|
            next unless (shared_verts = (faces[fid2] & face)).count == 2 && @vbuffer.distance_between(*shared_verts).between?(1.4, 1.42)
            existing_sqr = squares.each_with_index.map {|sqr,i| i if (sqr[:faces] & [fid1,fid2]).count==2 }.compact.first
            if existing_sqr then
              seam[:squares].last << existing_sqr
            else
              seam[:squares].last << squares.length
              squares << { faces: [fid1,fid2] }
            end
            faces.delete fid1
            faces.delete fid2
            break 
          end
        end
        
        # find remaining squares
        faces.to_a.each do |fid, face|
          # identify non-right angle vertices of face assuming that the hypotonuse length is √2
          hyp_verts = if @vbuffer.distance_between(face[0],face[1]).between?(1.4, 1.42) then [face[0],face[1]]
          elsif @vbuffer.distance_between(face[1],face[2]).between?(1.4, 1.42) then [face[1],face[2]]
          elsif @vbuffer.distance_between(face[2],face[0]).between?(1.4, 1.42) then [face[2],face[0]]
          else
            @fbuffer.get(fid).first.combination(2) do |a,b| p @vbuffer.distance_between(a,b) end
            throw "This face isn't a right unit triangle! #{fid}"
          end
          
          fid1, fid2 = (@fbuffer.locate(hyp_verts.first) & @fbuffer.locate(hyp_verts.last)).uniq
          
          existing_sqr = squares.each_with_index.map {|sqr,i| i if (sqr[:faces] & [fid1,fid2]).count==2 }.compact.first
          if existing_sqr then
            seam[:squares].last << existing_sqr
          else
            seam[:squares].last << squares.length
            squares << { faces: [fid1,fid2] }
          end
          faces.delete fid1
          faces.delete fid2
        end
        
        # fill out the squares representation: normal, vertices etc
        seam[:squares].last.each do |sqri|
          next if squares[sqri][:half_normal] # skip if this square isn't actually new
          squares[sqri][:half_normal] = @fbuffer.calculate_normal_of(squares[sqri][:faces].first, @vbuffer).map {|x| x/2}
          squares[sqri][:vertices] = @fbuffer.get(squares[sqri][:faces]).flatten.uniq
          # calculate the point which the center of the square plus half the normal
          squares[sqri][:half_normal_point] = @vbuffer.average_of(squares[sqri][:vertices]).each_with_index.map { |n,i| n + squares[sqri][:half_normal][i] }
        end
        
        # apply grouping rules to squares
        seam[:groups] << seam[:squares].last.
                          inject( Hash.new {|h,k| h[k]=[]} ) { |hsh,sqri| hsh[squares[sqri][:half_normal_point]] << sqri; hsh }.values.
                          sort_by {|s| s.length }
        
        # diagnose the type of vertex v and process it accordingly 
        new_vs = []
        groups = []
        squares_to_retriangulate = []
        case [ nm_edges.count(v), seam[:squares].last.count, seam[:groups].last.count]
        when [1,6,4] # top
          new_vs = @vbuffer.append([@vbuffer[v]]).unshift(v)
          squares_to_retriangulate = seam[:groups].last[0..1].flatten
          groups = seam[:groups].last[2..3]
        when [1,6,2] # bottom
          new_vs = @vbuffer.append([@vbuffer[v]]).unshift(v)
          groups = seam[:groups].last
        when [1,7,3] # half_bottom
          new_vs = @vbuffer.append([@vbuffer[v]]).unshift(v)
          groups = [seam[:groups].last[0..1].flatten, seam[:groups].last[2]]
        when [1,7,5] # half-top
          new_vs = @vbuffer.append([@vbuffer[v]]).unshift(v)
          groups = seam[:groups].last[3..4]
          seam[:groups].last[0..2].flatten.each do |sqri|
            if groups.first.any? { |sqrj| squares[sqrj][:half_normal] == squares[sqri][:half_normal] }
              groups.first << sqri 
            elsif groups.last.any? { |sqrj| squares[sqrj][:half_normal] == squares[sqri][:half_normal] }
              groups.last << sqri
            else
              squares_to_retriangulate = [sqri]
            end
          end
          # also add a triangle to fill split edge
          split_neighbor = (squares[groups.first.last][:vertices].flatten & squares[groups.last.last][:vertices].flatten - [v]).first
          @fbuffer.append [[new_vs[0],new_vs[1],split_neighbor]]
        when [2,8,4] # middle or corner
          case seam[:groups].last.map(&:length)
          when [2,2,2,2] # middle
            new_vs = @vbuffer.append([@vbuffer[v]]).unshift(v)
            groups = [seam[:groups].last[0],[]]
            seam[:groups].last[1..-1].each do |g|
              # test if first item in this group (representative of whole group) has h_n_p 1 unit away from h_n_p of first item of first group 
              if squares[g.first][:half_normal_point].zip(squares[groups.first.first][:half_normal_point]).map { |a,b| (a-b).abs }.count(1) == 1
                groups.first.concat g
              else
                groups.last.concat g
              end
            end
          when [1,2,2,3] # corner
            new_vs = @vbuffer.append([@vbuffer[v]]).unshift(v)
            groups = [seam[:groups].last[0..2].flatten, seam[:groups].last[3]]
          end
        when [3,9,3] # closedY
          new_vs = @vbuffer.append([@vbuffer[v]]*2).unshift(v)
          groups = seam[:groups].last
        when [3,9,4] # openY
          new_vs = @vbuffer.append([@vbuffer[v]]).unshift(v)
          groups = [seam[:groups].last[0..2].flatten, seam[:groups].last[3]]
        when [6,12,4] # star
          new_vs = @vbuffer.append([@vbuffer[v]]*3).unshift(v)
          groups = seam[:groups].last
        else
          throw "un-classifiable vertex!"
        end
        
        squares_to_retriangulate.each do |sqri|
          # split vertex v within this square
          squares[sqri][:vertices].map! { |sv| ( sv==v ? new_vs : sv ) }
        end

        throw "Square group - split vertices mismatch" unless new_vs.length == groups.length
        
        # update references to v and nudge new_vs apart
        groups.each_with_index do |group, i|
          nudge_vector = group.map { |gs| squares[gs][:half_normal] }.transpose.map { |ns| ns.inject(:+) }
          l = Math.sqrt(nudge_vector[0]**2 + nudge_vector[1]**2 + nudge_vector[2]**2)*1000
          nudges[new_vs[i]] =  nudge_vector.map! { |n| n/l } # nudge a distance of about 0.001
          group.each { |sqri| squares[sqri][:vertices].map! { |sv| ( sv==v ? new_vs[i] : sv ) } }
        end
      end
    end
    
    # nudge split vertices only after all vertices have been split
    nudges.each { |v,d| @vbuffer.add v, d }
    
    # build up an array of faces to be removed all at once so the indexes dont get screwed up
    faces_to_remove = []
    
    # update faces
    squares.each do |square|
      verts = square[:vertices].flatten
      
      if verts.count > 4 # need to retriangulate
        faces_to_remove << square[:faces]
        
        # sort vertices by clockwise angle from negative x-axis
        vertex_locations = @vbuffer.get(verts)
        plane_dimensions = [0,1,2]-[vertex_locations.transpose.map {|ns| ns.map(&:to_i).uniq.count }.index(1)]
        middle_point = vertex_locations.transpose.map { |ns| ns.inject(:+)/ns.count }
        c = middle_point.values_at(*plane_dimensions)
        # sort verts 
        ordered_verts = verts.each_with_index.map do |v,i| 
          vertex_locations[i].values_at(*plane_dimensions) << v
        end.sort {|a,b| (a[0]-c[0]) * (b[1]-c[1]) - (b[0] - c[0]) * (a[1] - c[1]) }.map(&:last)
        
        if verts.size == 5 # this is the most common case and is special for not needing an extra vertex to be inserted
          # get first index of a
          first_v = square[:vertices].select { |v| v.kind_of? Array }.first.map {|v| ordered_verts.index(v) }.sort.first
          first_v.times { ordered_verts.push(ordered_verts.shift) }
          @fbuffer.append( if (square[:half_normal][0] > 0 or square[:half_normal][1] < 0 or square[:half_normal][2] > 0)
            mp = @vbuffer.append [middle_point]
            [ [ ordered_verts[1], ordered_verts[0], ordered_verts[3] ],
              [ ordered_verts[2], ordered_verts[1], ordered_verts[3] ],
              [ ordered_verts[3], ordered_verts[0], ordered_verts[4] ] ]
          else
            [ [ ordered_verts[0], ordered_verts[1], ordered_verts[3] ],
              [ ordered_verts[1], ordered_verts[2], ordered_verts[3] ],
              [ ordered_verts[0], ordered_verts[3], ordered_verts[4] ] ]
          end)
        else
          # add an additional vertex to the middle of the square and use it for all triangles
          mp = @vbuffer.append [middle_point]
          
          @fbuffer.append( if (square[:half_normal][0] > 0 or square[:half_normal][1] < 0 or square[:half_normal][2] > 0)
            0.upto(ordered_verts.size-1).map { |i| [ordered_verts[i-1], mp, ordered_verts[i]] }
          else
            0.upto(ordered_verts.size-1).map { |i| [ordered_verts[i-1], ordered_verts[i], mp] }
          end)
        end
        
      else # just need to update one or two triangles
        faces = @fbuffer.get(square[:faces])
        vertex_updates = Hash[faces.flatten.uniq.zip(square[:vertices])]
        square[:faces].zip(faces).each { |i,face| @fbuffer.update i => face.map { |v| vertex_updates[v] } }
      end
    end
    
    # finally remove faces that have been replaced
    @fbuffer.remove faces_to_remove
    nil
  end
  
end

