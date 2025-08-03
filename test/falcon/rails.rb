# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

describe Falcon::Rails do
	it "has a version number" do
		expect(Falcon::Rails::VERSION).to be =~ /^\d+\.\d+\.\d+$/
	end
end
