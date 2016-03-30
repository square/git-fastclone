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

describe GitFastClone::Runner do
  let(:test_url_valid) { 'ssh://git@git.com/git-fastclone.git' }
  let(:test_url_invalid) { 'ssh://git@git.com/git-fastclone' }
  let(:test_reference_dir) { 'test_reference_dir' }
  let(:test_reference_repo_dir) { '/var/tmp/git-fastclone/reference/test_reference_dir' }
  let(:placeholder_arg) { 'PH' }

  let(:lockfile) {
      lockfile = double()
      expect(lockfile).to receive(:flock).with(File::LOCK_EX).once
      expect(lockfile).to receive(:flock).with(File::LOCK_UN).once
      expect(lockfile).to receive(:close).once
      lockfile
  }

  # Modified ARGV, watch out
  ARGV = ['ssh://git@git.com/git-fastclone.git', 'test_reference_dir']

  let(:yielded) { [] }

  describe '.initialize' do
    it 'should initialize properly' do
      stub_const('GitFastClone::DEFAULT_REFERENCE_REPO_DIR', 'new_dir')

      expect(Hash).to respond_to(:new).with(2).arguments
      expect(GitFastClone::DEFAULT_REFERENCE_REPO_DIR).to eq('new_dir')
      expect(subject.prefetch_submodules).to eq(true)
      expect(subject.reference_mutex).to eq({})
      expect(subject.reference_updated).to eq({})
      expect(subject.options).to eq({})
      expect(subject.logger).to eq(nil)
    end
  end

  describe '.run' do
    let(:options) { {:branch => placeholder_arg} }

    it 'should run with the correct args' do
      allow(subject).to receive(:parse_inputs) { [placeholder_arg, placeholder_arg, options] }
      expect(subject).to receive(:clone).with(placeholder_arg, placeholder_arg, placeholder_arg)

      subject.run
    end
  end

  describe '.parse_inputs' do
    it 'should print the proper inputs' do
      subject.reference_dir = test_reference_dir
      subject.options = {}
      allow(FileUtils).to receive(:mkdir_p) {}

      expect(subject.parse_inputs).to eq([test_url_valid, test_reference_dir, {:branch=>nil}])
    end
  end

  describe '.clone' do
    it 'should clone correctly' do
      cocaine_commandline_double = double('new_cocaine_commandline')
      allow(subject).to receive(:with_git_mirror) {}
      allow(cocaine_commandline_double).to receive(:run) {}
      allow(Cocaine::CommandLine).to receive(:new) { cocaine_commandline_double }

      expect(Time).to receive(:now).twice { 0 }
      expect(Cocaine::CommandLine).to receive(:new)
      expect(cocaine_commandline_double).to receive(:run)

      subject.clone(placeholder_arg, placeholder_arg, '.')
    end
  end

  describe '.update_submodules' do
    it 'should return if no submodules' do
      subject.update_submodules(placeholder_arg, placeholder_arg)
      allow(File).to receive(:exist?) { false }

      expect(Thread).not_to receive(:new)
    end

    it 'should correctly update submodules' do
      expect(subject).to receive(:update_submodule_reference)

      allow(File).to receive(:exist?) { true }
      subject.update_submodules('.', placeholder_arg)
    end
  end

  describe '.thread_update_submodule' do
    it 'should update correctly' do
      pending('need to figure out how to test this')
      fail
    end
  end

  describe '.with_reference_repo_lock' do
    it 'should acquire a lock' do
      allow(Mutex).to receive(:synchronize)
      expect(Mutex).to respond_to(:synchronize)
      expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

      subject.with_reference_repo_lock(test_url_valid) do
        yielded << test_url_valid
      end

      expect(yielded).to eq([test_url_valid])
    end
    it 'should un-flock on thrown exception' do
      allow(Mutex).to receive(:synchronize)
      expect(Mutex).to respond_to(:synchronize)
      expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

      expect do
        subject.with_reference_repo_lock(test_url_valid) do
          raise placeholder_arg
        end
      end.to raise_error(placeholder_arg)
    end
  end

  describe '.update_submodule_reference' do
    context 'when we have an empty submodule list' do
      it 'should return' do
        expect(subject).not_to receive(:with_reference_repo_lock)

        subject.prefetch_submodules = true
        subject.update_submodule_reference(placeholder_arg, [])
      end
    end

    context 'with a populated submodule list' do
      it 'should write to a file' do
        allow(File).to receive(:open) {}
        allow(File).to receive(:write) {}
        allow(subject).to receive(:reference_repo_name) {}
        allow(subject).to receive(:reference_repo_submodule_file) {}
        expect(File).to receive(:open)
        expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

        subject.update_submodule_reference(placeholder_arg, [placeholder_arg, placeholder_arg])
      end
    end
  end

  describe '.update_reference_repo' do
    context 'when prefetch is on' do
      it 'should grab the children immediately and then store' do
        expect(subject).to receive(:prefetch).once
        expect(subject).to receive(:store_updated_repo).once
        expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

        allow(File).to receive(:exist?) { true }
        subject.prefetch_submodules = true
        subject.reference_dir = placeholder_arg
        subject.update_reference_repo(test_url_valid, false)
      end
    end

    context 'when prefetch is off' do
      it 'should store the updated repo' do
        expect(subject).not_to receive(:prefetch)
        expect(subject).to receive(:store_updated_repo).once
        expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

        allow(File).to receive(:exist?) { true }
        subject.prefetch_submodules = false
        subject.reference_dir = placeholder_arg
        subject.update_reference_repo(placeholder_arg, false)
      end
    end

    let(:placeholder_hash) { Hash.new }

    context 'when already have a hash' do
      it 'should not store' do
        placeholder_hash[placeholder_arg] = true
        expect(subject).not_to receive(:store_updated_repo)

        allow(subject).to receive(:reference_repo_name) { placeholder_arg }
        allow(subject).to receive(:reference_repo_dir) { placeholder_arg }
        subject.reference_updated = placeholder_hash
        subject.prefetch_submodules = false
        subject.update_reference_repo(placeholder_arg, false)
      end
    end

    context 'when do not have a hash' do
      it 'should store' do
        placeholder_hash[placeholder_arg] = false
        expect(subject).to receive(:store_updated_repo)
        expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

        allow(subject).to receive(:reference_repo_name) { placeholder_arg }
        subject.reference_updated = placeholder_hash
        subject.reference_dir = placeholder_arg
        subject.prefetch_submodules = false
        subject.update_reference_repo(placeholder_arg, false)
      end
    end
  end

  describe '.prefetch' do
    it 'should go through the submodule file properly' do
      expect(Thread).to receive(:new).exactly(3).times

      allow(File).to receive(:readlines) { %w(1 2 3) }
      subject.prefetch_submodules = true
      subject.prefetch(placeholder_arg)
    end
  end

  describe '.store_updated_repo' do
    context 'when fail_hard is true' do
      it 'should raise a Cocaine error' do
        cocaine_commandline_double = double('new_cocaine_commandline')
        allow(cocaine_commandline_double).to receive(:run) { fail Cocaine::ExitStatusError }
        allow(Cocaine::CommandLine).to receive(:new) { cocaine_commandline_double }
        expect(FileUtils).to receive(:remove_entry_secure).with(placeholder_arg, force: true)
        expect do
          subject.store_updated_repo(placeholder_arg, placeholder_arg, placeholder_arg, true)
        end.to raise_error(Cocaine::ExitStatusError)
      end
    end

    context 'when fail_hard is false' do
      it 'should not raise a cocaine error' do
        cocaine_commandline_double = double('new_cocaine_commandline')
        allow(cocaine_commandline_double).to receive(:run) { fail Cocaine::ExitStatusError }
        allow(Cocaine::CommandLine).to receive(:new) { cocaine_commandline_double }
        expect(FileUtils).to receive(:remove_entry_secure).with(placeholder_arg, force: true)

        expect do
          subject.store_updated_repo(placeholder_arg, placeholder_arg, placeholder_arg, false)
        end.not_to raise_error
      end
    end

    let(:placeholder_hash) { Hash.new }

    it 'should correctly update the hash' do
      cocaine_commandline_double = double('new_cocaine_commandline')
      allow(cocaine_commandline_double).to receive(:run) {}
      allow(Cocaine::CommandLine).to receive(:new) { cocaine_commandline_double }
      allow(Dir).to receive(:chdir) {}

      subject.reference_updated = placeholder_hash
      subject.store_updated_repo(placeholder_arg, placeholder_arg, placeholder_arg, false)
      expect(subject.reference_updated).to eq(placeholder_arg => true)
    end
  end

  describe '.with_git_mirror' do
    it 'should yield properly' do
      allow(subject).to receive(:update_reference_repo) {}
      expect(subject).to receive(:reference_repo_dir)
      expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

      subject.with_git_mirror(test_url_valid) do
        yielded << test_url_valid
      end

      expect(yielded).to eq([test_url_valid])
    end
  end
end
