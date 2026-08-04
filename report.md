# Toward Falcon as the Default Rails Server

This report assesses the work required to make Falcon a credible future default
application server for Ruby on Rails. It covers Rails, Rack, Falcon, Action Cable,
Active Record, streaming, Solid Queue, development reloading, and deployment.

The research snapshot is **2026-08-04**. At that point the latest stable releases
were Rails 8.1.3.1, Falcon 0.56.0, Rack 3.2.6, Async Cable 0.3.1, and Solid Queue
1.6.0. Rails `main` was developing Rails 8.2.

## Executive position

Falcon has a plausible path to becoming the Rails default, but it should not be
made the default yet.

The architectural blockers are falling away:

- Rails has supported fiber-scoped execution state for several releases and its
  [configuration guide][rails-isolation-guide] tells fiber-based servers such as
  Falcon to select it.
- Active Record ownership is keyed through `IsolatedExecutionState`, and modern
  connection APIs allow connections to be borrowed for an individual operation
  instead of pinned for an entire request or job.
- Rails merged [Action Cable server adapterization][rails-ac-adapter-pr] in May
  2026. Async Cable now targets the resulting Rails 8.2 API instead of requiring
  the temporary `actioncable-next` fork.
- Solid Queue 1.6.0 added [bounded fiber worker execution][solid-queue-fiber-pr]
  in July 2026, while retaining process isolation and thread workers as defaults.
- Rack 3 defines callable streaming bodies, protocol upgrades, completion
  callbacks, and HTTP/2-aware `rack.protocol` semantics.

The remaining work is less glamorous but decisive for a default: eliminate known
correctness failures, make development reloading reliable, make the Rails command
and generated deployment topology unsurprising, test the stock Rails stack rather
than only the optimized Async stack, and establish sustained production evidence.

The recommended progression is:

1. Make Falcon a first-class, continuously tested Rails server option.
2. Offer and document `rails new --server=falcon` without changing the default.
3. Ship a release-candidate period with large reference applications and public
   compatibility results.
4. Change the generated default only after the acceptance gates in this report
   have held across at least one stable Rails release cycle.

The relevant measure is not whether Falcon can serve a Rails request—it can—but
whether a newly generated, otherwise ordinary Rails application behaves correctly
without its author understanding fiber schedulers.

## What “the default” means

Rails currently expresses a server preference in several different places. A
successful proposal needs to address all of them deliberately.

| Surface | Current state | Required Falcon outcome |
| --- | --- | --- |
| Generated bundle | The app generator hard-codes `puma >= 7.1` in [`web_server_gemfile_entry`][rails-app-generator]. | Generate Falcon, with Puma retained as an explicit escape hatch. |
| `bin/rails server` | Rails delegates to Rackup, but hard-codes Puma as its recommended missing server and lists Falcon as an available handler in [`ServerCommand`][rails-server-command]. | Falcon must work through the normal Rails command, flags, restart behavior, logging, and URL reporting. |
| Rackup discovery | Rackup tries Puma, then Falcon, then WEBrick when no handler is selected in [`Handler.default`][rackup-handler]. | Merely replacing the Gemfile entry can select Falcon, but discovery order and diagnostics should become intentional rather than incidental. |
| Development | Puma is the documented and tested development path. | Reloading, console output, debugger/system tests, HTTPS expectations, and interrupt/restart behavior must be reliable. |
| Generated production deployment | Rails generates Puma configuration and integrates it with Thruster, Docker, Kamal, and optionally the Solid Queue Puma plugin. | Generate a documented Falcon production service with equivalent environment-variable, health-check, signal, and proxy behavior. |
| Rails documentation | Rails calls Puma the default and its performance guide focuses on Puma. | Document both the compatibility baseline and the characteristics that differ under fiber concurrency. |

There is also an important distinction between Falcon's two launch paths:

- The [`Falcon::Rackup::Handler`][falcon-rackup-handler] used by `bin/rails
  server` currently creates one HTTP/1 server in the current process. It is a
  useful development bridge, but it is not Falcon's recommended production
  architecture and ignores many Rails/Rackup options.
- Falcon recommends `falcon host` and a `falcon.rb` service definition for
  production. That path provides worker processes, preloading, supervision, and
  richer endpoint configuration, but is not generated or managed by Rails.

Before a default change, these paths should either converge or have an explicit
division: `bin/rails server` for development and a generated Falcon service for
production. Passing options that Falcon silently ignores is not acceptable for a
default.

## Compatibility overview

| Area | Position on 2026-08-04 | Risk before default |
| --- | --- | --- |
| Ordinary Rack requests | Fundamentally compatible; Falcon adapts Protocol::HTTP to Rack 3. | Medium: request-body semantics and third-party middleware still expose differences. |
| Rails execution state | Rails supports `:fiber`; Falcon's Railtie selects it globally. | Medium: propagation into child fibers and activation/configuration semantics need a clear contract. |
| Active Record | Core ownership is fiber-aware and substantially improved. | Medium-high: pinned connections, driver behavior, pool sizing, roles/shards, and open reports need stress coverage. |
| Action Cable | Rails 8.2 has the required adapter seam; Async Cable is the reference native transport. | High until Rails 8.2 integration, pub/sub combinations, HTTP/1 and HTTP/2, and shutdown are comprehensively tested. |
| Response streaming/SSE | Falcon and Rack 3 have a strong native model. | Medium-high: Rails `ActionController::Live` remains thread-based and Rack middleware callable-body support is incomplete. |
| Request bodies/uploads | Network bodies are intentionally streamed and not universally rewindable. | High: common gems still assume Puma-like buffering; known open reports can lose or empty a body. |
| Development reload | Recent Rails fixes improve fiber ownership in the reloader. | High: a current open Falcon issue still reproduces a total stall on Rails `main`. |
| Solid Queue | Version 1.6.0 offers opt-in Async fiber workers. | Low for basic compatibility; medium for presenting fiber workers as a default or performance promise. |
| Active Storage | Normal operation needs a formal matrix; sharing a record across fibers exposes existing races. | Medium. |
| Operations | Falcon has supervision, metrics, HTTP/2, and preloading. | Medium-high: graceful restart/drain, configuration, logging defaults, and memory accounting remain adoption friction. |
| Ecosystem middleware | Rack 3 is the right common contract. | Medium-high: callable streaming bodies, locality assumptions, blocking native work, and rewind assumptions require auditing. |

## Detailed findings

### 1. Execution locality is supported, but it is a global application contract

Falcon's [Railtie][falcon-railtie] unconditionally sets:

```ruby
config.active_support.isolation_level = :fiber
```

Rails [documents this as the right setting for Falcon][rails-isolation-guide]. Rails' current
[`IsolatedExecutionState`][rails-isolated-state] keys state by either `Thread` or
`Fiber`, and Active Record uses that context for connection ownership. This is a
major improvement over the historical state captured in [Rails #42271][rails-ar-fiber].

However, the setting changes the locality of `CurrentAttributes`, query caches,
connection leases, execution wrappers, error context, and application/library
state across the entire process. It is not merely a Falcon tuning switch.

Two behaviors need to be made explicit:

- A request fiber is isolated correctly from another request fiber.
- A child fiber created inside a request does not automatically inherit arbitrary
  `IsolatedExecutionState`. Rails concluded in [#48279][rails-current-attributes]
  that callers must propagate required state explicitly. Async libraries and Rails
  APIs need one documented propagation mechanism for request ID, tenant, database
  role/shard, `CurrentAttributes`, tracing, and error-report context.

The server choice should also own activation clearly. Requiring the Falcon gem can
load its Railtie even if the process is later launched with another server. For a
default-quality integration, Rails should set or validate the execution model
explicitly, or Falcon should activate it only through a well-defined integration
point. Hidden global behavior based on Gemfile presence is hard to diagnose.

### 2. Active Record is no longer an architectural blocker, but it remains a gate

Active Record leases connections against
`ActiveSupport::IsolatedExecutionState.context`. Its current API distinguishes:

- `with_connection`, which ordinarily returns a borrowed connection after the
  block;
- `lease_connection`, which intentionally pins one for the request/job context;
- the legacy `connection` accessor, whose permanent checkout is being deprecated.

See [`connection_handling.rb`][rails-ar-connection-handling] and the pool
implementation in [`connection_pool.rb`][rails-ar-pool]. This model is compatible
with a fiber-per-request server and can use far fewer connections than the number
of in-flight fibers when application code does not pin a connection across waits.

The default-server standard must nevertheless cover:

- PostgreSQL, MySQL/mysql2, and SQLite under mixed concurrent I/O;
- transactions and savepoints across scheduler yields;
- roles, shards, `connected_to`, query cache, asynchronous queries, and schema
  loading;
- disconnect/reconnect, network failure, cancellation, and executor cleanup;
- pool exhaustion with thousands of request fibers;
- libraries calling `connection`, `lease_connection`, raw connection methods, or
  long-lived `with_connection` blocks;
- native extension behavior that releases the GVL but does not cooperate with a
  fiber scheduler in the expected way.

Open [Rails #57926][rails-mysql-fiber] reports mysql2 detecting a connection used
by another fiber even with fiber isolation configured. It is not yet established
as a Rails defect, but it illustrates why ownership needs load tests and diagnostic
messages rather than assumptions.

`ActionController::Live` complicates the model further. Its
[implementation][rails-live-source] still
runs the action in a cached thread pool, copies thread-local values, and calls
`IsolatedExecutionState.share_with`; Rails' own source calls this “very much a
hack” and says streaming should be rethought. Longstanding [Rails #21209][rails-live-ar]
and the more recent [#52906][rails-live-connected-to] show the interaction with
Active Record connection and role state.

### 3. Action Cable now has the right upstream seam

Stock Action Cable historically owns its transport and concurrency:

- WebSockets use `websocket-driver` and Rack full hijack.
- A dedicated NIO event loop reads and writes sockets.
- Connection/channel work and internal pub/sub work use separate thread pools.
- Production subscription adapters run listener threads.

This means running stock Action Cable behind Falcon does not make Cable fiber
native, limits WebSockets to the HTTP/1 hijack model, and gives Falcon little
control over connection lifetime. The history and design constraints are well
captured in [Rails #35657][rails-ac-async]. Rack itself now notes that full hijack
only works with HTTP/1, while `rack.protocol` and callable streaming bodies are the
forward-compatible HTTP/2+ mechanisms; see the [Rack specification][rack-spec].

The major positive development is merged [Rails PR #50979][rails-ac-adapter-pr].
It separates the application connection from the low-level server socket and
narrows the interfaces for transport, worker execution, pub/sub, and timers.

[Async Cable][async-cable] uses that abstraction to accept WebSockets through
`async-websocket`, drive the connection in Async tasks, and reuse Rails channel
and connection code. Its gemspec now depends on `actioncable >= 8.2.0.alpha`, so
Rails 8.2 is the first upstream-native baseline.

Work still required:

- Run the Action Cable conformance suite and browser/system tests against both
  stock and Async transports, Redis, PostgreSQL, Solid Cable, and the test/async
  adapters.
- Verify HTTP/1 Upgrade and HTTP/2 Extended CONNECT, proxies, TLS, origin checks,
  cookies/sessions, authentication middleware, reconnect, backpressure, slow
  consumers, and large broadcasts.
- Make the executor and pub/sub scheduling contract complete. Rails' built-in
  Redis and PostgreSQL listeners still start threads. Async Cable has just added
  an `Async::Cable::Executor` on `main`, but its lifecycle and configuration need
  to be wired and released coherently.
- Resolve compatibility reports such as [async-cable #3][async-cable-solid], in
  which the Solid Cable adapter and Async Cable disagree about server state.
- Fix and soak development reloading, including open [Falcon #325][falcon-cable-reload].
- Define graceful close and drain behavior for deploys, server restarts, and Rails
  reloads.

The desired endpoint is one Action Cable application API with selectable server
transports—not a permanent alternate fork of Action Cable.

### 4. Rails streaming should converge on Rack 3 callable bodies

Falcon's strongest use cases—SSE, generated downloads, LLM responses, and
real-time views—are also where Rails currently has overlapping abstractions:

- ordinary enumerable Rack bodies;
- Rack 3 callable streaming bodies (`body.call(stream)`);
- `ActionController::Live`, which introduces a producer thread and a queue;
- template streaming;
- WebSocket/hijack paths.

Rack 3 and Falcon can stream a callable body directly with natural backpressure
and cancellation. That should become the preferred Rails primitive. It avoids a
thread hop under Falcon and works across HTTP versions.

Compatibility is not complete across the middleware stack. Open [Rack #2470][rack-deflater]
shows `Rack::Deflater` calling `each` on a callable body, contrary to the Rack 3
contract. [Rails #23828][rails-template-streaming] documents longstanding and
surprising template-streaming behavior. Middleware for ETag, compression,
instrumentation, error pages, sessions, and proxies must be tested with both body
forms and client disconnects.

Rails should consider a scheduler-neutral controller streaming API implemented
on callable bodies. `ActionController::Live` can remain as a compatibility layer,
but its thread copying should not define the future model.

### 5. Request body rewind is an immediate correctness issue

A socket is not rewindable without buffering. Rack 3 therefore requires
`rack.input` to support `gets`, `each`, and `read`, but no longer requires
universal rewind. Falcon preserves streaming request bodies to avoid buffering
large uploads.

That correct design exposes a widespread ecosystem assumption: Puma commonly
presents a buffered/rewindable body, so middleware reads it, rewinds it, and lets
another layer read it again. Under Falcon that can become an empty body.

Relevant open reports include:

- [Falcon #302][falcon-request-body], where JSON input disappears before Rails or
  Grape parses it;
- [Falcon #310][falcon-body-rewind], covering Grape and HMAC verification after an
  earlier body read;
- [protocol-rack #33][protocol-rack-rewind], where `Input#rewind` falsely reported
  success in a released version and a reverse proxy forwarded an empty body.

Current protocol-rack `main` includes a selective
[`Rewindable` middleware][protocol-rack-rewindable] for conventional form media
types, but its `Input#rewind` still ignores a false result from the underlying
body—the defect reported by #33. The broader compatibility policy also remains
unsettled. The Rails/Falcon integration needs to choose and document one of these
approaches:

1. Buffer media types and request sizes that Rails and common middleware
   conventionally expect to be rewindable, with explicit memory/disk limits.
2. Keep all bodies streaming, make failed rewind unmistakable, and migrate the
   ecosystem to single-pass or explicitly buffered APIs.

A pragmatic default may combine both: compatibility buffering for bounded form
and JSON requests, streaming for large/unknown bodies, and an application API to
opt in or out. This area needs security testing as well as functional testing:
signature verification, CSRF parsing, multipart uploads, reverse proxies, and
content-length handling must never silently operate on different bytes.

### 6. Development reloading remains a release blocker

Rails recently merged [PR #57423][rails-reloader-fiber] to key the reloader share
lock by fiber execution context and [PR #57425][rails-reloader-hijack] to release
the share around a hijacked response. These changes fix real fiber-concurrency
defects and are strong evidence of upstream progress.

However, [Falcon #359][falcon-reload-stall] reports that editing a controller in a
new Rails app causes every later request to stall, including on Rails 8.2 alpha
and a Rails `main` revision containing those fixes. [Falcon #325][falcon-cable-reload]
separately reports unloaded constants during Async Cable reconnects.

No server should become the Rails development default until a repeatable suite
can run reload cycles while ordinary requests, Cable connections, streaming
responses, and background tasks are active. The suite should detect both deadlock
and stale-class use.

### 7. Solid Queue fiber workers are a useful convergence signal

Solid Queue 1.6.0's [fiber worker mode][solid-queue-fiber-pr] runs a bounded number
of jobs as Async tasks on one reactor thread. The implementation is intentionally
separate from supervisor mode: the recommended supervisor still forks processes,
and each worker can choose either `threads: N` or `fibers: N`.

Important safeguards in the [Solid Queue documentation][solid-queue-readme]
include:

- fiber workers refuse to boot unless Rails isolation is `:fiber`;
- `threads` and `fibers` are mutually exclusive per worker;
- fiber mode is recommended for cooperative, mostly I/O-bound jobs;
- pinned Active Record connections and transactions increase required pool size;
- process isolation and bounded concurrency remain available.

This is a good model for the web-server transition: explicit, bounded, and
reversible. It is also very new. It should first expand the shared compatibility
matrix for Rails' execution state and Active Record; it should not be treated as
proof that arbitrary Rails applications are fiber-safe.

Falcon's default-server proposal should work with stock Solid Queue thread
workers. Fiber workers are an optional optimization. Similarly, `falcon-rails`
currently bundles the separate Async Job adapter, but becoming Rails' default
should not require replacing Rails' default job backend.

### 8. Active Storage and application object safety need concurrency guidance

[Rails #52660][rails-active-storage-async] reproduces failures when the same
Active Record instance and attachment proxy are mutated concurrently from fibers.
The same race can be reproduced with threads; using independently loaded/cloned
records avoids it. This is not uniquely a Falcon defect, but Falcon makes such
concurrency easier and therefore makes undocumented object-sharing assumptions
more visible.

The compatibility program should test standard direct uploads, proxy downloads,
streaming downloads, checksums, variants, and local/cloud services. Rails guides
should state that model instances and mutable attachment state are not safe to
share between concurrent tasks.

### 9. Early Hints and protocol features need contract tests

Rails exposes Early Hints through `env["rack.early_hints"]`. Falcon can send
interim responses through its underlying Protocol::HTTP request and advertises
Early Hints support in its documentation. However, current protocol-rack `main`
does not appear to populate `rack.early_hints`, while Falcon's current interim
response guide tells applications to use the non-Rack
`env["protocol.http.request"]` extension.

This documentation/implementation mismatch should be resolved before claiming
Rails feature parity. The same applies to HTTP/2 WebSockets, trailers, streaming
uploads, completion callbacks, and cancellation: each feature needs an executable
cross-server contract test, not only documentation.

### 10. Operations and packaging are part of compatibility

The current Falcon issue tracker shows several default-quality gaps:

- [#188][falcon-graceful-restart]: graceful restart can break in-flight requests.
- [#344][falcon-supervisor-memory]: preloaded supervisor memory is over-counted on
  RSS-billed platforms and may require a different process topology.
- [#363][falcon-memory-footprint]: a production migration observed a higher memory
  baseline and possible growth; the investigation needs PSS/process-tree and heap
  data.
- [#127][falcon-configuration-docs]: users still struggle to discover production
  configuration such as workers and Unix sockets.
- [#90][falcon-request-logging]: request logging behavior and verbosity are not
  obvious.
- [falcon-rails #4][falcon-rails-logging]: the convenience gem replaces Rails'
  logger and stops writing `log/development.log` without an explicit opt-in.
- [falcon-rails #3][falcon-rails-full-rails]: the convenience gem pulls the entire
  Rails meta-gem and illustrates that it is broader than a server adapter.

For the Rails default, prefer a small core integration:

- `falcon` plus the minimum Rails/Rack bridge;
- no silent logger replacement;
- no mandatory alternate job, Cable, or live-view framework;
- production configuration generated by Rails;
- stable signal semantics, connection draining, health/readiness, metrics, and
  documented memory accounting.

`falcon-rails` can remain a curated opt-in bundle for the fully asynchronous stack,
but its current behavior is too broad to be the package that Rails silently adds
as “the web server.”

## Proposed roadmap

### Phase 0: Define and minimize the integration contract

- Agree with Rails core on the meanings of default development server, generated
  production server, and recommended deployment.
- Split server-essential integration from optional Async Cable, Async Job, Live,
  limiter, and logging integrations.
- Decide who configures fiber isolation and when.
- Publish supported Ruby, Rails, Rack, and dependency versions as a tested matrix.
- Create a shared Rails/Falcon tracking project with owners on both sides.

### Phase 1: Make Falcon a first-class generated option

- Add `rails new --server=falcon` and a matching skip/selection mechanism.
- Generate the correct Gemfile, development command, production `falcon.rb`,
  Docker/Kamal command, Thruster configuration, health check, and database-pool
  guidance.
- Make `bin/rails server` flags either work or fail clearly under Falcon.
- Add official Rails guides for Falcon configuration and concurrency semantics.
- Keep Puma as the generated default during this phase.

### Phase 2: Establish a compatibility laboratory

- Run a generated Rails reference application continuously against Puma and
  Falcon, comparing externally observable behavior rather than internal topology.
- Add Falcon jobs to relevant Rails component CI suites.
- Run Rack's specification/lint suite and callable-body tests against Falcon.
- Run Action Cable conformance, browser, and load tests with Async Cable.
- Run Solid Queue's thread and fiber worker suites with the same application code.
- Publish regressions, memory/process metrics, and performance results.

### Phase 3: Burn down correctness and lifecycle issues

Required before a candidate default:

- close the reload stall and stale-constant cases;
- settle request-body rewind/buffering semantics;
- complete Rails 8.2 Async Cable integration and common pub/sub adapters;
- fix callable streaming middleware failures;
- validate Active Record and driver behavior under pool pressure;
- provide graceful deploy/restart behavior for ordinary, streaming, and WebSocket
  requests;
- make logging, errors, and diagnostics Rails-native and unsurprising.

### Phase 4: Production candidate program

- Recruit applications representing CRUD, high-throughput APIs, Cable/Turbo,
  Active Storage, LLM streaming, multi-database/sharded deployments, and common
  authentication/observability gems.
- Require multi-week mixed-load soaks and real deploy/restart cycles.
- Collect CPU, latency, throughput, RSS, PSS, private memory, connection counts,
  scheduler stalls, queue depths, and disconnect/error rates.
- Document regressions as carefully as wins. Falcon need not win every workload,
  but the default must be safe and predictable.

### Phase 5: Change the generated default

Only after all gates below are met:

- switch the app generator and Rails missing-server recommendation;
- retain `--server=puma` as an easy, supported choice;
- provide an upgrade guide that separates correctness requirements from optional
  performance tuning;
- keep the comparative CI and reference applications permanently.

## Acceptance gates

### Correctness matrix

The matrix should cover at least:

| Dimension | Cases |
| --- | --- |
| Ruby | All Ruby versions supported by the target Rails release, with and without YJIT where relevant. |
| Protocol | HTTP/1.1 and HTTP/2; TLS directly and behind common reverse proxies. |
| Database | PostgreSQL, MySQL/mysql2, SQLite; pool exhaustion; roles and shards. |
| Request bodies | Empty, fixed, chunked/streamed, JSON, forms, multipart, large uploads, early rejection, read/rewind/re-read. |
| Response bodies | Enumerable, file, callable streaming, SSE, `send_stream`, errors before/after commit, client disconnect. |
| Cable | HTTP/1 and HTTP/2, Redis, PostgreSQL, Solid Cable, reconnect, slow client, broadcast fan-out, deploy drain. |
| Jobs | Solid Queue thread workers and fiber workers; transactions, retries, shutdown, recurring jobs. |
| Active Storage | Local and cloud services, direct upload, proxy/redirect download, variants, concurrent use. |
| Development | Reload during requests, streams, Cable connections and jobs; debugger, console, system tests. |
| Middleware | Sessions, cookies, CSRF, compression, ETag, authentication, request stores, tracing/APM, reverse proxy. |

### Reliability gates

- No known silent request/response data loss.
- No reproducible reload deadlock or stale-code execution.
- No cross-request leakage of identity, tenant, database role, transaction, query
  cache, logging, tracing, or error context.
- Bounded memory and task growth through long-lived connections and repeated
  reload/deploy cycles.
- Graceful shutdown completes or explicitly times out while reporting unfinished
  work; it must not silently drop accepted work.
- Backpressure exists for request bodies, streaming responses, Cable output, and
  job concurrency.

### Usability gates

- A fresh generated app works in development and production from Rails-owned
  documentation.
- `PORT`, bind address, worker count, TLS/proxy mode, logging, PID/signal behavior,
  health checks, and database pool sizing are discoverable.
- Diagnostics identify a blocking reactor, leaked/pinned database connection,
  stuck task, and slow client without requiring an Async maintainer.
- Switching back to Puma is a documented one-line generator or Gemfile/config
  choice.

## Suggested upstream work items

1. Add the Rails generator option and a minimal Falcon production template.
2. Add a shared Rails/Falcon reference app to CI before changing any default.
3. Resolve Falcon #359 and add the reproduction as a permanent Rails reload test.
4. Specify Rails request-body buffering policy and close Falcon #302/#310 plus
   protocol-rack #33 with cross-server tests.
5. Finish Async Cable's Rails 8.2-native release, executor wiring, Solid Cable
   compatibility, and conformance matrix.
6. Introduce or document a scheduler-neutral controller streaming API based on
   Rack callable bodies; fix Rack #2470.
7. Add Active Record fiber stress tests for drivers, transactions, roles/shards,
   cancellation, and pinned connections.
8. Generate a production lifecycle with graceful drain/restart and observable
   worker/process memory.
9. Make Early Hints and HTTP/2 upgrade behavior executable compatibility tests.
10. Collect and publish production candidate evidence before proposing the default
    flip to Rails core.

## Issue and change index

Status below is as of 2026-08-04.

### Rails

- [rails/rails#50979][rails-ac-adapter-pr] — Action Cable server adapterization;
  merged 2026-05-28.
- [rails/rails#57423][rails-reloader-fiber] — fiber-aware reloader share-lock
  ownership; merged 2026-05-21.
- [rails/rails#57425][rails-reloader-hijack] — release reloader share on hijack;
  merged 2026-05-21.
- [rails/rails#42271][rails-ar-fiber] — fiber-safe Active Record connection pool;
  closed after the core work landed.
- [rails/rails#57926][rails-mysql-fiber] — mysql2 connection owned by another
  fiber; open.
- [rails/rails#21209][rails-live-ar] — Active Record and
  `ActionController::Live` thread interaction; open.
- [rails/rails#52660][rails-active-storage-async] — concurrent Active Storage
  attachment mutation; open.
- [rails/rails#48279][rails-current-attributes] — child-fiber semantics for
  `CurrentAttributes`; closed as caller-managed propagation.
- [rails/rails#23828][rails-template-streaming] — surprising/broken template
  streaming cases; open.
- [rails/rails#35657][rails-ac-async] — historical Async Action Cable design
  discussion; closed after adapterization became available.

### Falcon and integration gems

- [socketry/falcon#359][falcon-reload-stall] — development reload stalls all
  requests; open.
- [socketry/falcon#325][falcon-cable-reload] — constant loading failure during
  development with Async Cable; open.
- [socketry/falcon#302][falcon-request-body] — JSON request body disappears;
  open.
- [socketry/falcon#310][falcon-body-rewind] — non-rewindable request bodies and
  Grape/HMAC workflows; open.
- [socketry/falcon#188][falcon-graceful-restart] — graceful restart breaks
  in-flight requests; open.
- [socketry/falcon#344][falcon-supervisor-memory] — supervisor/preload memory
  accounting and topology; open.
- [socketry/falcon#363][falcon-memory-footprint] — production memory regression
  investigation; open.
- [socketry/falcon#127][falcon-configuration-docs] — production configuration
  discoverability; open.
- [socketry/async-cable#3][async-cable-solid] — Async Cable and Solid Cable
  incompatibility report; open.
- [socketry/falcon-rails#4][falcon-rails-logging] — unexpected replacement of
  Rails file logging; open.

### Rack and Solid Queue

- [rack/rack#2470][rack-deflater] — `Rack::Deflater` fails on Rack 3 callable
  bodies; open.
- [socketry/protocol-rack#33][protocol-rack-rewind] — false successful rewind and
  empty forwarded request; open.
- [rails/solid_queue#728][solid-queue-fiber-pr] — bounded fiber worker execution;
  merged and released in Solid Queue 1.6.0.

## Conclusion

Falcon's case is strategically strong: Ruby and Rails now expose the execution
locality and server abstraction needed for fibers, while Rack 3 supplies a sound
streaming and protocol-upgrade foundation. The Rails 8.2 Action Cable work and
Solid Queue 1.6.0 fiber workers turn the proposal from a parallel ecosystem into
a credible upstream direction.

The next milestone should not be “make Falcon the default.” It should be “make a
stock Rails application continuously indistinguishable in correctness under
Falcon, then make the operational differences explicit and well supported.” Once
that is true—and demonstrated in CI and production—the generator flip becomes a
small policy change rather than a high-risk architectural bet.

[async-cable]: https://github.com/socketry/async-cable/tree/dddef54c29be190f8289225420a681a7c196da12
[async-cable-solid]: https://github.com/socketry/async-cable/issues/3
[falcon-body-rewind]: https://github.com/socketry/falcon/issues/310
[falcon-cable-reload]: https://github.com/socketry/falcon/issues/325
[falcon-configuration-docs]: https://github.com/socketry/falcon/issues/127
[falcon-graceful-restart]: https://github.com/socketry/falcon/issues/188
[falcon-memory-footprint]: https://github.com/socketry/falcon/issues/363
[falcon-rackup-handler]: https://github.com/socketry/falcon/blob/16965984b1c4bed02b788fd383d982587448a56c/lib/falcon/rackup/handler.rb
[falcon-railtie]: https://github.com/socketry/falcon/blob/16965984b1c4bed02b788fd383d982587448a56c/lib/falcon/railtie.rb
[falcon-reload-stall]: https://github.com/socketry/falcon/issues/359
[falcon-request-body]: https://github.com/socketry/falcon/issues/302
[falcon-request-logging]: https://github.com/socketry/falcon/issues/90
[falcon-supervisor-memory]: https://github.com/socketry/falcon/issues/344
[falcon-rails-full-rails]: https://github.com/socketry/falcon-rails/issues/3
[falcon-rails-logging]: https://github.com/socketry/falcon-rails/issues/4
[rack-deflater]: https://github.com/rack/rack/issues/2470
[rack-spec]: https://github.com/rack/rack/blob/b48e0303a6468eb96e8fc01dfeda6284870e562f/SPEC.rdoc
[rackup-handler]: https://github.com/rack/rackup/blob/f3fa1d6ada90e9e7aa1f712488ddde87ea2a2075/lib/rackup/handler.rb
[rails-ac-adapter-pr]: https://github.com/rails/rails/pull/50979
[rails-ac-async]: https://github.com/rails/rails/issues/35657
[rails-active-storage-async]: https://github.com/rails/rails/issues/52660
[rails-app-generator]: https://github.com/rails/rails/blob/f5ae04bef6d47a2ccbbd15a9075622ce6e84116a/railties/lib/rails/generators/app_base.rb#L294-L296
[rails-ar-connection-handling]: https://github.com/rails/rails/blob/f5ae04bef6d47a2ccbbd15a9075622ce6e84116a/activerecord/lib/active_record/connection_handling.rb#L290-L336
[rails-ar-fiber]: https://github.com/rails/rails/issues/42271
[rails-ar-pool]: https://github.com/rails/rails/blob/f5ae04bef6d47a2ccbbd15a9075622ce6e84116a/activerecord/lib/active_record/connection_adapters/abstract/connection_pool.rb
[rails-current-attributes]: https://github.com/rails/rails/issues/48279
[rails-isolated-state]: https://github.com/rails/rails/blob/f5ae04bef6d47a2ccbbd15a9075622ce6e84116a/activesupport/lib/active_support/isolated_execution_state.rb
[rails-isolation-guide]: https://github.com/rails/rails/blob/f5ae04bef6d47a2ccbbd15a9075622ce6e84116a/guides/source/configuring.md#configactivesupportisolation_level
[rails-live-ar]: https://github.com/rails/rails/issues/21209
[rails-live-connected-to]: https://github.com/rails/rails/issues/52906
[rails-live-source]: https://github.com/rails/rails/blob/f5ae04bef6d47a2ccbbd15a9075622ce6e84116a/actionpack/lib/action_controller/metal/live.rb
[rails-mysql-fiber]: https://github.com/rails/rails/issues/57926
[rails-reloader-fiber]: https://github.com/rails/rails/pull/57423
[rails-reloader-hijack]: https://github.com/rails/rails/pull/57425
[rails-server-command]: https://github.com/rails/rails/blob/f5ae04bef6d47a2ccbbd15a9075622ce6e84116a/railties/lib/rails/commands/server/server_command.rb
[rails-template-streaming]: https://github.com/rails/rails/issues/23828
[solid-queue-fiber-pr]: https://github.com/rails/solid_queue/pull/728
[solid-queue-readme]: https://github.com/rails/solid_queue/blob/86f3d92f1dd68547ec0ebe960fc9933c203d9e51/README.md#fork-vs-async-mode
[protocol-rack-rewind]: https://github.com/socketry/protocol-rack/issues/33
[protocol-rack-rewindable]: https://github.com/socketry/protocol-rack/blob/a58592b81672ad22a81b52d370a541663c41e872/lib/protocol/rack/rewindable.rb
