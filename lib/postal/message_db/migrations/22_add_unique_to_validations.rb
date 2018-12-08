module Postal
    module MessageDB
      module Migrations
        class AddUniqueToValidations < Postal::MessageDB::Migration
          def up
            @database.query("ALTER TABLE `#{@database.database_name}`.`vdomains` ADD UNIQUE `uc_domain` UNIQUE (`domain`)")
          end
        end
      end
    end
  end
  