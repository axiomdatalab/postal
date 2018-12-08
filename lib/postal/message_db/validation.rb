module Postal
  module MessageDB
    class Validation

      class NotFound < Postal::Error
      end

      def self.find_one(database, query)
        query = {:id => query.to_i} if query.is_a?(Fixnum)
        if validation = database.select('validations', :where => query, :limit => 1).first
          Validation.new(database, validation)
        else
          raise NotFound, "No validation found matching provided query #{query}"
        end
      end

      def self.find(database, options = {})
        if validations = database.select('validations', options)
          if validations.is_a?(Array)
            validations.map { |m| Validation.new(database, m) }
          else
            validations
          end
        else
          []
        end
      end

      def self.find_with_pagination(database, page, options = {})
        validations = database.select_with_pagination('validations', page, options)
        validations[:records] = validations[:records].map { |m| Validation.new(database, m) }
        validations
      end

      attr_reader :database

      def initialize(database, attributes)
        @database = database
        @attributes = attributes
      end

      #
      # Return the server for this validation
      #
      def server
        @database.server
      end

      #
      # Return the credential for this validation
      #
      def credential
        @credential ||= self.credential_id ? Credential.find_by_id(self.credential_id) : nil
      end

      #
      # Return the route for this validation
      #
      def route
        @route ||= self.route_id ? Route.find_by_id(self.route_id) : nil
      end

      #
      # Return the endpoint for this validation
      #
      def endpoint
        @endpoint ||= begin
          if self.endpoint_type && self.endpoint_id
            self.endpoint_type.constantize.find_by_id(self.endpoint_id)
          elsif self.route && self.route.mode == 'Endpoint'
            self.route.endpoint
          end
        end
      end

      #
      # Return the credential for this validation
      #
      def domain
        @domain ||= self.domain_id ? Domain.find_by_id(self.domain_id) : nil
      end

      #
      # Return the timestamp for this validation
      #
      def timestamp
        @timestamp ||= @attributes['timestamp'] ? Time.zone.at(@attributes['timestamp']) : nil
      end

      #
      # Return the time that the last delivery was attempted
      #
      def last_delivery_attempt
        @last_delivery_attempt ||= @attributes['last_delivery_attempt'] ? Time.zone.at(@attributes['last_delivery_attempt']) : nil
      end

      #
      # Provide access to set and get acceptable attributes
      #
      def method_missing(name, value = nil, &block)
        if @attributes.has_key?(name.to_s)
          @attributes[name.to_s]
        elsif name.to_s =~ /\=\z/
          @attributes[name.to_s.gsub('=', '').to_s] = value
        else
          nil
        end
      end

      #
      # Has this validation been persisted to the database yet?
      #
      def persisted?
        !@attributes['id'].nil?
      end

      #
      # Save this validation
      #
      def save
        persisted? ? _update : _create
        self
      end

      #
      # Update this validation
      #
      def update(attributes_to_change)
        @attributes = @attributes.merge(database.stringify_keys(attributes_to_change))
        if persisted?
          @database.update('validations', attributes_to_change, :where => {:id => self.id})
        else
          _create
        end
      end

      #
      # Delete the validation from the database
      #
      def delete
        if persisted?
          @database.delete('validations', :where => {:id => self.id})
        end
      end

      #
      # Return the recipient domain for this validation
      #
      def recipient_domain
        self.rcpt_to ? self.rcpt_to.split('@').last : nil
      end

      #
      # Create a new item in the validation queue for this validation
      #
      def add_to_validation_queue(options = {})
        QueuedValidation.create!(:validation => self, :server_id => @database.server_id, :batch_key => self.batch_key, :domain => self.recipient_domain, :route_id => self.route_id, :manual => options[:manual]).id
      end

      #
      # Return a suitable batch key for this validation
      #
      def batch_key
        key = "validation-"
        key += "rt:#{self.route_id}-ep:#{self.endpoint_id}-#{self.endpoint_type}"
        key
      end

      #
      # Return the queued validation
      #
      def queued_validation
        @queued_validation ||= self.id ? QueuedValidation.where(:validation_id => self.id, :server_id => @database.server_id).first : nil
      end

      #
      # Has this validation been held?
      #
      def held?
        status == 'Held'
      end

      #
      # Does this validation have our DKIM header yet?
      #
      def has_outgoing_headers?
        !!(raw_headers =~ /^X\-Postal\-MsgID\:/i)
      end

      #
      # Add dkim header
      #
      def add_outgoing_headers
        headers = []
        if self.domain
          dkim = Postal::DKIMHeader.new(self.domain, self.raw_validation)
          headers << dkim.dkim_header
        end
        headers << "X-Postal-MsgID: #{self.token}"
        append_headers(*headers)
      end

      #
      # Append a header to the existing headers
      #
      def append_headers(*headers)
        new_headers = headers.join("\r\n")
        new_headers = "#{new_headers}\r\n#{self.raw_headers}"
        @raw_headers = new_headers
        @raw_validation = nil
        @headers = nil
      end

      #
      # Return a suitable
      #
      def webhook_hash
        @webhook_hash ||= {
          :id => self.id,
          :token => self.token,
          :validation_id => self.validation_id,
          :to => self.rcpt_to,
          :from => self.mail_from,
          :timestamp => self.timestamp.to_f,
          :tag => self.tag
        }
      end

      #
      # Was thsi validation sent to a return path?
      #
      def rcpt_to_return_path?
        !!(rcpt_to =~ /\@#{Regexp.escape(Postal.config.dns.custom_return_path_prefix)}\./)
      end

      #
      
      #
      # Cancel the hold on this validation
      #
      def cancel_hold
        if self.status == 'Held'
          create_delivery('HoldCancelled', :details => "The hold on this validation has been removed without action.")
        end
      end

      private

      def _update
        @database.update('validations', @attributes.reject {|k,v| k == :id }, :where => {:id => @attributes['id']})
      end

      def _create
        self.timestamp = Time.now.to_f if self.timestamp.blank?
        self.status = 'Pending' if self.status.blank?
        self.token = Nifty::Utils::RandomString.generate(:length => 12) if self.token.blank?
        last_id = @database.insert('validations', @attributes.reject {|k,v| k == :id })
        @attributes['id'] = last_id
        add_to_validation_queue
      end

      def mail
        # This version of mail is only used for accessing the bodies.
        @mail ||= raw_validation? ? Mail.new(raw_validation) : nil
      end

    end
  end
end
