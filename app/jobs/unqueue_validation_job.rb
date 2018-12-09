class UnqueueValidationJob < Postal::Job
    def perform
        if original_validation = QueuedValidation.find_by_id(params['id'])
            
            if original_validation.acquire_lock

                log "Lock acquired for queued validation #{original_validation.id}"
  
                begin
                    original_validation.validation
                rescue Postal::MessageDB::Validation::NotFound
                    log "Unqueue #{original_validation.id} because backend validation has been removed."
                    original_validation.destroy
                    return
                end
  
                unless original_validation.retriable?
                    log "Skipping because retry after isn't reached"
                    original_validation.unlock
                    return
                end
    
                begin
                    other_validations = original_validation.batchable_validations(100)
                    log "Found #{other_validations.size} associated validations to process at the same time (batch key: #{original_validation.batch_key})"
                rescue
                    original_validation.unlock
                    raise
                end
  
                ([original_validation] + other_validations).each do |queued_validation|
                    log_prefix = "[#{queued_validation.server_id}::#{queued_validation.validation_id} #{queued_validation.id}]"
                    begin
                        log "#{log_prefix} Got queued validation with exclusive lock"
    
                        begin
                            queued_validation.validation
                        rescue Postal::MessageDB::Validation::NotFound
                            log "#{log_prefix} Unqueueing #{queued_validation.id} because backend validation has been removed"
                            queued_validation.destroy
                            next
                        end
    
                        # #
                        # # If the server is suspended, hold all validations
                        # #
                        if queued_validation.server.suspended?
                            log "#{log_prefix} Server is suspended. Holding validation."
                            queued_validation.validation.create_delivery('Held', :details => "Mail server has been suspended. No e-mails can be processed at present. Contact support for assistance.")
                            queued_validation.destroy
                            next
                        end
    
                        # We might not be able to send this any more, check the attempts
                        if queued_validation.attempts >= Postal.config.general.maximum_delivery_attempts
                            details = "Maximum number of delivery attempts (#{queued_validation.attempts}) has been reached."
                            if queued_validation.server.message_db.suppression_list.add(:recipient, queued_validation.validation.rcpt_to, :reason => "too many soft fails")
                                log "Added #{queued_validation.validation.rcpt_to} to suppression list because maximum attempts has been reached"
                                details += " Added #{queued_validation.validation.rcpt_to} to suppression list because delivery has failed #{queued_validation.attempts} times."
                            end
                            queued_validation.validation.create_delivery('HardFail', :details => details)
                            queued_validation.destroy
                            log "#{log_prefix} Message has reached maximum number of attempts. Hard failing."
                            next
                        end
    
                        if queued_validation.validation.domain.nil?
                            log "#{log_prefix} Message has no domain. Hard failing."
                            queued_validation.validation.create_delivery('HardFail', :details => "Message's domain no longer exist")
                            queued_validation.destroy
                            next
                        end
    
                        
                        # If there's no to address, we can't do much. Fail it.
                        
                        if queued_validation.validation.rcpt_to.blank?
                            log "#{log_prefix} Message has no to address. Hard failing."
                            queued_validation.validation.create_delivery('HardFail', :details => "Message doesn't have an RCPT to")
                            queued_validation.destroy
                            next
                        end
    
                        #
                        # If the credentials for this validation is marked as holding and this isn't manual, hold it
                        #
                        if !queued_validation.manual? && queued_validation.validation.credential && queued_validation.validation.credential.hold?
                            log "#{log_prefix} Credential wants us to hold validations. Holding."
                            queued_validation.validation.create_delivery('Held', :details => "Credential is configured to hold all validations authenticated by it.")
                            queued_validation.destroy
                            next
                        end
    
                        #
                        # If the recipient is on the suppression list and this isn't a manual queueing block sending
                        #
                        puts queued_validation.validation.inspect
                        if !queued_validation.manual? && sl = queued_validation.server.message_db.suppression_list.get(:recipient, queued_validation.validation.rcpt_to)
                            log "#{log_prefix} Recipient is on the suppression list. Holding."
                            queued_validation.validation.create_delivery('Held', :details => "Recipient (#{queued_validation.validation.rcpt_to}) is on the suppression list (reason: #{sl['reason']})")
                            queued_validation.destroy
                            next
                        end
    
                        # # Extract a tag and add it to the validation if one doesn't exist
                        if queued_validation.validation.tag.nil? && tag = queued_validation.validation.headers['x-postal-tag']
                            log "#{log_prefix} Added tag #{tag.last}"
                            queued_validation.validation.update(:tag => tag.last)
                        end
                    
                        # # Add outgoing headers
                        # if !queued_validation.validation.has_outgoing_headers?
                        #     queued_validation.validation.add_outgoing_headers
                        # end
    
                        # Check send limits
                        if queued_validation.server.send_limit_exceeded?
                            # If we're over the limit, we're going to be holding this validation
                            queued_validation.server.update_columns(:send_limit_exceeded_at => Time.now, :send_limit_approaching_at => nil)
                            queued_validation.validation.create_delivery('Held', :details => "Message held because send limit (#{queued_validation.server.send_limit}) has been reached.")
                            queued_validation.destroy
                            log "#{log_prefix} Server send limit has been exceeded. Holding."
                            next
                        elsif queued_validation.server.send_limit_approaching?
                            # If we're approaching the limit, just say we are but continue to process the validation
                            queued_validation.server.update_columns(:send_limit_approaching_at => Time.now, :send_limit_exceeded_at => nil)
                        else
                            queued_validation.server.update_columns(:send_limit_approaching_at => nil, :send_limit_exceeded_at => nil)
                        end
    
                        # If the server is in development mode, hold it
                        if queued_validation.server.mode == 'Development' && !queued_validation.manual?
                            log "Server is in development mode so holding."
                            queued_validation.validation.create_delivery('Held', :details => "Server is in development mode.")
                            queued_validation.destroy
                            log "#{log_prefix} Server is in development mode. Holding."
                            next
                        end
    
                        # Send the outgoing validation to the SMTP sender
                        begin
                            if @fixed_result
                                result = @fixed_result
                            else
                                sender = cached_sender(Postal::SMTPValidator, queued_validation.validation.recipient_domain, queued_validation.ip_address)
                                result = sender.send_validation(queued_validation.validation)
                                if result.connect_error
                                    @fixed_result = result
                                end
                            end
                        end
    
                        #
                        # If the validation has been hard failed, check to see how many other recent hard fails we've had for the address
                        # and if there are more than 2, suppress the address for 30 days.
                        #
                        if result.type == 'HardFail'
                            recent_hard_fails = queued_validation.server.message_db.select(:validations, :where => {:rcpt_to => queued_validation.validation.rcpt_to, :status => 'HardFail', :timestamp => {:greater_than => 24.hours.ago.to_f}}, :count => true)
                            if recent_hard_fails >= 1
                                if queued_validation.server.message_db.suppression_list.add(:recipient, queued_validation.validation.rcpt_to, :reason => "too many hard fails")
                                    log "#{log_prefix} Added #{queued_validation.validation.rcpt_to} to suppression list because #{recent_hard_fails} hard fails in 24 hours"
                                    result.details += "." if result.details =~ /\.\z/
                                    result.details += " Recipient added to suppression list (too many hard fails)."
                                end
                            end
                        end
    
                        # #
                        # # If a validation is sent successfully, remove the users from the suppression list
                        # #
                        if result.type == 'Sent'
                            if queued_validation.server.message_db.suppression_list.remove(:recipient, queued_validation.validation.rcpt_to)
                                log "#{log_prefix} Removed #{queued_validation.validation.rcpt_to} from suppression list because success"
                                result.details += "." if result.details =~ /\.\z/
                                result.details += " Recipient removed from suppression list."
                            end
                        end
    
                        # # Log the result
                        queued_validation.validation.create_delivery(result.type, :details => result.details, :output => result.output, :sent_with_ssl => result.secure, :log_id => result.log_id, :time => result.time)
                        if result.retry
                            log "#{log_prefix} Message requeued for trying later."
                            queued_validation.retry_later(result.retry.is_a?(Fixnum) ? result.retry : nil)
                        else
                            log "#{log_prefix} Processing complete"
                            queued_validation.destroy
                        end
  
                    rescue => e
                        log "#{log_prefix} Internal error: #{e.class}: #{e.validation}"
                        e.backtrace.each { |e| log("#{log_prefix} #{e}") }
                        queued_validation.retry_later
                        log "#{log_prefix} Queued validation was unlocked"
                        if defined?(Raven)
                            Raven.capture_exception(e, :extra => {:job_id => self.id, :server_id => queued_validation.server_id, :validation_id => queued_validation.validation_id})
                        end
                        if queued_validation.validation
                            queued_validation.validation.create_delivery("Error", :details => "An internal error occurred while sending this validation. This validation will be retried automatically. If this persists, contact support for assistance.", :output => "#{e.class}: #{e.validation}", :log_id => "J-#{self.id}")
                        end
                    end
                end
            else
                log "Couldn't get lock for validation #{params['id']}. I won't do this."
            end
        else
            log "No queued validation with ID #{params['id']} was available for processing."
        end
    ensure
      @sender&.finish rescue nil
    end
  
    private
  
    def cached_sender(klass, *args)
        @sender ||= begin
            sender = klass.new(*args)
            sender.start
            sender
        end
    end
end
  