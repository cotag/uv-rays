
module UV

    # AbstractTokenizer is similar to BufferedTokernizer however should
    # only be used when there is no delimiter to work with. It uses a
    # callback based system for application level tokenization without
    # the heavy lifting.
    class AbstractTokenizer

        attr_accessor :callback, :indicator, :size_limit, :verbose

        # @param [Hash] options
        def initialize(options)
            @callback  = options[:callback]
            @indicator  = options[:indicator]
            @size_limit = options[:size_limit]
            @verbose  = options[:verbose] if @size_limit

            raise ArgumentError, 'no indicator provided' unless @indicator
            raise ArgumentError, 'no callback provided' unless @callback

            @input = ''
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
            @input << data

            messages = @input.split(@indicator, -1)
            if messages.length > 1
                messages.shift      # the first item will always be junk
                last = messages.pop # the last item may require buffering

                entities = []
                messages.each do |msg|
                    entities << msg if @callback.call(msg)
                end

                # Check if buffering is required
                result = @callback.call(last)
                if result
                    # Check for multi-byte indicator edge case
                    if result.is_a? Fixnum
                        entities << last[0...result]
                        @input = last[result..-1]
                    else
                        @input = ''
                        entities << last
                    end
                else
                    # This will work with a regex
                    index = messages.last.nil? ? 0 : @input[0...-last.length].rindex(messages.last) + messages.last.length
                    indicator_val = @input[index...-last.length]
                    @input = indicator_val + last
                end
            else
                @input = messages.pop
                entities = messages
            end

            # Check to see if the buffer has exceeded capacity, if we're imposing a limit
            if @size_limit && @input.size > @size_limit
                if @indicator.respond_to?(:length) # check for regex
                    # save enough of the buffer that if one character of the indicator were
                    # missing we would match on next extract (very much an edge case) and
                    # best we can do with a full buffer.
                    @input = @input[-(@indicator.length - 1)..-1]
                else
                    @input = ''
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
            @input = ''
            buffer
        end

        # @return [Boolean]
        def empty?
            @input.empty?
        end
    end
end