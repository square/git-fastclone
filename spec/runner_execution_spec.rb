# frozen_string_literal: true

# Copyright 2023 Square Inc.

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

# Integration tests use real demo_tool.sh to inspect the E2E behavior
describe RunnerExecution do
  subject { described_class }
  let(:external_tool) { "#{__dir__}/../script/spec_demo_tool.sh" }
  let(:logger) { double('logger') }

  before do
    allow($stdout).to receive(:puts)
    allow(logger).to receive(:info)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:warn)
    allow(RunnerExecution).to receive(:logger).and_return(logger)
  end

  describe '.fail_on_error' do
    it 'should log failure info on command error' do
      expect(logger).to receive(:info).with("My error output\n")

      expect do
        described_class.fail_on_error(external_tool, '1', 'My error output', quiet: true,
                                                                             print_on_failure: true)
      end.to raise_error(RunnerExecution::RunnerExecutionRuntimeError)
    end

    it 'should not log failure output on command success' do
      expect($stdout).not_to receive(:info)

      described_class.fail_on_error(external_tool, '0', 'My success output', quiet: true,
                                                                             print_on_failure: true)
    end

    it 'should not log failure output when not in the quiet mode' do
      expect($stdout).not_to receive(:info)

      described_class.fail_on_error(external_tool, '0', 'My success output', quiet: false,
                                                                             print_on_failure: true)
    end
  end
end
