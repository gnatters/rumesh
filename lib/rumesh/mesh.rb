#!/usr/bin/env ruby
# encoding: utf-8
# 
# Created by Nat Noordanus on 2013-01-08.
# 

require 'rumesh/triple_buffer'
require 'rumesh/cuboid'

class Mesh
  
  attr_reader :vbuffer
  attr_reader :vnbuffer
  attr_reader :fbuffer
  
  # Creates a new instance of Mesh
  # 
  # @param input [String] the path of a mesh file or the ASCII contents.
  # @param type [Symbol] the type of mesh file, `:auto`, `:stl` or `:obj`
  # 
  def initialize(input, type=:auto)
    @name = nil
    case type
    when :auto
      if !input.include? "\n"
        # attempt to identify tpye by file extension
        case input.split(".").last
        when /[Ss][Tt][Ll]/ then  load_stl input
        when /[Oo][Bb][Jj]/ then  load_obj input
        else
          throw "Couldn't identify mesh file by extension."
        end
      else
        # attempt to identify tpye by first non whitespace or comment line of the file
        input.each_line do |line|
          next if line =~ /^\s*(#(.)*)?$/
          case line
          when /^\s*solid (.*)/ then load_stl input
          when /^\s*v\s+(\-?\d*\.\d+)\s+(\-?\d*\.\d+)\s+(\-?\d*\.\d+)/ then load_obj input
          else
            throw "Couldn't guess file format."
          end
        end
      end
    when :stl then load_stl input
    when :obj then load_obj input
    else
      throw "Unknown mesh type: #{type}"
    end
  end
  
  # Calculates the 3D bounding box of this mesh.
  # 
  # @return [Cuboid] defined by the mesh's most extreme vertices.
  #
  def bounding_box
    Cuboid.new @vbuffer.buffer.min(1).to_a, @vbuffer.buffer.max(1).to_a
  end

  # Calculates the 3D bounding box of the specified vertices of this mesh.
  # 
  # @return [Cuboid] defined by the most extreme specified vertices.
  #
  def subset_bounding_box *indices
    subset = @vbuffer.nget([*indices].flatten)
    Cuboid.new subset.min(1).to_a, subset.max(1).to_a
  end

  # Calulates the center point of this mesh.
  #
  # @return [Array] containing three floating point numbers.
  #
  def center
    @vbuffer.buffer.min(1).to_a.zip(@vbuffer.buffer.max(1).to_a).map {|min,max| min + ((max-min)/2).abs }
  end
  
  # Efficiently applies one or more 4D translation matrices in the order provided.
  # 
  # @param *ms [NMatrix] the transformation matrices to be applied (in order of desired effect).
  # 
  # @return [self]
  #
  def transform! *ms
    m = [*ms].flatten.reverse.inject(:*)
    @vbuffer.each_triple_with_index do |t,i|
      q = m * NMatrix[[t[0]],[t[1]],[t[2]],[1]]
      @vbuffer[i] = [q[0]/q[3], q[1]/q[3], q[2]/q[3]]
    end
    self
  end

  # Like _transfrom!_ but only applies the transformation(s) to the specified vertices.
  # 
  # @param indices [Array] specifies which indicies to apply the transformation(s) to.
  # @param *ms [NMatrix] the transformation matrices to be applied (in order of desired effect).
  # 
  # @return [self]
  #
  def subset_transform! indices, *ms
    indices = QuickIndex.new indices
    m = [*ms].flatten.reverse.inject(:*)
    @vbuffer.each_triple_with_index do |t,i|
      next unless indices.include? i 
      q = m * NMatrix[[t[0]],[t[1]],[t[2]],[1]]
      @vbuffer[i] = [q[0]/q[3], q[1]/q[3], q[2]/q[3]]
    end
    self
  end

  # Writes this mesh to an Wavefront .obj file
  # 
  # @param output_path [String] the path where the file should be written to including the full file name.
  # 
  # @return [self]
  #
  def write_obj_file output_path
    File.open(output_path, 'w') do |f|
      @vbuffer.each_triple do |a,b,c|
        f.puts "v #{a} #{b} #{c}"
      end
      @vnbuffer.each_triple do |a,b,c|
        f.puts "vn #{a} #{b} #{c}"
      end
      @fbuffer.each_triple do |a,b,c|
        f.puts "f #{a+1}//#{a+1} #{b+1}//#{b+1} #{c+1}//#{c+1}"
      end
    end
    self
  end
  
  # Writes this mesh to an STL (STereoLithography) file
  # 
  # @param output_path [String] the path where the file should be written to including the full file name.
  # 
  # @return [self]
  #
  def write_stl_file output_path    
    @name ||= "ascii"
    
    File.open(output_path, 'w') do |f|
      f.puts "solid #{@name}"
      @fbuffer.each_triple do |a,b,c|
        facet_normal = @vnbuffer.avg_normal a, b, c
        f.puts "facet normal #{facet_normal[0].round(5)} #{facet_normal[1].round(5)} #{facet_normal[2].round(5)}\nouter loop"
        f.puts "vertex #{@vbuffer[a].map { |x| x.round(5) }.join(" ")}"
        f.puts "vertex #{@vbuffer[b].map { |x| x.round(5) }.join(" ")}"
        f.puts "vertex #{@vbuffer[c].map { |x| x.round(5) }.join(" ")}"
        f.puts "endloop\nendfacet"
      end
      f.puts "endsolid #{@name}"
    end
  end
  
  # Detects multiple occurences of the same vertex, removes all but the first copy, and updates the topology accordingly.
  # 
  # @return [self]
  #
  def unify_dup_verts
    # might be more memory efficient to use the index, though this method is simpler
    
    matches = []
    duplicates = Hash.new
    i = -1
    summary = @vbuffer.buffer.to_a.map { |t| t << i += 1 }.sort!
    # summary = NArray.hcat(@vbuffer.buffer, NArray[0...@vbuffer.buffer.shape.last].reshape(1,@vbuffer.buffer.shape.last)).to_a.sort!
    complete = false
    
    until complete do
      (v = summary.shift) or (complete = true) # loop must run once more than there are items in summary
      if (v[2] == matches.last[2] && v[1] == matches.last[1] && v[0] == matches.last[0] rescue false)
        matches << v
      elsif matches.count > 1
        dups = matches.map(&:last)
        primary = dups.shift
        duplicates[primary] = dups
        
        # Replace normal of primary duplicate with an average of the normals of all duplicates
        @vnbuffer.update primary => @vnbuffer.avg_normal(dups)
        
        matches = [v]
      else
        duplicates[matches.first.last] = [] if matches.first
        matches = [v]
      end
    end
    primaries = duplicates.keys.sort!
    secondaries = duplicates.values.flatten.sort!
    
    # Build a map from indices of duplicates onto primary indices remapped for the removal of secondary duplicates 
    index_map = Hash.new
    p = s = 0
    while p < primaries.size
      s += 1 while (primaries[p] > secondaries[s] rescue false)
      index_map[primaries[p]] = primaries[p] - s
      duplicates[primaries[p]].each { |sec| index_map[sec] = primaries[p] - s }
      p += 1
    end
    
    # update buffers
    @vbuffer.remove_and_optimize secondaries
    @vnbuffer.remove_and_optimize secondaries
    @fbuffer.remap index_map
    [@vbuffer, @vnbuffer, @fbuffer].each { |b| b.build_index }
    self
  end

  def intersects_with? other
    return false unless bounding_box.intersects? other.bounding_box
    verts = ( nget(ownb).to_a.map         { |t| t << 0 } + 
              other.nget(otherb).to_a.map { |t| t << 1 } ).sort!
    
    prev = nil
    until verts.empty?
      v = verts.shift
      if (v[3] > prev[3] && v[2] == prev[2] && v[1] == prev[1] && v[0] == prev[0] rescue false)
        return true
      else
        prev = v
      end
    end
    
    false
  end
  
  def intersection other
    # identify the vertices in both this mesh and the other one, or return false
    
    return false unless bounding_box.intersects? other.bounding_box
    
    i = j = -1
    verts = ( nget(ownb).to_a.map         { |t| t.concat [0, i += 1] } + 
              other.nget(otherb).to_a.map { |t| t.concat [1, j += 1] } ).sort!
    
    prev = nil
    until verts.empty?
      v = verts.shift
      if (v[3] > prev[3] && v[2] == prev[2] && v[1] == prev[1] && v[0] == prev[0] rescue false)
        # this will only be true when prev is from ownb and v is from otherb
        
        prev[4]
        prev = nil
      else
        prev = v
      end
    end
    
    
  end
  
  private
  
  def load_obj input
    # if input inlcude multiple lines then assume it's an obj string, otherwise assume it's a path of an obj file
    input = File.open(input, 'r') unless input =~ /\n/
    
    vertices = Array.new
    vertex_normals = Array.new
    faces = Array.new
    
    types = [
      [:vertices,        /^\s*v\s+(\-?\d*\.\d+)\s+(\-?\d*\.\d+)\s+(\-?\d*\.\d+)/],
      [:vertex_normals,  /^\s*vn\s+(\-?\d*\.\d+)\s+(\-?\d*\.\d+)\s+(\-?\d*\.\d+)/],
      [:faces,           /^\s*f\s+(\d*)\/?(\d*)?\/?(\d*)?\s+(\d*)\/?(\d*)?\/?(\d*)?\s+(\d*)\/?(\d*)?\/?(\d*)?/]
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
      when :faces then          faces.push         (match[0].to_i-1), (match[3].to_i-1), (match[6].to_i-1)
      end      
    end
    
    @vbuffer  = VertexBuffer.new    :array => vertices
    @vnbuffer = VectorBuffer.new    :array => vertex_normals
    @fbuffer  = TriangleBuffer.new  :array => faces
  end
  
  def load_stl input, calculate_missing_normals = true, optimize = true
    # solid name
    # facet normal 0 -0.196243 -0.980555
    #  outer loop
    #   vertex -53 100 149.5
    #   vertex -54 100 149.5
    #   vertex -54 101 149.3
    #  endloop
    # endfacet
    # endsolid name
    
    input = File.open(input, 'r') unless input =~ /\n/
    
    vertices = []
    vertex_normals = []
    faces = []
    
    state = nil
    normal = nil
    facet = []
    
    facet_re = /^\s*facet normal\s+(\-?\d*\.?\d*([Ee]-?\d+)?)\s+(\-?\d*\.?\d*([Ee]-?\d+)?)\s+(\-?\d*\.?\d*([Ee]-?\d+)?)/
    vertex_re =      /^\s*vertex\s+(\-?\d*\.?\d*([Ee]-?\d+)?)\s+(\-?\d*\.?\d*([Ee]-?\d+)?)\s+(\-?\d*\.?\d*([Ee]-?\d+)?)/
    
    input.each_line do |line|
      case state
      when nil
        if line.scan(/^\s*solid (.*)/)
          @name = $1
          state = :solid
          next
        end
      
      when :solid
        if (normal = line.scan(facet_re).first)
          normal = normal.values_at(0,2,4).map(&:to_f)
          state = :facet
          next
        # elsif line.scan(/^\s*endsolid (#{@name})/) This is the same as matching nothing ??
        end
      
      when :facet 
        if line.scan(/^\s*outer loop/).first
          state = :loop
          next
        elsif line.scan(/\s*endfacet/).first
          state = :solid
          next
        end
      
      when :loop
        if (v = line.scan(vertex_re).first)
          facet << v.values_at(0,2,4).map(&:to_f)
          next
          
        elsif line.scan(/^\s*endloop/).first
          warn "WARNING: Encountered facet with more than three vertices. Ignoring extra vertices.#{facet}" if facet.length > 9
          facet = facet.flatten[0...9]
          vertices.concat facet
          
          if calculate_missing_normals and normal[0] == 0 && normal[1] == 0 && normal[2] == 0
            # If normal was specified as (0,0,0) then calculate a normal based on the order of the triangle vertices using the 'right-hand rule'
            
            # define the vectors of two sides of the triangle
            v1 = [ facet[3]-facet[0], facet[4]-facet[1], facet[5]-facet[2] ]
            v2 = [ facet[6]-facet[0], facet[7]-facet[1], facet[8]-facet[2] ]
            
            # calculate the cross product
            cp = [ v1[1]*v2[2]-v1[2]*v2[1], v1[2]*v2[0]-v1[0]*v2[2], v1[0]*v2[1]-v1[1]*v2[0] ]
            
            # normalize the cross product
            l = Math.sqrt( cp[0]**2 + cp[1]**2 + cp[2]**2 )
            normal = [ cp[0]/l, cp[1]/l, cp[2]/l ]
          end
          vertex_normals.concat normal * 3
          
          vcount = vertices.length/3
          faces.push vcount-3, vcount-2, vcount-1
          faces[-3..-1]
          
          normal = nil
          facet = []
          state = :facet
          next
        end
      end
      
      next if line =~ /^\s*(#(.)*)?$/ # ignore empty or commented lines
      
      # solid ended or line invalid... abort solid
      state = nil
      normal = nil
      facet = []
    end
    
    @vbuffer  = VertexBuffer.new    :array => vertices
    @vnbuffer = VectorBuffer.new    :array => vertex_normals
    @fbuffer  = TriangleBuffer.new  :array => faces, :big => true
    
    # optimise by combining identical vertices
    unify_dup_verts if optimize
  end
  
end