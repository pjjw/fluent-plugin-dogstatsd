module Fluent
  class DogstatsdOutput < BufferedOutput
    Plugin.register_output('dogstatsd', self)

    config_param :host, :string, :default => nil
    config_param :port, :integer, :default => nil
    config_param :use_tag_as_key, :bool, :default => false
    config_param :key_prefix, :string, :default => nil
    config_param :metric_type, :string, :default => nil
    config_param :value_key, :string, :default => nil

    unless method_defined?(:log)
      define_method(:log) { $log }
    end

    attr_accessor :statsd

    def initialize
      super

      require 'statsd' # dogstatsd-ruby
    end

    def start
      super

      host = @host || Statsd::DEFAULT_HOST
      port = @port || Statsd::DEFAULT_PORT

      @statsd ||= Statsd.new(host, port)
    end

    def format(tag, time, record)
      [tag, time, record].to_msgpack
    end

    def write(chunk)
      @statsd.batch do |s|
        chunk.msgpack_each do |tag, time, record|
          key = if @use_tag_as_key
                  tag
                else
                  record.delete('key')
                end

          unless key
            log.warn "'key' is not specified. skip this record:", tag: tag
            next
          end

          if @key_prefix
            key = key_prefix + key
          end

          value = record.delete(@value_key || 'value')

          options = {}

          tags = record['tags']

          title = record.delete('title')
          text  = record.delete('text')
          type  = @metric_type || record.delete('type')

          if tags
            options[:tags] = tags.map do |k, v|
              "#{k}:#{v}"
            end
          end

          case type
          when 'increment'
            s.increment(key, options)
          when 'decrement'
            s.decrement(key, options)
          when 'count'
            s.count(key, value, options)
          when 'gauge'
            s.gauge(key, value, options)
          when 'histogram'
            s.histogram(key, value, options)
          when 'timing'
            s.timing(key, value, options)
          when 'set'
            s.set(key, value, options)
          when 'event'
            s.event(title, text, options)
          when nil
            log.warn "type is not provided (You can provide type via `metric_type` in config or `type` field in a record."
          else
            log.warn "Type '#{type}' is unknown."
          end
        end
      end
    end
  end
end

