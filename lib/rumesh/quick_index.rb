
class QuickIndex
  # is desgined mostly to work with numeric values but should also work with strings and objects
  
  def initialize ary
    @size = ary.size
    @index = Hash.new
    ary.each_with_index do |num, i|
      num = num.to_s.split("") << "!"
      index = @index
      until num.empty?
        n = num.shift
        index = index[n] ||= (n == "!" ? [] : {})
      end
      index << i
    end
  end
  
  def index item
    index = @index
    (item.to_s.split("") << "!").each { |n| next unless index = (index[n] or nil rescue nil) }
    index
  end
  
  def size
    @size
  end
end
