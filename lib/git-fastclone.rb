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

require 'optparse'
require 'fileutils'
require 'timeout'
require_relative 'runner_execution'

# Contains helper module UrlHelper and execution class GitFastClone::Runner
module GitFastClone
  # Helper methods for fastclone url operations
  module UrlHelper
    def path_from_git_url(url)
      File.basename(url, '.git')
    end
    module_function :path_from_git_url

    def parse_update_info(line)
      [line.strip.match(/'([^']*)'$/)[1], line.strip.match(/\(([^)]*)\)/)[1]]
    end
    module_function :parse_update_info

    def reference_repo_name(url)
      url.gsub(%r{^.*://}, '').gsub(/^[^@]*@/, '').tr('/', '-').tr(':', '-').to_s
    end
    module_function :reference_repo_name

    def reference_repo_dir(url, reference_dir, using_local_repo)
      if using_local_repo
        File.join(reference_dir, "local#{reference_repo_name(url)}")
      else
        File.join(reference_dir, reference_repo_name(url))
      end
    end
    module_function :reference_repo_dir

    def reference_filename(filename)
      separator = if RbConfig::CONFIG['host_os'] =~ /mswin|msys|mingw|cygwin|bccwin|wince|emc/
                    '__'
                  else
                    ':'
                  end
      "#{separator}#{filename}"
    end
    module_function :reference_filename

    def reference_repo_submodule_file(url, reference_dir, using_local_repo)
      "#{reference_repo_dir(url, reference_dir, using_local_repo)}#{reference_filename('submodules.txt')}"
    end
    module_function :reference_repo_submodule_file

    def reference_repo_lock_file(url, reference_dir, using_local_repo)
      lock_file_name = "#{reference_repo_dir(url, reference_dir, using_local_repo)}#{reference_filename('lock')}"
      File.open(lock_file_name, File::RDWR | File::CREAT, 0o644)
    end
    module_function :reference_repo_lock_file
  end

  # Spawns one thread per submodule, and updates them in parallel. They will be
  # cached in the reference directory (see DEFAULT_REFERENCE_REPO_DIR), and their
  # index will be incrementally updated. This prevents a large amount of data
  # copying.
  class Runner
    require 'colorize'

    include GitFastClone::UrlHelper
    include RunnerExecution

    DEFAULT_REFERENCE_REPO_DIR = '/var/tmp/git-fastclone/reference'

    DEFAULT_GIT_ALLOW_PROTOCOL = 'file:git:http:https:ssh'

    attr_accessor :reference_dir, :prefetch_submodules, :reference_updated, :reference_mutex,
                  :options, :abs_clone_path, :using_local_repo, :verbose, :print_git_errors, :color,
                  :flock_timeout_secs, :sparse_paths

    def initialize
      # Prefetch reference repos for submodules we've seen before
      # Keep our own reference accounting of module dependencies.
      self.prefetch_submodules = true

      # Thread-level locking for reference repos
      # TODO: Add flock-based locking if we want to avoid conflicting with
      # ourselves.
      self.reference_mutex = Hash.new { |hash, key| hash[key] = Mutex.new }

      # Only update each reference repo once per run.
      # TODO: May want to update this so we don't duplicate work with other copies
      # of ourself. Perhaps a last-updated-time and a timeout per reference repo.
      self.reference_updated = Hash.new { |hash, key| hash[key] = false }

      self.options = {}

      self.abs_clone_path = Dir.pwd

      self.using_local_repo = false

      self.verbose = false

      self.print_git_errors = false

      self.color = false

      self.flock_timeout_secs = 0

      self.sparse_paths = nil
    end

    def run
      url, path, options = parse_inputs

      require_relative 'git-fastclone/version'
      msg = "git-fastclone #{GitFastCloneVersion::VERSION}"
      if color
        puts msg.yellow
      else
        puts msg
      end

      puts "Cloning #{path_from_git_url(url)} to #{File.join(abs_clone_path, path)}"
      ENV['GIT_ALLOW_PROTOCOL'] ||= DEFAULT_GIT_ALLOW_PROTOCOL
      clone(url, options[:branch], path, options[:config])
    end

    def parse_options
      # One option --branch=<branch>  We're not as brittle as clone. That branch
      # can be a sha or tag and we're still okay.
      OptionParser.new do |opts|
        opts.banner = usage
        options[:branch] = nil

        opts.on('-b', '--branch BRANCH', 'Checkout this branch rather than the default') do |branch|
          options[:branch] = branch
        end

        opts.on('-v', '--verbose', 'Verbose mode') do
          puts '--print_git_errors is redundant when using --verbose' if print_git_errors
          self.verbose = true
        end

        opts.on('--print_git_errors', 'Print git output if a command fails') do
          puts '--print_git_errors is redundant when using --verbose' if verbose
          self.print_git_errors = true
        end

        opts.on('-c', '--color', 'Display colored output') do
          self.color = true
        end

        opts.on('--config CONFIG', 'Git config applied to the cloned repo') do |config|
          options[:config] = config
        end

        opts.on('--lock-timeout N', 'Timeout in seconds to acquire a lock on any reference repo.',
                'Default is 0 which waits indefinitely.') do |timeout_secs|
          self.flock_timeout_secs = timeout_secs.to_i
        end

        opts.on('--pre-clone-hook script_file',
                'An optional file that should be invoked before cloning mirror repo',
                'No-op when a file is missing') do |script_file|
          options[:pre_clone_hook] = script_file
        end

        opts.on('--sparse-paths PATHS',
                'Comma-separated list of paths for sparse checkout.',
                'Enables sparse checkout mode using git sparse-checkout.') do |paths|
          self.sparse_paths = paths.split(',').map(&:strip)
        end
      end.parse!
    end

    def parse_inputs
      parse_options

      unless ARGV[0]
        warn usage
        exit(129)
      end

      if Dir.exist?(ARGV[0])
        url = File.expand_path ARGV[0]
        self.using_local_repo = true
      else
        url = ARGV[0]
      end

      path = ARGV[1] || path_from_git_url(url)

      if Dir.exist?(path)
        msg = "Clone destination #{File.join(abs_clone_path, path)} already exists!"
        raise msg.red if color

        raise msg
      end

      # Validate that --branch is specified when using --sparse-paths
      if sparse_paths && !options[:branch]
        msg = "Error: --branch is required when using --sparse-paths\n" \
              "Sparse checkouts need an explicit branch/revision to checkout.\n" \
              'Usage: git-fastclone --sparse-paths <paths> --branch <branch> <url>'
        raise msg.red if color

        raise msg
      end

      self.reference_dir = ENV['REFERENCE_REPO_DIR'] || DEFAULT_REFERENCE_REPO_DIR
      FileUtils.mkdir_p(reference_dir)

      [url, path, options]
    end

    def clear_clone_dest_if_needed(attempt_number, clone_dest)
      return unless attempt_number.positive?

      dest_with_dotfiles = Dir.glob("#{clone_dest}/*", File::FNM_DOTMATCH)
      dest_files = dest_with_dotfiles.reject { |f| %w[. ..].include?(File.basename(f)) }
      return if dest_files.empty?

      clear_clone_dest(dest_files)
    end

    def clear_clone_dest(dest_files)
      puts 'Non-empty clone directory found, clearing its content now.'
      FileUtils.rm_rf(dest_files)
    end

    # Checkout to SOURCE_DIR. Update all submodules recursively. Use reference
    # repos everywhere for speed.
    def clone(url, rev, src_dir, config)
      clone_dest = File.join(abs_clone_path, src_dir).to_s
      initial_time = Time.now

      if Dir.exist?(clone_dest) && !Dir.empty?(clone_dest)
        raise "Can't clone into an existing non-empty path: #{clone_dest}"
      end

      with_git_mirror(url) do |mirror, attempt_number|
        clear_clone_dest_if_needed(attempt_number, clone_dest)

        clone_commands = ['git', 'clone', verbose ? '--verbose' : '--quiet']
        # For sparse checkouts, clone directly from the local mirror and skip the actual checkout process
        # For normal clones, use --reference and clone from the remote URL
        if sparse_paths
          clone_commands.push('--no-checkout')
          clone_commands << mirror.to_s << clone_dest
        else
          clone_commands << '--reference' << mirror.to_s << url.to_s << clone_dest
        end
        clone_commands << '--config' << config.to_s unless config.nil?
        fail_on_error(*clone_commands, quiet: !verbose, print_on_failure: print_git_errors)

        # Configure sparse checkout if enabled
        perform_sparse_checkout(clone_dest, rev) if sparse_paths
      end

      # Only checkout if we're changing branches to a non-default branch (for non-sparse clones)
      if !sparse_paths && rev
        fail_on_error('git', 'checkout', '--quiet', rev.to_s, quiet: !verbose,
                                                              print_on_failure: print_git_errors,
                                                              chdir: File.join(abs_clone_path, src_dir))
      end

      update_submodules(src_dir, url)

      final_time = Time.now

      msg = "Checkout of #{src_dir} took #{final_time - initial_time}s"
      if color
        puts msg.green
      else
        puts msg
      end
    end

    def perform_sparse_checkout(clone_dest, rev)
      puts 'Configuring sparse checkout...' if verbose

      # Initialize sparse checkout with cone mode
      fail_on_error('git', 'sparse-checkout', 'init', '--cone',
                    quiet: !verbose, print_on_failure: print_git_errors, chdir: clone_dest)

      # Set the sparse paths
      fail_on_error('git', 'sparse-checkout', 'set', *sparse_paths,
                    quiet: !verbose, print_on_failure: print_git_errors, chdir: clone_dest)

      # Checkout the specified branch/revision
      fail_on_error('git', 'checkout', '--quiet', rev.to_s,
                    quiet: !verbose, print_on_failure: print_git_errors, chdir: clone_dest)
    end

    def update_submodules(pwd, url)
      return unless File.exist?(File.join(abs_clone_path, pwd, '.gitmodules'))

      puts 'Updating submodules...' if verbose

      threads = []
      submodule_url_list = []
      output = fail_on_error('git', 'submodule', 'init', quiet: !verbose,
                                                         print_on_failure: print_git_errors,
                                                         chdir: File.join(abs_clone_path, pwd))

      output.split("\n").each do |line|
        submodule_path, submodule_url = parse_update_info(line)
        submodule_url_list << submodule_url

        thread_update_submodule(submodule_url, submodule_path, threads, pwd)
      end

      update_submodule_reference(url, submodule_url_list)
      threads.each(&:join)
    end

    def thread_update_submodule(submodule_url, submodule_path, threads, pwd)
      threads << Thread.new do
        with_git_mirror(submodule_url) do |mirror, _|
          cmd = ['git', 'submodule',
                 verbose ? nil : '--quiet', 'update', '--reference', mirror.to_s, submodule_path.to_s].compact
          fail_on_error(*cmd, quiet: !verbose, print_on_failure: print_git_errors,
                              chdir: File.join(abs_clone_path, pwd))
        end

        update_submodules(File.join(pwd, submodule_path), submodule_url)
      end
    end

    def with_reference_repo_lock(url, &)
      # Sane POSIX implementations remove exclusive flocks when a process is terminated or killed
      # We block here indefinitely. Waiting for other git-fastclone processes to release the lock.
      # With the default timeout of 0 we will wait forever, this can be overridden on the command line.
      lockfile = reference_repo_lock_file(url, reference_dir, using_local_repo)
      Timeout.timeout(flock_timeout_secs) { lockfile.flock(File::LOCK_EX) }
      with_reference_repo_thread_lock(url, &)
    ensure
      # Not strictly necessary to do this unlock as an ensure. If ever exception is caught outside this
      # primitive, ensure protection may come in handy.
      lockfile.flock(File::LOCK_UN)
      lockfile.close
    end

    def with_reference_repo_thread_lock(url, &)
      # We also need thread level locking because pre-fetch means multiple threads can
      # attempt to update the same repository from a single git-fastclone process
      # file locks in posix are tracked per process, not per userland thread.
      # This gives us the equivalent of pthread_mutex around these accesses.
      reference_mutex[reference_repo_name(url)].synchronize(&)
    end

    def update_submodule_reference(url, submodule_url_list)
      return if submodule_url_list.empty? || prefetch_submodules.nil?

      with_reference_repo_lock(url) do
        # Write the dependency file using submodule list
        File.open(reference_repo_submodule_file(url, reference_dir, using_local_repo), 'w') do |f|
          submodule_url_list.each { |submodule_url| f.write("#{submodule_url}\n") }
        end
      end
    end

    # Fail_hard indicates whether the update is considered a failure of the
    # overall checkout or not. When we pre-fetch based off of cached information,
    # fail_hard is false. When we fetch based off info in a repository directly,
    # fail_hard is true.
    def update_reference_repo(url, fail_hard, attempt_number)
      repo_name = reference_repo_name(url)
      mirror = reference_repo_dir(url, reference_dir, using_local_repo)

      with_reference_repo_lock(url) do
        # we've created this to track submodules' history
        submodule_file = reference_repo_submodule_file(url, reference_dir, using_local_repo)

        # if prefetch is on, then grab children immediately to frontload network requests
        prefetch(submodule_file, attempt_number) if File.exist?(submodule_file) && prefetch_submodules

        # Store the fact that our repo has been updated if necessary
        store_updated_repo(url, mirror, repo_name, fail_hard, attempt_number) unless reference_updated[repo_name]
      end
    end

    # Grab the children in the event of a prefetch
    def prefetch(submodule_file, attempt_number)
      File.readlines(submodule_file).each do |line|
        # We don't join these threads explicitly
        Thread.new { update_reference_repo(line.strip, false, attempt_number) }
      end
    end

    # Creates or updates the mirror repo then stores an indication
    # that this repo has been updated on this run of fastclone
    def store_updated_repo(url, mirror, repo_name, fail_hard, attempt_number)
      trigger_pre_clone_hook_if_needed(url, mirror, attempt_number)
      # If pre_clone_hook correctly creates a mirror directory, we don't want to clone, but just update it
      unless Dir.exist?(mirror)
        fail_on_error('git', 'clone', verbose ? '--verbose' : '--quiet', '--mirror', url.to_s, mirror.to_s,
                      quiet: !verbose, print_on_failure: print_git_errors)
      end

      cmd = ['git', 'remote', verbose ? '--verbose' : nil, 'update', '--prune'].compact
      fail_on_error(*cmd, quiet: !verbose, print_on_failure: print_git_errors, chdir: mirror)

      reference_updated[repo_name] = true
    rescue RunnerExecutionRuntimeError => e
      # To avoid corruption of the cache, if we failed to update or check out we remove
      # the cache directory entirely. This may cause the current clone to fail, but if the
      # underlying error from git is transient it will not affect future clones.
      #
      # The only exception to this is authentication failures, because they are transient,
      # usually due to either a remote server outage or a local credentials config problem.
      clear_cache(mirror, url) unless auth_error?(e.output)
      raise e if fail_hard
    end

    def auth_error?(error)
      error.to_s =~ /.*^fatal: Authentication failed/m
    end

    def retriable_error?(error)
      error_strings = [
        /^fatal: missing blob object/,
        /^fatal: remote did not send all necessary objects/,
        /^fatal: packed object [a-z0-9]+ \(stored in .*?\) is corrupt/,
        /^fatal: pack has \d+ unresolved delta/,
        /^error: unable to read sha1 file of /,
        /^fatal: did not receive expected object/,
        /^fatal: unable to read tree [a-z0-9]+\n^warning: Clone succeeded, but checkout failed/,
        /^fatal: Authentication failed/
      ]
      error.to_s =~ /.*#{Regexp.union(error_strings)}/m
    end

    def print_formatted_error(error)
      indented_error = error.to_s.split("\n").map { |s| ">  #{s}\n" }.join
      puts "[INFO] Encountered a retriable error:\n#{indented_error}\n"
    end

    # To avoid corruption of the cache, if we failed to update or check out we remove
    # the cache directory entirely. This may cause the current clone to fail, but if the
    # underlying error from git is transient it will not affect future clones.
    def clear_cache(dir, url)
      puts "[WARN] Removing the fastclone cache at #{dir}"
      FileUtils.remove_entry_secure(dir, force: true)
      reference_updated.delete(reference_repo_name(url))
    end

    # This command will create and bring the mirror up-to-date on-demand,
    # blocking any code passed in while the mirror is brought up-to-date
    #
    # In future we may need to synchronize with flock here if we run multiple
    # builds at once against the same reference repos. One build per slave at the
    # moment means we only need to synchronize our own threads in case a single
    # submodule url is included twice via multiple dependency paths
    def with_git_mirror(url)
      retries_allowed ||= 1
      attempt_number ||= 0

      update_reference_repo(url, true, attempt_number)
      dir = reference_repo_dir(url, reference_dir, using_local_repo)

      # Sometimes remote updates involve re-packing objects on a different thread
      # We grab the reference repo lock here just to make sure whatever thread
      # ended up doing the update is done with its housekeeping.
      # This makes sure we have control and unlock when the block returns:
      with_reference_repo_lock(url) do
        yield dir, attempt_number
      end
    rescue RunnerExecutionRuntimeError => e
      if retriable_error?(e.output)
        print_formatted_error(e.output)
        clear_cache(dir, url)

        if attempt_number < retries_allowed
          attempt_number += 1
          retry
        end
      end

      raise e
    end

    def usage
      'Usage: git fastclone [options] <git-url> [path]'
    end

    private def trigger_pre_clone_hook_if_needed(url, mirror, attempt_number)
      return if Dir.exist?(mirror) || !options.include?(:pre_clone_hook)

      hook_command = options[:pre_clone_hook]
      unless File.exist?(File.expand_path(hook_command))
        puts 'pre_clone_hook script is missing' if verbose
        return
      end

      popen2e_wrapper(hook_command, url.to_s, mirror.to_s, attempt_number.to_s, quiet: !verbose)
    end
  end
end
