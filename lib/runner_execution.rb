# frozen_string_literal: true
# rubocop:disable all

require 'open3'
require 'logger'

# Execution primitives that force explicit error handling and never call the shell.
# Cargo-culted from internal BuildExecution code on top of public version: https://github.com/square/build_execution
module RunnerExecution
  class RunnerExecutionRuntimeError < RuntimeError
    attr_reader :status, :exitstatus, :command, :output

    def initialize(status, command, output = nil)
      @status           = status
      @exitstatus       = status.exitstatus
      @command          = command
      @output           = output

      super "#{status.inspect}\n#{command.inspect}"
    end
  end

  # Runs a command that fails on error.
  # Uses popen2e wrapper. Handles bad statuses with potential for retries.
  def fail_on_error(*cmd, stdin_data: nil, binmode: false, quiet: false, print_on_failure: false, **opts)
    print_command('Running Shell Safe Command:', [cmd]) unless quiet
    shell_safe_cmd = shell_safe(cmd)
    retry_times = opts[:retry] || 0
    opts.delete(:retry)

    while retry_times >= 0
      output, status = popen2e_wrapper(*shell_safe_cmd, stdin_data: stdin_data, binmode: binmode,
                                       quiet: quiet, **opts)

      break unless status.exitstatus != 0

      logger.debug("Command failed with exit status #{status.exitstatus}, retrying #{retry_times} more time(s).") if retry_times > 0
      retry_times -= 1
    end

    # Get out with the status, good or bad.
    # When quiet, we don't need to print the output, as it is already streamed from popen2e_wrapper
    exit_prints_on_failure = quiet && print_on_failure
    exit_on_status(output, [shell_safe_cmd], [status], quiet: quiet, print_on_failure: exit_prints_on_failure)
  end
  module_function :fail_on_error

  # Wrapper around open3.popen2e
  #
  # We emulate open3.capture2e with the following changes in behavior:
  # 1) The command is printed to stdout before execution.
  # 2) Attempts to use the shell implicitly are blocked.
  # 3) Nonzero return codes result in the process exiting.
  # 4) Combined stdout/stderr goes to callers stdout
  #    (continuously streamed) and is returned as a string
  #
  # If you're looking for more process/stream control read the spawn
  # documentation, and pass options directly here
  def popen2e_wrapper(*shell_safe_cmd, stdin_data: nil, binmode: false,
                       quiet: false, **opts)

    env = opts.delete(:env) { {} }
    raise ArgumentError, "The :env option must be a hash, not #{env.inspect}" if !env.is_a?(Hash)

    # Most of this is copied from Open3.capture2e in ruby/lib/open3.rb
    _output, _status = Open3.popen2e(env, *shell_safe_cmd, opts) do |i, oe, t|
      if binmode
        i.binmode
        oe.binmode
      end

      outerr_reader = Thread.new do
        if quiet
          oe.read
        else
          # Instead of oe.read, we redirect. Output from command goes to stdout
          # and also is returned for processing if necessary.
          tee(oe, STDOUT)
        end
      end

      if stdin_data
        begin
          i.write stdin_data
        rescue Errno::EPIPE
        end
      end

      i.close
      [outerr_reader.value, t.value]
    end
  end
  module_function :popen2e_wrapper

  # Look at a cmd list intended for spawn.
  # determine if spawn will call the shell implicitly, fail in that case.
  def shell_safe(cmd)
    # Take the first string and change it to a list of [executable,argv0]
    # This syntax for calling popen2e (and eventually spawn) avoids
    # the shell in all cases
    shell_safe_cmd = Array.new(cmd)
    if shell_safe_cmd[0].class == String
      shell_safe_cmd[0] = [shell_safe_cmd[0], shell_safe_cmd[0]]
    end
    shell_safe_cmd
  end
  module_function :shell_safe

  def debug_print_cmd_list(cmd_list)
    # Take a list of command argument lists like you'd sent to open3.pipeline or
    # fail_on_error_pipe and print out a string that would do the same thing when
    # entered at the shell.
    #
    # This is a converter from our internal representation of commands to a subset
    # of bash that can be executed directly.
    #
    # Note this has problems if you specify env or opts
    # TODO: make this remove those command parts
    "\"" +
      cmd_list.map do |cmd|
        cmd.map do |arg|
          arg.gsub("\"", "\\\"") # Escape all double quotes in command arguments
        end.join("\" \"") # Fully quote all command parts, beginning and end.
      end.join("\" | \"") + "\"" # Pipe commands to one another.
  end
  module_function :debug_print_cmd_list

  # Prints a formatted string with command
  def print_command(message, cmd)
    logger.debug("#{message} #{debug_print_cmd_list(cmd)}\n")
  end
  module_function :print_command

  # Takes in an input stream and an output stream
  # Redirects data from one to the other until the input stream closes.
  # Returns all data that passed through on return.
  def tee(in_stream, out_stream)
    alldata = ''
    loop do
      begin
        data = in_stream.read_nonblock(4096)
        alldata += data
        out_stream.write(data)
        out_stream.flush
      rescue IO::WaitReadable
        IO.select([in_stream])
        retry
      rescue IOError
        break
      end
    end
    alldata
  end
  module_function :tee

  # If any of the statuses are bad, exits with the
  # return code of the first one.
  #
  # Otherwise returns first argument (output)
  def exit_on_status(output, cmd_list, status_list, quiet: false, print_on_failure: false)
    status_list.each_index do |index|
      status = status_list[index]
      cmd = cmd_list[index]
      # When quiet, we don't need to print the outputs, as they are already printed
      check_status(cmd, status, output: output, quiet: quiet, print_on_failure: print_on_failure)
    end

    output
  end
  module_function :exit_on_status

  def check_status(cmd, status, output: nil, quiet: false, print_on_failure: false)
    return if status.exited? && status.exitstatus == 0

    puts output if print_on_failure
    # If we exited nonzero or abnormally, print debugging info and explode.
    if status.exited?
      logger.debug("Process Exited normally. Exit status:#{status.exitstatus}") unless quiet
    else
      # This should only get executed if we're stopped or signaled
      logger.debug("Process exited abnormally:\nProcessStatus: #{status.inspect}\n" \
        "Raw POSIX Status: #{status.to_i}\n") unless quiet
    end

    raise RunnerExecutionRuntimeError.new(status, cmd, output)
  end
  module_function :check_status

  DEFAULT_LOGGER = Logger.new(STDOUT)
  private_constant :DEFAULT_LOGGER

  def logger
    DEFAULT_LOGGER
  end
  module_function :logger
end
# rubocop:enable all
