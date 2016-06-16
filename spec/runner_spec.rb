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

require 'spec_helper'
require 'git-fastclone'

describe GitFastClone::Runner do
  include TestManager
  track_shell_actions

  let(:url_valid) { 'ssh://git@git.com/git-fastclone.git' }
  let(:local_repo) { 'spec' }
  let(:path) { 'path' }
  let(:test_reference_repo_dir) { '/var/tmp/git-fastclone/reference/path' }
  let(:placeholder_arg) { 'PH' }
  let(:flock_timeout) { 5 }

  let(:lockfile) do
    lockfile = double
    expect(lockfile).to receive(:flock).with(File::LOCK_EX).once
    expect(lockfile).to receive(:flock).with(File::LOCK_UN).once
    expect(lockfile).to receive(:close).once
    lockfile
  end

  # Modified ARGV, watch out
  before do
    ARGV = [url_valid, path, '--verbose', '--color', '--lock-timeout', flock_timeout].freeze
    mock_commands
  end

  after(:all) do
    FileUtils.rm('PH:lock') if File.exist?('PH:lock')
  end

  let(:yielded) { [] }

  describe '.initialize' do
    it 'parses args' do
      expect(subject.url).to eq(url_valid)
      expect(subject.path).to eq(path)
      expect(subject.flock_timeout_secs).to eq(flock_timeout)
      expect(subject.branch).to be_nil
      expect(subject.color).to be_truthy
      expect(subject.verbose).to be_truthy
    end

    context 'local repo' do
      it 'indicates using_local_repo' do
        ARGV = [local_repo].freeze
        expect(subject.using_local_repo).to be_truthy
      end
    end

    context 'verbose' do
      it 'creates a logger' do
        expect(Cocaine::CommandLine.logger).to be_instance_of(Logger)
      end
    end
  end

  describe '#run' do
    it 'runs' do
      expect(subject).to receive(:clone).with(url_valid, nil, path)
      subject.run
    end
  end

  describe '#clone' do
    context 'destination empty' do
      let(:steps) do
        [{ cmd: ['git clone', '--mirror :url :mirror'], opts: {} },
         { cmd: ['cd', ':path; git remote update --prune'], opts: {} },
         { cmd: ['git clone', '--quiet --reference :mirror :url :path'], opts: {} }]
      end

      it 'updates mirror' do
        allow(subject).to receive(:reference_repo_lock_file).and_return(double(flock: nil, close: nil))
        expect(subject).to receive(:update_submodules).with(path, url_valid)
        subject.send(:clone, url_valid, nil, path)
        expect(actions).to eq(steps)
      end
    end

    context 'destination exists' do
      it 'raises' do
        expect { subject.send(:clone, url_valid, nil, local_repo) }.to raise_error
        expect(actions).to be_empty
      end
    end
  end

  describe '#update_submodules' do
    context 'no submodules' do
      it 'returns' do
        subject.send(:update_submodules, subject.abs_clone_path, subject.url)
        expect(Thread).not_to receive(:new)
        expect(actions).to be_empty
      end
    end

    context 'with submodules' do
      let(:steps) { [{ cmd: ['cd', ':path; git submodule init'], opts: {} }] }

      it 'should correctly update submodules' do
        expect(subject).to receive(:update_submodule_reference).with(url_valid, [])
        allow(File).to receive(:exist?) { true }
        subject.send(:update_submodules, subject.abs_clone_path, subject.url)
        expect(actions).to eq(steps)
      end
    end
  end

  describe '#thread_update_submodule' do
    it 'updates submodules' do
      pending('need to figure out how to test this')
      raise
    end
  end

  describe '#with_reference_repo_lock' do
    it 'should acquire a lock' do
      allow(Mutex).to receive(:synchronize)
      expect(Mutex).to respond_to(:synchronize)
      expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

      subject.send(:with_reference_repo_lock, url_valid) do
        yielded << url_valid
      end

      expect(yielded).to eq([url_valid])
    end

    it 'should un-flock on thrown exception' do
      allow(Mutex).to receive(:synchronize)
      expect(Mutex).to respond_to(:synchronize)
      expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

      expect do
        subject.send(:with_reference_repo_lock, url_valid) do
          raise placeholder_arg
        end
      end.to raise_error(placeholder_arg)
    end
  end

  describe '#update_submodule_reference' do
    context 'when we have an empty submodule list' do
      it 'should return' do
        expect(subject).not_to receive(:with_reference_repo_lock)

        subject.prefetch_submodules = true
        subject.send(:update_submodule_reference, placeholder_arg, [])
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

        subject.send(:update_submodule_reference, placeholder_arg, [placeholder_arg, placeholder_arg])
      end
    end
  end

  describe '#update_reference_repo' do
    context 'when prefetch is on' do
      it 'should grab the children immediately and then store' do
        expect(subject).to receive(:prefetch).once
        expect(subject).to receive(:store_updated_repo).once
        expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

        allow(File).to receive(:exist?) { true }
        subject.prefetch_submodules = true
        subject.reference_dir = placeholder_arg
        subject.send(:update_reference_repo, url_valid, false)
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
        subject.send(:update_reference_repo, placeholder_arg, false)
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
        subject.send(:update_reference_repo, placeholder_arg, false)
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
        subject.send(:update_reference_repo, placeholder_arg, false)
      end
    end
  end

  describe '#prefetch' do
    it 'should go through the submodule file properly' do
      expect(Thread).to receive(:new).exactly(3).times

      allow(File).to receive(:readlines) { %w(1 2 3) }
      subject.prefetch_submodules = true
      subject.send(:prefetch, placeholder_arg)
    end
  end

  describe '#store_updated_repo' do
    context 'when fail_hard is true' do
      it 'should raise a Cocaine error' do
        cocaine_commandline_double = double('new_cocaine_commandline')
        allow(cocaine_commandline_double).to receive(:run) { raise Cocaine::ExitStatusError }
        allow(Cocaine::CommandLine).to receive(:new) { cocaine_commandline_double }
        expect(FileUtils).to receive(:remove_entry_secure).with(placeholder_arg, force: true)
        expect do
          subject.send(:store_updated_repo, placeholder_arg, placeholder_arg, placeholder_arg, true)
        end.to raise_error(Cocaine::ExitStatusError)
      end
    end

    context 'when fail_hard is false' do
      it 'should not raise a cocaine error' do
        cocaine_commandline_double = double('new_cocaine_commandline')
        allow(cocaine_commandline_double).to receive(:run) { raise Cocaine::ExitStatusError }
        allow(Cocaine::CommandLine).to receive(:new) { cocaine_commandline_double }
        expect(FileUtils).to receive(:remove_entry_secure).with(placeholder_arg, force: true)

        expect do
          subject.send(:store_updated_repo, placeholder_arg, placeholder_arg, placeholder_arg, false)
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
      subject.send(:store_updated_repo, placeholder_arg, placeholder_arg, placeholder_arg, false)
      expect(subject.reference_updated).to eq(placeholder_arg => true)
    end
  end

  describe '.with_git_mirror' do
    it 'should yield properly' do
      allow(subject).to receive(:update_reference_repo) {}
      expect(subject).to receive(:reference_repo_dir)
      expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

      subject.send(:with_git_mirror, url_valid) do
        yielded << url_valid
      end

      expect(yielded).to eq([url_valid])
    end
  end
end
