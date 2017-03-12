# frozen_string_literal: true, encoding: ASCII-8BIT

module UV

    # AbstractTokenizer is similar to BufferedTokernizer however should
    # only be used when there is no delimiter to work with. It uses a
    # callback based system for application level tokenization without
    # the heavy lifting.
    class AbstractTokenizer
        DEFAULT_ENCODING = 'ASCII-8BIT'

        attr_accessor :callback, :indicator, :size_limit, :verbose

        # @param [Hash] options
        def initialize(options)
            @callback  = options[:callback]
            @indicator  = options[:indicator]
            @size_limit = options[:size_limit]
            @verbose  = options[:verbose] if @size_limit
            @encoding   = options[:encoding] || DEFAULT_ENCODING

            raise ArgumentError, 'no callback provided' unless @callback

            reset
            if @indicator.is_a?(String)
                @indicator = String.new(@indicator).force_encoding(@encoding).freeze
            end
        end

        # Extract takes an arbitrary string of input data and returns an array of
        # tokenized entities using a message start indicator
        #
        # @example
        #
        #     tokenizer.extract(data).
        #         map { |entity| Decode(entity) }.each { ... }
        #
        # @param [String] data
        def extract(data)
            data.force_encoding(@encoding)
            @input << data

            entities = []

            loop do
                found = false

                last = if @indicator
                    check = @input.partition(@indicator)
                    break unless check[1].length > 0

                    check[2]
                else
                    @input
                end

                result = @callback.call(last)

                if result
                    found = true

                    # Check for multi-byte indicator edge case
                    case result
                    when Integer, Fixnum
                        entities << last[0...result]
                        @input = last[result..-1]
                    else
                        entities << last
                        reset
                    end
                end

                break if not found
            end

            # Check to see if the buffer has exceeded capacity, if we're imposing a limit
            if @size_limit && @input.size > @size_limit
                if @indicator.respond_to?(:length) # check for regex
                    # save enough of the buffer that if one character of the indicator were
                    # missing we would match on next extract (very much an edge case) and
                    # best we can do with a full buffer.
                    @input = @input[-(@indicator.length - 1)..-1]
                else
                    reset
                end
                raise 'input buffer exceeded limit' if @verbose
            end

            return entities
        end

        # Flush the contents of the input buffer, i.e. return the input buffer even though
        # a token has not yet been encountered.
        #
        # @return [String]
        def flush
            buffer = @input
            reset
            buffer
        end

        # @return [Boolean]
        def empty?
            @input.empty?
        end


        private


        def reset
            @input = String.new.force_encoding(@encoding)
        end
    end
end