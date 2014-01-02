
# BufferedTokenizer takes a delimiter upon instantiation.
# It allows input to be spoon-fed from some outside source which receives
# arbitrary length datagrams which may-or-may-not contain the token by which
# entities are delimited.
#
# @example Using BufferedTokernizer to parse lines out of incoming data
#
#     module LineBufferedConnection
#         def receive_data(data)
#             (@buffer ||= BufferedTokenizer.new(delimiter: "\n")).extract(data).each do |line|
#                 receive_line(line)
#             end
#         end
#     end
module UV
    class BufferedTokenizer

        attr_accessor :delimiter, :indicator, :size_limit, :verbose

        # @param [Hash] options
        def initialize(options)
            @delimiter  = options[:delimiter]
            @indicator  = options[:indicator]
            @size_limit = options[:size_limit]
            @verbose    = options[:verbose] if @size_limit

            raise ArgumentError, 'no delimiter provided' unless @delimiter

            @input = ''
        end

        # Extract takes an arbitrary string of input data and returns an array of
        # tokenized entities, provided there were any available to extract.
        #
        # @example
        #
        #     tokenizer.extract(data).
        #         map { |entity| Decode(entity) }.each { ... }
        #
        # @param [String] data
        def extract(data)
            @input << data

            # Extract token-delimited entities from the input string with the split command.
            # There's a bit of craftiness here with the -1 parameter.    Normally split would
            # behave no differently regardless of if the token lies at the very end of the
            # input buffer or not (i.e. a literal edge case)    Specifying -1 forces split to
            # return "" in this case, meaning that the last entry in the list represents a
            # new segment of data where the token has not been encountered
            messages = @input.split(@delimiter, -1)

            if @indicator
                @input = messages.pop
                entities = []
                messages.each do |msg|
                    res = msg.split(@indicator, -1)
                    entities << res.last if res.length > 1
                end
            else
                entities = messages
                @input = entities.pop
            end

            # Check to see if the buffer has exceeded capacity, if we're imposing a limit
            if @size_limit && @input.size > @size_limit
                if @indicator && @indicator.respond_to?(:length) # check for regex
                    # save enough of the buffer that if one character of the indicator were
                    # missing we would match on next extract (very much an edge case) and
                    # best we can do with a full buffer. If we were one char short of a
                    # delimiter it would be unfortunate
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