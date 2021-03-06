
require 'narray'
require 'rumesh/narray_ext'
require 'rumesh/quick_index'

class TripleBuffer
  
  def initialize params
    # can be initialised from array
    # can be initialised from stream (from a file)
    # int or float
    
    throw "Error: input array size is not a multiple of three!" if params[:array].kind_of?(Array) and params[:array].size % 3 > 0
    @empties = []
    @buffers = []
    
    if params[:array].kind_of?(Array) and params[:type] == :float
      ntriples = params[:array].size / 3
      if params[:big]
        @buffers << NArray.float(3, ntriples)
        @type = :bfloat
      else
        @buffers << NArray.sfloat(3, ntriples)
        @type = :float
      end
      @buffers.first.length.times {|i| @buffers.first[i] = params[:array].shift }
    
    elsif params[:array].kind_of?(Array) and params[:type] == :int
      ntriples = params[:array].size / 3
      if params[:big]
        @buffers << NArray.int(3, ntriples)
        @type = :bint
      else
        @buffers << NArray.sint(3, ntriples)
        @type = :int
      end
      @buffers.first.length.times {|i| @buffers.first[i] = params[:array].shift }
    
    elsif params[:array].kind_of?(Array) and
      @buffers << NArray.to_na(params[:array])
      @buffers.first.reshape! 3, params[:array].size/3
      if params[:big]
        @type = Hash[Float => :bfloat, Fixnum => :bint][@buffers.first[0].class]
      else
        @type = Hash[Float => :float, Fixnum => :int][@buffers.first[0].class]
      end
      
    elsif params[:size].kind_of?(Fixnum) and params[:type] == :int
      if params[:big]
        @buffers << NArray.int(3, params[:size])
        @type = :bint
      else
        @buffers << NArray.sint(3, params[:size])
        @type = :int
      end
    
    elsif params[:size].kind_of?(Fixnum) and params[:type] == :float
      if params[:big]
        @buffers << NArray.float(3, params[:size])
        @type = :bfloat
      else
        @buffers << NArray.sfloat(3, params[:size])
        @type = :float
      end
      
    end
  end
  
  def buffer
    optimize
    @buffers.first
  end
  
  def size
    @buffers.map(&:length).inject(0, :+)/3 - @empties.count
  end
  
  def build_index
    @index = Hash.new
    
    each_triple_with_index do |nums, i|
      nums.to_a.map{ |num| num.to_s.split("") << "!" }.each do |num|
        index = @index
        until num.empty?
          n = num.shift
          index = index[n] ||= (n == "!" ? [] : {})
        end
        index << i
      end
    end
  end
  
  def remove_index
    @index = nil
  end
  
  def indexed?
    @index and not @index.empty?
  end
  
  def include? value
    if indexed?
      return true if find value
    else
      # revert to linear search if no index available
      @buffers.each do |buffer|
        buffer.each { |item| return true if item == value }
      end
    end
    false
  end
  
  def locate value
    if indexed?
      return false unless (found = find value)
      return found.map { |i| i - @empties.count { |e| e < i } }
    else
      # revert to linear search with NArray's methods if no index available
      matches = []
      @buffers.each do |buffer|
        logical = buffer.eq(value).sum(0)
        i = -1
        logical.each {|m| i += 1; matches << i if m > 0}
      end
      return matches unless matches.empty?
    end
    false
  end
  
  def to_a
    return @buffers.first.to_a if optimal?
    a = Array.new
    offset = 0
    @buffers.each do |buffer|
      (0...buffer.size).step(3) do |i|
        next if @empties.include? (i/3) + offset
        a << buffer[i..i+2].to_a
      end
      offset += (buffer.shape.last or 0)
    end
    a
  end
  
  def as_string decimals=5
    optimize
    if [:float,:bfloat].include? @type
      places=10**decimals
      (buffer.reshape(buffer.size)*places).to_i.to_a.map {|x| x.to_f/places }.join(",")
    else
      buffer.reshape(buffer.size).to_a.join(",")
    end
  end
  
  def each_triple
    return enum_for :each_triple unless block_given?
    
    offset = 0
    @buffers.each do |buffer|
      (0...buffer.size).step(3) do |i|
        next if @empties.include? i/3 + offset
        yield buffer[i..i+2].to_a
      end
      offset += (buffer.shape.last or 0)
      
    end
    offset
  end
  
  def each_triple_with_index &block
    return enum_for :each_triple_with_index unless block_given?
    
    real_i = -1
    offset = 0
    @buffers.each do |buffer|
      (0...buffer.size).step(3) do |i|
        next if @empties and @empties.include? i/3 + offset
        yield buffer[i..i+2].to_a, real_i+=1
      end
      offset += (buffer.shape.last or 0)
    end
    offset
  end
  
  def each_index &block
    size.times { |i| yield i }
  end
  
  def [] i
    raise "TrippleBuffer: Cannot access triple, index out of range! (#{i}/#{self.size-1})" if i < -self.size or i >= self.size
    self.get(i).first
  end
  
  def []= i, t
    raise "TrippleBuffer: Cannot update triple, index out of range! (#{i}/#{self.size-1})" if i < -self.size or i >= self.size
    update(i => t).first
  end
  
  def lookup *indices
    # determines the actual location of triples in case of empty spaces and/or extra NArrays
    # returns an array of [buffer, index] pairs
    
    [*indices].flatten.map do |i|
      @empties.sort!.each { |e| i += 1 if e <= i }
      match = nil
      
      @buffers.map{ |b| b.shape.last }.each_with_index do |buffer_size, b|
        if i < buffer_size
          match = [b, i]
          break
        end
        i -= buffer_size
      end
      match
    end
  end
  
  def get *indices
    # returns nil for out of range indicies
    
    [*indices].flatten.map do |i|
      @empties.sort!.each { |e| i += 1 if e <= i }
      got = nil
      @buffers.each do |buffer|
        if i <  (buffer.shape.last or 0)
          got = [buffer[i*3],buffer[i*3+1],buffer[i*3+2]] rescue nil
          break
        end
        i -= (buffer.shape.last or 0)
      end
      got
    end
  end
  
  def nget *indices
    # Will cause error if indices are out of range
    optimize
    buffer[[0..2], [*indices]]
  end
  
  def update triples_hash
    # triples_hash := {index => [a,b,c]}
    # returns array of boolean values indicating success or failure for each update
    
    # verify triples
    throw "Invalid triples hash: #{triples_hash}" unless triples_hash.values.map { |t| t.length == 3 }.all?
        
    triples_hash.keys.map do |ext_i|
      int_i = ext_i
      @empties.sort!.each { |e| int_i += 1 if e <= int_i }
      updated = false
      @buffers.each do |buffer|
        if int_i < (buffer.shape.last or 0)
          buffer[int_i*3..int_i*3+2] rescue break   # test if index within range
          
          delete_from_index ext_i if indexed?
          buffer[int_i*3..int_i*3+2] = triples_hash[ext_i]
          add_to_index buffer[int_i*3..int_i*3+2], ext_i if indexed?
          updated = true
          break
        end
        int_i -= (buffer.shape.last or 0)
      end
      
      updated
    end
  end
  
  def append triples
    # validate triples
    throw "Invalid triples: #{triples}" unless triples.map { |t| t.length == 3 }.all?
    used_indices = []
    
    # use empty slots first
    while !@empties.empty? and !triples.empty?
      abs_e = be = @empties.shift
      bi = 0
      @buffers.map { |b| b.shape.last }.each_with_index { |bs, i| if be < bs then (bi = i and break) else be -= bs end }
      
      t = triples.shift
      @buffers[bi][be*3]   = t[0]
      @buffers[bi][be*3+1] = t[1]
      @buffers[bi][be*3+2] = t[2]
      used_indices << abs_e
    end
    
    if triples.size > 0
      offset =  size
      @buffers << case @type
      when :bint   then NArray.int( 3, triples.size )
      when :bfloat then NArray.float( 3, triples.size )
      when :int    then NArray.sint( 3, triples.size )
      when :float  then NArray.sfloat( 3, triples.size )
      end
    
      extras = triples.flatten
      buffer = @buffers.last
      (buffer.length/3).times do |i|
        buffer[i*3]   = extras.shift
        buffer[i*3+1] = extras.shift
        buffer[i*3+2] = extras.shift
        used_indices << offset + i
      end
    end
    
    used_indices.each do |i|
      abs_i = i
      @buffers.each do |buffer|
        if i <  (buffer.shape.last or 0)
          add_to_index [buffer[i*3],buffer[i*3+1],buffer[i*3+2]], abs_i
          break
        end
        i -= (buffer.shape.last or 0)
      end
    end if indexed?
    
    used_indices
  end
  
  def remove *indices
    # updates the indicated triples to zero and adds them to the empties
    # returns array of boolean values indicating truth for each index that was found and removed
    
    [*indices].flatten.sort.reverse.map do |i|
      ii = i
      @empties.sort!.each { |e| i += 1 if e <= i }
      real_i = i
      removed = false
      @buffers.each do |buffer|
        if i < (buffer.shape.last or 0) and !@empties.include? real_i
          buffer[i*3..i*3+2] rescue break
          delete_from_index(ii) if indexed?
          buffer[i*3..i*3+2] = 0
          @empties << real_i
          removed = true
          break
        end
        i -= (buffer.shape.last or 0)
      end
      removed
    end
  end
  
  def remove_and_optimize *indices
    indices = QuickIndex.new [*indices].flatten
    new_buffer = case @type
    when :float   then NArray.sfloat(3, size-indices.size)
    when :bfloat  then NArray.float(3, size-indices.size)
    when :int     then NArray.sint(3, size-indices.size)
    when :bint    then NArray.int(3, size-indices.size)
    end
    
    i2 = 0
    each_triple_with_index { |t,i| new_buffer[i2*3..i2*3+2], i2 = t, i2+1 unless indices.index i }
        
    @empties = []
    @buffers = [new_buffer]
    build_index if indexed?
    true
  end

  def append_and_optimize triples
    # validate triples
    throw "Invalid triples: #{triples}" unless triples.map { |t| t.length == 3 }.all?
    
    new_buffer = case @type
    when :float   then NArray.sfloat(3, size+triples.size)
    when :bfloat  then NArray.float(3, size+triples.size)
    when :int     then NArray.sint(3, size+triples.size)
    when :bint    then NArray.int(3, size+triples.size)
    end
    
    each_triple_with_index { |t,i| new_buffer[i*3..i*3+2] = t }
    i = size
    triples.each { |t| new_buffer[i*3..i*3+2] = t; i+=1 }
        
    @empties = []
    @buffers = [new_buffer]
    build_index if indexed?
    true
  end
  
  def merge! *other_buffers
    # validate triples
    additional_triples = other_buffers.map(&:size).inject(:+)
    
    new_buffer = case @type
    when :float   then NArray.sfloat(3, size+additional_triples)
    when :bfloat  then NArray.float(3, size+additional_triples)
    when :int     then NArray.sint(3, size+additional_triples)
    when :bint    then NArray.int(3, size+additional_triples)
    end
    
    each_triple_with_index { |t,i| new_buffer[i*3..i*3+2] = t }
    i = size
    other_buffers.each { |ob| ob.each_triple.each { |t| new_buffer[i*3..i*3+2] = t; i+=1 } }
        
    @empties = []
    @buffers = [new_buffer]
    build_index if indexed?
    true
  end
  
  def extend_by n
    new_buffer = case @type
    when :float   then NArray.sfloat(3, size+n)
    when :bfloat  then NArray.float(3, size+n)
    when :int     then NArray.sint(3, size+n)
    when :bint    then NArray.int(3, size+n)
    end
    
    each_triple_with_index { |t,i| new_buffer[i*3..i*3+2] = t }
    
    @empties = []
    @buffers = [new_buffer]
    build_index if indexed?
    true
  end
  
  def optimize
    # collapse empty slots, merge extra and rebuild index
    return false if optimal?
    
    new_buffer = case @type
    when :float   then NArray.sfloat(3, size)
    when :bfloat  then NArray.float(3, size)
    when :int     then NArray.sint(3, size)
    when :bint    then NArray.int(3, size)
    end
    
    each_triple_with_index { |t,i| new_buffer[i*3..i*3+2] = t }
    
    @empties = []
    @buffers = [new_buffer]
    build_index if indexed?
    true
  end
  
  def optimal?
    @buffers.size == 1 && @empties == []
  end
  
  def in_range? *indices
    max = size
    [*indices].flatten.map {|i| i >= 0 && i < size}
  end
  
  private
    def delete_from_index ext_i
      b, i = lookup(ext_i).first
      abs_i = i + (0.upto(b-1).map{|bi| @buffers[bi].length }.inject(0, :+) or 0)
      @buffers[b][i*3..i*3+2].each do |v|
        index = @index
        (v.to_s.split("") << "!").each { |n| next unless index = (index[n] rescue false) }
        index.delete abs_i
      end
    end

    def add_to_index t, ext_i
      t.to_a.map{ |num| num.to_s.split("") << "!" }.each do |num|
        index = @index
        until num.empty?
          n = num.shift
          index = index[n] ||= (n == "!" ? [] : {})
        end
        index << ext_i
      end
    end

    def find item
      index = @index
      (item.to_s.split("") << "!").each { |n| next unless index = (index[n] or false rescue false) }
      index
    end
    
    def index_leaves
      build_index unless indexed?
      
      def leaves_rec hash
        hashes, arrays = hash.values.partition { |x| x.class == Hash }
        arrays.concat hashes.map { |h| leaves_rec(h) }.flatten(1)
      end
      
      leaves_rec [@index]     
    end
    
end

class PointBuffer < TripleBuffer
  
  def x *indices
    return get(*indices).first[0] if indices.length == 1
    get(*indices).map {|t| t[0]}
  end
  
  def y *indices
    return get(*indices).first[1] if indices.length == 1
    get(*indices).map {|t| t[1]}
  end
  
  def z *indices
    return get(*indices).first[2] if indices.length == 1
    get(*indices).map {|t| t[2]}
  end
    
  def add i, vector
    t = get(i).first
    update i => [t[0]+vector[0], t[1]+vector[1], t[2]+vector[2]]
  end
  
  def sub i, vector
    t = get(i).first
    update i => [t[0]-vector[0], t[1]-vector[1], t[2]-vector[2]]
  end
  
  def mul i, vector
    t = get(i).first
    update i => [t[0]*vector[0], t[1]*vector[1], t[2]*vector[2]]
  end
  
  def div i, vector
    t = get(i).first
    update i => [t[0]/vector[0], t[1]/vector[1], t[2]/vector[2]]
  end
  
  def neg i
    t = get(i).first
    update i => [-t[0], -t[1], -t[2]]
  end
  
  def add_all vector
    v, v[0], v[1], v[2] = NArray.float(3,1), vector[0], vector[1], vector[2]
    @buffers.each_index { |i| @buffers[i].add! v }
    true
  end
  
  def sub_all vector
    v, v[0], v[1], v[2] = NArray.float(3,1), vector[0], vector[1], vector[2]
    @buffers.each_index { |i| @buffers[i].sbt! v }
    true
    true
  end
  
  def mul_all vector
    v, v[0], v[1], v[2] = NArray.float(3,1), vector[0], vector[1], vector[2]
    @buffers.each_index { |i| @buffers[i].mul! v }
    true
    true
  end
  
  def div_all vector
    v, v[0], v[1], v[2] = NArray.float(3,1), vector[0], vector[1], vector[2]
    @buffers.each_index { |i| @buffers[i].div! v }
    true
    true
  end
  
  def neg_all
    @buffers.each_index { |i| @buffers[i] = -@buffers[i] }
    true
  end
  
  def average_of *indices
    begin # if an index is invalid then nget will cause an error
      ts = nget(*indices)
      return ts.sum(1)/ts.shape.last.to_a
    rescue
      return get(*indices).transpose.map {|xs| xs.inject(0,:+) / xs.length }.to_a
    end
  end
  
end


class VertexBuffer < PointBuffer
  
  def initialize params
    super params.merge(:type => :float)
  end
  
  def distance_to i, other_vertex
    t = get(i).first
    Math.sqrt( (t[0]-other_vertex[0])**2 + (t[1]-other_vertex[1])**2 + (t[2]-other_vertex[2])**2 )
  end

  def distance_between i1,i2
    t1 = get(i1).first
    t2 = get(i2).first
    Math.sqrt( (t1[0]-t2[0])**2 + (t1[1]-t2[1])**2 + (t1[2]-t2[2])**2 )
  end
  
  
  def distance_from_line i, line_segment
		# Finds the shortest distance to the line of line_segment which is of a form equivalent to [[x1,y1,z1],[x2,y2,z2]]
    
    t = get(i).first
    other = [ line_segment.first[0] - t[0], 
              line_segment.first[1] - t[1], 
              line_segment.first[2] - t[2]]
    seg = [ line_segment.first[0] - line_segment.last[0], 
            line_segment.first[1] - line_segment.last[1], 
            line_segment.first[2] - line_segment.last[2]]
    
    Math.sqrt( (seg[1]*other[2]-seg[2]*other[1])**2 + 
               (seg[2]*other[0]-seg[0]*other[2])**2 + 
               (seg[0]*other[1]-seg[1]*other[0])**2 ) / Math.sqrt( seg[0]**2 + 
                                                                   seg[1]**2 + 
                                                                   seg[2]**2 )
	end
	
	def distance_from_line_segment i, lineSegment
		# This function considers the vertex and the line segement to form a triangle abc
		# if abc is obtuse then the shortest distance from c to the line segment is the distance 
		# from c to the nearest of either a or b 
		# if abc is not obtuse then the shortest distance to line segment ab is the same as to the 
		# line of ab
		
	  distance_between = Proc.new { |a,b| Math.sqrt( (a[0]-b[0])**2 + (a[1]-b[1])**2 + (a[2]-b[2])**2 ) }
		
		a , b = lineSegment
		c = get(i).first
    ab_distance = distance_between a, b
		ca_distance = distance_between c, a
		cb_distance = distance_between c, b
		
		if cb_distance > ab_distance
			return ca_distance
		elsif ca_distance > ab_distance then
			return cb_distance
		else 
			return distance_from_line i, lineSegment
		end
	end
  
end


class VectorBuffer < PointBuffer
  
  def initialize params
    super params.merge(:type => :float)
  end
  
  def length_of i
    t = get(i).first
    Math.sqrt( t[0]**2 + t[1]**2 + t[2]**2 )
  end
  
  def normal_of i
    t = get(i).first
    l = Math.sqrt(t[0]**2 + t[1]**2 + t[2]**2)
    [t[0]/l, t[1]/l, t[2]/l]
  end
  
  def normalize! i
    t = get(i).first
    l = Math.sqrt(t[0]**2 + t[1]**2 + t[2]**2)
    update i => [t[0]/l, t[1]/l, t[2]/l]
  end
  
  def normalize_all!
    @buffers.each_index do |bi|
      @buffers[bi].shape.last.times do |i|
        i3 = i*3
        l = Math.sqrt(@buffers[bi][i3]**2 + @buffers[bi][i3+1]**2 + @buffers[bi][i3+2]**2)
        @buffers[bi][i3]   /= l
        @buffers[bi][i3+1] /= l
        @buffers[bi][i3+2] /= l
      end
    end
  end
  
  def normal? i
    t = get(i).first
    ((Math.sqrt(t[0]**2 + t[1]**2 + t[2]**2) * 10000000).to_i - 10000000).abs <= 1
  end
  
  def cross_prod i, other
    t = get(i).first
    [t[1]*other[2]-t[2]*other[1], t[2]*other[0]-t[0]*other[2], t[0]*other[1]-t[1]*other[0]]
  end  
  
  def dot_prod i, other
    NVector[get(i).first] * NVector[other]
  end
  
  def avg_normal *indices
    average = average_of *indices
    l = Math.sqrt(average[0]**2 + average[1]**2 + average[2]**2)
    [average[0]/l, average[1]/l, average[2]/l]
  end
  
end


class TriangleBuffer < TripleBuffer
  
  def initialize params
    super params.merge(:type => :int)
  end
  
  def hypotenuse_of i, vbuffer, float_equality_threshold = 0.000001
    x1,y1,z1, x2,y2,z2, x3,y3,z3 = vbuffer.get(get(i)).flatten
    
    sqr_a = ((x1-x2)**2 + (y1-y2)**2 + (z1-z2)**2)
    sqr_b = ((x2-x3)**2 + (y2-y3)**2 + (z2-z3)**2)
    sqr_c = ((x3-x1)**2 + (y3-y1)**2 + (z3-z1)**2)
    
    if (sqr_a - sqr_b + sqr_c).abs < float_equality_threshold
      [x1,y1,z1, x2,y2,z2]
    elsif (sqr_b - sqr_c + sqr_a).abs < float_equality_threshold
      [x2,y2,z2, x3,y3,z3]
    elsif (sqr_c - sqr_a + sqr_b).abs < float_equality_threshold
      [x3,y3,z3, x1,y1,z1]
    else
      false
    end
  end
  
  def calculate_normal_of i, vbuffer=nil
    # calculate a normal vector based on the order of the triangle vertices using the 'right-hand rule'
    raise "No vbuffer available" unless vbuffer ||= @vbuffer
    facet = vbuffer.get(*get(i)).flatten
     
    # define the vectors of two sides of the triangle
    v1 = [ facet[3]-facet[0], facet[4]-facet[1], facet[5]-facet[2] ]
    v2 = [ facet[6]-facet[0], facet[7]-facet[1], facet[8]-facet[2] ]
    
    # calculate the cross product
    cp = [ v1[1]*v2[2]-v1[2]*v2[1], v1[2]*v2[0]-v1[0]*v2[2], v1[0]*v2[1]-v1[1]*v2[0] ]
    
    # normalize the cross product
    l = Math.sqrt( cp[0]**2 + cp[1]**2 + cp[2]**2 )
    [ cp[0]/l, cp[1]/l, cp[2]/l ]
  end
  
  def faces_with i1, i2=nil, i3=nil
    # Returns the set of all faces which include a reference to vertex i
    if !i2
      get *locate(i1)
    elsif !i3
      get *(locate(i1) & locate(i2))
    else
      get *(locate(i1) & locate(i2) & locate(i3))
    end
  end
  
  def faces_with2 i1, i2=nil, i3=nil
    # Returns the set of all faces which include a reference to vertex i
    if !i2
      indices = locate(i1)
      Hash[*indices.zip(get(*indices)).flatten(1)]
    elsif !i3
      indices = (locate(i1) & locate(i2))
      Hash[*indices.zip(get(*indices)).flatten(1)]
    else
      indices = (locate(i1) & locate(i2) & locate(i3))
      Hash[*indices.zip(get(*indices)).flatten(1)]
    end
  end
  
  def neighbors_of i
    # Returns the indices of all vertices which share an edge with vertex i
    faces_with(i).flatten.uniq! - [i]
  end
  
  def replace olds, new_value
    # replaces all occurences of items in the olds array with the new_value
    @buffers.each do |buffer|
      buffer.collect! { |v| olds.include?(v) ? new_value : v }
    end
    true
  end
  
  # Find and remove any duplicate triangles
  def ensure_uniqueness
    b = buffer
    #summary = buffer.to_a.map { |t| t << i += 1 }.sort!
    summary = NArray.hcat(b, NArray[0...b.shape.last].reshape(1,b.shape.last)).to_a.sort!
    
    duplicates = []
    matches = []
    complete = false
    
    until complete do
      (f = summary.shift) or (complete = true) # loop must run once more than there are items in summary
      
      if (f[2] == matches.last[2] && f[1] == matches.last[1] && f[0] == matches.last[0] rescue false)
        matches << f
      else
        duplicates.concat(( matches[1..-1].map(&:last) rescue Array.new ))
        matches = [f]
      end
    end
    remove_and_optimize duplicates
    self
  end
  
  def remap index_map
    optimize
    @buffers.first.length.times do |i|
      @buffers.first[i] = (index_map[@buffers.first[i]] or @buffers.first[i])
    end
  end
  
end