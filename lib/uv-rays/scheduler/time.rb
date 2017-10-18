# frozen_string_literal: true

#--
# Copyright (c) 2006-2013, John Mettraux, jmettraux@gmail.com
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Made in Japan.
#++

require 'parse-cron'


module UV
    class Scheduler

        # Thread safe timezone time class for use with parse-cron
        class TimeInZone
            def initialize(timezone)
                @timezone = timezone
            end

            def now
                time = nil
                Time.use_zone(@timezone) do
                    time = Time.now
                end
                time
            end

            def local(*args)
                result = nil
                Time.use_zone(@timezone) do
                    result = Time.local(*args)
                end
                result
            end
        end


        def self.parse_in(o, quiet = false)
            # if o is an integer we are looking at ms
            o.is_a?(String) ? parse_duration(o, quiet) : o
        end

        TZ_REGEX = /\b((?:[a-zA-Z][a-zA-z0-9\-+]+)(?:\/[a-zA-Z0-9\-+]+)?)\b/

        def self.parse_at(o, quiet = false)
            return (o.to_f * 1000).to_i if o.is_a?(Time)

            tz = nil
            s = o.to_s.gsub(TZ_REGEX) { |m|
                t = TZInfo::Timezone.get(m) rescue nil
                tz ||= t
                t ? '' : m
            }

            begin
                DateTime.parse(o)
            rescue
                raise ArgumentError, "no time information in #{o.inspect}"
            end if RUBY_VERSION < '1.9.0'

            t = Time.parse(s)
            t = tz.local_to_utc(t) if tz
            (t.to_f * 1000).to_i    # Convert to milliseconds

        rescue StandardError => se
            return nil if quiet
            raise se
        end

        def self.parse_cron(o, quiet = false, timezone: nil)
            if timezone
                tz = TimeInZone.new(timezone)
                CronParser.new(o, tz)
            else
                CronParser.new(o)
            end

        rescue ArgumentError => ae
            return nil if quiet
            raise ae
        end

        def self.parse_to_time(o)
            t = o
            t = parse(t) if t.is_a?(String)
            t = Time.now + t if t.is_a?(Numeric)

            raise ArgumentError.new(
                "cannot turn #{o.inspect} to a point in time, doesn't make sense"
            ) unless t.is_a?(Time)

            t
        end

        DURATIONS2M = [
            [ 'y', 365 * 24 * 3600 * 1000 ],
            [ 'M', 30 * 24 * 3600 * 1000 ],
            [ 'w', 7 * 24 * 3600 * 1000 ],
            [ 'd', 24 * 3600 * 1000 ],
            [ 'h', 3600 * 1000 ],
            [ 'm', 60 * 1000 ],
            [ 's', 1000 ]
        ]
        DURATIONS2 = DURATIONS2M.dup
        DURATIONS2.delete_at(1)

        DURATIONS = DURATIONS2M.inject({}) { |r, (k, v)| r[k] = v; r }
        DURATION_LETTERS = DURATIONS.keys.join

        DU_KEYS = DURATIONS2M.collect { |k, v| k.to_sym }

        # Turns a string like '1m10s' into a float like '70.0', more formally,
        # turns a time duration expressed as a string into a Float instance
        # (millisecond count).
        #
        # w -> week
        # d -> day
        # h -> hour
        # m -> minute
        # s -> second
        # M -> month
        # y -> year
        # 'nada' -> millisecond
        #
        # Some examples:
        #
        #   Rufus::Scheduler.parse_duration "0.5"    # => 0.5
        #   Rufus::Scheduler.parse_duration "500"    # => 0.5
        #   Rufus::Scheduler.parse_duration "1000"   # => 1.0
        #   Rufus::Scheduler.parse_duration "1h"     # => 3600.0
        #   Rufus::Scheduler.parse_duration "1h10s"  # => 3610.0
        #   Rufus::Scheduler.parse_duration "1w2d"   # => 777600.0
        #
        # Negative time strings are OK (Thanks Danny Fullerton):
        #
        #   Rufus::Scheduler.parse_duration "-0.5"   # => -0.5
        #   Rufus::Scheduler.parse_duration "-1h"    # => -3600.0
        #
        def self.parse_duration(string, quiet = false)
            string = string.to_s

            return 0 if string == ''

            m = string.match(/^(-?)([\d\.#{DURATION_LETTERS}]+)$/)

            return nil if m.nil? && quiet
            raise ArgumentError.new("cannot parse '#{string}'") if m.nil?

            mod = m[1] == '-' ? -1.0 : 1.0
            val = 0.0

            s = m[2]

            while s.length > 0
                m = nil
                if m = s.match(/^(\d+|\d+\.\d*|\d*\.\d+)([#{DURATION_LETTERS}])(.*)$/)
                    val += m[1].to_f * DURATIONS[m[2]]
                elsif s.match(/^\d+$/)
                    val += s.to_i
                elsif s.match(/^\d*\.\d*$/)
                    val += s.to_f
                elsif quiet
                    return nil
                else
                    raise ArgumentError.new(
                        "cannot parse '#{string}' (unexpected '#{s}')"
                    )
                end
                break unless m && m[3]
                s = m[3]
            end

            res = mod * val
            res.to_i
        end


        # Turns a number of seconds into a a time string
        #
        #   Rufus.to_duration 0                    # => '0s'
        #   Rufus.to_duration 60                   # => '1m'
        #   Rufus.to_duration 3661                 # => '1h1m1s'
        #   Rufus.to_duration 7 * 24 * 3600        # => '1w'
        #   Rufus.to_duration 30 * 24 * 3600 + 1   # => "4w2d1s"
        #
        # It goes from seconds to the year. Months are not counted (as they
        # are of variable length). Weeks are counted.
        #
        # For 30 days months to be counted, the second parameter of this
        # method can be set to true.
        #
        #   Rufus.to_duration 30 * 24 * 3600 + 1, true   # => "1M1s"
        #
        # If a Float value is passed, milliseconds will be displayed without
        # 'marker'
        #
        #   Rufus.to_duration 0.051                       # => "51"
        #   Rufus.to_duration 7.051                       # => "7s51"
        #   Rufus.to_duration 0.120 + 30 * 24 * 3600 + 1  # => "4w2d1s120"
        #
        # (this behaviour mirrors the one found for parse_time_string()).
        #
        # Options are :
        #
        # * :months, if set to true, months (M) of 30 days will be taken into
        #   account when building up the result
        # * :drop_seconds, if set to true, seconds and milliseconds will be trimmed
        #   from the result
        #
        def self.to_duration(seconds, options = {})
            h = to_duration_hash(seconds, options)

            return (options[:drop_seconds] ? '0m' : '0s') if h.empty?

            s = DU_KEYS.inject(String.new) { |r, key|
                count = h[key]
                count = nil if count == 0
                r << "#{count}#{key}" if count
                r
            }

            ms = h[:ms]
            s << ms.to_s if ms
            s
        end

        # Turns a number of seconds (integer or Float) into a hash like in :
        #
        #   Rufus.to_duration_hash 0.051
        #     # => { :ms => "51" }
        #   Rufus.to_duration_hash 7.051
        #     # => { :s => 7, :ms => "51" }
        #   Rufus.to_duration_hash 0.120 + 30 * 24 * 3600 + 1
        #     # => { :w => 4, :d => 2, :s => 1, :ms => "120" }
        #
        # This method is used by to_duration behind the scenes.
        #
        # Options are :
        #
        # * :months, if set to true, months (M) of 30 days will be taken into
        #   account when building up the result
        # * :drop_seconds, if set to true, seconds and milliseconds will be trimmed
        #   from the result
        #
        def self.to_duration_hash(seconds, options = {})
            h = {}

            if (seconds % 1000) > 0
                h[:ms] = (seconds % 1000).to_i
                seconds = (seconds / 1000).to_i * 1000
            end

            if options[:drop_seconds]
                h.delete(:ms)
                seconds = (seconds - seconds % 60000)
            end

            durations = options[:months] ? DURATIONS2M : DURATIONS2

            durations.each do |key, duration|
                count = seconds / duration
                seconds = seconds % duration

                h[key.to_sym] = count if count > 0
            end

            h
        end

        #--
        # misc
        #++

        # Produces the UTC string representation of a Time instance
        #
        # like "2009/11/23 11:11:50.947109 UTC"
        #
        def self.utc_to_s(t=Time.now)
            "#{t.utc.strftime('%Y-%m-%d %H:%M:%S')}.#{sprintf('%06d', t.usec)} UTC"
        end

        # Produces a hour/min/sec/milli string representation of Time instance
        #
        def self.h_to_s(t=Time.now)
            "#{t.strftime('%H:%M:%S')}.#{sprintf('%06d', t.usec)}"
        end
    end
end
