class Volume
  
  attr_accessor :image
  attr_accessor :header
  attr_accessor :labels
  
  def initialize(source, labels={})
    
    labels_included = false
    if File.exists? source
      if source.end_with? ".nii"
        load_nifti_file source
      elsif source.end_with? ".bin"
        labels_included = load_bin_file source
      else
        throw "unrecognised format #{source.split(".").last}"
      end
    else
      throw "File not found: #{source}"
    end
    
    @dims = @header["dim"][1..@header["dim"][0]]
    @image.reshape! *@dims
    
    @offset = [0,0,0]
    @meshes = Hash.new
    
    @labels = Hash[labels.map {|k, v| [k, v.gsub(/\s/, "_")] }] unless labels_included
    self.check_labels
  end
  
  def dim
    @image.dim
  end
  
  def reshape= *d
    @image.reshape!(*d) and @dims = d
  end
  
  def cubic_label_surf output_dir
    output_dir += "/" unless output_dir[-1] == "/"
    x_,y_,z_ = @dims
    
    z_.times do |z|
      y_.times do |y|
        x_.times do |x|
          current  = get(x,y,z)
          previous = get(x-1,y,z)
          above    = get(x,y-1,z)
          behind   = get(x,y,z-1)
          
          surfaces = []
          
          if x != 0 and current != previous
            surfaces << Hash.new
            surfaces[-1][:labels]   = [previous, current]
            surfaces[-1][:vertices] = [[x,y,z],
                                       [x,y+1,z],
                                       [x,y+1,z+1],
                                       [x,y,z+1]].map { |v| Vertex.new v }
            surfaces[-1][:normal]   = [1,0,0]
          end
          if y != 0 and current != above
            surfaces << Hash.new
            surfaces[-1][:labels]   = [above, current]
            surfaces[-1][:vertices] = [[x,y,z+1],
                                       [x+1,y,z+1],
                                       [x+1,y,z],                                       
                                       [x,y,z]].map { |v| Vertex.new v }
            surfaces[-1][:normal]   = [0,1,0]
          end
          if z != 0 and current != behind
            surfaces << Hash.new
            surfaces[-1][:labels]   = [behind, current]
            surfaces[-1][:vertices] = [[x,y,z],
                                       [x+1,y,z],
                                       [x+1,y+1,z],
                                       [x,y+1,z]].map { |v| Vertex.new v }
            surfaces[-1][:normal]   = [0,0,1]
          end          
          
          unless surfaces.empty?
            surfaces.each do |s|
              init_mesh s[:labels], output_dir unless @meshes.has_key? labels_to_id(s[:labels])
              write_square *s[:vertices], s[:normal], s[:labels]
            end
          end
        end
      end
    end
    
    finalize_meshes
  end
    
  def to_coords i
    z = i/(@dims[0]*@dims[1])
    y = (i-z*@dims[0]*@dims[1])/@dims[0]
    x = i-z*@dims[0]*@dims[1]-y*@dims[0]
    [x,y,z]
  end
  
  def to_i x, y, z
    x + y*@dims[0] + z*@dims[0]*@dims[1]
  end
  
  def get x,y,z 
    @image[self.to_i(x,y,z)]
  end
  
  def set x,y,z,v
    @image[self.to_i(x,y,z)] = v
  end
  
  def [](i)
    @image[i]
  end

  def []=(i,n)
    @image[i] = n
  end
  
  def each &block
    @image.size.times { |i| yield @image[i] }
  end
  
  def each_with_index &block
    @image.size.times { |i| yield @image[i], i }
  end
  
  def check_labels
    encountered = {}
    self.each { |n| encountered[n] = true }
    encountered = encountered.keys
    
    if @labels.keys.include? :first
      @labels.delete(:first) unless (encountered - @labels.keys).size > 1
      # assign @labels[:first] to the first unlabeled value
      encountered.each do |n|
        next if n == 0
        unless @labels.has_key? n
          @labels[n] = @labels[:first]
          @labels.delete(:first)
          break
        end
      end
    end
    
    # throw an error if there's an empty label
    @labels.each { |n,label| throw "EMPTY LABEL: #{[n,label]}: #{encountered}" unless encountered.include? n}
    
    encountered.each do |n|
      unless @labels.keys.include?(n) or n == 0
        @labels[n] = "label_#{n}"
      end
    end
  end
  
  def next_label
    found = nil
    nl = 1
    until found
      found = nl unless @labels.keys.include? nl
      nl += 1
    end
    found
  end
  
  def get_label_stats
    @label_stats = Hash.new {|h,k|  h[k] = {:count => 0, :xmin => 10000, :xmax => -10000, :ymin => 10000, :ymax => -10000, :zmin => 10000, :zmax => -10000 }}
    self.each_with_index do |n, i|
      @label_stats[n][:count] += 1
      x,y,z = to_coords i
      @label_stats[n][:xmin] = [@label_stats[n][:xmin], x].min
      @label_stats[n][:xmax] = [@label_stats[n][:xmax], x].max
      @label_stats[n][:ymin] = [@label_stats[n][:ymin], y].min
      @label_stats[n][:ymax] = [@label_stats[n][:ymax], y].max
      @label_stats[n][:zmin] = [@label_stats[n][:zmin], z].min
      @label_stats[n][:zmax] = [@label_stats[n][:zmax], z].max
    end
    @label_stats
  end
  
  def merge! other
    """create a third volume including all the labeled areas defined by the other_volume overlayed onto this one"""
    throw "Cannot merge volumes with different dimensions!" unless self.dim == other.dim
    new_labels_map = {}
    overwritten_values = {}
    
    other.each_with_index do |n, i|
      next if n == 0
      combo = "#{self[i]}-#{n}"
      if new_labels_map.has_key? combo
        l = new_labels_map[combo]
      else
        l = new_labels_map[combo] = next_label
        if self[i] == 0
          @labels[l] = other.labels[n]
        else
          @labels[l] = "#{@labels[self[i]]}-#{other.labels[n]}"
          overwritten_values[self[i]] = :overwritten
        end
      end
      
      self[i] = l
    end
    
    # if a previous label was enitrely subsumed by adding this new one then remove it
    encountered = {}
    self.each { |n| encountered[n] = true }
    
    overwritten_values.keys.each do |overwritten_value|
      @labels.delete overwritten_value unless encountered.keys.include? overwritten_value
    end

    # the rest of this function removes very small overlaps (apparently due to some kind of error) between labels
    # => by reuniting them with the original label
    self.get_label_stats
    
    @label_stats.each do |n, stats|
      if stats[:count] < 50 and 
        ((stats[:xmax]-stats[:xmin]) < 2 or
          (stats[:ymax]-stats[:ymin]) < 2 or
            (stats[:zmax]-stats[:zmin]) < 2)
        # if this label is the overlap of an existing label and a new one, then assign it to the existing label
        label = @labels[n]
        if label and label.split("-").size > 1
          old_label = label.split("-")[0...-1].join("-")
          if @labels.values.include? old_label
            old_n = @labels.select {|k,v| v==old_label}.keys.first
            self.each_with_index { |nn, i| self[i] = old_n if nn == n }
            @labels.delete n
          end
        end
      end
    end    
  end
    
  def to_bin
    header = YAML::dump @header
    labels = YAML::dump @labels
    image = @image.to_a.flatten.pack("C*")
    header+"//end header//\n"+labels+"//end labels//\n"+image
  end
  
  private
    def labels_to_id labels
      labels.sort.join("-")
    end
   
    def init_mesh labels, output_dir
      mesh_id = labels_to_id labels
      file_path = output_dir + "#{mesh_id}.stl"
      File.open(file_path, 'w') { |f| f.write "solid ascii" }
      @meshes[mesh_id] = file_path
    end
   
    def finalize_meshes
      @meshes.keys.each do |id|
        File.open(@meshes.delete(id), 'a') { |f| f.write "\nendsolid" }
      end
    end
    
    def write_triangle_strip
      # can write a triangle or a square ;D
    end
    
    def write_square a,b,c,d,n,labels
      if labels.first > labels.last
        stl_string = "
    facet normal #{n.join(" ")}
     outer loop
      #{a.to_stl}
      #{b.to_stl}
      #{c.to_stl}
     endloop
    endfacet
    facet normal #{n.join(" ")}
     outer loop
      #{c.to_stl}
      #{d.to_stl}
      #{a.to_stl}
     endloop
    endfacet"
      else
        stl_string = "
    facet normal #{n.map{|x| -x}.join(" ")}
     outer loop
      #{a.to_stl}
      #{c.to_stl}
      #{b.to_stl}
     endloop
    endfacet
    facet normal #{n.map{|x| -x}.join(" ")}
     outer loop
      #{c.to_stl}
      #{a.to_stl}
      #{d.to_stl}
     endloop
    endfacet"
     end
     mesh_id = labels_to_id labels
     File.open(@meshes[mesh_id], 'a') { |f| f.write stl_string }
    end
    
    def write_fine_square a,b,c,d,n,labels
      aab = a+(b-a)/3
      abb = b+(a-b)/3
      bbc = b+(c-b)/3
      bcc = c+(b-c)/3
      ccd = c+(d-c)/3
      cdd = d+(c-d)/3
      dda = d+(a-d)/3
      daa = a+(d-a)/3
      aa  = a+(c-a)/3
      bb  = b+(d-b)/3
      cc  = c+(a-c)/3
      dd  = d+(b-d)/3
      write_square(a,aab,aa,daa,n,labels)
      write_square(aab,abb,bb,aa,n,labels)
      write_square(abb,b,bbc,bb,n,labels)
      write_square(daa,aa,dd,dda,n,labels)
      write_square(aa,bb,cc,dd,n,labels)
      write_square(bb,bbc,bcc,cc,n,labels)
      write_square(dda,dd,cdd,d,n,labels)
      write_square(dd,cc,ccd,cdd,n,labels)
      write_square(cc,bcc,c,ccd,n,labels)
    end

    def load_bin_file bin_path
      header, labels, image = File.open(bin_path, "r").read.split(/\/\/end \w{6}\/\/\n/, 3)
      @header = YAML::load header
      @labels = YAML::load labels
      @image = NArray.to_na(image.unpack("C*")).to_i
    end
    
    def load_nifti_file nifti_path
      nifti = NIFTI::NObject.new(nifti_path)
      @header = nifti.header
      @image = NArray.to_na(nifti.get_image).to_i
    end
    
end
