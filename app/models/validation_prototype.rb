require 'resolv'

class ValidationPrototype

  attr_accessor :from
  attr_accessor :to
  attr_accessor :tag
  attr_accessor :credential

  def initialize(server, ip, source_type, attributes)
    @server = server
    @ip = ip
    @source_type = source_type
    @validation_id = "#{SecureRandom.uuid}@#{Postal.config.dns.return_path}"
    attributes.each do |key, value|
      instance_variable_set("@#{key}", value)
    end
  end

  def validation_id
    @validation_id
  end

  def from_address
    Postal::Helpers.strip_name_from_address(@from)
  end

  def sender_address
    Postal::Helpers.strip_name_from_address(@sender)
  end

  def domain
    @domain ||= begin
      d = find_domain
      d == :none ? nil : d
    end
  end

  def find_domain
    @domain ||= begin
      domain = @server.authenticated_domain_for_address(@from)
      if @server.allow_sender? && domain.nil?
        domain = @server.authenticated_domain_for_address(@sender)
      end
      domain || :none
    end
  end

  def to_addresses
    @to.is_a?(String) ? @to.to_s.split(/\,\s*/) : @to.to_a
  end

  def all_addresses
    [to_addresses].flatten
  end

  def create_validations
    if valid?
      all_addresses.each_with_object({}) do |address, hash|
        if address = Postal::Helpers.strip_name_from_address(address)
          hash[address] = create_validation(address)
        end
      end
    else
      false
    end
  end

  def valid?
    validate
    errors.empty?
  end

  def errors
    @errors || {}
  end

  def validate
    @errors = Array.new

    if to_addresses.empty?
      @errors << "NoRecipients"
    end

    if to_addresses.size > 50
      @errors << 'TooManyToAddresses'
    end

    if from.blank?
      @errors << "FromAddressMissing"
    end

    if domain.nil?
      @errors << "UnauthenticatedFromAddress"
    end

    @errors
  end

  def create_validation(address)
    validation = @server.validation_db.new_validation
    validation.rcpt_to = address
    validation.mail_from = self.from_address
    validation.domain_id = self.domain.id
    validation.tag = self.tag
    validation.credential_id = self.credential&.id
    validation.received_with_ssl = true
    validation.save
    {:id => validation.id, :token => validation.token}
  end

  def resolved_hostname
    @resolved_hostname ||= Resolv.new.getname(@ip) rescue @ip
  end

end
