# Real-Time Views

This guide explains how to implement real-time interfaces with `Live::View`.

## What is `Live::View`?

`Live::View` enables real-time, interactive web interfaces using WebSocket connections. It allows you to update the DOM in real-time without JavaScript, making it perfect for dynamic content that changes frequently.

**When to use `Live::View`:**
- Real-time dashboards and status displays.
- Interactive forms with live validation.
- Live updating content (clocks, counters, progress bars).
- Simple games and interactive applications.

**When NOT to use `Live::View`:**
- Static content that doesn't change.
- Complex client-side interactions requiring heavy JavaScript.

## Setup

### Import Maps Configuration

Use `bin/importmap` to install the required JavaScript packages:

```bash
> bin/importmap pin @socketry/live
Pinning "@socketry/live" to vendor/javascript/@socketry/live.js via download from https://ga.jspm.io/npm:@socketry/live@0.14.0/Live.js
Pinning "morphdom" to vendor/javascript/morphdom.js via download from https://ga.jspm.io/npm:morphdom@2.7.7/dist/morphdom-esm.js
```

### JavaScript Setup

Create `app/javascript/live.js` to initialize `Live::View`:

```javascript
import {Live} from "@socketry/live"
window.live = Live.start()
```

Pin your local `live.js` file in `config/importmap.rb`:

```ruby
pin "live"
```

**Key Points:**
- Import maps handle the `@socketry/live` package automatically.
- The `live.js` file starts the `Live::View` client connection.
- `pin "live"` makes your local `live.js` file importable in view templates.
- `window.live` makes the Live connection globally available.

## Basic Implementation: Live Clock

### Live::View Class

Create a `Live::View` class that handles the real-time logic:

```ruby
require 'live'

class ClockTag < Live::View
	def initialize(...)
		super
	end
	
	def bind(page)
		@task ||= start_clock
	end
	
	def close
		if task = @task
			@task = nil
			task.stop
		end
	end
	
	def start_clock
		Async do
			while true
				sleep 1
				self.update!
			end
		end
	end
	
	def forward_event(name)
		"event.preventDefault(); live.forwardEvent(#{JSON.dump(@id)}, event, {name: #{name.inspect}})"
	end

	def render(builder)
		builder.tag(:div, class: "clock-container") do
			builder.tag(:h2) {builder.text("Live Clock")}
			builder.tag(:div, id: "clock", class: "clock-display") do
				builder.text(Time.now.strftime("%H:%M:%S"))
			end
		end
	end
end
```

**Key Points:**
- Inherit from `Live::View` to get real-time capabilities.
- Use `Async` blocks for background tasks.
- Use `self.update!` to queue a full re-render.
- Define `forward_event` method to handle user interactions.
- The `render` method defines the initial HTML structure.

### Controller

Create a controller to handle the Live::View connection:

```ruby
require 'async/websocket/adapters/rails'

class ClockController < ApplicationController
	RESOLVER = Live::Resolver.allow(ClockTag)

	def index
		@tag = ClockTag.new('clock')
	end
	
	skip_before_action :verify_authenticity_token, only: :live
	
	def live
		self.response = Async::WebSocket::Adapters::Rails.open(request) do |connection|
			Live::Page.new(RESOLVER).run(connection)
		end
	end
end
```

**Key Points:**
- Use `Live::Resolver.allow` to whitelist your `Live::View` sub-classes.
- Skip CSRF verification for the WebSocket endpoint.
- Use `Async::WebSocket::Adapters::Rails.open` for WebSocket handling.
- `Live::Page.new(RESOLVER).run(connection)` handles the `Live::View` protocol.

### View Template

Create a view template that renders the Live::View:

```html
<h1>⏰ Live Clock Example</h1>
<p>This clock updates every second using Live::View.</p>

<%= javascript_import_module_tag "live" %>

<div class="clock-wrapper">
	<%= raw @tag.to_html %>
</div>

<style>
.clock-container {
	text-align: center;
	padding: 2rem;
	border: 2px solid #ddd;
	border-radius: 8px;
	margin: 2rem 0;
}

.clock-display {
	font-size: 3rem;
	font-family: 'Monaco', 'Consolas', monospace;
	color: #333;
	background: #f0f0f0;
	padding: 1rem;
	border-radius: 4px;
	margin-top: 1rem;
}
</style>
```

**Key Points:**
- Use `<%= javascript_import_module_tag "live" %>` to load Live::View on specific pages.
- Use `raw @tag.to_html` to render the Live::View component.
- The Live::View will automatically connect via WebSocket.
- This loads Live::View only on pages that need it, not globally.

### Routing Configuration

Add routes to your `config/routes.rb`:

```ruby
Rails.application.routes.draw do
	# Live Clock Example:
	get "clock/index"
	connect "clock/live"
end
```

**Key Points:**
- Use the Rails 8 `connect` helper for WebSocket routes.
- The `live` action handles the WebSocket connection.

## Interactive Example: Counter with Buttons

### Live::View Class with User Interaction

```ruby
class CounterTag < Live::View
	def initialize(count: 0)
		super

		# @data is persisted on the tag in `data-` attributes.
		@data["count"] = @data.fetch("count", count).to_i
	end
	
	def handle(event)
		case event[:type]
		when "click"
			case event.dig(:detail, :name)
			when "increment"
				@data["count"] += 1
			when "decrement"
				@data["count"] -= 1
			end
			
			update_counter
		end
	end
	
	def update_counter
		self.replace("#counter") do |builder|
			builder.tag(:div, id: "counter", class: "counter-display") do
				builder.text(@data["count"].to_s)
			end
		end
	end
	
	def forward_event(name)
		"event.preventDefault(); live.forwardEvent(#{JSON.dump(@id)}, event, {name: #{name.inspect}})"
	end

	def render(builder)
		builder.tag(:div, class: "counter-container") do
			builder.tag(:h2) { builder.text("Live Counter") }
			
			builder.tag(:div, id: "counter", class: "counter-display") do
				builder.text(@count.to_s)
			end
			
			builder.tag(:div, class: "counter-buttons") do
				builder.tag(:button, onclick: forward_event("decrement")) do
					builder.text("-")
				end
				builder.tag(:button, onclick: forward_event("increment")) do
					builder.text("+")
				end
			end
		end
	end
end
```

**Key Points:**
- Define `forward_event` (or `forward_click`, etc) methods to generate JavaScript for event handling.
- `live.forwardEvent(...)` on the client side invokes `handle(event)` on the server side.
- Update the DOM in response to user actions.
- Maintain persistent state in `@data`.
