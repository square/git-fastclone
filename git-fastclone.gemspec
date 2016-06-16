# Copyright 2016 Square Inc.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

$:.push File.expand_path("../lib", __FILE__)
require 'git-fastclone/info'

Gem::Specification.new do |gem|
  gem.name          = 'git-fastclone'
  gem.version       = GitFastClone::Info::VERSION
  gem.date          = Date.today.to_s
  gem.summary       = GitFastClone::Info::SUMMARY
  gem.description   = GitFastClone::Info::DESCRIPTION
  gem.authors       = ['Michael Tauraso', 'James Chang']
  gem.email         = ['mtauraso@squareup.com', 'jchang@squareup.com']
  gem.files         = Dir['Rakefile', '{bin,lib,man,test,spec}/**/*', 'README*', 'LICENSE*'] & `git ls-files -z`.split("\0")
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ['lib']
  gem.homepage      = 'http://square.github.io/git-fastclone/'
  gem.license       = 'Apache'

  gem.add_runtime_dependency 'cocaine', '~> 0.5'
  gem.add_runtime_dependency 'colorize', '~> 0.7'
  gem.add_runtime_dependency 'docopt', '~> 0.5'
end
