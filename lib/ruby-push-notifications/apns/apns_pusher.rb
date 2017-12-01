
module RubyPushNotifications
  module APNS
    # This class coordinates the process of sending notifications.
    # It takes care of reopening closed APNSConnections and seeking back to
    # the failed notification to keep writing.
    #
    # Remember that APNS doesn't confirm successful notification, it just
    # notifies when one went wrong and closes the connection. Therefore, this
    # APNSPusher reconnects and rewinds the array until the notification that
    # Apple rejected.
    #
    # @author Carlos Alonso
    class APNSPusher

      # @param certificate [String]. The PEM encoded APNS certificate.
      # @param sandbox [Boolean]. Whether the certificate is an APNS sandbox or not.
      def initialize(certificate, sandbox)
        @certificate = certificate
        @sandbox = sandbox
      end

      # Pushes the notifications.
      # Builds an array with all the binaries (one for each notification and receiver)
      # and pushes them sequentially to APNS monitoring the response.
      # If an error is received, the connection is reopened and the process
      # continues at the next notification after the failed one (pointed by the response error)
      #
      # For each notification assigns an array with the results of each submission.
      #
      # @param notifications [Array]. All the APNSNotifications to be sent.
      def push(notifications)
        conn = APNSConnection.open @certificate, @sandbox

        binaries = notifications.each_with_object([]) do |notif, binaries|
          notif.each_message(binaries.count) do |msg|
            binaries << msg
          end
        end

        results = []
        i = 0
        while i < binaries.count
          begin
            conn.write binaries[i]
          rescue Exception => e
            # in case of unhandled error log it, mark in results and try to reopen connection
            logger.warn "APNS connection write error: " + e.message
            logger.warn e.backtrace.join("\n")
            results << UNKNOWN_ERROR_STATUS_CODE
            conn = APNSConnection.open @certificate, @sandbox, @pass, @options
          else
            # this was the default behaviour
            if i == binaries.count-1
              conn.flush
              rs, = IO.select([conn], nil, nil, 2)
            else
              rs, = IO.select([conn], [conn])
            end
            if rs && rs.any?
              packed = rs[0].read 6
              if packed.nil? && i == 0
                # The connection wasn't properly open
                # Probably because of wrong certificate/sandbox? combination
                results << UNKNOWN_ERROR_STATUS_CODE
              else
                err = packed.unpack 'ccN'
                results.slice! err[2]..-1
                results << err[1]
                i = err[2]
                conn = APNSConnection.open @certificate, @sandbox, @pass, @options
              end
            else
              results << NO_ERROR_STATUS_CODE
            end
          ensure
            i += 1
          end
        end

        conn.close

        notifications.each do |notif|
          notif.results = APNSResults.new(results.slice! 0, notif.count)
        end
      end
    end
  end
end
