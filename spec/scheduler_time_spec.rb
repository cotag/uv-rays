
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

            pd('-1.0d1.0w1.0d').should == -777600000
            pd('-1d1w1d').should == -777600000
            pd('-1w2d').should == -777600000
            pd('-1h10s').should == -3610000
            pd('-1h').should == -3600000
            pd('-5.').should == -5
            pd('-2.5s').should == -2500
            pd('-1s').should == -1000
            pd('-500').should == -500
            pd('').should == 0
            pd('5.0').should == 5
            pd('0.5').should == 0
            pd('.5').should == 0
            pd('5.').should == 5
            pd('500').should == 500
            pd('1000').should == 1000
            pd('1').should == 1
            pd('1s').should == 1000
            pd('2.5s').should == 2500
            pd('1h').should == 3600000
            pd('1h10s').should == 3610000
            pd('1w2d').should == 777600000
            pd('1d1w1d').should == 777600000
            pd('1.0d1.0w1.0d').should == 777600000

            pd('.5m').should == 30000
            pd('5.m').should == 300000
            pd('1m.5s').should == 60500
            pd('-.5m').should == -30000

            pd('1').should == 1
            pd('0.1').should == 0
            pd('1s').should == 1000
        end

        it 'calls #to_s on its input' do

            pd(1).should == 1
        end

        it 'raises on wrong duration strings' do

            lambda { pd('-') }.should raise_error(ArgumentError)
            lambda { pd('h') }.should raise_error(ArgumentError)
            lambda { pd('whatever') }.should raise_error(ArgumentError)
            lambda { pd('hms') }.should raise_error(ArgumentError)

            lambda { pd(' 1h ') }.should raise_error(ArgumentError)
        end
    end

    describe '.to_duration' do

        def td(o, opts={})
            UvRays::Scheduler.to_duration(o, opts)
        end

        it 'turns integers into duration strings' do

            td(0).should == '0s'
            td(60000).should == '1m'
            td(61000).should == '1m1s'
            td(3661000).should == '1h1m1s'
            td(24 * 3600 * 1000).should == '1d'
            td(7 * 24 * 3600 * 1000 + 1000).should == '1w1s'
            td(30 * 24 * 3600 * 1000 + 1000).should == '4w2d1s'
        end

        it 'ignores seconds and milliseconds if :drop_seconds => true' do

            td(0, :drop_seconds => true).should == '0m'
            td(5000, :drop_seconds => true).should == '0m'
            td(61000, :drop_seconds => true).should == '1m'
        end

        it 'displays months if :months => true' do

            td(1000, :months => true).should == '1s'
            td(30 * 24 * 3600 * 1000 + 1000, :months => true).should == '1M1s'
        end

        it 'turns floats into duration strings' do

            td(100).should == '100'
            td(1100).should == '1s100'
        end
    end

    describe '.to_duration_hash' do

        def tdh(o, opts={})
            UvRays::Scheduler.to_duration_hash(o, opts)
        end

        it 'turns integers duration hashes' do

            tdh(0).should == {}
            tdh(60000).should == { :m => 1 }
        end

        it 'turns floats duration hashes' do

            tdh(128).should == { :ms => 128 }
            tdh(60127).should == { :m => 1, :ms => 127 }
        end

        it 'drops seconds and milliseconds if :drop_seconds => true' do

            tdh(61127).should == { :m => 1, :s => 1, :ms => 127 }
            tdh(61127, :drop_seconds => true).should == { :m => 1 }
        end
    end
end
