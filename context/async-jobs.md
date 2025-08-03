# Job Processing

This guide explains how to implement background job processing with Falcon and Rails using the async-job gem.

## What are Async Jobs?

Async jobs allow you to perform work in the background without blocking web requests. The async-job gem provides high-performance job processing that integrates seamlessly with Rails' ActiveJob.

**When to use async jobs:**
- Long-running tasks (data processing, file uploads).
- Email sending and external API calls.
- Scheduled tasks and periodic jobs.
- Heavy computations that would slow down web responses.

**When NOT to use async jobs:**
- Simple operations that complete quickly.
- Tasks that need immediate user feedback.

## Basic Implementation

### Server-Side: Job Class

Create a job class that inherits from `ApplicationJob`:

```ruby
class MyJob < ApplicationJob
	# Specify the queue adapter per-job rather than globally:
	# queue_adapter :async_job
	
	queue_as "default"
	
	def perform
		# ... work ...
	end
end
```

**Key Points:**
- Use `queue_as` to specify which queue this job should use.
- The `perform` method contains your background work.

### Configuration

Configure async-job queues in `config/initializers/async_job.rb`:

```ruby
require 'async/job'
require 'async/job/processor/aggregate'
require 'async/job/processor/redis'
require 'async/job/processor/inline'

Rails.application.configure do
	config.async_job.define_queue "default" do
		# Double-buffers incoming jobs to avoid submission latency:
		enqueue Async::Job::Processor::Aggregate
		dequeue Async::Job::Processor::Redis
	end
	
	config.async_job.define_queue "local" do
		dequeue Async::Job::Processor::Inline
	end
end
```

**Key Points:**
- `default` queue uses Redis for persistent job storage.
- `local` queue processes jobs inline, but in a background Async task - higher throughput but lower robustness.
- Different processors can be used for different queue behaviors.

Configure the default adapter in `config/application.rb`:

```ruby
# ... in the application configuration:
config.active_job.queue_adapter = :async_job
```

**Key Points:**
- This sets `Async::Job` as the default queue adapter. You can instead specify this per-job for incremental migration.
