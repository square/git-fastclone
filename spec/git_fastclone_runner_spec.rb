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

  def create_lockfile_double
    lockfile = double
    expect(lockfile).to receive(:flock).with(File::LOCK_EX).once
    expect(lockfile).to receive(:flock).with(File::LOCK_UN).once
    expect(lockfile).to receive(:close).once
    lockfile
  end

  let(:lockfile) { create_lockfile_double }

  before do
    stub_const('ARGV', ['ssh://git@git.com/git-fastclone.git', 'test_reference_dir'])
    allow($stdout).to receive(:puts)
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
    end
  end

  describe '.run' do
    let(:options) { { branch: placeholder_arg } }

    it 'should run with the correct args' do
      allow(subject).to receive(:parse_inputs) { [placeholder_arg, placeholder_arg, options, nil] }
      expect(subject).to receive(:clone).with(placeholder_arg, placeholder_arg, placeholder_arg, nil)

      subject.run
    end

    describe 'with custom configs' do
      let(:options) { { branch: placeholder_arg, config: 'conf' } }

      it 'should clone correctly' do
        allow(subject).to receive(:parse_inputs) { [placeholder_arg, placeholder_arg, options, 'conf'] }
        expect(subject).to receive(:clone).with(placeholder_arg, placeholder_arg, placeholder_arg, 'conf')

        subject.run
      end
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
    let(:runner_execution_double) { double('runner_execution') }
    before(:each) do
      allow(runner_execution_double).to receive(:fail_on_error) {}
      allow(Dir).to receive(:pwd) { '/pwd' }
      allow(Dir).to receive(:chdir).and_yield
      allow(subject).to receive(:with_git_mirror).and_yield('/cache', 0)
      expect(subject).to receive(:clear_clone_dest_if_needed).once {}
    end

    it 'should clone correctly' do
      expect(subject).to receive(:fail_on_error).with(
        'git', 'checkout', '--quiet', 'PH',
        { quiet: true, print_on_failure: false }
      ) { runner_execution_double }
      expect(subject).to receive(:fail_on_error).with(
        'git', 'clone', '--quiet', '--reference', '/cache', 'PH', '/pwd/.',
        { quiet: true, print_on_failure: false }
      ) { runner_execution_double }

      subject.clone(placeholder_arg, placeholder_arg, '.', nil)
    end

    it 'should clone correctly with verbose mode on' do
      subject.verbose = true
      expect(subject).to receive(:fail_on_error).with(
        'git', 'checkout', '--quiet', 'PH',
        { quiet: false, print_on_failure: false }
      ) { runner_execution_double }
      expect(subject).to receive(:fail_on_error).with(
        'git', 'clone', '--verbose', '--reference', '/cache', 'PH', '/pwd/.',
        { quiet: false, print_on_failure: false }
      ) { runner_execution_double }

      subject.clone(placeholder_arg, placeholder_arg, '.', nil)
    end

    it 'should clone correctly with custom configs' do
      expect(subject).to receive(:fail_on_error).with(
        'git', 'clone', '--quiet', '--reference', '/cache', 'PH', '/pwd/.', '--config', 'config',
        { quiet: true, print_on_failure: false}
      ) { runner_execution_double }

      subject.clone(placeholder_arg, nil, '.', 'config')
    end
  end

  describe '.clear_clone_dest_if_needed' do
    it 'does not clear on first attempt' do
      expect(Dir).not_to receive(:glob)
      expect(subject).not_to receive(:clear_clone_dest)
      subject.clear_clone_dest_if_needed(0, '/some/path')
    end

    it 'does not clear if the directory is only FNM_DOTMATCH self and parent refs' do
      expect(Dir).to receive(:glob).and_return(%w[. ..])
      expect(subject).not_to receive(:clear_clone_dest)
      subject.clear_clone_dest_if_needed(1, '/some/path')
    end

    it 'does clear if the directory is not empty' do
      expect(Dir).to receive(:glob).and_return(%w[. .. /some/path/file.txt])
      expect(subject).to receive(:clear_clone_dest) {}
      subject.clear_clone_dest_if_needed(1, '/some/path')
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
      it 'should raise a Runtime error and clear cache' do
        status = double('status')
        allow(status).to receive(:exitstatus).and_return(1)
        ex = RunnerExecution::RunnerExecutionRuntimeError.new(status, 'cmd')
        allow(subject).to receive(:fail_on_error) { raise ex }
        expect(FileUtils).to receive(:remove_entry_secure).with(placeholder_arg, force: true)
        expect do
          subject.store_updated_repo(placeholder_arg, placeholder_arg, placeholder_arg, true)
        end.to raise_error(ex)
      end
    end

    context 'when fail_hard is false' do
      it 'should not raise a Runtime error but clear cache' do
        status = double('status')
        allow(status).to receive(:exitstatus).and_return(1)
        ex = RunnerExecution::RunnerExecutionRuntimeError.new(status, 'cmd')
        allow(subject).to receive(:fail_on_error) { raise ex }
        expect(FileUtils).to receive(:remove_entry_secure).with(placeholder_arg, force: true)
        expect do
          subject.store_updated_repo(placeholder_arg, placeholder_arg, placeholder_arg, false)
        end.to_not raise_error
      end
    end

    let(:placeholder_hash) { {} }

    it 'should correctly update the hash' do
      allow(subject).to receive(:fail_on_error)
      allow(Dir).to receive(:chdir) {}

      subject.reference_updated = placeholder_hash
      subject.store_updated_repo(placeholder_arg, placeholder_arg, placeholder_arg, false)
      expect(subject.reference_updated).to eq(placeholder_arg => true)
    end
  end

  describe '.with_git_mirror' do
    def retriable_error
      %(
        fatal: bad object ee35b1e14e7c3a53dcc14d82606e5b872f6a05a7
        fatal: remote did not send all necessary objects
      ).strip.split("\n").map(&:strip).join("\n")
    end

    def try_with_git_mirror(responses, results)
      lambdas = responses.map do |response|
        if response == true
          # Simulate successful response
          ->(url) { url }
        else
          # Simulate failed error response
          lambda { |_url|
            status = double('status')
            allow(status).to receive(:exitstatus).and_return(1)
            raise RunnerExecution::RunnerExecutionRuntimeError.new(status, 'cmd', response)
          }
        end
      end

      subject.with_git_mirror(test_url_valid) do |url, attempt|
        raise 'Not enough responses were provided!' if lambdas.empty?

        yielded << [lambdas.shift.call(url), attempt]
      end

      expect(lambdas).to be_empty
      expect(yielded).to eq(results)
    end

    let(:expected_commands) { [] }

    before(:each) do
      allow(subject).to receive(:fail_on_error) { |*params|
        # last one is an argument `quiet:`
        command = params.first(params.size - 1)
        expect(expected_commands.length).to be > 0
        expected_command = expected_commands.shift
        expect(command).to eq(expected_command)
      }
      allow(Dir).to receive(:chdir).and_yield

      allow(subject).to receive(:print_formatted_error) {}
      allow(subject).to receive(:reference_repo_dir).and_return(test_reference_repo_dir)
      allow(subject).to receive(:reference_repo_lock_file) { create_lockfile_double }
    end

    after(:each) do
      expect(expected_commands).to be_empty
    end

    def clone_cmds(verbose: false)
      [
        ['git', 'clone', verbose ? '--verbose' : '--quiet', '--mirror', test_url_valid,
         test_reference_repo_dir],
        ['git', 'remote', verbose ? '--verbose' : nil, 'update', '--prune'].compact
      ]
    end

    context 'expecting 1 clone attempt' do
      context 'with verbose mode on' do
        before { subject.verbose = true }
        let(:expected_commands) { clone_cmds(verbose: true) }

        it 'should succeed with a successful clone' do
          expect(subject).not_to receive(:clear_cache)
          try_with_git_mirror([true], [[test_reference_repo_dir, 0]])
        end

        it 'should fail after a non-retryable clone error' do
          expect(subject).not_to receive(:clear_cache)
          expect do
            try_with_git_mirror(['Some unexpected error message'], [])
          end.to raise_error(RunnerExecution::RunnerExecutionRuntimeError)
        end
      end

      context 'with verbose mode off' do
        let(:expected_commands) { clone_cmds }

        it 'should succeed with a successful clone' do
          expect(subject).not_to receive(:clear_cache)
          try_with_git_mirror([true], [[test_reference_repo_dir, 0]])
        end

        it 'should fail after a non-retryable clone error' do
          expect(subject).not_to receive(:clear_cache)
          expect do
            try_with_git_mirror(['Some unexpected error message'], [])
          end.to raise_error(RunnerExecution::RunnerExecutionRuntimeError)
        end
      end
    end

    context 'expecting 2 clone attempts' do
      let(:expected_commands) { clone_cmds + clone_cmds }
      let(:expected_commands_args) { clone_args + clone_args }

      it 'should succeed after a single retryable clone failure' do
        expect(subject).to receive(:clear_cache).and_call_original
        try_with_git_mirror([retriable_error, true], [[test_reference_repo_dir, 1]])
      end

      it 'should fail after two retryable clone failures' do
        expect(subject).to receive(:clear_cache).twice.and_call_original
        expect do
          try_with_git_mirror([retriable_error, retriable_error], [])
        end.to raise_error(RunnerExecution::RunnerExecutionRuntimeError)
      end
    end
  end

  describe '.retriable_error?' do
    def format_error(error)
      error_wrapper = error.to_s
      error_wrapper.strip.lines.map(&:strip).join("\n")
    end

    it 'not for a random error message' do
      error = format_error 'random error message'

      expect(subject.retriable_error?(error)).to be_falsey
    end

    it 'when the cache looks corrupted' do
      error = format_error <<-ERROR
        fatal: bad object ee35b1e14e7c3a53dcc14d82606e5b872f6a05a7
        fatal: remote did not send all necessary objects
      ERROR

      expect(subject.retriable_error?(error)).to be_truthy
    end

    it 'when the clone succeeds but checkout fails with corrupt packed object' do
      error = format_error <<-ERROR
        fatal: packed object 7c4d79704f8adf701f38a7bfb3e33ec5342542f1 (stored in /private/var/tmp/git-fastclone/reference/some-repo.git/objects/pack/pack-d37d7ed3e88d6e5f0ac141a7b0a2b32baf6e21a0.pack) is corrupt
        warning: Clone succeeded, but checkout failed.
        You can inspect what was checked out with 'git status' and retry with 'git restore --source=HEAD :/'
      ERROR

      expect(subject.retriable_error?(error)).to be_truthy
    end

    it 'when the clone succeeds but checkout fails with unable to read tree' do
      error = format_error <<-ERROR
        error: Could not read 92cf57b8f07df010ab5f607b109c325e30e46235
        fatal: unable to read tree 0c32c0521d3b0bfb4e74e4a39b97a84d1a3bb9a1
        warning: Clone succeeded, but checkout failed.
        You can inspect what was checked out with 'git status'
        and retry with 'git restore --source=HEAD :/'
      ERROR

      expect(subject.retriable_error?(error)).to be_truthy
    end

    it 'when one delta is missing' do
      error = format_error <<-ERROR
        error: Could not read f7fad86d06fee0678f9af7203b6031feabb40c3e
        fatal: pack has 1 unresolved delta
        fatal: index-pack failed
      ERROR

      expect(subject.retriable_error?(error)).to be_truthy
    end

    it 'when deltas are missing' do
      error = format_error <<-ERROR
        error: Could not read f7fad86d06fee0678f9af7203b6031feabb40c3e
        fatal: pack has 138063 unresolved deltas
        fatal: index-pack failed
      ERROR

      expect(subject.retriable_error?(error)).to be_truthy
    end

    it 'when the cache errors with unable to read sha1 file' do
      error = format_error <<-ERROR
        error: unable to read sha1 file of sqiosbuild/lib/action/action.rb (6113b739af82d8b07731de8a58d6e233301f80ab)
        fatal: unable to checkout working tree
        warning: Clone succeeded, but checkout failed.
        You can inspect what was checked out with 'git status'
        and retry with 'git restore --source=HEAD :/'
      ERROR

      expect(subject.retriable_error?(error)).to be_truthy
    end

    it 'when the cache errors with did not receive expected object' do
      error = format_error <<-ERROR
      error: Could not read 6682dfe81f66656436e60883dd795e7ec6735153
      error: Could not read 0cd3703c23fa44c0043d97fbc26356a23939f31b
      fatal: did not receive expected object 3c64c9dd49c79bd09aa13d4b05ac18263ca29ccd
      fatal: index-pack failed
      ERROR

      expect(subject.retriable_error?(error)).to be_truthy
    end
  end
end
