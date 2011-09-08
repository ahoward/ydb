## ydb.gemspec
#

Gem::Specification::new do |spec|
  spec.name = "ydb"
  spec.version = "0.0.1"
  spec.platform = Gem::Platform::RUBY
  spec.summary = "ydb"
  spec.description = "description: ydb kicks the ass"

  spec.files =
["README", "Rakefile", "lib", "lib/ydb.rb"]

  spec.executables = []
  
  spec.require_path = "lib"

  spec.test_files = nil

  
    spec.add_dependency(*["map", "~> 4.4.0"])
  

  spec.extensions.push(*[])

  spec.rubyforge_project = "codeforpeople"
  spec.author = "Ara T. Howard"
  spec.email = "ara.t.howard@gmail.com"
  spec.homepage = "https://github.com/ahoward/ydb"
end
