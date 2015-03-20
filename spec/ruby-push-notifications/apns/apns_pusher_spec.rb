
module RubyPushNotifications
  module APNS
    describe APNSPusher do

      let(:sandbox) { true }
      let(:certificate) { 'abc' }
      let(:tcp_socket) { instance_double(TCPSocket).as_null_object }
      let(:ssl_socket) { instance_double(OpenSSL::SSL::SSLSocket).as_null_object }
      let(:pusher) { APNSPusher.new certificate, sandbox }
      let(:connection) { APNSConnection.new tcp_socket, ssl_socket }
      let(:data) { { a: 1 } }

      before do
        allow(APNSConnection).to receive(:open).with(certificate, sandbox).and_return connection
      end

      describe '#push' do

        context 'a single notification' do

          context 'containing a single destination' do

            let(:token) { generate :apns_token }
            let(:notification) { build :apns_notification, data: data, tokens: [token] }

            describe 'success' do

              before { allow(IO).to receive(:select).and_return [[]] }

              it 'writes the notification to the socket' do
                expect(connection).to receive(:write).with apns_binary(data, token, 0)
                pusher.push [notification]
              end

              it 'flushes the socket contents' do
                expect(connection).to receive(:flush)
                pusher.push [notification]
              end

              it 'saves the results into the notification' do
                expect do
                  pusher.push [notification]
                end.to change { notification.results }.from(nil).to [NO_ERROR_STATUS_CODE]
              end
            end

            describe 'failure' do

              before do
                allow(IO).to receive(:select).and_return [[ssl_socket]]
                allow(ssl_socket).to receive(:read).with(6).and_return [8, PROCESSING_ERROR_STATUS_CODE, 0].pack 'ccN'
              end

              it 'returns the error' do
                expect do
                  pusher.push [notification]
                end.to change { notification.results }.from(nil).to [PROCESSING_ERROR_STATUS_CODE]
              end
            end
          end

          context 'containing several destinations' do
            let(:tokens) { [generate(:apns_token), generate(:apns_token)] }
            let(:notification) { build :apns_notification, data: data, tokens: tokens }

            describe 'success' do

              before { allow(IO).to receive(:select).and_return [[]] }

              it 'writes the messages to the socket' do
                expect(connection).to receive(:write).with apns_binary(data, tokens[0], 0)
                expect(connection).to receive(:write).with apns_binary(data, tokens[1], 1)
                pusher.push [notification]
              end

              it 'flushes the socket contents' do
                expect(connection).to receive(:flush).once
                pusher.push [notification]
              end

              it 'saves the results into the notification' do
                expect do
                  pusher.push [notification]
                end.to change { notification.results }.from(nil).to [NO_ERROR_STATUS_CODE, NO_ERROR_STATUS_CODE]
              end
            end

            describe 'failure' do

              before do
                allow(IO).to receive(:select).and_return [[ssl_socket]], []
                allow(ssl_socket).to receive(:read).with(6).and_return [8, PROCESSING_ERROR_STATUS_CODE, 0].pack 'ccN'
              end

              it 'returns the error' do
                expect do
                  pusher.push [notification]
                end.to change { notification.results }.from(nil).to [PROCESSING_ERROR_STATUS_CODE, NO_ERROR_STATUS_CODE]
              end
            end
          end
        end

        context 'several notifications' do
          let(:tokens) { (0...10).map { generate:apns_token } }
          let(:notifications) { tokens.map { |token| build :apns_notification, data: data, tokens: [token] } }

          describe 'success' do

            before { allow(IO).to receive(:select).and_return [[]] }

            it 'writes the notifications to the socket' do
              notifications.each_with_index do |notification, i|
                expect(connection).to receive(:write).with(apns_binary(data, tokens[i], i)).once
              end
              pusher.push notifications
            end

            it 'flushes the socket contents' do
              expect(connection).to receive(:flush).once
              pusher.push notifications
            end

            it 'returns success' do
              expect do
                pusher.push notifications
              end.to change { notifications.map { |n| n.results } }.from([nil]*10).to([[NO_ERROR_STATUS_CODE]]*10)
            end
          end

          describe 'failure' do

            context 'several failures' do

              before do
                allow(IO).to receive(:select).and_return [], [], [[ssl_socket]], [], [], [[ssl_socket]], []
                allow(ssl_socket).to receive(:read).with(6).and_return [8, PROCESSING_ERROR_STATUS_CODE, 2].pack('ccN'), [8, MISSING_DEVICE_TOKEN_STATUS_CODE, 5].pack('ccN')
              end

              it 'repones the connection' do
                expect(APNSConnection).to receive(:open).with(certificate, sandbox).and_return(connection).exactly(3).times
                pusher.push notifications
              end

              it 'returns the statuses' do
                expect do
                  pusher.push notifications
                end.to change { notifications.map { |n| n.results } }.from([nil]*10).to [
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [PROCESSING_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [MISSING_DEVICE_TOKEN_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE]
                  ]
              end
            end

            context 'failing first notification' do
              before do
                allow(IO).to receive(:select).and_return [[ssl_socket]], []
                allow(ssl_socket).to receive(:read).with(6).and_return [8, PROCESSING_ERROR_STATUS_CODE, 0].pack 'ccN'
              end

              it 'repones the connection' do
                expect(APNSConnection).to receive(:open).with(certificate, sandbox).and_return(connection).twice
                pusher.push notifications
              end

              it 'returns the statuses' do
                expect do
                  pusher.push notifications
                end.to change { notifications.map { |n| n.results } }.from([nil]*10).to [
                    [PROCESSING_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE]
                  ]
              end
            end

            context 'failing last notification' do
              before do
                allow(IO).to receive(:select).and_return [], [], [], [], [], [], [], [], [], [[ssl_socket]]
                allow(ssl_socket).to receive(:read).with(6).and_return [8, PROCESSING_ERROR_STATUS_CODE, 9].pack 'ccN'
              end

              it 'returns the statuses' do
                expect do
                  pusher.push notifications
                end.to change { notifications.map { |n| n.results } }.from([nil]*10).to [
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [NO_ERROR_STATUS_CODE],
                    [PROCESSING_ERROR_STATUS_CODE]
                  ]
              end
            end
          end
        end
      end
    end
  end
end