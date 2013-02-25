Gem::Specification.new do |s|
  s.name        = 'rumesh'
  s.version     = '0.0.1'
  s.date        = '2013-02-10'
  s.summary     = "For maniupulating 3D meshes in ruby."
  s.description = "Built atop NArray, rumesh aims to make simple workflows with mesh data easy to implement efficiently in ruby."
  s.authors     = ["Nat Noordanus"]
  s.email       = 'n@natn.me'
  s.files       = ["lib/rumesh.rb", *Dir['lib/**/*.rb']]
  s.homepage    = 'https://github.com/gnatters/rumesh'
  s.add_runtime_dependency "narray", [">= 0.6.0.7", "< 0.7.0"]
  s.add_runtime_dependency "nifti"
  s.add_runtime_dependency "json"
  s.add_development_dependency "rspec"
end
