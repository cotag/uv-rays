# frozen_string_literal: true

require 'ipaddress' # IP Address parser
require 'ipaddr'

module UV; end
class UV::Ping

    def initialize(host, count: 1, interval: 1, timeout: 5)
        @host = host
        @count = count
        @interval = interval
        @timeout = timeout
    end

    attr_reader :host, :count, :interval, :timeout, :exception, :warning, :duration, :pingable

    def ping
        ip = if IPAddress.valid?(@host)
            @host
        else
            nslookup(@host)
        end

        if ip.nil?
            @pingable = false
            @exception = 'DNS lookup failed for both IPv4 and IPv6'
            return false
        end

        ipaddr = IPAddr.new ip
        if ipaddr.ipv4?
            ping4(@host, @count, @interval, @timeout)
        else
            ping6(@host, @count, @interval, @timeout)
        end
    end


    protected


    def nslookup(domain)
        value = nil
        reactor = Libuv::Reactor.current
        begin
            value = reactor.lookup(domain)[0][0]
        rescue => e
            begin
                value = reactor.lookup(domain, :IPv6)[0][0]
            rescue; end
        end
        value
    end

    def ping4(host, count, interval, timeout)
        pargs = nil
        bool = false

        case ::RbConfig::CONFIG['host_os']
        when /linux/i
            pargs = ['-c', count.to_s, '-W', timeout.to_s, host, '-i', interval.to_s]
        when /aix/i
            pargs = ['-c', count.to_s, '-w', timeout.to_s, host]
        when /bsd|osx|mach|darwin/i
            pargs = ['-c', count.to_s, '-t', timeout.to_s, host]
        when /solaris|sunos/i
            pargs = [host, timeout.to_s]
        when /hpux/i
            pargs = [host, "-n#{count.to_s}", '-m', timeout.to_s]
        when /win32|windows|msdos|mswin|cygwin|mingw/i
            pargs = ['-n', count.to_s, '-w', (timeout * 1000).to_s, host]
        else
            pargs = [host]
        end

        start_time = Time.now
        exitstatus, info, err = spawn_ping('ping', pargs)

        case exitstatus
        when 0
            if info =~ /unreachable/ix # Windows
                bool = false
                @exception = "host unreachable"
            else
                bool = true  # Success, at least one response.
            end

            if err =~ /warning/i
                @warning = err.chomp
            end
        when 2
            bool = false # Transmission successful, no response.
            @exception = err.chomp if err
        else
            bool = false # An error occurred
            if err
                @exception = err.chomp
            else
                info.each_line do |line|
                    if line =~ /(timed out|could not find host|packet loss)/i
                        @exception = line.chomp
                        break
                    end
                end
            end
        end

        @duration = Time.now - start_time if bool
        @pingable = bool
        bool
    end

    def ping6(host, count, interval, timeout)
        pargs = nil
        bool = false

        case RbConfig::CONFIG['host_os']
        when /linux/i
            pargs =['-c', count.to_s, '-W', timeout.to_s, '-i', interval.to_s, host]
        when /aix/i
            pargs =['-c', count.to_s, '-w', timeout.to_s, host]
        when /bsd|osx|mach|darwin/i
            pargs =['-c', count.to_s, host]
        when /solaris|sunos/i
            pargs =[host, timeout.to_s]
        when /hpux/i
            pargs =[host, "-n#{count.to_s}", '-m', timeout.to_s]
        when /win32|windows|msdos|mswin|cygwin|mingw/i
            pargs =['-n', count.to_s, '-w', (timeout * 1000).to_s, host]
        else
            pargs =[host]
        end

        start_time = Time.now
        exitstatus, info, err = spawn_ping('ping6', pargs)

        case exitstatus
        when 0
            if info =~ /unreachable/ix # Windows
                bool = false
                @exception = "host unreachable"
            else
                bool = true  # Success, at least one response.
            end

            if err =~ /warning/i
                @warning = err.chomp
            end
        when 2
            bool = false # Transmission successful, no response.
            @exception = err.chomp if err
        else
            bool = false # An error occurred
            if err
                @exception = err.chomp
            else
                info.each_line do |line|
                    if line =~ /(timed out|could not find host|packet loss)/i
                        @exception = line.chomp
                        break
                    end
                end
            end
        end

        @duration = Time.now - start_time if bool
        @pingable = bool
        bool
    end

    def spawn_ping(cmd, args)
        stdout = String.new
        stderr = String.new

        process = Libuv::Reactor.current.spawn(cmd, args: args)
        process.stdout.progress { |data| stdout << data }
        process.stderr.progress { |data| stderr << data }
        process.stdout.start_read
        process.stderr.start_read
        begin
            process.value
            [0, stdout, stderr]
        rescue => e
            [e.exit_status, stdout, stderr]
        end
    end
end
