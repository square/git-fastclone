require 'docopt'

require 'git-fastclone/info'

module GitFastClone
  # This module takes care of CLI argument parsing
  class Options
    def initialize
      @options = docopt.freeze
      puts GitFastClone::Info::Version if @options['--version']
    end

    def branch
      @options['--branch']
    end

    def color?
      @options['--color']
    end

    def lock_timeout
      @options['--lock-timeout'].to_i
    end

    def path
      @options['<path>']
    end

    def url
      @options['<git-url>']
    end

    def verbose?
      @options['--verbose']
    end

    private

    def docopt
      doc = <<DOCOPT
Usage:
  git-fastclone [options] <git-url> [<path>]

Options:
  -h --help                        Show this screen.
  -b <branch>, --branch <branch>   Branch name.
  --lock-timeout <N>               Lock timeout (seconds).
  -c --color                       Colored output.
  -v --verbose                     Verbose mode.
  --version                        Show version.
DOCOPT
      begin
        Docopt.docopt(doc)
      rescue Docopt::Exit => e
        puts e.message
        exit
      end
    end
  end
end
