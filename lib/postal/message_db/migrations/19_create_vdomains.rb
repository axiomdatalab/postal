module Postal
    module MessageDB
      module Migrations
        class CreateVdomains < Postal::MessageDB::Migration
          def up
            @database.provisioner.create_table(:messages,
              :columns => {
                :id                           =>  'int(11) NOT NULL AUTO_INCREMENT',
                :token                        =>  'varchar(255) DEFAULT NULL',
                :scope                        =>  'varchar(10) DEFAULT NULL',
                :domain                       =>  'varchar(50) DEFAULT NULL',
                :catchall                     =>  'boolean NOT NULL default 0',
                :timestamp                    =>  'decimal(18,6) DEFAULT NULL',
              },
              :indexes => {
                :on_message_id                =>  '`message_id`(8)',
                :on_token                     =>  '`token`(6)',
                :on_domain                    =>  '`domain`',
              }
            )
          end
        end
      end
    end
  end
  