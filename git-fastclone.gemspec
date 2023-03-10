# frozen_string_literal: true

# Copyright 2015 Square Inc.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'date'

$LOAD_PATH.push File.expand_path('lib', __dir__)
require 'git-fastclone/version'

Gem::Specification.new do |gem|
  gem.name          = 'git-fastclone'
  gem.version       = GitFastCloneVersion::VERSION
  gem.summary       = 'git-clone --recursive on steroids!'
  gem.description   = 'A git command that uses reference repositories and threading to quickly' \
                      'and recursively clone repositories with many nested submodules'
  gem.authors       = ['Michael Tauraso', 'James Chang']
  gem.email         = ['mtauraso@squareup.com', 'jchang@squareup.com']
  gem.files         = Dir['Rakefile', '{bin,lib,man,test,spec}/**/*', 'README*', 'LICENSE*'] &
                      `git ls-files -z`.split("\0")
  gem.executables   = gem.files.grep(%r{^bin/}).map { |f| File.basename(f) }
  gem.require_paths = ['lib']
  gem.homepage      = 'http://square.github.io/git-fastclone/'
  gem.license       = 'Apache'

  gem.required_ruby_version = '>= 2.7'

  gem.add_runtime_dependency 'colorize'
  gem.metadata['rubygems_mfa_required'] = 'true'
end
