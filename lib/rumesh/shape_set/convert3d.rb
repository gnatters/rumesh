
# A very light wrapper for the InsightToolkit Convert3D tool which must be downloaded seperately.
# See http://www.itksnap.org/pmwiki/pmwiki.php?n=Convert3D.Convert3D
module Convert3D
  
  @@c3d_path = nil
  @@InputFormats = [".nrrd", ".hdr", ".img", ".img.gz", ".dcm", ".cub", ".mha", ".df3", ".nii.gz"]
  
  def self.setup path
    if File.exist? path
      @@c3d_path = path
      self
    else
      false
    end
  end
  
  def self.convert input_path, output_path
    system "#{@@c3d_path} #{input_path} -o #{output_path}"
  end
  
  def self.input_formats
    @@InputFormats
  end
  
end