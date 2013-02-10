
# Cuboids are neccesarily aligned with the axes.

class Cuboid
  
  attr_accessor :origin
  attr_accessor :terminus
  
  def width; (@terminus[0] - @origin[0]).abs end
  
  def height; (@terminus[1] - @origin[1]).abs end
  
  def depth; (@terminus[2] - @origin[2]).abs end
  
  def diagonal_length; Math.sqrt( @terminus.zip(@origin).map { |t,o| (t-o)**2 }.inject(:+) ) end
  
  def center; @terminus.zip(@origin).map { |t,o| o+(t-o)/2 } end
  
  def volume; (self.width*self.height*self.depth).abs end
  
  def left; @origin[0] end
  
  def bottom; @origin[1] end
  
  def back; @origin[2] end
  
  def right; @terminus[0] end
  
  def top; @terminus[1] end
  
  def front; @terminus[2] end
    
  def initialize(*args)
    case args.size
    when 2
      @origin = Array.new args[0]
      @terminus = Array.new args[1]
    when 4
      @origin = Array.new args[0]
      @terminus = Array.new(args[1],args[2],args[3])
    when 6
      @origin = Array.new(args[0],args[1],args[2])
      @terminus = Array.new(args[3],args[4],args[5])
    end
    if @origin[0] > @terminus[0]
      x = @origin[0]
      @origin[0] = @terminus[0]
      @terminus[0] = x
    end
    if @origin[1] > @terminus[1]
      x = @origin[1]
      @origin[1] = @terminus[1]
      @terminus[1] = x
    end
    if @origin[0] > @terminus[1]
      x = @origin[1]
      @origin[1] = @terminus[1]
      @terminus[1] = x
    end
  end
  
  # @param [Array] of Cuboids
  #
  # @return [Cuboid] Representing the bounding box of all of the supplied Cuboids combined
  #
  def self.global_bounding_box bounding_boxes
    origin = [10^10,10^10,10^10]
    terminus = [-10^10,-10^10,-10^10]
    bounding_boxes.each do |bb|
      origin[0]   = [origin[0],   bb.origin[0]  ].min
      origin[1]   = [origin[1],   bb.origin[1]  ].min
      origin[2]   = [origin[2],   bb.origin[2]  ].min
      terminus[0] = [terminus[0], bb.terminus[0]].max
      terminus[1] = [terminus[1], bb.terminus[1]].max
      terminus[2] = [terminus[2], bb.terminus[2]].max
    end
    Cuboid.new origin, terminus
  end
  
  # @param A 3D vertex as an [Array].
  #
  # @return [Boolean] indicating whether the given point is within this Cuboid.
  #
  def contains?(point)
    point[0]>=@origin[0] && point[0]<=@terminus[0] && 
    point[1]>=@origin[1] && point[1]<=@terminus[1] && 
    point[2]>=@origin[2] && point[2]<=@terminus[2]
  end
  
  # @param A [Numeric] distance for the Cuboid to be expanded by in all axial directions.
  #
  # @return [self]
  #
  def expand!(d)
    #expands the cuboid by distance d in all directions
    @origin = @origin.zip([d]*3).map {|a,b| a+b}
    @terminus = @terminus.zip([d]*3).map {|a,b| a+b}
    return self
  end
  
  # @return [Cuboid]
  #
  def intersects? other_cuboid
    not( self.top < other_cuboid.bottom ||
         self.bottom > other_cuboid.top ||
         self.left > other_cuboid.right ||
         self.right < other_cuboid.left ||
         self.front < other_cuboid.back ||
         self.back > other_cuboid.front )    
  end
  
  # @param [Cubiod]
  #
  # @return [Cuboid]
  #
  def intersection other_cuboid
    return false unless self.intersects? other_cuboid
    Cuboid.new [self.left, other_cuboid.left].max,
               [self.bottom, other_cuboid.bottom].max,
               [self.back, other_cuboid.back].max,
               [self.right, other_cuboid.right].min,
               [self.top, other_cuboid.top].min,
               [self.front, other_cuboid.front].min
  end
  
  # @return [String]
  #
  def to_obj
    obj_string = ""
    obj_string << "v #{@origin[0]} #{@origin[1]} #{@origin[2]}\n"
    obj_string << "v #{@terminus[0]} #{@origin[1]} #{@origin[2]}\n"
    obj_string << "v #{@terminus[0]} #{@origin[1]} #{@terminus[2]}\n"
    obj_string << "v #{@origin[0]} #{@origin[1]} #{@terminus[2]}\n"
    obj_string << "v #{@origin[0]} #{@terminus[1]} #{@origin[2]}\n"
    obj_string << "v #{@terminus[0]} #{@terminus[1]} #{@origin[2]}\n"
    obj_string << "v #{@terminus[0]} #{@terminus[1]} #{@terminus[2]}\n"
    obj_string << "v #{@origin[0]} #{@terminus[1]} #{@terminus[2]}\n"
    obj_string << "f 1// 2// 3//\n"
    obj_string << "f 1// 3// 4//\n"
    obj_string << "f 1// 2// 6//\n"
    obj_string << "f 1// 6// 5//\n"
    obj_string << "f 2// 3// 7//\n"
    obj_string << "f 2// 7// 6//\n"
    obj_string << "f 3// 4// 8//\n"
    obj_string << "f 3// 8// 7//\n"
    obj_string << "f 4// 1// 5//\n"
    obj_string << "f 4// 5// 8//\n"
    obj_string << "f 6// 7// 8//\n"
    obj_string << "f 6// 8// 5//\n"
  end
  
  # @return [Mesh]
  #
  def to_mesh; Mesh.new self.to_obj, :obj end
  
end
