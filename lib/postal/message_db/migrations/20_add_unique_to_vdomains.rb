module Postal
    module MessageDB
      module Migrations
        class AddUniqueToVdomains < Postal::MessageDB::Migration
          def up
            @database.query("ALTER TABLE `#{@database.database_name}`.`vdomains` ADD CONSTRAINT `uc_domain` UNIQUE (`domain`)")
          end
        end
      end
    end
  end
  