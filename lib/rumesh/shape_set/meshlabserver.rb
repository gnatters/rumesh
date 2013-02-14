require 'open3'

module MeshLabServer
  # some helpful methods for working with meshlabserver
  
  @@exec_dir = nil
  @@mls_path = nil
  
  def self.exec_dir
    @@exec_dir
  end

  def self.exec_dir= dir
    @@exec_dir = dir if Dir.exist? dir
  end
  
  def self.mls_path
    @@exec_dir
  end

  def self.mls_path= executable
    @@mls_path = executable if File.exist? executable
  end
  
  def self.write_new_script name, output_dir, type, params={}
    output_path = "#{output_dir}/#{name.to_s}.mlx"
    File.open(output_path, 'w') { |f| MeshLabServer::ScriptTemplates.compose type, params }
    output_path
  end
  
  def self.run script_location, input_file, output_file
    if @@exec_dir
      Open3.capture3("cd #{@@exec_dir}; #{@@mls_path} -i #{input_file} -s #{script_location} -o #{output_file}")
    else
      Open3.capture3("#{@@mls_path} -i #{input_file} -s #{script_location} -o #{output_file}")
    end
  end
  
end


module MeshLabServer::ScriptTemplates
  
  @@script_header = "<!DOCTYPE FilterScript>\n<FilterScript>"
  @@script_footer = "\n</FilterScript>"
  
  def self.compose type, params
    script = @@script_header
    raise ArgumentError, "unknown script type: #{type}" unless ScriptTemplates[type]
    ScriptTemplates[type].each do |s|
      if s.kind_of? String
        script << s
      elsif s.kind_of? Symbol
        if params[s]
          script << params[s]
        else
          raise ArgumentError, "missing required paramter: #{s} for type: #{type}"
        end
      elsif s.kind_of? Array
        script << (params[s[0]] or s[1])
      end
    end
    script << @@script_footer
  end
  
  def self.params_for type
    ScriptTemplates[type].map do |s| 
      if s.kind_of? Symbol then s
      elsif s.kind_of? Array then s.first
      end
    end.compact
  end
  
  def self.required_params_for type
    ScriptTemplates[type].map { |s| s if s.kind_of? Symbol }.compact
  end
  
  def self.get_script_template type
    ScriptTemplates[type]
  end
  
  def self.put_script_template type, template
    ScriptTemplates[type] = template
  end
  
  class ScriptTemplates
    def self.[] type
      self.script_templates[type]
    end
    
    def self.[]= type, template
      self.script_templates
      @@script_templates[type] = template
    end
    
    def self.script_templates
      @@script_templates ||= Hash[
        merge_close_vertices: ["
  <filter name=\"Merge Close Vertices\">
    <Param type=\"RichAbsPerc\" value=\"0\" min=\"0\" name=\"Threshold\" max=\"",[:max,0.3],"\"/>
  </filter>"
        ],
        apply_smoothing: ["
  <filter name=\"Taubin Smooth\">
   <Param type=\"RichFloat\" value=\"",[:taubin_lambda,0.5],"\" name=\"lambda\"/>
   <Param type=\"RichFloat\" value=\"",[:taubin_mu,-0.53],"\" name=\"mu\"/>
   <Param type=\"RichInt\" value=\"",[:taubin_stepSmoothNum,10],"\" name=\"stepSmoothNum\"/>
   <Param type=\"RichBool\" value=\"false\" name=\"Selected\"/>
  </filter>
  <filter name=\"Select Border\">
   <Param type=\"RichInt\" value=\"1\" name=\"Iteration\"/>
  </filter>
  <filter name=\"Invert Selection\">
   <Param type=\"RichBool\" value=\"true\" name=\"InvFaces\"/>
   <Param type=\"RichBool\" value=\"true\" name=\"InvVerts\"/>
  </filter>
  <filter name=\"Laplacian Smooth\">
   <Param type=\"RichInt\" value=\"",[:laplacian_stepSmoothNum,3],"\" name=\"stepSmoothNum\"/>
   <Param type=\"RichBool\" value=\"",[:laplacian_Boundary,false],"\" name=\"Boundary\"/>
   <Param type=\"RichBool\" value=\"true\" name=\"Selected\"/>
  </filter>
  <filter name=\"Select None\"/>"
        ],
        isolate_non_manifold_edges: ["
  <filter name=\"Merge Close Vertices\">
   <Param type=\"RichAbsPerc\" value=\"0\" min=\"0\" name=\"Threshold\" max=\"0.605558\"/>
  </filter>
  <filter name=\"Select non Manifold Edges \"/>
  <filter name=\"Invert Selection\">
   <Param type=\"RichBool\" value=\"true\" name=\"InvFaces\"/>
   <Param type=\"RichBool\" value=\"true\" name=\"InvVerts\"/>
  </filter>
  <filter name=\"Delete Selected Faces\"/>
  <filter name=\"Remove Unreferenced Vertex\"/>"
        ],
        apply_decimation: ["
  <filter name=\"Quadric Edge Collapse Decimation\">
   <Param type=\"RichInt\" value=\"", :TargetFaceNum, "\" name=\"TargetFaceNum\"/>
   <Param type=\"RichFloat\" value=\"",[:TargetPerc,0],"\" name=\"TargetPerc\"/>
   <Param type=\"RichFloat\" value=\"",[:QualityThr,0.3],"\" name=\"QualityThr\"/>
   <Param type=\"RichBool\" value=\"",[:PreserveBoundary,true],"\" name=\"PreserveBoundary\"/>
   <Param type=\"RichBool\" value=\"",[:PreserveNormal,true],"\" name=\"PreserveNormal\"/>
   <Param type=\"RichBool\" value=\"",[:PreserveTopology,true],"\" name=\"PreserveTopology\"/>
   <Param type=\"RichBool\" value=\"",[:OptimalPlacement,true],"\" name=\"OptimalPlacement\"/>
   <Param type=\"RichBool\" value=\"",[:PlanarQuadric,false],"\" name=\"PlanarQuadric\"/>
   <Param type=\"RichBool\" value=\"",[:QualityWeight,false],"\" name=\"QualityWeight\"/>
   <Param type=\"RichBool\" value=\"",[:AutoClean,true],"\" name=\"AutoClean\"/>
   <Param type=\"RichBool\" value=\"false\" name=\"Selected\"/>
  </filter>
  <filter name=\"Remove Duplicated Vertex\"/>
  <filter name=\"Remove Duplicate Faces\"/>"
        ]
      ]
    end
  end
  
end
