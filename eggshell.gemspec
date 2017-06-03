require 'rake'
Gem::Specification.new do |s|
	s.bindir      = 'bin'
	s.name        = 'eggshell'
	s.version     = '1.0.4'
	s.license     = 'MIT'
	s.summary     = "Simple document markup and flexible templating all in one!"
	s.description = "From fast and basic HTML to complex decouments and more, Eggshell aims to provide you with all the document generation power you need through simple markup."
	s.authors     = ["Kaiser Shahid"]
	s.email       = 'kaisershahid@gmail.com'
	s.files       = FileList["bin/*", "lib/**/*.rb"]
	s.homepage    = 'https://acmedinotech.com/products/eggshell'
end