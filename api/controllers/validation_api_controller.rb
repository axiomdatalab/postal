controller :validation do
    friendly_name "Validation API"
    description "This API allows you to validate an email address"
    authenticator :server
  
    action :validate do
        title "Validate an email address"
        description "This action allows you to validate an email address by providing the appropriate options"
        # Acceptable Parameters
        param :to, "The e-mail addresses of the recipients (max 50)", :type => Array
        param :from, "The e-mail address for the From header", :type => String
        param :tag, "The tag of the e-mail", :type => String
        # Errors
        error 'ValidationError', "The provided data was not sufficient to send an email", :attributes => {:errors => "A hash of error details"}
        error 'NoRecipients', "There are no recipients defined to received this message"
        error 'TooManyToAddresses', "The maximum number of To addresses has been reached (maximum 50)"
        error 'FromAddressMissing', "The From address is missing and is required"
        error 'UnauthenticatedFromAddress', "The From address is not authorised to send mail from this server"
        # Return
        returns Hash
        # Action
        action do
            attributes = {}
            attributes[:to] = params.to
            attributes[:from] = params.from
            attributes[:tag] = params.tag
            validation = ValidationPrototype.new(identity.server, request.ip, 'api', attributes)
            validation.credential = identity
            if validation.valid?
                result = validation.create_validations
                {:validation_id => validation.validation_id, :validations => result}
            else
                error validation.errors.first
            end
        end
    end

  end
  