
#
# Specifying rufus-scheduler
#
# Wed Apr 17 06:00:59 JST 2013
#



describe UvRays::Scheduler do

    describe '.parse_duration' do

        def pd(s)
            UvRays::Scheduler.parse_duration(s)
        end

        it 'parses duration strings' do

            expect(pd('-1.0d1.0w1.0d')).to eq(-777600000)
            expect(pd('-1d1w1d')).to eq(-777600000)
            expect(pd('-1w2d')).to eq(-777600000)
            expect(pd('-1h10s')).to eq(-3610000)
            expect(pd('-1h')).to eq(-3600000)
            expect(pd('-5.')).to eq(-5)
            expect(pd('-2.5s')).to eq(-2500)
            expect(pd('-1s')).to eq(-1000)
            expect(pd('-500')).to eq(-500)
            expect(pd('')).to eq(0)
            expect(pd('5.0')).to eq(5)
            expect(pd('0.5')).to eq(0)
            expect(pd('.5')).to eq(0)
            expect(pd('5.')).to eq(5)
            expect(pd('500')).to eq(500)
            expect(pd('1000')).to eq(1000)
            expect(pd('1')).to eq(1)
            expect(pd('1s')).to eq(1000)
            expect(pd('2.5s')).to eq(2500)
            expect(pd('1h')).to eq(3600000)
            expect(pd('1h10s')).to eq(3610000)
            expect(pd('1w2d')).to eq(777600000)
            expect(pd('1d1w1d')).to eq(777600000)
            expect(pd('1.0d1.0w1.0d')).to eq(777600000)

            expect(pd('.5m')).to eq(30000)
            expect(pd('5.m')).to eq(300000)
            expect(pd('1m.5s')).to eq(60500)
            expect(pd('-.5m')).to eq(-30000)

            expect(pd('1')).to eq(1)
            expect(pd('0.1')).to eq(0)
            expect(pd('1s')).to eq(1000)
        end

        it 'calls #to_s on its input' do

            expect(pd(1)).to eq(1)
        end

        it 'raises on wrong duration strings' do

            expect  { pd('-') }.to raise_error(ArgumentError)
            expect  { pd('h') }.to raise_error(ArgumentError)
            expect  { pd('whatever') }.to raise_error(ArgumentError)
            expect  { pd('hms') }.to raise_error(ArgumentError)

            expect  { pd(' 1h ') }.to raise_error(ArgumentError)
        end
    end

    describe '.to_duration' do

        def td(o, opts={})
            UvRays::Scheduler.to_duration(o, opts)
        end

        it 'turns integers into duration strings' do

            expect(td(0)).to eq('0s')
            expect(td(60000)).to eq('1m')
            expect(td(61000)).to eq('1m1s')
            expect(td(3661000)).to eq('1h1m1s')
            expect(td(24 * 3600 * 1000)).to eq('1d')
            expect(td(7 * 24 * 3600 * 1000 + 1000)).to eq('1w1s')
            expect(td(30 * 24 * 3600 * 1000 + 1000)).to eq('4w2d1s')
        end

        it 'ignores seconds and milliseconds if :drop_seconds => true' do

            expect(td(0, :drop_seconds => true)).to eq('0m')
            expect(td(5000, :drop_seconds => true)).to eq('0m')
            expect(td(61000, :drop_seconds => true)).to eq('1m')
        end

        it 'displays months if :months => true' do

            expect(td(1000, :months => true)).to eq('1s')
            expect(td(30 * 24 * 3600 * 1000 + 1000, :months => true)).to eq('1M1s')
        end

        it 'turns floats into duration strings' do

            expect(td(100)).to eq('100')
            expect(td(1100)).to eq('1s100')
        end
    end

    describe '.to_duration_hash' do

        def tdh(o, opts={})
            UvRays::Scheduler.to_duration_hash(o, opts)
        end

        it 'turns integers duration hashes' do

            expect(tdh(0)).to eq({})
            expect(tdh(60000)).to eq({ :m => 1 })
        end

        it 'turns floats duration hashes' do

            expect(tdh(128)).to eq({ :ms => 128 })
            expect(tdh(60127)).to eq({ :m => 1, :ms => 127 })
        end

        it 'drops seconds and milliseconds if :drop_seconds => true' do

            expect(tdh(61127)).to eq({ :m => 1, :s => 1, :ms => 127 })
            expect(tdh(61127, :drop_seconds => true)).to eq({ :m => 1 })
        end
    end
end
