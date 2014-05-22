require 'uv-rays'

describe UV::BufferedTokenizer do
    describe 'delimiter' do

        before :each do
            @buffer = UV::BufferedTokenizer.new({
                delimiter: "\n\r"
            })
        end


        it "should not return anything when a complete message is not available" do
            msg1 = "test"

            result = @buffer.extract(msg1)
            expect(result).to eq([])
        end

        it "should not return anything when the messages is empty" do
            msg1 = ""

            result = @buffer.extract(msg1)
            expect(result).to eq([])
        end

        it "should tokenize messages where the data is a complete message" do
            msg1 = "test\n\r"

            result = @buffer.extract(msg1)
            expect(result).to eq(['test'])
        end

        it "should return multiple complete messages" do
            msg1 = "test\n\rwhoa\n\r"

            result = @buffer.extract(msg1)
            expect(result).to eq(['test', 'whoa'])
        end
        
        it "should tokenize messages where the delimiter is split" do
            msg1 = "test\n"
            msg2 = "\rwhoa\n\r"

            result = @buffer.extract(msg1)
            expect(result).to eq([])
            result = @buffer.extract(msg2)
            expect(result).to eq(['test', 'whoa'])


            msg3 = "test\n"
            msg4 = "\rwhoa\n"
            msg5 = "\r"

            result = @buffer.extract(msg3)
            expect(result).to eq([])
            result = @buffer.extract(msg4)
            expect(result).to eq(['test']        )

            result = @buffer.extract(msg5)
            expect(result).to eq(['whoa'])
        end
    end



    describe 'indicator with delimiter' do

        before :each do
            @buffer = UV::BufferedTokenizer.new({
                delimiter: "\n\r",
                indicator: "GO"
            })
        end


        it "should not return anything when a complete message is not available" do
            msg1 = "GO-somedata"

            result = @buffer.extract(msg1)
            expect(result).to eq([])
        end

        it "should not return anything when the messages is empty" do
            msg1 = ""

            result = @buffer.extract(msg1)
            expect(result).to eq([])
        end

        it "should tokenize messages where the data is a complete message" do
            msg1 = "GOtest\n\r"

            result = @buffer.extract(msg1)
            expect(result).to eq(['test'])
        end

        it "should discard data that is not relevant" do
            msg1 = "1234-GOtest\n\r"

            result = @buffer.extract(msg1)
            expect(result).to eq(['test'])
        end

        it "should return multiple complete messages" do
            msg1 = "GOtest\n\rGOwhoa\n\r"

            result = @buffer.extract(msg1)
            expect(result).to eq(['test', 'whoa'])
        end

        it "should discard data between multiple complete messages" do
            msg1 = "1234-GOtest\n\r12345-GOwhoa\n\r"

            result = @buffer.extract(msg1)
            expect(result).to eq(['test', 'whoa'])
        end
        
        it "should tokenize messages where the delimiter is split" do
            msg1 = "GOtest\n"
            msg2 = "\rGOwhoa\n\r"

            result = @buffer.extract(msg1)
            expect(result).to eq([])
            result = @buffer.extract(msg2)
            expect(result).to eq(['test', 'whoa'])


            msg3 = "GOtest\n"
            msg4 = "\rGOwhoa\n"
            msg5 = "\r"

            result = @buffer.extract(msg3)
            expect(result).to eq([])
            result = @buffer.extract(msg4)
            expect(result).to eq(['test']        )

            result = @buffer.extract(msg5)
            expect(result).to eq(['whoa'])
        end

        it "should tokenize messages where the indicator is split" do
            msg1 = "GOtest\n\rG"
            msg2 = "Owhoa\n"
            msg3 = "\rGOwhoa\n\r"

            result = @buffer.extract(msg1)
            expect(result).to eq(['test'])
            result = @buffer.extract(msg2)
            expect(result).to eq([])
            result = @buffer.extract(msg3)
            expect(result).to eq(['whoa', 'whoa'])
        end

        it "should tokenize messages where the indicator is split and there is discard data" do
            msg1 = "GOtest\n\r1234G"
            msg2 = "Owhoa\n"
            msg3 = "\r1234GOwhoa\n\r"

            result = @buffer.extract(msg1)
            expect(result).to eq(['test'])
            result = @buffer.extract(msg2)
            expect(result).to eq([])
            result = @buffer.extract(msg3)
            expect(result).to eq(['whoa', 'whoa'])
        end
    end

    describe 'buffer size limit with indicator' do
        before :each do
            @buffer = UV::BufferedTokenizer.new({
                delimiter: "\n\r",
                indicator: "Start",
                size_limit: 10
            })
        end

        it "should empty the buffer if the limit is exceeded" do
            result = @buffer.extract('1234567890G')
            expect(result).to eq([])
            expect(@buffer.flush).to eq('890G')
        end
    end

    describe 'buffer size limit without indicator' do
        before :each do
            @buffer = UV::BufferedTokenizer.new({
                delimiter: "\n\r",
                size_limit: 10
            })
        end

        it "should empty the buffer if the limit is exceeded" do
            result = @buffer.extract('1234567890G')
            expect(result).to eq([])
            expect(@buffer.flush).to eq('')
        end
    end
end
