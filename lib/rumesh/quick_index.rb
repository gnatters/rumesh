
# Provides an efficiently searchable tree index of a given array of stringafiable objects.
# Is specifically designed to be much faster than using Array's _index_ or _include?_ methods for locating a numerical value within an Array.
# However it should work just as well with Arrays of strings or other objects that respond appropriately to _to_s_.

class QuickIndex
  
  # @param ary [Array] of items to be indexed.
  # @param stop_char (String) which should not occur as a substring in any of the stringified objects in ary.
  #
  def initialize ary, stop_char = "!"
    @stop_char = stop_char
    @size = ary.size
    @index = Hash.new
    ary.each_with_index do |num, i|
      num = num.to_s.split("") << @stop_char
      index = @index
      until num.empty?
        n = num.shift
        index = index[n] ||= (n == @stop_char ? [] : {})
      end
      index << i
    end
  end
  
  # Equivalent to the _index_ method of Array (but faster).
  #
  # @param item [Object] to be located or not in the index.
  #
  # @return [Fixnum] indicating the location of the item in the orignal Array or *false* if it wasn't found.
  #
  def index item
    index = @index
    (item.to_s.split("") << @stop_char).each { |n| next unless index = (index[n] or nil rescue nil) }
    index
  end
  
  # Equivalent to the _include?_ method of Array (but faster).
  #
  # @param item [Object] to be found or not in the index.
  #
  # @return [Boolean] indicating whether the item is to be found in the index.
  #
  def include? item
    index(item)? true : false
  end
  
  # @return (Fixnum) the number of items in the index.
  #
  def size 
    @size
  end
  
  # @return (Array) of leaves of the index tree (which are Arrays of indices of the original Array).
  def leaves
    def leaves_rec hsh
      hshs, arys = hsh.values.partition { |x| x.kind_of? Hash }
      arys.concat hshs.map { |h| leaves_rec(h) }.flatten(1)
    end
    leaves_rec [@index]
  end
end
