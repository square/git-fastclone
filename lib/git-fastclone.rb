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
require 'logger'
require 'terrapin'
require 'timeout'

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
        File.join(reference_dir, 'local' + reference_repo_name(url))
      else
        File.join(reference_dir, reference_repo_name(url))
      end
    end
    module_function :reference_repo_dir

    def reference_repo_submodule_file(url, reference_dir, using_local_repo)
      "#{reference_repo_dir(url, reference_dir, using_local_repo)}:submodules.txt"
    end
    module_function :reference_repo_submodule_file

    def reference_repo_lock_file(url, reference_dir, using_local_repo)
      lock_file_name = "#{reference_repo_dir(url, reference_dir, using_local_repo)}:lock"
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

    DEFAULT_REFERENCE_REPO_DIR = '/var/tmp/git-fastclone/reference'.freeze

    DEFAULT_GIT_ALLOW_PROTOCOL = 'file:git:http:https:ssh'.freeze

    attr_accessor :reference_dir, :prefetch_submodules, :reference_updated, :reference_mutex,
                  :options, :logger, :abs_clone_path, :using_local_repo, :verbose, :color,
                  :flock_timeout_secs

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

      self.logger = nil # Only set in verbose mode

      self.abs_clone_path = Dir.pwd

      self.using_local_repo = false

      self.verbose = false

      self.color = false

      self.flock_timeout_secs = 0
    end

    def run
      url, path, options = parse_inputs

      require_relative './git-fastclone/version'
      msg = "git-fastclone #{GitFastCloneVersion::VERSION}"
      if color
        puts msg.yellow
      else
        puts msg
      end

      puts "Cloning #{path_from_git_url(url)} to #{File.join(abs_clone_path, path)}"
      Terrapin::CommandLine.environment['GIT_ALLOW_PROTOCOL'] =
        ENV['GIT_ALLOW_PROTOCOL'] || DEFAULT_GIT_ALLOW_PROTOCOL
      clone(url, options[:branch], path)
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
          self.verbose = true
          self.logger = Logger.new(STDOUT)
          logger.formatter = proc do |_severity, _datetime, _progname, msg|
            "#{msg}\n"
          end
          Terrapin::CommandLine.logger = logger
        end

        opts.on('-c', '--color', 'Display colored output') do
          self.color = true
        end

        opts.on('--lock-timeout N', 'Timeout in seconds to acquire a lock on any reference repo.
                Default is 0 which waits indefinitely.') do |timeout_secs|
          self.flock_timeout_secs = timeout_secs
        end
      end.parse!
    end

    def parse_inputs
      parse_options

      unless ARGV[0]
        STDERR.puts usage
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

      self.reference_dir = ENV['REFERENCE_REPO_DIR'] || DEFAULT_REFERENCE_REPO_DIR
      FileUtils.mkdir_p(reference_dir)

      [url, path, options]
    end

    # Checkout to SOURCE_DIR. Update all submodules recursively. Use reference
    # repos everywhere for speed.
    def clone(url, rev, src_dir)
      initial_time = Time.now

      with_git_mirror(url) do |mirror|
        Terrapin::CommandLine.new('git clone', '--quiet --reference :mirror :url :path')
                             .run(mirror: mirror.to_s,
                                  url: url.to_s,
                                  path: File.join(abs_clone_path, src_dir).to_s)
      end

      # Only checkout if we're changing branches to a non-default branch
      if rev
        Dir.chdir(File.join(abs_clone_path, src_dir)) do
          Terrapin::CommandLine.new('git checkout', '--quiet :rev').run(rev: rev.to_s)
        end
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

    def update_submodules(pwd, url)
      return unless File.exist?(File.join(abs_clone_path, pwd, '.gitmodules'))

      puts 'Updating submodules...' if verbose

      threads = []
      submodule_url_list = []

      Terrapin::CommandLine.new('cd', ':path; git submodule init 2>&1')
                           .run(path: File.join(abs_clone_path, pwd)).split("\n").each do |line|
        submodule_path, submodule_url = parse_update_info(line)
        submodule_url_list << submodule_url

        thread_update_submodule(submodule_url, submodule_path, threads, pwd)
      end

      update_submodule_reference(url, submodule_url_list)
      threads.each(&:join)
    end

    def thread_update_submodule(submodule_url, submodule_path, threads, pwd)
      threads << Thread.new do
        with_git_mirror(submodule_url) do |mirror|
          Terrapin::CommandLine.new('cd', ':dir; git submodule update --quiet --reference :mirror :path')
                               .run(dir: File.join(abs_clone_path, pwd).to_s,
                                    mirror: mirror.to_s,
                                    path: submodule_path.to_s)
        end

        update_submodules(File.join(pwd, submodule_path), submodule_url)
      end
    end

    def with_reference_repo_lock(url, &block)
      # Sane POSIX implementations remove exclusive flocks when a process is terminated or killed
      # We block here indefinitely. Waiting for other git-fastclone processes to release the lock.
      # With the default timeout of 0 we will wait forever, this can be overridden on the command line.
      lockfile = reference_repo_lock_file(url, reference_dir, using_local_repo)
      Timeout.timeout(flock_timeout_secs) { lockfile.flock(File::LOCK_EX) }
      with_reference_repo_thread_lock(url, &block)
    ensure
      # Not strictly necessary to do this unlock as an ensure. If ever exception is caught outside this
      # primitive, ensure protection may come in handy.
      lockfile.flock(File::LOCK_UN)
      lockfile.close
    end

    def with_reference_repo_thread_lock(url)
      # We also need thread level locking because pre-fetch means multiple threads can
      # attempt to update the same repository from a single git-fastclone process
      # file locks in posix are tracked per process, not per userland thread.
      # This gives us the equivalent of pthread_mutex around these accesses.
      reference_mutex[reference_repo_name(url)].synchronize do
        yield
      end
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
    def update_reference_repo(url, fail_hard)
      repo_name = reference_repo_name(url)
      mirror = reference_repo_dir(url, reference_dir, using_local_repo)

      with_reference_repo_lock(url) do
        # we've created this to track submodules' history
        submodule_file = reference_repo_submodule_file(url, reference_dir, using_local_repo)

        # if prefetch is on, then grab children immediately to frontload network requests
        prefetch(submodule_file) if File.exist?(submodule_file) && prefetch_submodules

        # Store the fact that our repo has been updated if necessary
        store_updated_repo(url, mirror, repo_name, fail_hard) unless reference_updated[repo_name]
      end
    end

    # Grab the children in the event of a prefetch
    def prefetch(submodule_file)
      File.readlines(submodule_file).each do |line|
        # We don't join these threads explicitly
        Thread.new { update_reference_repo(line.strip, false) }
      end
    end

    # Creates or updates the mirror repo then stores an indication
    # that this repo has been updated on this run of fastclone
    def store_updated_repo(url, mirror, repo_name, fail_hard)
      unless Dir.exist?(mirror)
        Terrapin::CommandLine.new('git clone', '--mirror :url :mirror')
                             .run(url: url.to_s, mirror: mirror.to_s)
      end

      Terrapin::CommandLine.new('cd', ':path; git remote update --prune').run(path: mirror)

      reference_updated[repo_name] = true
    rescue Terrapin::ExitStatusError => e
      # To avoid corruption of the cache, if we failed to update or check out we remove
      # the cache directory entirely. This may cause the current clone to fail, but if the
      # underlying error from git is transient it will not affect future clones.
      FileUtils.remove_entry_secure(mirror, force: true)
      raise e if fail_hard
    end

    # This command will create and bring the mirror up-to-date on-demand,
    # blocking any code passed in while the mirror is brought up-to-date
    #
    # In future we may need to synchronize with flock here if we run multiple
    # builds at once against the same reference repos. One build per slave at the
    # moment means we only need to synchronize our own threads in case a single
    # submodule url is included twice via multiple dependency paths
    def with_git_mirror(url)
      update_reference_repo(url, true)

      # Sometimes remote updates involve re-packing objects on a different thread
      # We grab the reference repo lock here just to make sure whatever thread
      # ended up doing the update is done with its housekeeping.
      # This makes sure we have control and unlock when the block returns:
      with_reference_repo_lock(url) do
        dir = reference_repo_dir(url, reference_dir, using_local_repo)
        retries_left = 1

        begin
          yield dir
        rescue Terrapin::ExitStatusError => e
          error_strings = [
            'missing blob object',
            'remote did not send all necessary objects',
            /packed object [a-z0-9]+ \(stored in .*?\) is corrupt/,
            /pack has \d+ unresolved deltas/
          ]
          if e.to_s =~ /^STDERR:\n.+^fatal: #{Regexp.union(error_strings)}/m
            # To avoid corruption of the cache, if we failed to update or check out we remove
            # the cache directory entirely. This may cause the current clone to fail, but if the
            # underlying error from git is transient it will not affect future clones.
            FileUtils.remove_entry_secure(dir, force: true)
            if retries_left > 0
              retries_left -= 1
              retry
            end
          end

          raise
        end
      end
    end

    def usage
      'Usage: git fastclone [options] <git-url> [path]'
    end
  end
end
