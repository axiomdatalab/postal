module HasValidation

    def self.included(base)
      base.extend ClassMethods
    end
  
    def validation
      @validation ||= self.server.message_db.validation(self.validation_id)
    end
  
    def validation=(validation)
      @validation = validation
      self.validation_id = validation&.id
    end
  
    module ClassMethods
      def include_validation
        queued_validations = all.to_a
        server_ids = queued_validations.map(&:server_id).uniq
        if server_ids.size == 0
          return []
        elsif server_ids.size > 1
          raise Postal::Error, "'include_validation' can only be used on collections of validations from the same server"
        end
        validation_ids = queued_validations.map(&:validation_id).uniq
        server = queued_validations.first&.server
        validations = server.message_db.validations(:where => {:id => validation_ids}).each_with_object({}) do |validation, hash|
          hash[validation.id] = validation
        end
        queued_validations.each do |queued_validation|
          if m = validations[queued_validation.validation_id]
            queued_validation.validation = m
          end
        end
      end
    end
  
  end
  