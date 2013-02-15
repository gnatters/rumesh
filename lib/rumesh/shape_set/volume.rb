require 'yaml'
require 'nifti'

class Volume
  
  attr_accessor :header
  attr_accessor :image
  attr_accessor :labels
  
  # type =: :auto, :nii, :bin
  def initialize(input_file, labels={}, type=:auto, cast_to_int=true)
    @filename = input_file.scan(/\A(.*\/)?(.*)\.(bin|nii)\z/)[0][1].gsub(/\s/,"_")
    @meshes = {}
    
    if File.exists? input_file
      if type==:nii or type==:auto and input_file.end_with? ".nii"
        @header, @dims, @image = load_nifti(input_file)
        @image = @image.to_i if cast_to_int
        @labels = if labels.kind_of? String
          load_labels labels
        elsif labels.kind_of? Hash
          Hash[labels.map { |k,v| [k,v] }]
        end
        complete_labels
      elsif type==:bin or type==:auto and input_file.end_with? ".bin"
        @header, @dims, @labels, @image = load_bin(input_file)
        @image = @image.to_i if cast_to_int
        complete_labels
      else
        raise ArgumentError, "Unrecognised file format: #{input_file.split(".").last}"
      end
    else
      raise ArgumentError, "Input file not found: #{input_file}"
    end
    
  end
  
  def dim
    @image.dim
  end
  
  def uniq
    values = {}
    @image.each { |n| values[n] = true }
    values.keys
  end
  
  def coords_of i
    z = i/(@dims[0]*@dims[1])
    y = (i-z*@dims[0]*@dims[1])/@dims[0]
    x = i-z*@dims[0]*@dims[1]-y*@dims[0]
    [x,y,z]
  end
 
  def index_of x, y, z
    x + y*@dims[0] + z*@dims[0]*@dims[1]
  end
 
  def each &block
    @image.size.times { |i| yield @image[i] }
  end
 
  def each_with_index &block
    @image.size.times { |i| yield @image[i], i }
  end
  
  def build_label_surfaces output_dir
    output_dir += "/" unless output_dir[-1] == "/"
    present = nil
    
    @dims[2].times do |z|
      @dims[1].times do |y|
        @dims[0].times do |x|
          
          previous = present || @image[index_of(x-1,y,z)]
          present  = @image[index_of(x,y,z)]
          above    = @image[index_of(x,y-1,z)]
          behind   = @image[index_of(x,y,z-1)]
          
          surfaces = []
          
          surfaces << {
            :labels   =>  [ previous, present ],
            :vertices =>  [ [ x, y,   z   ],
                            [ x, y+1, z   ],
                            [ x, y+1, z+1 ],                                       
                            [ x, y,   z+1 ] ],
            :normal   =>  [ 1, 0, 0 ]
          } if x != 0 and present != previous
          
          surfaces << {
            :labels   =>  [ above, present ],
            :vertices =>  [ [ x,   y, z+1 ],
                            [ x+1, y, z+1 ],
                            [ x+1, y, z   ],                                       
                            [ x,   y, z   ] ],
            :normal   =>  [ 0, 1, 0 ]
          } if y != 0 and present != above
          
          surfaces << {
            :labels   =>  [ behind, present ],
            :vertices =>  [ [ x,   y,   z ],
                            [ x+1, y,   z ],
                            [ x+1, y+1, z ],                                       
                            [ x,   y+1, z ] ],
            :normal   =>  [ 0, 0, 1 ]
          } if z != 0 and present != behind
                    
          surfaces.each do |s|
            unless @meshes.has_key? (mesh_id = s[:labels].sort.join("-"))
              file_path = output_dir + "#{mesh_id}.stl"
              File.open(file_path, 'w') { |f| f.write "solid voxel_surface" }
              @meshes[mesh_id] = file_path
            end
            write_square *s[:vertices], s[:normal], s[:labels]
          end
          
        end
      end
    end
    
    @meshes.keys.each do |id|
      File.open(@meshes.delete(id), 'a') { |f| f.write "\nendsolid" }
    end
  end
  
  def get_value_stats
    label_stats = Hash.new {|h,k|  h[k] = {:count => 0, :xmin => 100000, :xmax => -100000, :ymin => 100000, :ymax => -100000, :zmin => 100000, :zmax => -100000 }}
    self.each_with_index do |v, i|
      x,y,z = coords_of i
      label_stats[v][:count] += 1
      label_stats[v][:xmin] = x if x < label_stats[v][:xmin]
      label_stats[v][:xmax] = x if x > label_stats[v][:xmax]
      label_stats[v][:ymin] = y if y < label_stats[v][:ymin]
      label_stats[v][:ymax] = y if y > label_stats[v][:ymax]
      label_stats[v][:zmin] = z if z < label_stats[v][:ymin]
      label_stats[v][:zmax] = z if z > label_stats[v][:ymax]
    end
    label_stats
  end
  
  def merge! other
    """create a third volume including all the labeled areas defined by the other_volume overlayed onto this one"""
    throw "Cannot merge volumes with different dimensions!" unless self.dim == other.dim
    
    available_values = (0...256).to_a - uniq
    new_values_map = {}
    
    other.each_with_index do |v, i|
      next if v == 0
      combo = "#{@image[i]}-#{v}"
      new_values_map[combo] = available_values.shift unless new_values_map.has_key? combo
      @image[i] = new_values_map[combo]
    end
    
    new_values_map.each do |combo, value|
      own_v, other_v = combo.split("-").map(&:to_i)
      if own_v == 0
        @labels[value] = [other.labels[other_v]].flatten
      else
        @labels[value] = @labels[own_v].concat(other.labels[other_v]).uniq
      end
    end
    complete_labels # this should just remove any empty labels from fully overwritten values
    self
  end
  
  def clean_up_messy_voxels
    # Sometimes a few voxels overlap where they shouldn't it's better just to undo overlap labels that looks like this
    # should be called after every merge!
    overlap_values = @labels.select { |v,l| l.size > 1 }.keys
    
    get_value_stats.each do |v, stats|
      if ( overlap_values.include? v &&
           stats[:count] < 50 && 
           ( (stats[:xmax]-stats[:xmin]) < 2 ||
             (stats[:ymax]-stats[:ymin]) < 2 ||
             (stats[:zmax]-stats[:zmin]) < 2 ) &&
           @labels.has_value?(@labels[v][0...-1]) )
        
        old_value = @labels.key(@labels[v][0...-1])
        @image.collext! { |x| x == v ? x = old_value : x }
      end
    end
    
    complete_labels # remove labels for removed values
  end
    
  def write_serial_file output_path
    File.open(output_path,'w') do |f|
      f.write YAML::dump(@header) << "//end header//\n" << YAML::dump(@labels) << "//end labels//\n" << @image.to_a.flatten.pack("C*")
    end
  end
  
  private
      
    def write_square a,b,c,d,n,labels
      if labels.first > labels.last
        t1 = [a,b,c]
        t2 = [c,d,a]
      else
        n.map! {|x| -x}
        t1 = [a,c,b]
        t2 = [c,a,d]
      end
      mesh_id = labels.sort.join("-")
      
      File.open(@meshes[mesh_id], 'a') do |f| 
        f.write "
    facet normal #{n.join(" ")}
     outer loop
      #{ t1.map { |v| "vertex #{v[0].round(6)} #{v[1].round(6)} #{v[2].round(6)}" }.join("\n      ") }
     endloop
    endfacet
    facet normal #{n.join(" ")}
     outer loop
      #{ t2.map { |v| "vertex #{v[0].round(6)} #{v[1].round(6)} #{v[2].round(6)}" }.join("\n      ") }
     endloop
    endfacet"
      end     
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

    def load_bin bin_path
      header, labels, image = File.open(bin_path, "r").read.split(/\/\/end \w{6}\/\/\n/, 3)
      header = YAML::load header
      dims = header["dim"][1..header["dim"][0]]
      labels = YAML::load labels
      image = NArray.to_na(image.unpack("C*")).reshape! *dims
      [ header, dims, labels, image ]
    end
    
    def load_nifti nifti_path
      nifti = NIFTI::NObject.new nifti_path
      header = nifti.header
      dims = header["dim"][1..header["dim"][0]]
      image = NArray.to_na(nifti.get_image).reshape! *dims
      [ header, dims, image ]
    end
    
    # really need to document this one!!!
    # labels may not contain the '+' character 
    # invalid labels in the label file will simply be ignored
    def load_labels labels_path, check_header=true
      labels = Hash.new
      volume_name = ( check_header ? true : nil)
      
      File.open(input, 'r').each_line do |line|
        next if line =~ /^\s*(#(.)*)?$/ # ignore empty or commented lines
        raise ArgumentError, "Label file lacks appropriate header." unless volume_name or (volume_name = line.scan(/labels_for (.*)\.nii/).first.first)
        
        if line.scan(/\s*(\d+)\s+([0-9a-zA-z\s\.\*\-,]+)\#?/).first
          value, label = $1, $2
          labels[value] = label.strip.squeeze(" ").gsub("\s")
        end
      end
      
      labels
    end
    
    def complete_labels
      all_values = uniq
      all_values.delete(0)
      
      @labels ||= {}
      @labels.reject! { |v,l| !all_values.include? v }
      
      if all_values.length == 1 and @labels.empty?
        @labels[all_values.first] = [@filename]
      else
        all_values.select { |v| !@labels[v] }.each { |v| @labels[v] = ["#{@filename}=>#{v}"] }
      end
      @labels
    end
end
