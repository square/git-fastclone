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

require 'spec_helper'
require 'git-fastclone'

describe GitFastClone::UrlHelper do
  let(:test_url_valid) { 'ssh://git@git.com/git-fastclone.git' }
  let(:test_url_invalid) { 'ssh://git@git.com/git-fastclone' }
  let(:test_reference_dir) { 'test_reference_dir' }
  let(:submodule_str) do
    "Submodule 'TestModule' (https://github.com/TestModule1/TestModule2) registered for path
      'TestModule'"
  end

  describe '.path_from_git_url' do
    let(:tail) { 'git-fastclone' }

    context 'with a valid path' do
      it 'should get the tail' do
        expect(subject.path_from_git_url(test_url_valid)).to eq(tail)
      end
    end

    context 'with an invalid path' do
      it 'should still get the tail' do
        expect(subject.path_from_git_url(test_url_invalid)).to eq(tail)
      end
    end
  end

  describe '.parse_update_info' do
    it 'should parse correctly' do
      expect(subject.parse_update_info(submodule_str))
        .to eq(['TestModule', 'https://github.com/TestModule1/TestModule2'])
    end
  end

  describe '.reference_repo_name' do
    let(:expected_result) { 'git.com-git-fastclone.git' }

    it 'should come up with a unique repo name' do
      expect(subject.reference_repo_name(test_url_valid)).to eq(expected_result)
    end
  end

  describe '.reference_repo_dir' do
    it 'should join correctly' do
      allow(subject).to receive(:reference_repo_name) { test_reference_dir }

      expect(subject.reference_repo_dir(test_url_valid, test_reference_dir, false))
        .to eq(test_reference_dir + '/' + test_reference_dir)
    end
  end

  describe '.reference_repo_submodule_file' do
    it 'should return the right string' do
      allow(subject).to receive(:reference_repo_dir) { test_reference_dir }

      expect(subject.reference_repo_submodule_file(test_url_valid, test_reference_dir, false))
        .to eq('test_reference_dir:submodules.txt')
    end
  end
end
