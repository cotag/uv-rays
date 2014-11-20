require 'uv-rays'

describe UV::AbstractTokenizer do
    before :each do
        @buffer = UV::AbstractTokenizer.new({
            indicator: "Start",
            callback: lambda { |data|
                return 4 if data.length > 3
                return false
            },
            size_limit: 10,
            encoding: "ASCII-8BIT"
        })
    end

    it "should not return anything when a complete message is not available" do
        msg1 = "test"

        result = @buffer.extract(msg1)
        expect(result).to eq([])
    end

    it "should not return anything when an empty message is present" do
        msg1 = "test"

        result = @buffer.extract(msg1)
        expect(result).to eq([])
    end

    it "should tokenize messages where the data is a complete message" do
        msg1 = "Start1234"

        result = @buffer.extract(msg1)
        expect(result).to eq(['1234'])
    end

    it "should return multiple complete messages" do
        msg1 = "Start1234Start123456"

        result = @buffer.extract(msg1)
        expect(result).to eq(['1234', '1234'])
        expect(@buffer.flush).to eq('56')    # as we've indicated a message length of 4
    end
    
    it "should tokenize messages where the indicator is split" do
        msg1 = "123Star"
        msg2 = "twhoaStart1234"

        result = @buffer.extract(msg1)
        expect(result).to eq([])
        result = @buffer.extract(msg2)
        expect(result).to eq(['whoa', '1234'])

        msg1 = "123Star"
        msg2 = "twhoaSt"
        msg3 = "art1234"

        result = @buffer.extract(msg1)
        expect(result).to eq([])
        result = @buffer.extract(msg2)
        expect(result).to eq(['whoa'])
        result = @buffer.extract(msg3)
        expect(result).to eq(['1234'])
    end

    it "should empty the buffer if the limit is exceeded" do
        result = @buffer.extract('1234567890G')
        expect(result).to eq([])

        # We keep enough to match a possible partial indicator
        expect(@buffer.flush).to eq('890G')
    end

    it "should work with regular expressions" do
        @buffer = UV::AbstractTokenizer.new({
            indicator: /Start/i,
            callback: lambda { |data|
                return 4 if data.length > 3
                return false
            }
        })

        result = @buffer.extract('1234567starta')
        expect(result).to eq([])
        result = @buffer.extract('bcd')
        expect(result).to eq(['abcd'])
    end
end
