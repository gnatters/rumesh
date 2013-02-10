
# Extends the NArray class with code borrowed from https://github.com/princelab/narray/wiki/Tentative-NArray-Tutorial

class NArray
  
  class << self
    # borrows other dimension lengths from the first object and relies on it to
    # raise errors (or not) upon concatenation.
    
    # Produces a new NArray by concatenating a number of NArray objects along the specified dimension
    def cat(dim=0, *narrays)
      raise ArgumentError, "'dim' must be an integer (did you forget your dim arg?)" unless dim.is_a?(Integer)
      raise ArgumentError, "must have narrays to cat" if narrays.size == 0
      new_typecode = narrays.map(&:typecode).max
      narrays.uniq.each {|narray| narray.newdim!(dim) if narray.shape[dim].nil? }
      shapes = narrays.map(&:shape)
      new_dim_size = shapes.inject(0) {|sum,v| sum + v[dim] }
      new_shape = shapes.first.dup
      new_shape[dim] = new_dim_size
      narr = NArray.new(new_typecode, *new_shape)
      range_cnt = 0
      narrays.zip(shapes) do |narray, shape|
        index = shape.map {true}
        index[dim] = (range_cnt...(range_cnt += shape[dim]))
        narr[*index] = narray
      end
      narr
    end
    
    # Produces a new NArray by concatenating a number of NArray objects along the vertical dimension (dim=1)
    def vcat(*narrays) ; cat(1, *narrays) end

    # Produces a new NArray by concatenating a number of NArray objects along the horizontal dimension (dim=0)
    def hcat(*narrays) ; cat(0, *narrays) end
  end

  def cat(dim=0, *narrays) ; NArray.cat(dim, self, *narrays) end
  def vcat(*narrays) ; NArray.vcat(self, *narrays) end
  def hcat(*narrays) ; NArray.hcat(self, *narrays) end
end
