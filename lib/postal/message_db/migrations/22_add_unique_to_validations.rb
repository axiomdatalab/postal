module Postal
    module MessageDB
      module Migrations
        class AddUniqueToValidations < Postal::MessageDB::Migration
          def up
            @database.query("ALTER TABLE `#{@database.database_name}`.`validations` ADD CONSTRAINT `uc_rcpt` UNIQUE (`rcpt_to`)")
          end
        end
      end
    end
  end
  