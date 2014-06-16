require 'redisse/version'
require 'redisse/publisher'
require 'redis'

# Public: A HTTP API to serve Server-Sent Events via a Redis backend.
module Redisse
  # Public: Gets/Sets the String URL of the Redis server to connect to.
  #
  # Note that while the Redis pubsub mechanism works outside of the Redis key
  # namespace and ignores the database (the path part of the URL), the
  # database will still be used to store an history of the events sent to
  # support Last-Event-Id.
  #
  # Examples
  #
  #   class Events < Redisse
  #     # ...
  #   end
  #   Events.redis_server = "redis://localhost:6379/42"
  attr_accessor :redis_server

  # Public: The default port of the server.
  attr_accessor :default_port

  # Public: Send an event to subscribers, of the given type.
  #
  # All browsers subscribing to the events server will receive a Server-Sent
  # Event of the chosen type.
  #
  # channel      - The channel to publish the message to.
  # type_message - The type of the event and the content of the message, as a
  #                Hash of form { type => message } or simply the message as
  #                a String, for the default event type :message.
  #
  # Examples
  #
  #   Redisse.publish(:global, notice: 'This is a server-sent event.')
  #   Redisse.publish(:global, 'Hello, World!')
  #
  #   # on the browser side:
  #   var source = new EventSource(eventsURL);
  #   source.addEventListener('notice', function(e) {
  #     console.log(e.data) // logs 'This is a server-sent event.'
  #   }, false)
  #   source.addEventListener('message', function(e) {
  #     console.log(e.data) // logs 'Hello, World!'
  #   }, false)
  def publish(channel, message)
    type, message = Hash(message).first if message.respond_to?(:to_h)
    type ||= :message
    publisher.publish(channel, message, type)
  end

  # Public: The list of channels to subscribe to.
  #
  # The Redis keys with the same name as the channels will be used to store an
  # history of the last events sent, in order to support Last-Event-Id.
  #
  # You need to override this method in your subclass, and depending on the
  # Rack environment, return a list of channels the current user has access to.
  #
  # env - The Rack environment for this request.
  #
  # Examples
  #
  #   def channels(env)
  #     %w( comment post )
  #   end
  #   # will result in subscriptions to 'comment' and 'post' channels.
  #
  # Returns an Array of String naming the channels to subscribe to.
  def channels(env)
    raise NotImplementedError, "you must implement #{self}.channels"
  end

  # Public: Use test mode.
  #
  # Instead of actually publishing to Redis, events will be stored in
  # {#published} to use for tests.
  #
  # Must be called before each test in order for published events to be
  # emptied.
  #
  # See also {#test_filter=}.
  #
  # Examples
  #
  #   # RSpec
  #   before { Events.test_mode! }
  def test_mode!
    @publisher = TestPublisher.new
  end

  # Public: Filter events stored in test mode.
  #
  # If set, only events whose type match with the filter are stored in
  # {#published}. A filter matches by using case equality, which allows using
  # a simple Symbol or a Proc for more advanced filters:
  #
  # Automatically sets {#test_mode!}, so it also clears the previous events.
  #
  # Examples
  #
  #   Events.test_filter = -> type { %i(foo baz).include? type }
  #   Events.publish :global, foo: 'stored'
  #   Events.publish :global, bar: 'skipped'
  #   Events.publish :global, baz: 'stored'
  #   Events.published.size # => 2
  def test_filter=(filter)
    test_mode!
    publisher.filter = filter
  end

  # Public: Returns the published events.
  #
  # Fails unless {#test_mode!} is set.
  def published
    fail "Call #{self}.test_mode! first" unless publisher.respond_to?(:published)
    publisher.published
  end

  # Internal: List of middlewares defined with {#use}.
  #
  # Used by Goliath to build the server.
  def middlewares
    @middlewares ||= []
  end

  # Public: Define a middleware for the server.
  #
  # See {https://github.com/postrank-labs/goliath/wiki/Middleware Goliath middlewares}.
  #
  # Examples
  #
  #    module Events
  #      extend Redisse
  #      use MyMiddleware, foo: true
  #    end
  def use(middleware, *args, &block)
    middlewares << [middleware, args, block]
  end

  # Public: Define a Goliath plugin to run with the server.
  #
  # See {https://github.com/postrank-labs/goliath/wiki/Plugins Goliath plugins}.
  def plugin(name, *args)
    plugins << [name, args]
  end

private

  def plugins
    @plugins ||= []
  end

  def publisher
    @publisher ||= RedisPublisher.new(redis)
  end

  def redis
    @redis ||= Redis.new(url: redis_server)
  end
end
