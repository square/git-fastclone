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
      File.open(lock_file_name, File::RDWR | File::CREAT, 0644)
    end
    module_function :reference_repo_lock_file
  end
end
