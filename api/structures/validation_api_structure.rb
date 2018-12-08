structure :validate do
    basic :id
    basic :token
  
    expansion(:status) {
      {
        :status => o.status,
        :last_delivery_attempt => o.last_delivery_attempt ? o.last_delivery_attempt.to_f : nil,
        :held => o.held == 1 ? true : false,
        :hold_expiry => o.hold_expiry ? o.hold_expiry.to_f : nil
      }
    }
  
    expansion(:details) {
      {
        :rcpt_to => o.rcpt_to,
        :mail_from => o.mail_from,
        :validate_id => o.validate_id,
        :timestamp => o.timestamp.to_f,
        :direction => o.scope,
        :size => o.size,
        :bounce => o.bounce,
        :bounce_for_id => o.bounce_for_id,
        :tag => o.tag,
        :received_with_ssl => o.received_with_ssl
      }
    }

  end
  