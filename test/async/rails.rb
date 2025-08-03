# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

describe Async::Rails do
	it "has a version number" do
		expect(Async::Rails::VERSION).to be =~ /^\d+\.\d+\.\d+$/
	end
end
