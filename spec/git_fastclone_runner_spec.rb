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

describe GitFastClone::Runner do
  let(:test_url_valid) { 'ssh://git@git.com/git-fastclone.git' }
  let(:test_url_invalid) { 'ssh://git@git.com/git-fastclone' }
  let(:test_reference_dir) { 'test_reference_dir' }
  let(:test_reference_repo_dir) { '/var/tmp/git-fastclone/reference/test_reference_dir' }
  let(:placeholder_arg) { 'PH' }

  let(:lockfile) do
    lockfile = double
    expect(lockfile).to receive(:flock).with(File::LOCK_EX).once
    expect(lockfile).to receive(:flock).with(File::LOCK_UN).once
    expect(lockfile).to receive(:close).once
    lockfile
  end

  before do
    stub_const('ARGV', ['ssh://git@git.com/git-fastclone.git', 'test_reference_dir'])
  end

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
    let(:options) { { branch: placeholder_arg } }

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

      expect(subject.parse_inputs).to eq([test_url_valid, test_reference_dir, { branch: nil }])
    end
  end

  describe '.clone' do
    it 'should clone correctly' do
      terrapin_commandline_double = double('new_terrapin_commandline')
      allow(subject).to receive(:with_git_mirror) {}
      allow(terrapin_commandline_double).to receive(:run) {}
      allow(Terrapin::CommandLine).to receive(:new) { terrapin_commandline_double }

      expect(Time).to receive(:now).twice { 0 }
      expect(Terrapin::CommandLine).to receive(:new)
      expect(terrapin_commandline_double).to receive(:run)

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
      raise
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

    let(:placeholder_hash) { {} }

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

      allow(File).to receive(:readlines) { %w[1 2 3] }
      subject.prefetch_submodules = true
      subject.prefetch(placeholder_arg)
    end
  end

  describe '.store_updated_repo' do
    context 'when fail_hard is true' do
      it 'should raise a Terrapin error' do
        terrapin_commandline_double = double('new_terrapin_commandline')
        allow(terrapin_commandline_double).to receive(:run) { raise Terrapin::ExitStatusError }
        allow(Terrapin::CommandLine).to receive(:new) { terrapin_commandline_double }
        expect(FileUtils).to receive(:remove_entry_secure).with(placeholder_arg, force: true)
        expect do
          subject.store_updated_repo(placeholder_arg, placeholder_arg, placeholder_arg, true)
        end.to raise_error(Terrapin::ExitStatusError)
      end
    end

    context 'when fail_hard is false' do
      it 'should not raise a terrapin error' do
        terrapin_commandline_double = double('new_terrapin_commandline')
        allow(terrapin_commandline_double).to receive(:run) { raise Terrapin::ExitStatusError }
        allow(Terrapin::CommandLine).to receive(:new) { terrapin_commandline_double }
        expect(FileUtils).to receive(:remove_entry_secure).with(placeholder_arg, force: true)

        expect do
          subject.store_updated_repo(placeholder_arg, placeholder_arg, placeholder_arg, false)
        end.not_to raise_error
      end
    end

    let(:placeholder_hash) { {} }

    it 'should correctly update the hash' do
      terrapin_commandline_double = double('new_terrapin_commandline')
      allow(terrapin_commandline_double).to receive(:run) {}
      allow(Terrapin::CommandLine).to receive(:new) { terrapin_commandline_double }
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

    it 'should retry when the cache looks corrupted' do
      allow(subject).to receive(:update_reference_repo) {}
      expect(subject).to receive(:reference_repo_dir)
      expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

      responses = [
        lambda { |_url|
          raise Terrapin::ExitStatusError, <<-ERROR.gsub(/^ {12}/, '')
            STDOUT:

            STDERR:

            fatal: bad object ee35b1e14e7c3a53dcc14d82606e5b872f6a05a7
            fatal: remote did not send all necessary objects
          ERROR
        },
        ->(url) { url }
      ]
      subject.with_git_mirror(test_url_valid) do
        yielded << responses.shift.call(test_url_valid)
      end

      expect(responses).to be_empty
      expect(yielded).to eq([test_url_valid])
    end

    it 'should retry when the clone succeeds but checkout fails with corrupt packed object' do
      allow(subject).to receive(:update_reference_repo) {}
      expect(subject).to receive(:reference_repo_dir)
      expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

      responses = [
        lambda { |_url|
          raise Terrapin::ExitStatusError, <<-ERROR.gsub(/^ {12}/, '')
            STDOUT:

            STDERR:

            fatal: packed object 7c4d79704f8adf701f38a7bfb3e33ec5342542f1 (stored in /private/var/tmp/git-fastclone/reference/some-repo.git/objects/pack/pack-d37d7ed3e88d6e5f0ac141a7b0a2b32baf6e21a0.pack) is corrupt
            warning: Clone succeeded, but checkout failed.
            You can inspect what was checked out with 'git status' and retry with 'git restore --source=HEAD :/'
          ERROR
        },
        ->(url) { url }
      ]
      subject.with_git_mirror(test_url_valid) do
        yielded << responses.shift.call(test_url_valid)
      end

      expect(responses).to be_empty
      expect(yielded).to eq([test_url_valid])
    end

    it 'should retry when the clone succeeds but checkout fails with unable to read tree' do
      allow(subject).to receive(:update_reference_repo) {}
      expect(subject).to receive(:reference_repo_dir)
      expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

      responses = [
        lambda { |_url|
          raise Terrapin::ExitStatusError, <<-ERROR.gsub(/^ {12}/, '')
            STDOUT:

            STDERR:

            error: Could not read 92cf57b8f07df010ab5f607b109c325e30e46235
            fatal: unable to read tree 0c32c0521d3b0bfb4e74e4a39b97a84d1a3bb9a1
            warning: Clone succeeded, but checkout failed.
            You can inspect what was checked out with 'git status'
            and retry with 'git restore --source=HEAD :/'
          ERROR
        },
        ->(url) { url }
      ]
      subject.with_git_mirror(test_url_valid) do
        yielded << responses.shift.call(test_url_valid)
      end

      expect(responses).to be_empty
      expect(yielded).to eq([test_url_valid])
    end

    it 'should retry when one delta is missing' do
      allow(subject).to receive(:update_reference_repo) {}
      expect(subject).to receive(:reference_repo_dir)
      expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

      responses = [
        lambda { |_url|
          raise Terrapin::ExitStatusError, <<-ERROR.gsub(/^ {12}/, '')
            STDOUT:

            STDERR:

            error: Could not read f7fad86d06fee0678f9af7203b6031feabb40c3e
            fatal: pack has 1 unresolved delta
            fatal: index-pack failed
          ERROR
        },
        ->(url) { url }
      ]
      subject.with_git_mirror(test_url_valid) do
        yielded << responses.shift.call(test_url_valid)
      end

      expect(responses).to be_empty
      expect(yielded).to eq([test_url_valid])
    end

    it 'should retry when deltas are missing' do
      allow(subject).to receive(:update_reference_repo) {}
      expect(subject).to receive(:reference_repo_dir)
      expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

      responses = [
        lambda { |_url|
          raise Terrapin::ExitStatusError, <<-ERROR.gsub(/^ {12}/, '')
            STDOUT:

            STDERR:

            error: Could not read f7fad86d06fee0678f9af7203b6031feabb40c3e
            fatal: pack has 138063 unresolved deltas
            fatal: index-pack failed
          ERROR
        },
        ->(url) { url }
      ]
      subject.with_git_mirror(test_url_valid) do
        yielded << responses.shift.call(test_url_valid)
      end

      expect(responses).to be_empty
      expect(yielded).to eq([test_url_valid])
    end
  end

  it 'should retry when the cache errors with unable to read sha1 file' do
    allow(subject).to receive(:update_reference_repo) {}
    expect(subject).to receive(:reference_repo_dir)
    expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

    responses = [
      lambda { |_url|
        raise Terrapin::ExitStatusError, <<-ERROR.gsub(/^ {12}/, '')
            STDOUT:

            STDERR:

            error: unable to read sha1 file of sqiosbuild/lib/action/action.rb (6113b739af82d8b07731de8a58d6e233301f80ab)
            fatal: unable to checkout working tree
            warning: Clone succeeded, but checkout failed.
            You can inspect what was checked out with 'git status'
            and retry with 'git restore --source=HEAD :/'
        ERROR
      },
      ->(url) { url }
    ]
    subject.with_git_mirror(test_url_valid) do
      yielded << responses.shift.call(test_url_valid)
    end

    expect(responses).to be_empty
    expect(yielded).to eq([test_url_valid])
  end

  it 'should retry when the cache errors with did not receive expected object' do
    allow(subject).to receive(:update_reference_repo) {}
    expect(subject).to receive(:reference_repo_dir)
    expect(subject).to receive(:reference_repo_lock_file).and_return(lockfile)

    responses = [
      lambda { |_url|
        raise Terrapin::ExitStatusError, <<-ERROR.gsub(/^ {12}/, '')
            STDOUT:

            STDERR:

            error: Could not read 6682dfe81f66656436e60883dd795e7ec6735153
            error: Could not read 0cd3703c23fa44c0043d97fbc26356a23939f31b
            fatal: did not receive expected object 3c64c9dd49c79bd09aa13d4b05ac18263ca29ccd
            fatal: index-pack failed
        ERROR
      },
      ->(url) { url }
    ]
    subject.with_git_mirror(test_url_valid) do
      yielded << responses.shift.call(test_url_valid)
    end

    expect(responses).to be_empty
    expect(yielded).to eq([test_url_valid])
  end
end
