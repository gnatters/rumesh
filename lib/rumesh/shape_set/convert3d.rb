
# A very light wrapper for the InsightToolkit Convert3D tool which must be downloaded seperately.
# See http://www.itksnap.org/pmwiki/pmwiki.php?n=Convert3D.Convert3D
module Convert3D
  
  @@c3d_path = "c3d" # assume c3d is in the environment path by default
  @@Formats = [".nrrd", ".hdr", ".img", ".img.gz", ".dcm", ".cub", ".mha", ".df3", ".nii.gz"]
  
  def self.path= path
    if File.exist? path
      @@c3d_path = path
      self
    else
      false
    end
  end
  
  def self.path
    @@c3d_path
  end
  
  def self.convert input_path, output_path
    system "#{@@c3d_path} #{input_path} -o #{output_path}"
  end
  
  def self.batch_convert input_dir, output_dir=nil, output_ext=".nii.gz"
    input_dir.chomp!("/")
    output_dir = (output_dir.chomp!("/") rescue input_dir)

    convertable_files = Dir.foreach(input_dir).inject([]) do |fs,f|
      next fs unless f[0] != "." and File.exists? "#{input_dir}/#{f}"
      @@Formats.any? { |ext| f.end_with?(ext) and not f.end_with?(output_ext) } ? fs << f : fs
    end.map { |f| "#{input_dir}/#{f}" }

    convertable_files.each do |file_path|
      file_name, file_ext = file_path.split("/").last.split(".",2)
      
      # make sure there are no spaces in the file name
      if file_name[/\s/]
        file_name.gsub!(/\s/,"_")
        new_path = "#{input_dir}/#{file_name}.#{file_ext}"
        File.rename file_path, new_path
        file_path = new_path
      end
      system "#{@@c3d_path} #{file_path.gsub(" ","\ ")} -o #{output_dir}/#{file_name+output_ext}"
    end
  end

  def self.input_formats
    @@Formats
  end
  
end