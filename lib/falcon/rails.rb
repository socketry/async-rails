# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require_relative "rails/version"

require "falcon"

# Load all the dependencies:
require "async/cable"
require "async/job/adapter/active_job"
require "async/websocket"
require "console/adapter/rails"
require "live"
