require 'rspec/core'
require 'rspec/mocks'

$VERBOSE = nil

module TestManager
  def self.included(clazz)
    clazz.send(:extend, ClassMethods)
  end

  def mock_commands
    allow(Cocaine::CommandLine).to receive(:new, &add_to_actions)
    allow_any_instance_of(Array).to receive(:run).and_return('')
    allow(FileUtils).to receive(:mkdir_p)
  end

  module ClassMethods
    def track_shell_actions
      let(:actions) { [] }

      let(:add_to_actions) do
        ->(*cmd, **opts) { actions << { cmd: cmd, opts: opts } }
      end
    end
  end
end
