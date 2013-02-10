
# Cuboid objects represent axis aligned cuboids which are defined by a miminum corner (origin)
# and a maximum corner (terminus), such that the x, y and z components of the _origin_ are less 
# than the corresponding x, y and z components of the _terminus_.

class Cuboid
  
  # The minimum corner of this Cuboid.
  #
  # @return [Array] of floats
  #
  attr_accessor :origin

  # The maximum corner of this Cuboid.
  #
  # @return [Array] of floats
  #
  attr_accessor :terminus
  
  # Calculates the distance between the minimum and maximum x values of this Cuboid.
  #
  # @return [Float]
  #
  def width; (@terminus[0].to_f - @origin[0]).abs end
  
  # Calculates the distance between the minimum and maximum y values of this Cuboid.
  #
  # @return [Float]
  #
  def height; (@terminus[1].to_f - @origin[1]).abs end
  
  # Calculates the distance between the minimum and maximum z values of this Cuboid.
  #
  # @return [Float]
  #
  def depth; (@terminus[2].to_f - @origin[2]).abs end
  
  # Calculates the distance between the minimum and maximum corners of this Cuboid.
  #
  # @return [Float]
  #
  def diagonal_length; Math.sqrt( @terminus.zip(@origin).map { |t,o| (t.to_f-o)**2 }.inject(:+) ) end
  
  # Calculates center point of this Cuboid.
  #
  # @return (Array) of three floats.
  #
  def center; @terminus.zip(@origin).map { |t,o| o+(t.to_f-o)/2 } end
  
  # The volume of this Cuboid.
  #
  # @return [Float]
  #
  def volume; (self.width*self.height*self.depth).abs end
  
  # The minimum x value of this Cuboid.
  #
  # @return [Float]
  #
  def left; @origin[0] end
  
  # The minimum y value of this Cuboid.
  #
  # @return [Float]
  #
  def bottom; @origin[1] end
  
  # The minimum z value of this Cuboid.
  #
  # @return [Float]
  #
  def back; @origin[2] end
  
  # The maximum x value of this Cuboid.
  #
  # @return [Float]
  #
  def right; @terminus[0] end
  
  # The maximum y value of this Cuboid.
  #
  # @return [Float]
  #
  def top; @terminus[1] end
  
  # The maximum z value of this Cuboid.
  #
  # @return [Float]
  #
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
    @origin.map!(&:to_f)
    @terminus .map!(&:to_f)
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
  
  # Calculates the bounding box containing all the supplied cuboids.
  #
  # @param bounding_boxes [Array] of Cuboids
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
  
  # @param point [Array] 3D vertex
  #
  # @return [Boolean] indicating whether the given point is within this Cuboid.
  #
  def contains?(point)
    point[0]>=@origin[0] && point[0]<=@terminus[0] && 
    point[1]>=@origin[1] && point[1]<=@terminus[1] && 
    point[2]>=@origin[2] && point[2]<=@terminus[2]
  end
  
  # Expands the cuboid by distance d in all directions.
  #
  # @param d [Numeric] distance for the Cuboid to be expanded by in all axial directions.
  #
  # @return [self]
  #
  def expand!(d)
    @origin = @origin.zip([d]*3).map {|a,b| a+b}
    @terminus = @terminus.zip([d]*3).map {|a,b| a+b}
    return self
  end
  
  # Determines whether this Cuboid intersects with another Cuboid.
  #
  # @return other_cuboid [Cuboid]
  #
  def intersects? other_cuboid
    not( self.top < other_cuboid.bottom ||
         self.bottom > other_cuboid.top ||
         self.left > other_cuboid.right ||
         self.right < other_cuboid.left ||
         self.front < other_cuboid.back ||
         self.back > other_cuboid.front )    
  end
  
  # Produces the Cuboid defined by the intersection of this Cuboid with another one, or returns false if there is none.
  #
  # @param other_cuboid [Cubiod]
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
  
  # Generates a Wavefront obj string representing this Cuboid as a solid 3d shape.
  #
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
  
  # Creates a Mesh object of this Cuboid as a solid 3D shape.
  #
  # @return [Mesh]
  #
  def to_mesh; Mesh.new self.to_obj, :obj end
  
end
