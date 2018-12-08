module Postal
    module MessageDB
      module Migrations
        class CreateValidations < Postal::MessageDB::Migration
          def up
            @database.provisioner.create_table(:messages,
              :columns => {
                :id                           =>  'int(11) NOT NULL AUTO_INCREMENT',
                :token                        =>  'varchar(255) DEFAULT NULL',
                :rcpt_to                      =>  'varchar(255) DEFAULT NULL',
                :mail_from                    =>  'varchar(255) DEFAULT NULL',
                :server_response              =>  'varchar(255) DEFAULT NULL',
                :validation_id                =>  'varchar(255) DEFAULT NULL',
                :timestamp                    =>  'decimal(18,6) DEFAULT NULL',
                :route_id                     =>  'int(11) DEFAULT NULL',
                :domain_id                    =>  'int(11) DEFAULT NULL',
                :credential_id                =>  'int(11) DEFAULT NULL',
                :status                       =>  'varchar(255) DEFAULT NULL',
                :held                         =>  'tinyint(1) DEFAULT 0',
                :last_delivery_attempt        =>  'decimal(18,6) DEFAULT NULL',
                :received_with_ssl            =>  'tinyint(1) DEFAULT NULL',
              },
              :indexes => {
                :on_message_id                =>  '`message_id`(8)',
                :on_token                     =>  '`token`(6)',
                :on_bounce_for_id             =>  '`bounce_for_id`',
                :on_held                      =>  '`held`',
                :on_rcpt_to                   =>  '`rcpt_to`(12), `timestamp`',
                :on_mail_from                 =>  '`mail_from`(12), `timestamp`',
              }
            )
          end
        end
      end
    end
  end
  