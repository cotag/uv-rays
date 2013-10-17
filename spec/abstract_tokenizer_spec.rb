require 'uv-rays'

describe UvRays::AbstractTokenizer do
    before :each do
        @buffer = UvRays::AbstractTokenizer.new({
            indicator: "Start",
            callback: lambda { |data|
                return 4 if data.length > 3
                return false
            },
            size_limit: 10
        })
    end

    it "should not return anything when a complete message is not available" do
        msg1 = "test"

        result = @buffer.extract(msg1)
        result.should == []
    end

    it "should not return anything when an empty message is present" do
        msg1 = "test"

        result = @buffer.extract(msg1)
        result.should == []
    end

    it "should tokenize messages where the data is a complete message" do
        msg1 = "Start1234"

        result = @buffer.extract(msg1)
        result.should == ['1234']
    end

    it "should return multiple complete messages" do
        msg1 = "Start1234Start123456"

        result = @buffer.extract(msg1)
        result.should == ['1234', '1234']
        @buffer.flush.should == '56'    # as we've indicated a message length of 4
    end
    
    it "should tokenize messages where the indicator is split" do
        msg1 = "123Star"
        msg2 = "twhoaStart1234"

        result = @buffer.extract(msg1)
        result.should == []
        result = @buffer.extract(msg2)
        result.should == ['whoa', '1234']

        msg1 = "123Star"
        msg2 = "twhoaSt"
        msg3 = "art1234"

        result = @buffer.extract(msg1)
        result.should == []
        result = @buffer.extract(msg2)
        result.should == ['whoa']
        result = @buffer.extract(msg3)
        result.should == ['1234']
    end

    it "should empty the buffer if the limit is exceeded" do
        result = @buffer.extract('1234567890G')
        result.should == []

        # We keep enough to match a possible partial indicator
        @buffer.flush.should == '890G'
    end

    it "should work with regular expressions" do
        @buffer = UvRays::AbstractTokenizer.new({
            indicator: /Start/i,
            callback: lambda { |data|
                return 4 if data.length > 3
                return false
            }
        })

        result = @buffer.extract('1234567starta')
        result.should == []
        result = @buffer.extract('bcd')
        result.should == ['abcd']
    end
end
